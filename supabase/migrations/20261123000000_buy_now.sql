-- Buy now (ADR 0006): personal items are bought, not reserved.
-- See docs/data-dictionary.md ("purchases", "conversations") and
-- docs/api-contracts.md ("Buy now").
--
-- How it works:
--   * A student may chat about an available item without holding it.
--   * buy_item() takes the units the moment the purchase is confirmed, under
--     the listing's row lock: first come, first served. The listing is sold
--     when none are left. The seller doesn't accept.
--   * Cash waits for the handover and is never released automatically (the
--     item may already have changed hands). The buyer may cancel; the seller
--     may relist it 24 hours after the purchase.
--   * A transfer has 30 minutes for the receipt, then it is released. Once a
--     receipt is sent, only a person (the seller) can release the units.
--   * Lock order: the buyer's advisory lock (buy_item only), then listing,
--     purchase, payment.
--
-- Existing data: reservations become purchases with the same ids, and their
-- payments and chats follow them. The original rows are kept in
-- legacy.reservations, which the API doesn't expose.

------------------------------------------------------------------------------
-- 1. Settle overdue reservations by the old rules, and keep the originals
------------------------------------------------------------------------------

create schema if not exists legacy;
revoke all on schema legacy from public, anon, authenticated;

create table legacy.reservations as table public.reservations;
alter table legacy.reservations enable row level security;
revoke all on legacy.reservations from public, anon, authenticated;

-- Where money may have been sent, nothing is released automatically.
update public.reservations as rv
set expires_at = now() + interval '1 day'
where rv.status in ('requested', 'accepted')
  and rv.expires_at <= now()
  and exists (select 1 from public.deal_payments as dp
              where dp.reservation_id = rv.id and dp.status in ('submitted', 'accepted'));

do $$
declare
  stale uuid;
begin
  for stale in
    select distinct rv.listing_id from public.reservations as rv
    where rv.status in ('requested', 'accepted') and rv.expires_at <= now()
  loop
    perform 1 from public.listings as l where l.id = stale for update;
    perform public.expire_listing_reservations(stale);
  end loop;
end;
$$;

------------------------------------------------------------------------------
-- 2. Purchases
------------------------------------------------------------------------------

create table public.purchases (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  qty integer not null check (qty between 1 and 999),
  -- Snapshots: editing the listing doesn't change what was agreed.
  unit_price_sen integer not null check (unit_price_sen >= 0),
  total_sen bigint not null,
  payment_method text not null check (payment_method in ('cash', 'transfer')),
  status text not null
    check (status in ('awaiting_payment', 'awaiting_handover', 'completed', 'cancelled')),
  cancelled_by text check (cancelled_by in ('buyer', 'seller', 'system')),
  cancel_reason text check (cancel_reason is null or char_length(cancel_reason) between 1 and 200),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (buyer_id <> seller_id),
  check (total_sen = unit_price_sen::bigint * qty),
  check (status <> 'awaiting_payment' or payment_method = 'transfer'),
  check ((status = 'completed') = (completed_at is not null)),
  check (status = 'cancelled' or (cancelled_by is null and cancel_reason is null))
);

-- Reservations didn't store a price: a transfer's is in its payment, a cash
-- one's is the listing's. Who cancelled one wasn't stored either.
insert into public.purchases (
  id, listing_id, buyer_id, seller_id, qty, unit_price_sen, total_sen, payment_method, status,
  cancelled_by, cancel_reason, completed_at, created_at, updated_at
)
select rv.id, rv.listing_id, rv.buyer_id, rv.seller_id, rv.qty, price.unit, price.unit::bigint * rv.qty,
       case when dp.id is null then 'cash' else 'transfer' end,
       case
         when rv.status = 'collected' then 'completed'
         when rv.status in ('declined', 'cancelled', 'expired') then 'cancelled'
         when rv.status = 'requested' and dp.id is not null then 'awaiting_payment'
         else 'awaiting_handover'
       end,
       case rv.status when 'declined' then 'seller' when 'expired' then 'system' end,
       case rv.status
         when 'declined' then coalesce(dp.reject_reason, 'The seller declined the reservation.')
         when 'cancelled' then 'The reservation was cancelled.'
         when 'expired' then 'The reservation expired.'
       end,
       case when rv.status = 'collected' then rv.updated_at end,
       rv.created_at, rv.updated_at
from public.reservations as rv
join public.listings as l on l.id = rv.listing_id
left join public.deal_payments as dp on dp.reservation_id = rv.id
cross join lateral (
  select coalesce((dp.amount_sen / rv.qty)::integer, l.price_sen) as unit
) as price;

create trigger purchases_set_updated_at
  before update on public.purchases
  for each row execute function public.set_updated_at();

create unique index purchases_one_unfinished_per_buyer
  on public.purchases (listing_id, buyer_id)
  where status in ('awaiting_payment', 'awaiting_handover');
create index purchases_listing_idx on public.purchases (listing_id, status);
create index purchases_buyer_idx on public.purchases (buyer_id, created_at desc);
create index purchases_seller_idx on public.purchases (seller_id, created_at desc);

------------------------------------------------------------------------------
-- 3. Payments follow their purchase
------------------------------------------------------------------------------

alter table public.deal_payments
  add column purchase_id uuid unique references public.purchases (id) on delete cascade;
update public.deal_payments set purchase_id = reservation_id where reservation_id is not null;
-- Also drops the old "one of order or reservation" check.
alter table public.deal_payments drop column reservation_id;
alter table public.deal_payments
  add constraint deal_payments_one_deal check (num_nonnulls(order_id, purchase_id) = 1);

------------------------------------------------------------------------------
-- 4. One item chat per listing and buyer; order chats are unchanged
------------------------------------------------------------------------------

-- Also drops the old "one of reservation or order" check. What's left with
-- no order_id is an item chat.
alter table public.conversations drop column reservation_id;

-- A buyer who reserved an item twice has two chats: merge into the older.
-- A closed chat (the block) stays closed.
do $$
declare
  d record;
begin
  for d in
    select c.id as dup, first_value(c.id) over w as keep
    from public.conversations as c
    where c.order_id is null
    window w as (partition by c.listing_id, c.buyer_id order by c.created_at, c.id)
  loop
    continue when d.dup = d.keep;

    update public.messages as m set conversation_id = d.keep where m.conversation_id = d.dup;
    -- One open report per reporter and chat.
    update public.reports as r
    set status = 'reviewed', action = 'dismissed', reviewed_at = now(),
        review_note = 'Merged with another report on the same chat.'
    where r.conversation_id = d.dup and r.status = 'open'
      and exists (select 1 from public.reports as k
                  where k.conversation_id = d.keep and k.reporter_id = r.reporter_id and k.status = 'open');
    update public.reports as r set conversation_id = d.keep where r.conversation_id = d.dup;

    update public.conversations as k
    set buyer_last_read_id = greatest(k.buyer_last_read_id, o.buyer_last_read_id),
        seller_last_read_id = greatest(k.seller_last_read_id, o.seller_last_read_id),
        last_message_at = greatest(k.last_message_at, o.last_message_at),
        closed_at = coalesce(k.closed_at, o.closed_at),
        closed_by = coalesce(k.closed_by, o.closed_by)
    from public.conversations as o
    where k.id = d.keep and o.id = d.dup;
    delete from public.conversations as c where c.id = d.dup;
  end loop;
end;
$$;

create unique index conversations_one_per_listing_buyer
  on public.conversations (listing_id, buyer_id)
  where order_id is null;

------------------------------------------------------------------------------
-- 5. Reservations go; listings are available or sold
------------------------------------------------------------------------------

drop function public.request_reservation(uuid, integer, text, text);
drop function public.resolve_reservation(uuid, text);
drop function public.my_reservations(text);
drop type public.reservation_card;
drop table public.reservations;
drop function public.reservations_personal_only();
drop function public.expire_listing_reservations(uuid);

-- A reserved listing had every unit held.
update public.listings
set status = case when stock = 0 then 'sold' else 'available' end
where status = 'reserved';
alter table public.listings drop constraint listings_status_check;
alter table public.listings
  add constraint listings_status_check check (status in ('draft', 'available', 'sold', 'closed'));

------------------------------------------------------------------------------
-- 6. Releasing units
------------------------------------------------------------------------------

-- Cancels a purchase and returns its units. The caller holds the listing's
-- lock. listing_after: 'available' (the seller relists), 'closed' (the seller
-- closes it), or null (a sold listing is available again, a closed one stays
-- closed).
create function public.cancel_purchase_hold(
  target_purchase uuid,
  by_whom text,
  why text,
  listing_after text default null
)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  p public.purchases;
begin
  select * into p from public.purchases as pu where pu.id = target_purchase for update;
  update public.purchases as pu
  set status = 'cancelled', cancelled_by = by_whom, cancel_reason = why
  where pu.id = p.id;

  update public.listings as l
  set stock = l.stock + p.qty,
      status = coalesce(listing_after, case when l.status = 'sold' then 'available' else l.status end)
  where l.id = p.listing_id;

  update public.deal_payments as dp
  set status = case when by_whom = 'system' then 'expired' else 'cancelled' end
  where dp.purchase_id = p.id and dp.status in ('awaiting_proof', 'submitted');
end;
$$;

-- Releases one listing's transfers with no receipt by the deadline. Cash,
-- and transfers with a receipt, are never released here. The caller holds
-- the listing's lock.
create function public.expire_unpaid_purchases(target_listing uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  r record;
  n integer := 0;
begin
  for r in
    select pu.id, pu.buyer_id, pu.seller_id, pu.qty, l.title
    from public.deal_payments as dp
    join public.purchases as pu on pu.id = dp.purchase_id
    join public.listings as l on l.id = pu.listing_id
    where pu.listing_id = target_listing
      and pu.status = 'awaiting_payment'
      and dp.status = 'awaiting_proof' and dp.due_at <= now()
    order by pu.id
  loop
    perform public.cancel_purchase_hold(r.id, 'system', 'No receipt was sent within 30 minutes.');
    perform public.notify(r.buyer_id, 'purchase_payment_expired', 'Payment time ran out',
      format('You didn''t send a receipt for %s × %s in time, so the purchase was cancelled.', r.qty, r.title),
      'purchase:' || r.id);
    perform public.notify(r.seller_id, 'purchase_payment_expired', 'Purchase cancelled: no payment',
      format('%s × %s went back on sale.', r.qty, r.title), 'purchase:' || r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

create or replace function public.expire_overdue_payments()
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  p record;
  n integer := 0;
begin
  for p in
    select distinct coalesce(o.campaign_id, o.listing_id, pu.listing_id) as target,
           o.campaign_id is not null as is_campaign,
           o.id is not null as is_order
    from public.deal_payments as dp
    left join public.orders as o on o.id = dp.order_id
    left join public.purchases as pu on pu.id = dp.purchase_id
    where dp.status = 'awaiting_proof' and dp.due_at <= now()
    limit 50
  loop
    if p.is_campaign then
      perform 1 from public.campaigns as c where c.id = p.target for update skip locked;
      if found then n := n + public.expire_unpaid_orders(null, p.target); end if;
    else
      perform 1 from public.listings as l where l.id = p.target for update skip locked;
      if found then
        if p.is_order then
          n := n + public.expire_unpaid_orders(p.target, null);
        else
          n := n + public.expire_unpaid_purchases(p.target);
        end if;
      end if;
    end if;
  end loop;
  return n;
end;
$$;

------------------------------------------------------------------------------
-- 7. Buying and selling
------------------------------------------------------------------------------

-- Confirm purchase: the units are the buyer's at once.
create function public.buy_item(listing_id uuid, qty integer default 1, payment_method text default 'cash')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  transfer boolean := buy_item.payment_method = 'transfer';
  listing public.listings;
  seller_active boolean;
  v_status text;
  v_total bigint;
  new_id uuid;
  v_payment uuid;
  v_due timestamptz;
begin
  -- 1. Caller and input
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to buy.');
  end if;
  if buy_item.qty is null or buy_item.qty not between 1 and 999 then
    perform public.raise_app_error('INVALID_INPUT', 'Buy between 1 and 999 units.');
  end if;
  if buy_item.payment_method is null or buy_item.payment_method not in ('cash', 'transfer') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose cash or transfer.');
  end if;

  -- 2. One purchase at a time per buyer, so two taps on two listings can't
  --    both pass the limits. (Not the profile row: two students buying from
  --    each other would deadlock on it.)
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('buy_item:' || uid::text, 0));
  if (select count(*) from public.purchases as pu
      where pu.buyer_id = uid and pu.created_at > now() - interval '1 hour') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve made a lot of purchases. Try again in an hour.');
  end if;

  -- 3. Lock the listing: everything below sees a stable stock
  select * into listing from public.listings as l where l.id = buy_item.listing_id for update;
  if not found or listing.status = 'draft' then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.mode <> 'personal' then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'Business products are ordered, not bought here.');
  end if;
  if listing.owner_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t buy your own listing.');
  end if;
  select p.account_status = 'active' into seller_active from public.profiles as p where p.id = listing.owner_id;
  if listing.hidden or not seller_active then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'This item is no longer available.');
  end if;
  if transfer and (public.payment_details_for(listing.owner_id, null)).id is null then
    perform public.raise_app_error('INVALID_INPUT', 'This seller takes cash on pickup only.');
  end if;

  -- 4. Free what overdue transfers hold, then decide
  if public.expire_unpaid_purchases(listing.id) > 0 then
    select * into listing from public.listings as l where l.id = listing.id;
  end if;
  if exists (select 1 from public.purchases as pu
             where pu.listing_id = listing.id and pu.buyer_id = uid
               and pu.status in ('awaiting_payment', 'awaiting_handover')) then
    perform public.raise_app_error('ALREADY_EXISTS', 'You already bought this item. See it under Purchases.');
  end if;
  if listing.status <> 'available' or listing.stock < buy_item.qty then
    perform public.raise_app_error('ITEM_UNAVAILABLE',
      case when listing.status = 'available' and listing.stock > 0 then format('Only %s left.', listing.stock)
           when listing.status = 'sold' then 'Sorry, this item has just been sold.'
           else 'This item is no longer available.' end);
  end if;
  if not transfer and (
    select count(*) from public.purchases as pu
    where pu.buyer_id = uid and pu.payment_method = 'cash' and pu.status = 'awaiting_handover'
  ) >= 3 then
    perform public.raise_app_error('RATE_LIMITED', 'Please complete your current purchases first.');
  end if;

  -- 5. Take the units and record the purchase (and a transfer's payment)
  update public.listings as l
  set stock = l.stock - buy_item.qty,
      status = case when l.stock - buy_item.qty = 0 then 'sold' else l.status end
  where l.id = listing.id;

  v_total := listing.price_sen::bigint * buy_item.qty;
  v_status := case when transfer then 'awaiting_payment' else 'awaiting_handover' end;
  insert into public.purchases (listing_id, buyer_id, seller_id, qty, unit_price_sen, total_sen, payment_method, status)
  values (listing.id, uid, listing.owner_id, buy_item.qty, listing.price_sen, v_total, buy_item.payment_method, v_status)
  returning id into new_id;

  if transfer then
    v_due := now() + interval '30 minutes';
    insert into public.deal_payments (purchase_id, buyer_id, seller_id, amount_sen, due_at)
    values (new_id, uid, listing.owner_id, v_total, v_due)
    returning id into v_payment;
  end if;

  perform public.notify(listing.owner_id, 'purchase_created',
    case when transfer then 'Item bought (paying by transfer)' else 'Item bought (cash on pickup)' end,
    format('%s × %s', buy_item.qty, listing.title), 'purchase:' || new_id);

  return jsonb_build_object('purchase_id', new_id, 'status', v_status, 'total_sen', v_total,
                            'payment_id', v_payment, 'payment_due_at', v_due);
end;
$$;

-- Loads a purchase the caller is part of, with its listing locked and
-- overdue transfers on it expired. Internal.
create function public.lock_purchase(target_purchase uuid)
returns public.purchases
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  p public.purchases;
begin
  select * into p from public.purchases as pu where pu.id = target_purchase;
  -- Strangers get the same answer as a missing purchase.
  if not found or uid is null or uid not in (p.buyer_id, p.seller_id) then
    perform public.raise_app_error('NOT_FOUND', 'Purchase not found.');
  end if;
  perform 1 from public.listings as l where l.id = p.listing_id for update;
  perform public.expire_unpaid_purchases(p.listing_id);
  select * into p from public.purchases as pu where pu.id = p.id for update;
  return p;
end;
$$;

-- The seller handed the item over.
create function public.complete_purchase(purchase_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  p public.purchases;
  v_title text;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  p := public.lock_purchase(complete_purchase.purchase_id);
  if auth.uid() <> p.seller_id then
    perform public.raise_app_error('FORBIDDEN', 'Only the seller can do that.');
  end if;
  if p.status = 'awaiting_payment' then
    perform public.raise_app_error('INVALID_TRANSITION', 'Check the buyer''s payment before completing the sale.');
  elsif p.status <> 'awaiting_handover' then
    perform public.raise_app_error('INVALID_TRANSITION', 'This purchase can no longer be changed.');
  end if;

  update public.purchases as pu set status = 'completed', completed_at = now() where pu.id = p.id;

  select l.title into v_title from public.listings as l where l.id = p.listing_id;
  perform public.notify(p.buyer_id, 'purchase_completed', 'Purchase completed',
    format('%s × %s', p.qty, v_title), 'purchase:' || p.id);

  return jsonb_build_object('purchase_id', p.id, 'status', 'completed');
end;
$$;

-- The buyer cancels until they've sent a receipt. The seller cancels with a
-- reason and chooses to relist or close the item.
create function public.cancel_purchase(purchase_id uuid, reason text default null, relist boolean default true)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_reason text := nullif(btrim(coalesce(cancel_purchase.reason, '')), '');
  p public.purchases;
  by_seller boolean;
  pay_status text;
  v_title text;
  v_listing_status text;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if cancel_purchase.relist is null or char_length(v_reason) > 200 then
    perform public.raise_app_error('INVALID_INPUT', 'Choose relist or close, with a reason of up to 200 characters.');
  end if;

  p := public.lock_purchase(cancel_purchase.purchase_id);
  by_seller := uid = p.seller_id;
  if by_seller and v_reason is null then
    perform public.raise_app_error('INVALID_INPUT', 'Say why you''re cancelling, so the buyer knows.');
  end if;
  if p.status not in ('awaiting_payment', 'awaiting_handover') then
    perform public.raise_app_error('INVALID_TRANSITION', 'This purchase can no longer be changed.');
  end if;
  select dp.status into pay_status from public.deal_payments as dp where dp.purchase_id = p.id for update;
  if not by_seller and pay_status in ('submitted', 'accepted') then
    perform public.raise_app_error('INVALID_TRANSITION',
      'You''ve sent your payment. Ask the seller to cancel and refund you.');
  end if;

  perform public.cancel_purchase_hold(p.id,
    case when by_seller then 'seller' else 'buyer' end,
    v_reason,
    case when not by_seller then null when cancel_purchase.relist then 'available' else 'closed' end);

  select l.title, l.status into v_title, v_listing_status from public.listings as l where l.id = p.listing_id;
  perform public.notify(case when by_seller then p.buyer_id else p.seller_id end, 'purchase_cancelled',
    'Purchase cancelled',
    format('%s × %s', p.qty, v_title) || coalesce(': ' || v_reason, '')
      || case when pay_status in ('submitted', 'accepted') then ' Any refund is arranged outside the app.' else '' end,
    'purchase:' || p.id);

  return jsonb_build_object('purchase_id', p.id, 'status', 'cancelled', 'listing_status', v_listing_status);
end;
$$;

-- A cash buyer didn't turn up: after 24 hours the seller may relist.
create function public.relist_purchase(purchase_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  p public.purchases;
  v_title text;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  p := public.lock_purchase(relist_purchase.purchase_id);
  if auth.uid() <> p.seller_id then
    perform public.raise_app_error('FORBIDDEN', 'Only the seller can do that.');
  end if;
  if p.status <> 'awaiting_handover' or p.payment_method <> 'cash' then
    perform public.raise_app_error('INVALID_TRANSITION', 'Only an uncollected cash purchase can be relisted.');
  end if;
  if now() < p.created_at + interval '24 hours' then
    perform public.raise_app_error('INVALID_TRANSITION', 'You can relist 24 hours after the purchase.');
  end if;

  perform public.cancel_purchase_hold(p.id, 'seller', 'The buyer didn''t collect the item.', 'available');

  select l.title into v_title from public.listings as l where l.id = p.listing_id;
  perform public.notify(p.buyer_id, 'purchase_cancelled', 'Purchase cancelled',
    format('You didn''t collect %s × %s, so the seller put it back on sale.', p.qty, v_title),
    'purchase:' || p.id);

  return jsonb_build_object('purchase_id', p.id, 'status', 'cancelled', 'listing_status', 'available');
end;
$$;

-- What Purchases shows. No emails: the two sides talk in the item chat.
create type public.purchase_card as (
  id uuid,
  listing_id uuid,
  listing_title text,
  listing_photo text,
  pickup_area text,
  qty integer,
  unit_price_sen integer,
  total_sen bigint,
  payment_method text,
  status text,
  cancelled_by text,
  cancel_reason text,
  relist_from timestamptz,
  created_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz,
  i_am_buyer boolean,
  other_party_name text,
  payment_id uuid,
  payment_status text,
  payment_due_at timestamptz,
  payment_reject_reason text
);

create function public.my_purchases(side text default 'buying', page_size integer default 50, page_offset integer default 0)
returns setof public.purchase_card
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if my_purchases.side is null or my_purchases.side not in ('buying', 'selling') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose buying or selling.');
  end if;
  if my_purchases.page_size is null or my_purchases.page_size not between 1 and 100
     or my_purchases.page_offset is null or my_purchases.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 100 purchases from a non-negative offset.');
  end if;

  perform public.expire_overdue_payments();

  return query
  select pu.id, pu.listing_id, l.title, l.photo_paths[1], l.pickup_area,
         pu.qty, pu.unit_price_sen, pu.total_sen, pu.payment_method, pu.status, pu.cancelled_by, pu.cancel_reason,
         case when pu.status = 'awaiting_handover' and pu.payment_method = 'cash'
              then pu.created_at + interval '24 hours' end,
         pu.created_at, pu.updated_at, pu.completed_at,
         pu.buyer_id = uid,
         p.name,
         dp.id, dp.status, dp.due_at, dp.reject_reason
  from public.purchases as pu
  join public.listings as l on l.id = pu.listing_id
  join public.profiles as p on p.id = case when pu.buyer_id = uid then pu.seller_id else pu.buyer_id end
  left join public.deal_payments as dp on dp.purchase_id = pu.id
  where case when my_purchases.side = 'buying' then pu.buyer_id = uid else pu.seller_id = uid end
  order by (pu.status in ('awaiting_payment', 'awaiting_handover')) desc, pu.created_at desc, pu.id
  limit my_purchases.page_size
  offset my_purchases.page_offset;
end;
$$;

------------------------------------------------------------------------------
-- 8. Functions that knew about reservations
------------------------------------------------------------------------------

-- Same as the pickup-pins version, without the reserved status.
create or replace function public.upsert_listing(
  listing_id uuid,
  title text,
  description text,
  category text,
  price_sen integer,
  condition text,
  quantity integer,
  photo_paths text[],
  pickup_area text,
  mode text default 'personal',
  pickup_lat double precision default null,
  pickup_lng double precision default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_id uuid := upsert_listing.listing_id;
  v_title text := btrim(coalesce(upsert_listing.title, ''));
  v_description text := btrim(coalesce(upsert_listing.description, ''));
  v_pickup text := btrim(coalesce(upsert_listing.pickup_area, ''));
  v_photos text[] := coalesce(upsert_listing.photo_paths, '{}');
  v_pin_problem text := public.pickup_pin_problem(upsert_listing.pickup_lat, upsert_listing.pickup_lng);
  v_mode text;
  v_business uuid;
  v_status text;
  existing public.listings;
  path text;
begin
  -- 1. Caller
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to sell.');
  end if;

  -- 2. The listing being edited, if any, locked; or the new listing's mode
  if v_id is not null then
    select * into existing from public.listings as l where l.id = v_id for update;
    if not found then
      perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
    end if;
    if existing.owner_id <> uid then
      perform public.raise_app_error('FORBIDDEN', 'You can only edit your own listings.');
    end if;
    -- The mode never changes; the parameter only matters when creating.
    v_mode := existing.mode;
    v_business := existing.business_id;
    if v_mode = 'business' and not public.owns_business(v_business) then
      perform public.raise_app_error('FORBIDDEN', 'Your business isn''t approved, so its products can''t be changed.');
    end if;
    if v_mode = 'personal' and existing.status = 'sold' then
      perform public.raise_app_error('INVALID_TRANSITION', 'A sold listing can''t be edited.');
    end if;
  else
    v_mode := coalesce(upsert_listing.mode, 'personal');
    if v_mode not in ('personal', 'business') then
      perform public.raise_app_error('INVALID_INPUT', 'Choose personal or business.');
    end if;
    if v_mode = 'business' then
      select b.id into v_business from public.businesses as b where b.owner_id = uid;
      if v_business is null or not public.owns_business(v_business) then
        perform public.raise_app_error('FORBIDDEN', 'Only approved businesses can list business products.');
      end if;
    end if;
    -- Abuse control: at most 20 new listings an hour.
    if (select count(*) from public.listings as l
        where l.owner_id = uid and l.created_at > now() - interval '1 hour') >= 20 then
      perform public.raise_app_error('RATE_LIMITED', 'You''ve created a lot of listings. Try again in an hour.');
    end if;
    v_id := gen_random_uuid();
  end if;

  -- 3. Input
  if char_length(v_title) not between 3 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'The title must be 3 to 80 characters.');
  end if;
  if char_length(v_description) > 1000 then
    perform public.raise_app_error('INVALID_INPUT', 'The description can be up to 1,000 characters.');
  end if;
  if upsert_listing.category is null or not (upsert_listing.category = any (public.listing_categories())) then
    perform public.raise_app_error('INVALID_INPUT', 'Choose one of the listed categories.');
  end if;
  if upsert_listing.price_sen is null or upsert_listing.price_sen not between 0 and 10000000 then
    perform public.raise_app_error('INVALID_INPUT', 'The price must be between RM 0 and RM 100,000.');
  end if;
  if upsert_listing.condition is null or upsert_listing.condition not in ('new', 'like_new', 'good', 'fair') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose the item''s condition.');
  end if;
  if upsert_listing.quantity is null or upsert_listing.quantity not between 1 and 999 then
    perform public.raise_app_error('INVALID_INPUT', 'The quantity must be 1 to 999.');
  end if;
  if char_length(v_pickup) not between 2 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'Give a campus pickup location (2 to 80 characters).');
  end if;
  if v_pin_problem is not null then
    perform public.raise_app_error('INVALID_INPUT', v_pin_problem);
  end if;
  if cardinality(v_photos) > 5 then
    perform public.raise_app_error('INVALID_INPUT', 'Add up to 5 photos.');
  end if;
  foreach path in array v_photos loop
    if path is null or path !~ ('^' || uid::text || '/' || v_id::text || '/[^/]+\.(jpe?g|png|webp)$') then
      perform public.raise_app_error('INVALID_INPUT', 'A photo isn''t one of this listing''s uploads.');
    end if;
  end loop;
  if existing.status is not null and existing.status <> 'draft' and cardinality(v_photos) = 0 then
    perform public.raise_app_error('INVALID_INPUT', 'A published listing needs at least one photo.');
  end if;

  -- 4. Write
  if existing.id is null then
    v_status := 'draft';
    insert into public.listings (
      id, owner_id, mode, business_id, title, normalized_title, description, category,
      price_sen, condition, photo_paths, stock, pickup_area, pickup_lat, pickup_lng, status
    ) values (
      v_id, uid, v_mode, v_business, v_title, public.normalize_text(v_title), v_description,
      upsert_listing.category, upsert_listing.price_sen, upsert_listing.condition,
      v_photos, upsert_listing.quantity, v_pickup, upsert_listing.pickup_lat, upsert_listing.pickup_lng, 'draft'
    );
  else
    -- Restocking a sold-out business product puts it back on sale.
    v_status := case when existing.mode = 'business' and existing.status = 'sold' then 'available'
                     else existing.status end;
    update public.listings as l set
      title = v_title,
      normalized_title = public.normalize_text(v_title),
      description = v_description,
      category = upsert_listing.category,
      price_sen = upsert_listing.price_sen,
      condition = upsert_listing.condition,
      stock = upsert_listing.quantity,
      photo_paths = v_photos,
      pickup_area = v_pickup,
      pickup_lat = upsert_listing.pickup_lat,
      pickup_lng = upsert_listing.pickup_lng,
      status = v_status
    where l.id = v_id;
  end if;

  return jsonb_build_object('listing_id', v_id, 'status', v_status);
end;
$$;

-- The owner publishes, closes, re-opens or marks sold. Closing and marking
-- sold affect only the units still for sale: purchases in progress carry on.
create or replace function public.set_listing_status(listing_id uuid, new_status text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  listing public.listings;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to sell.');
  end if;
  if new_status is null or new_status not in ('draft', 'available', 'sold', 'closed') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown listing status.');
  end if;

  select * into listing from public.listings as l where l.id = set_listing_status.listing_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id <> auth.uid() then
    perform public.raise_app_error('FORBIDDEN', 'You can only change your own listings.');
  end if;

  if public.expire_unpaid_purchases(listing.id) > 0 then
    select * into listing from public.listings as l where l.id = listing.id;
  end if;

  if (listing.status, new_status) not in (
    ('draft', 'available'), ('draft', 'closed'),
    ('available', 'closed'), ('available', 'sold'),
    ('closed', 'available')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This listing is %s, so it can''t be changed to %s.', listing.status, new_status));
  end if;
  if new_status = 'available' and cardinality(listing.photo_paths) = 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Add at least one photo before publishing.');
  end if;

  update public.listings as l set
    status = new_status,
    -- Marking sold means every remaining unit went (sold outside the app).
    stock = case when new_status = 'sold' then 0 else l.stock end
  where l.id = listing.id;

  return jsonb_build_object('listing_id', listing.id, 'status', new_status);
end;
$$;

-- Same as ADR 0005; only the message for personal items changes.
create or replace function public.place_order(
  listing_id uuid,
  qty integer default 1,
  campaign_id uuid default null,
  buyer_note text default null,
  payment_method text default 'cash'
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(place_order.buyer_note, '')), '');
  transfer boolean := place_order.payment_method = 'transfer';
  listing public.listings;
  business public.businesses;
  campaign public.campaigns;
  owner_active boolean;
  v_price integer;
  v_collection text;
  v_total bigint;
  new_id uuid;
  v_payment uuid;
  v_due timestamptz;
begin
  -- 1. Caller and input
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to order.');
  end if;
  if place_order.qty is null or place_order.qty not between 1 and 999 then
    perform public.raise_app_error('INVALID_INPUT', 'Order between 1 and 999 units.');
  end if;
  if char_length(v_note) > 200 then
    perform public.raise_app_error('INVALID_INPUT', 'The note can be up to 200 characters.');
  end if;
  if place_order.payment_method is null or place_order.payment_method not in ('cash', 'transfer') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose cash or transfer.');
  end if;
  if (select count(*) from public.orders as o
      where o.buyer_id = uid and o.created_at > now() - interval '1 hour') >= 20 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve placed a lot of orders. Try again in an hour.');
  end if;

  -- 2. Lock what the order takes from: the campaign (pre-order) or the
  --    listing (ready stock). Free what overdue unpaid orders hold. Everything
  --    below sees a stable quantity.
  if place_order.campaign_id is not null then
    select * into campaign from public.campaigns as c where c.id = place_order.campaign_id for update;
    if not found or campaign.status = 'draft' then
      perform public.raise_app_error('NOT_FOUND', 'Pre-order not found.');
    end if;
    if campaign.listing_id <> place_order.listing_id then
      perform public.raise_app_error('INVALID_INPUT', 'That pre-order is for another product.');
    end if;
    if public.expire_unpaid_orders(null, campaign.id) > 0 then
      select * into campaign from public.campaigns as c where c.id = campaign.id;
    end if;
    select * into listing from public.listings as l where l.id = campaign.listing_id;
  else
    select * into listing from public.listings as l where l.id = place_order.listing_id for update;
    if found and public.expire_unpaid_orders(listing.id, null) > 0 then
      select * into listing from public.listings as l where l.id = listing.id;
    end if;
  end if;
  if listing.id is null or listing.status = 'draft' then
    perform public.raise_app_error('NOT_FOUND', 'Product not found.');
  end if;
  if listing.mode <> 'business' then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'Personal items are bought with Buy now, not ordered.');
  end if;

  select * into business from public.businesses as b where b.id = listing.business_id;
  if business.owner_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t order from your own business.');
  end if;
  select p.account_status = 'active' into owner_active from public.profiles as p where p.id = business.owner_id;
  if listing.hidden or business.status <> 'approved' or not owner_active then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'This product is no longer available.');
  end if;
  if transfer and (public.payment_details_for(business.owner_id, business.id)).id is null then
    perform public.raise_app_error('INVALID_INPUT', 'This business takes cash on pickup only.');
  end if;

  -- 3. Decide and take the quantity
  if campaign.id is not null then
    if campaign.status <> 'open' or now() >= campaign.close_at then
      perform public.raise_app_error('INVALID_TRANSITION', 'This pre-order is closed.');
    end if;
    if now() < campaign.start_at then
      perform public.raise_app_error('INVALID_TRANSITION',
        format('Pre-orders open on %s.', to_char(campaign.start_at at time zone 'Asia/Kuala_Lumpur', 'FMDD Mon YYYY, FMHH12:MI AM')));
    end if;
    if campaign.per_order_limit is not null and place_order.qty > campaign.per_order_limit then
      perform public.raise_app_error('INVALID_INPUT', format('You can pre-order up to %s per order.', campaign.per_order_limit));
    end if;
    if campaign.allocated_qty + place_order.qty > campaign.capacity then
      perform public.raise_app_error('CAPACITY_FULL',
        case when campaign.allocated_qty < campaign.capacity
             then format('Only %s left in this pre-order.', campaign.capacity - campaign.allocated_qty)
             else 'This pre-order is full.' end);
    end if;
    update public.campaigns as c set allocated_qty = c.allocated_qty + place_order.qty where c.id = campaign.id;
    v_price := campaign.price_sen;
    v_collection := campaign.pickup_details;
  else
    if listing.status <> 'available' or listing.stock < place_order.qty then
      perform public.raise_app_error('ITEM_UNAVAILABLE',
        case when listing.status = 'available' and listing.stock > 0
             then format('Only %s left.', listing.stock)
             else 'This product is sold out.' end);
    end if;
    update public.listings as l
    set stock = l.stock - place_order.qty,
        status = case when l.stock - place_order.qty = 0 then 'sold' else l.status end
    where l.id = listing.id;
    v_price := listing.price_sen;
    v_collection := business.pickup_details;
  end if;

  -- 4. Record the order (prices and pickup details are snapshots) and, for a
  --    transfer, its payment with a 30-minute deadline for the proof.
  v_total := v_price::bigint * place_order.qty;
  insert into public.orders (buyer_id, business_id, listing_id, campaign_id, qty, unit_price_sen, total_sen,
                             status, buyer_note, collection_details)
  values (uid, business.id, listing.id, campaign.id, place_order.qty, v_price, v_total,
          'pending_confirmation', v_note, v_collection)
  returning id into new_id;

  if transfer then
    v_due := now() + interval '30 minutes';
    insert into public.deal_payments (order_id, buyer_id, seller_id, business_id, amount_sen, due_at)
    values (new_id, uid, business.owner_id, business.id, v_total, v_due)
    returning id into v_payment;
  end if;

  perform public.notify(business.owner_id, 'order_placed',
    case when campaign.id is null then 'New order' else 'New pre-order' end
      || case when transfer then ' (paying by transfer)' else '' end,
    format('%s × %s', place_order.qty, coalesce(campaign.title, listing.title)), 'order:' || new_id);

  return jsonb_build_object('order_id', new_id, 'status', 'pending_confirmation', 'total_sen', v_total,
                            'payment_id', v_payment, 'payment_due_at', v_due);
end;
$$;

-- The payment functions, with purchases in place of reservations.
create or replace function public.lock_payment(target_payment uuid)
returns public.deal_payments
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  pay public.deal_payments;
  o public.orders;
  v_listing uuid;
begin
  select * into pay from public.deal_payments as dp where dp.id = target_payment;
  if pay.order_id is not null then
    select * into o from public.orders as ord where ord.id = pay.order_id;
    if o.campaign_id is not null then
      perform 1 from public.campaigns as c where c.id = o.campaign_id for update;
      perform public.expire_unpaid_orders(null, o.campaign_id);
    else
      perform 1 from public.listings as l where l.id = o.listing_id for update;
      perform public.expire_unpaid_orders(o.listing_id, null);
    end if;
    perform 1 from public.orders as ord where ord.id = o.id for update;
  else
    select pu.listing_id into v_listing from public.purchases as pu where pu.id = pay.purchase_id;
    perform 1 from public.listings as l where l.id = v_listing for update;
    perform public.expire_unpaid_purchases(v_listing);
    perform 1 from public.purchases as pu where pu.id = pay.purchase_id for update;
  end if;
  select * into pay from public.deal_payments as dp where dp.id = target_payment for update;
  return pay;
end;
$$;

create or replace function public.get_payment(payment_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  pay public.deal_payments;
  details public.payment_details;
  v_title text;
  v_qty integer;
  v_deal_status text;
  v_seller text;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  perform public.expire_overdue_payments();

  select * into pay from public.deal_payments as dp where dp.id = get_payment.payment_id;
  -- Strangers get the same answer as a missing payment.
  if not found or uid not in (pay.buyer_id, pay.seller_id) then
    perform public.raise_app_error('NOT_FOUND', 'Payment not found.');
  end if;

  if pay.order_id is not null then
    select coalesce(c.title, l.title), o.qty, o.status, b.name
    into v_title, v_qty, v_deal_status, v_seller
    from public.orders as o
    join public.listings as l on l.id = o.listing_id
    join public.businesses as b on b.id = o.business_id
    left join public.campaigns as c on c.id = o.campaign_id
    where o.id = pay.order_id;
  else
    select l.title, pu.qty, pu.status, p.name
    into v_title, v_qty, v_deal_status, v_seller
    from public.purchases as pu
    join public.listings as l on l.id = pu.listing_id
    join public.profiles as p on p.id = pu.seller_id
    where pu.id = pay.purchase_id;
  end if;

  if uid = pay.buyer_id and pay.status in ('awaiting_proof', 'submitted') then
    details := public.payment_details_for(pay.seller_id, pay.business_id);
  end if;

  return jsonb_build_object(
    'payment_id', pay.id,
    'order_id', pay.order_id,
    'purchase_id', pay.purchase_id,
    'i_am_buyer', uid = pay.buyer_id,
    'item_title', v_title,
    'qty', v_qty,
    'deal_status', v_deal_status,
    'seller_name', v_seller,
    'amount_sen', pay.amount_sen,
    'status', pay.status,
    'due_at', pay.due_at,
    'proof_path', pay.proof_path,
    'submitted_at', pay.submitted_at,
    'decided_at', pay.decided_at,
    'reject_reason', pay.reject_reason,
    'pay_to', case when details.id is null then null else jsonb_build_object(
      'bank_name', details.bank_name,
      'account_name', details.account_name,
      'account_number', details.account_number,
      'qr_path', details.qr_path) end
  );
end;
$$;

-- The buyer sends the receipt before the deadline. The units then wait for
-- the seller, however long that takes.
create or replace function public.submit_payment_proof(payment_id uuid, proof_path text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  pay public.deal_payments;
  v_path text := nullif(btrim(coalesce(submit_payment_proof.proof_path, '')), '');
  v_title text;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  select * into pay from public.deal_payments as dp where dp.id = submit_payment_proof.payment_id;
  if not found or uid not in (pay.buyer_id, pay.seller_id) then
    perform public.raise_app_error('NOT_FOUND', 'Payment not found.');
  end if;
  if uid <> pay.buyer_id then
    perform public.raise_app_error('FORBIDDEN', 'Only the buyer sends payment proof.');
  end if;
  if v_path is null
     or split_part(v_path, '/', 1) <> uid::text
     or split_part(v_path, '/', 2) <> pay.id::text
     or not exists (select 1 from storage.objects as o where o.bucket_id = 'payment-proofs' and o.name = v_path) then
    perform public.raise_app_error('INVALID_INPUT', 'Upload a photo of your payment first.');
  end if;

  pay := public.lock_payment(pay.id);
  if pay.status = 'expired' then
    perform public.raise_app_error('INVALID_TRANSITION', 'The 30 minutes to pay have run out, so the item went back on sale.');
  end if;
  if pay.status <> 'awaiting_proof' then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This payment is %s, so proof can''t be sent now.', replace(pay.status, '_', ' ')));
  end if;

  update public.deal_payments as dp
  set status = 'submitted', proof_path = v_path, submitted_at = now()
  where dp.id = pay.id;
  if pay.purchase_id is not null then
    select l.title into v_title from public.purchases as pu join public.listings as l on l.id = pu.listing_id
    where pu.id = pay.purchase_id;
  else
    select coalesce(c.title, l.title) into v_title
    from public.orders as o join public.listings as l on l.id = o.listing_id
    left join public.campaigns as c on c.id = o.campaign_id where o.id = pay.order_id;
  end if;

  perform public.notify(pay.seller_id, 'payment_submitted', 'Payment proof received',
    format('Check your bank for %s, then accept or reject the payment for %s.',
           'RM ' || to_char(pay.amount_sen / 100.0, 'FM999999990.00'), v_title),
    coalesce('order:' || pay.order_id, 'purchase:' || pay.purchase_id));

  return jsonb_build_object('payment_id', pay.id, 'status', 'submitted');
end;
$$;

-- The seller accepts (the order is confirmed / the purchase awaits handover)
-- or rejects with a reason (cancelled, units back on sale).
create or replace function public.review_payment(payment_id uuid, accept boolean, reason text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  pay public.deal_payments;
  v_reason text := nullif(btrim(coalesce(review_payment.reason, '')), '');
  v_title text;
  v_deal_status text;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if review_payment.accept is null then
    perform public.raise_app_error('INVALID_INPUT', 'Accept or reject the payment.');
  end if;
  if not review_payment.accept and (v_reason is null or char_length(v_reason) > 200) then
    perform public.raise_app_error('INVALID_INPUT', 'Say why you''re rejecting the payment (up to 200 characters).');
  end if;

  select * into pay from public.deal_payments as dp where dp.id = review_payment.payment_id;
  if not found or uid not in (pay.buyer_id, pay.seller_id) then
    perform public.raise_app_error('NOT_FOUND', 'Payment not found.');
  end if;
  if uid <> pay.seller_id then
    perform public.raise_app_error('FORBIDDEN', 'Only the seller checks the payment.');
  end if;
  if pay.business_id is not null and not public.owns_business(pay.business_id) then
    perform public.raise_app_error('FORBIDDEN', 'Your business isn''t approved, so it can''t progress orders.');
  end if;

  pay := public.lock_payment(pay.id);
  if pay.status <> 'submitted' then
    perform public.raise_app_error('INVALID_TRANSITION',
      case when pay.status = 'awaiting_proof' then 'The buyer hasn''t sent payment proof yet.'
           else format('This payment is already %s.', replace(pay.status, '_', ' ')) end);
  end if;

  update public.deal_payments as dp
  set status = case when review_payment.accept then 'accepted' else 'rejected' end,
      reject_reason = case when review_payment.accept then null else v_reason end,
      decided_at = now()
  where dp.id = pay.id;

  if pay.order_id is not null then
    select coalesce(c.title, l.title) into v_title
    from public.orders as o join public.listings as l on l.id = o.listing_id
    left join public.campaigns as c on c.id = o.campaign_id where o.id = pay.order_id;
    if review_payment.accept then
      update public.orders as o set status = 'confirmed' where o.id = pay.order_id and o.status = 'pending_confirmation';
      v_deal_status := 'confirmed';
    else
      perform public.cancel_order_hold(pay.order_id, 'seller');
      v_deal_status := 'cancelled';
    end if;
  else
    select l.title into v_title
    from public.purchases as pu join public.listings as l on l.id = pu.listing_id
    where pu.id = pay.purchase_id;
    if review_payment.accept then
      update public.purchases as pu set status = 'awaiting_handover'
      where pu.id = pay.purchase_id and pu.status = 'awaiting_payment';
      v_deal_status := 'awaiting_handover';
    else
      perform public.cancel_purchase_hold(pay.purchase_id, 'seller', v_reason);
      v_deal_status := 'cancelled';
    end if;
  end if;

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, case when review_payment.accept then 'payment.accepted' else 'payment.rejected' end,
          'deal_payment', pay.id::text,
          jsonb_strip_nulls(jsonb_build_object('order_id', pay.order_id, 'purchase_id', pay.purchase_id,
                                               'reason', case when review_payment.accept then null else v_reason end)));

  perform public.notify(pay.buyer_id,
    case when review_payment.accept then 'payment_accepted' else 'payment_rejected' end,
    case when review_payment.accept then 'Payment accepted' else 'Payment rejected' end,
    case when review_payment.accept then format('The seller confirmed your payment for %s.', v_title)
         else format('The seller rejected your payment for %s: %s', v_title, v_reason) end,
    coalesce('order:' || pay.order_id, 'purchase:' || pay.purchase_id));

  return jsonb_build_object('payment_id', pay.id,
                            'status', case when review_payment.accept then 'accepted' else 'rejected' end,
                            'deal_status', v_deal_status);
end;
$$;

------------------------------------------------------------------------------
-- 9. Chat: about an item (no hold), or a confirmed order (as before)
------------------------------------------------------------------------------

-- True when the student bought the item and may still need the seller: any
-- purchase that wasn't cancelled, or a cancelled one they'd sent money for.
create function public.has_bought_item(target_listing uuid, student uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.purchases as pu
    where pu.listing_id = target_listing and pu.buyer_id = student
      and (pu.status <> 'cancelled'
           or exists (select 1 from public.deal_payments as dp
                      where dp.purchase_id = pu.id and dp.submitted_at is not null)));
$$;

create or replace function public.conversation_can_send(c public.conversations)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select c.closed_at is null
    and not exists (
      select 1 from public.profiles as p
      where p.id in (c.buyer_id, c.seller_id) and p.account_status <> 'active')
    and case
    when c.order_id is null then
      exists (select 1 from public.listings as l
              where l.id = c.listing_id and l.status = 'available' and not l.hidden)
      or public.has_bought_item(c.listing_id, c.buyer_id)
    else exists (
      select 1 from public.orders as o
      join public.businesses as b on b.id = o.business_id
      where o.id = c.order_id
        and o.status in ('confirmed', 'preparing', 'ready_for_pickup')
        and b.status = 'approved')
  end;
$$;

drop function public.my_conversations(integer, integer);
drop function public.get_conversation(uuid);
drop function public.conversation_cards(uuid);
drop type public.conversation_card;

create type public.conversation_card as (
  conversation_id uuid,
  kind text,                -- 'item' or 'order'
  order_id uuid,
  listing_id uuid,
  listing_title text,
  listing_photo text,
  other_party_name text,
  i_am_buyer boolean,
  last_message text,
  last_message_at timestamptz,
  last_message_mine boolean,
  unread_count integer,
  can_send boolean,
  closed boolean,
  created_at timestamptz
);

create function public.conversation_cards(uid uuid)
returns setof public.conversation_card
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         case when c.order_id is null then 'item' else 'order' end,
         c.order_id, c.listing_id, l.title, l.photo_paths[1],
         p.name,
         c.buyer_id = uid,
         last.body, c.last_message_at, last.sender_id = uid,
         (select count(*)::integer from public.messages as m
          where m.conversation_id = c.id and m.sender_id <> uid
            and m.id > case when c.buyer_id = uid then c.buyer_last_read_id else c.seller_last_read_id end),
         public.conversation_can_send(c),
         c.closed_at is not null,
         c.created_at
  from public.conversations as c
  join public.listings as l on l.id = c.listing_id
  join public.profiles as p on p.id = case when c.buyer_id = uid then c.seller_id else c.buyer_id end
  left join lateral (
    select m.body, m.sender_id from public.messages as m
    where m.conversation_id = c.id order by m.id desc limit 1
  ) as last on true
  where uid in (c.buyer_id, c.seller_id);
$$;

-- The caller's chats, newest activity first. A seller isn't shown an item
-- chat that a student opened and never wrote in.
create function public.my_conversations(page_size integer default 30, page_offset integer default 0)
returns setof public.conversation_card
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if my_conversations.page_size is null or my_conversations.page_size not between 1 and 100
     or my_conversations.page_offset is null or my_conversations.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 100 chats from a non-negative offset.');
  end if;

  return query
  select * from public.conversation_cards(auth.uid()) as card
  where card.kind = 'order' or card.i_am_buyer or card.last_message_at is not null
  order by coalesce(card.last_message_at, card.created_at) desc, card.conversation_id
  limit my_conversations.page_size
  offset my_conversations.page_offset;
end;
$$;

-- One chat's header (title, the other person, whether it can send).
create function public.get_conversation(conversation_id uuid)
returns public.conversation_card
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  card public.conversation_card;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  select * into card from public.conversation_cards(auth.uid()) as c
  where c.conversation_id = get_conversation.conversation_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Chat not found.');
  end if;
  return card;
end;
$$;

drop function public.open_conversation(uuid, uuid);

-- Returns one chat, creating it when allowed:
--   listing_id   a student asks about an available personal item, or one
--                they bought. The student is the buyer side.
--   purchase_id  either side of a purchase: that item's chat.
--   order_id     either side of a confirmed business order, as before.
-- An existing chat is returned whatever its state, so history stays readable.
create function public.open_conversation(
  listing_id uuid default null,
  order_id uuid default null,
  purchase_id uuid default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  existing uuid;
  listing public.listings;
  v_listing uuid;
  v_buyer uuid;
  v_seller uuid;
  v_active boolean;
  new_id uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if num_nonnulls(open_conversation.listing_id, open_conversation.order_id, open_conversation.purchase_id) <> 1 then
    perform public.raise_app_error('INVALID_INPUT', 'Open a chat for one item, purchase or order.');
  end if;

  if open_conversation.order_id is not null then
    select o.listing_id, o.buyer_id, b.owner_id,
           o.status in ('confirmed', 'preparing', 'ready_for_pickup') and b.status = 'approved'
    into v_listing, v_buyer, v_seller, v_active
    from public.orders as o join public.businesses as b on b.id = o.business_id
    where o.id = open_conversation.order_id;
    if v_buyer is null or uid not in (v_buyer, v_seller) then
      perform public.raise_app_error('NOT_FOUND', 'Order not found.');
    end if;
  elsif open_conversation.purchase_id is not null then
    select pu.listing_id, pu.buyer_id, pu.seller_id
    into v_listing, v_buyer, v_seller
    from public.purchases as pu where pu.id = open_conversation.purchase_id;
    if v_buyer is null or uid not in (v_buyer, v_seller) then
      perform public.raise_app_error('NOT_FOUND', 'Purchase not found.');
    end if;
    v_active := public.has_bought_item(v_listing, v_buyer)
      or exists (select 1 from public.listings as l
                 where l.id = v_listing and l.status = 'available' and not l.hidden);
  else
    select * into listing from public.listings as l where l.id = open_conversation.listing_id;
    if not found or listing.status = 'draft' then
      perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
    end if;
    if listing.owner_id = uid then
      perform public.raise_app_error('FORBIDDEN', 'You can''t start a chat on your own listing.');
    end if;
    if listing.mode <> 'personal' then
      perform public.raise_app_error('INVALID_INPUT', 'Chat with a business opens once it confirms your order.');
    end if;
    v_listing := listing.id;
    v_buyer := uid;
    v_seller := listing.owner_id;
    v_active := (listing.status = 'available' and not listing.hidden
                 and exists (select 1 from public.profiles as p
                             where p.id = listing.owner_id and p.account_status = 'active'))
      or public.has_bought_item(listing.id, uid);
  end if;

  if open_conversation.order_id is not null then
    select c.id into existing from public.conversations as c where c.order_id = open_conversation.order_id;
  else
    select c.id into existing from public.conversations as c
    where c.order_id is null and c.listing_id = v_listing and c.buyer_id = v_buyer;
  end if;
  if existing is not null then
    return jsonb_build_object('conversation_id', existing, 'created', false);
  end if;

  if not v_active then
    if open_conversation.order_id is not null then
      perform public.raise_app_error('INVALID_TRANSITION', 'Chat opens once the business confirms the order.');
    end if;
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'This item is no longer available.');
  end if;
  -- Asking about items is open to every student, so limit how many strangers
  -- one account can write to.
  if open_conversation.listing_id is not null and (
    select count(*) from public.conversations as c
    where c.buyer_id = uid and c.order_id is null and c.created_at > now() - interval '1 day'
  ) >= 20 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve started a lot of chats today. Try again tomorrow.');
  end if;

  insert into public.conversations (order_id, listing_id, buyer_id, seller_id)
  values (open_conversation.order_id, v_listing, v_buyer, v_seller)
  on conflict do nothing
  returning id into new_id;

  if new_id is null then
    -- Opened twice at the same moment.
    select c.id into new_id from public.conversations as c
    where c.order_id is not distinct from open_conversation.order_id
      and c.listing_id = v_listing and c.buyer_id = v_buyer;
    return jsonb_build_object('conversation_id', new_id, 'created', false);
  end if;
  return jsonb_build_object('conversation_id', new_id, 'created', true);
end;
$$;

create or replace function public.send_message(conversation_id uuid, body text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_body text := btrim(coalesce(send_message.body, ''));
  conv public.conversations;
  new_id bigint;
  sent_at timestamptz;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if v_body = '' or char_length(v_body) > 1000 then
    perform public.raise_app_error('INVALID_INPUT', 'Write a message of up to 1,000 characters.');
  end if;

  -- The lock orders messages and read markers per conversation.
  conv := public.participant_conversation(send_message.conversation_id, true);
  if conv.closed_at is not null then
    perform public.raise_app_error('INVALID_TRANSITION', 'This chat was closed.');
  end if;
  if not public.conversation_can_send(conv) then
    perform public.raise_app_error('INVALID_TRANSITION', case when conv.order_id is null then 'This chat is read-only because the item is no longer available.'
           else 'This chat is read-only because the order has ended.' end);
  end if;
  if (select count(*) from public.messages as m
      where m.sender_id = uid and m.created_at > now() - interval '1 minute') >= 20 then
    perform public.raise_app_error('RATE_LIMITED', 'You''re sending messages very fast. Wait a moment.');
  end if;

  insert into public.messages (conversation_id, sender_id, body)
  values (conv.id, uid, v_body)
  returning id, created_at into new_id, sent_at;

  update public.conversations as c
  set last_message_at = sent_at,
      buyer_last_read_id = case when c.buyer_id = uid then new_id else c.buyer_last_read_id end,
      seller_last_read_id = case when c.seller_id = uid then new_id else c.seller_last_read_id end
  where c.id = conv.id;

  return jsonb_build_object('message_id', new_id, 'created_at', sent_at);
end;
$$;

------------------------------------------------------------------------------
-- 10. Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.purchases enable row level security;

-- Written only by the functions above.
revoke all on public.purchases from anon, authenticated;
grant select on public.purchases to authenticated;

create policy "Buyers and sellers see their purchases; admins see all"
  on public.purchases for select to authenticated
  using (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()) or (select public.is_admin()));

revoke execute on function
  public.cancel_purchase_hold(uuid, text, text, text),
  public.expire_unpaid_purchases(uuid),
  public.lock_purchase(uuid),
  public.has_bought_item(uuid, uuid),
  public.conversation_cards(uuid)
from public, anon, authenticated;

revoke execute on function
  public.buy_item(uuid, integer, text),
  public.complete_purchase(uuid),
  public.cancel_purchase(uuid, text, boolean),
  public.relist_purchase(uuid),
  public.my_purchases(text, integer, integer),
  public.my_conversations(integer, integer),
  public.get_conversation(uuid),
  public.open_conversation(uuid, uuid, uuid)
from public, anon;

grant execute on function
  public.buy_item(uuid, integer, text),
  public.complete_purchase(uuid),
  public.cancel_purchase(uuid, text, boolean),
  public.relist_purchase(uuid),
  public.my_purchases(text, integer, integer),
  public.my_conversations(integer, integer),
  public.get_conversation(uuid),
  public.open_conversation(uuid, uuid, uuid)
to authenticated;
