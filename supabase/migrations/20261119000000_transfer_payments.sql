-- Pay by bank transfer or QR, with payment proof (ADR 0005).
-- See docs/data-dictionary.md ("payment_details", "deal_payments") and
-- docs/api-contracts.md ("Transfer payments").
--
-- No money moves through CampusNiaga. A seller saves a bank account and/or a
-- QR code; a buyer who chooses "transfer" pays in their own banking app,
-- uploads a screenshot as proof, and the seller checks their own bank and
-- accepts or rejects it. The app never claims a payment happened: it records
-- what the seller decided.
--
-- How the item is held:
--   * Ordering or reserving takes the units at once, as before (row lock on
--     the listing or campaign). A transfer deal also gets a deal_payments row
--     with a 30-minute deadline for the proof.
--   * No proof by the deadline: the order is cancelled (cancelled_by
--     'system') or the reservation expires, and the units go back on sale.
--   * Proof sent: the hold stays until the seller decides. Accepting confirms
--     the order / accepts the reservation; rejecting cancels / declines it
--     and returns the units.
--   * Expiry is lazy, like reservations. A listing's or campaign's overdue
--     payments are expired whenever it is locked to change; read functions
--     (search, listing, storefront, My Orders, Bookings, the payment page)
--     sweep every overdue payment first, skipping rows another transaction
--     holds (for update skip locked), so a read never waits and never
--     deadlocks.
--   * Lock order stays listing (or campaign), then reservation or order, then
--     payment.

------------------------------------------------------------------------------
-- Orders can now be cancelled by the system (payment time ran out)
------------------------------------------------------------------------------

alter table public.orders drop constraint orders_cancelled_by_check;
alter table public.orders add constraint orders_cancelled_by_check
  check (cancelled_by in ('buyer', 'seller', 'system'));

------------------------------------------------------------------------------
-- A seller's payment details: one set per student, and optionally one for
-- their business (used for its orders instead of the student's)
------------------------------------------------------------------------------

create table public.payment_details (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles (id) on delete cascade,
  business_id uuid unique references public.businesses (id) on delete cascade,
  bank_name text check (bank_name is null or char_length(bank_name) between 2 and 60),
  account_name text check (account_name is null or char_length(account_name) between 2 and 80),
  account_number text check (account_number is null or account_number ~ '^[0-9]{6,20}$'),
  qr_path text check (qr_path is null or char_length(qr_path) <= 300),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(profile_id, business_id) = 1),
  -- The bank fields go together; a QR code alone is enough.
  check (num_nonnulls(bank_name, account_name, account_number) in (0, 3)),
  check (account_number is not null or qr_path is not null)
);

create trigger payment_details_set_updated_at
  before update on public.payment_details
  for each row execute function public.set_updated_at();

-- The details a buyer pays: the business's own for a business order, else
-- the seller's. Internal: callers check who may see them.
create function public.payment_details_for(seller uuid, business uuid)
returns public.payment_details
language sql
stable
security definer
set search_path = ''
as $$
  select pd.*
  from public.payment_details as pd
  where (business is not null and pd.business_id = business) or pd.profile_id = seller
  order by (pd.business_id is not null) desc
  limit 1;
$$;

-- Saves (or, with neither an account number nor a QR code, removes) the
-- caller's details, or their approved business's when for_business.
create function public.set_payment_details(
  for_business boolean,
  bank_name text default null,
  account_name text default null,
  account_number text default null,
  qr_path text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_bank text := nullif(btrim(coalesce(set_payment_details.bank_name, '')), '');
  v_name text := nullif(btrim(coalesce(set_payment_details.account_name, '')), '');
  -- Spaces and dashes are how people write account numbers; store digits.
  v_number text := nullif(regexp_replace(coalesce(set_payment_details.account_number, ''), '[\s-]', '', 'g'), '');
  v_qr text := nullif(btrim(coalesce(set_payment_details.qr_path, '')), '');
  v_business uuid;
begin
  -- 1. Caller
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if coalesce(set_payment_details.for_business, false) then
    select b.id into v_business from public.businesses as b where b.owner_id = uid;
    if v_business is null or not public.owns_business(v_business) then
      perform public.raise_app_error('FORBIDDEN', 'Only an approved business can save business payment details.');
    end if;
  end if;

  -- 2. Input
  if num_nonnulls(v_bank, v_name, v_number) not in (0, 3) then
    perform public.raise_app_error('INVALID_INPUT',
      'Give the bank, the account holder''s name and the account number together.');
  end if;
  if v_number is not null and v_number !~ '^[0-9]{6,20}$' then
    perform public.raise_app_error('INVALID_INPUT', 'An account number has 6 to 20 digits.');
  end if;
  if char_length(v_bank) not between 2 and 60 then
    perform public.raise_app_error('INVALID_INPUT', 'The bank name is 2 to 60 characters.');
  end if;
  if char_length(v_name) not between 2 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'The account holder''s name is 2 to 80 characters.');
  end if;
  -- The QR image must be the caller's own upload (no pointing at someone
  -- else's file).
  if v_qr is not null and (
       split_part(v_qr, '/', 1) <> uid::text
       or not exists (select 1 from storage.objects as o where o.bucket_id = 'payment-qr' and o.name = v_qr)) then
    perform public.raise_app_error('INVALID_INPUT', 'Upload the QR code image first.');
  end if;

  -- 3. Remove, or save
  if v_number is null and v_qr is null then
    delete from public.payment_details as pd
    where (v_business is null and pd.profile_id = uid) or (v_business is not null and pd.business_id = v_business);
    return jsonb_build_object('saved', false);
  end if;

  if v_business is null then
    insert into public.payment_details (profile_id, bank_name, account_name, account_number, qr_path)
    values (uid, v_bank, v_name, v_number, v_qr)
    on conflict (profile_id) do update
      set bank_name = excluded.bank_name, account_name = excluded.account_name,
          account_number = excluded.account_number, qr_path = excluded.qr_path;
  else
    insert into public.payment_details (business_id, bank_name, account_name, account_number, qr_path)
    values (v_business, v_bank, v_name, v_number, v_qr)
    on conflict (business_id) do update
      set bank_name = excluded.bank_name, account_name = excluded.account_name,
          account_number = excluded.account_number, qr_path = excluded.qr_path;
  end if;
  return jsonb_build_object('saved', true);
end;
$$;

------------------------------------------------------------------------------
-- Payments on deals: one per transfer order or reservation (cash deals have
-- none)
------------------------------------------------------------------------------

create table public.deal_payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid unique references public.orders (id) on delete cascade,
  reservation_id uuid unique references public.reservations (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  -- Set for business orders, so their own payment details are used.
  business_id uuid references public.businesses (id) on delete cascade,
  amount_sen bigint not null check (amount_sen >= 0),
  status text not null default 'awaiting_proof'
    check (status in ('awaiting_proof', 'submitted', 'accepted', 'rejected', 'expired', 'cancelled')),
  due_at timestamptz not null,
  proof_path text check (proof_path is null or char_length(proof_path) <= 300),
  submitted_at timestamptz,
  decided_at timestamptz,
  reject_reason text check (reject_reason is null or char_length(reject_reason) between 1 and 200),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(order_id, reservation_id) = 1),
  check (buyer_id <> seller_id),
  check (status not in ('submitted', 'accepted', 'rejected') or (proof_path is not null and submitted_at is not null)),
  check ((status in ('accepted', 'rejected')) = (decided_at is not null)),
  check ((status = 'rejected') = (reject_reason is not null))
);

create trigger deal_payments_set_updated_at
  before update on public.deal_payments
  for each row execute function public.set_updated_at();

create index deal_payments_overdue_idx on public.deal_payments (due_at) where status = 'awaiting_proof';
create index deal_payments_buyer_idx on public.deal_payments (buyer_id, created_at desc);
create index deal_payments_seller_idx on public.deal_payments (seller_id, created_at desc);

------------------------------------------------------------------------------
-- Releasing holds
------------------------------------------------------------------------------

-- Cancels an order and returns its quantity. The caller holds the lock on
-- the order's campaign (pre-order) or listing (ready stock). A payment still
-- waiting is closed: 'expired' when the system cancels, else 'cancelled'.
create function public.cancel_order_hold(target_order uuid, by_whom text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  o public.orders;
begin
  select * into o from public.orders as ord where ord.id = target_order for update;
  update public.orders as ord
  set status = 'cancelled', completed_at = null, cancelled_by = by_whom
  where ord.id = o.id;

  if o.campaign_id is not null then
    update public.campaigns as c set allocated_qty = c.allocated_qty - o.qty where c.id = o.campaign_id;
  else
    update public.listings as l
    set stock = l.stock + o.qty,
        status = case when l.status = 'sold' then 'available' else l.status end
    where l.id = o.listing_id;
  end if;

  update public.deal_payments as dp
  set status = case when by_whom = 'system' then 'expired' else 'cancelled' end
  where dp.order_id = o.id and dp.status in ('awaiting_proof', 'submitted');
end;
$$;

-- Cancels the overdue unpaid orders of one ready-stock listing (campaign
-- null) or one campaign. The caller holds that row's lock.
create function public.expire_unpaid_orders(target_listing uuid, target_campaign uuid)
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
    select o.id, o.buyer_id, o.qty, b.owner_id, coalesce(c.title, l.title) as title
    from public.deal_payments as dp
    join public.orders as o on o.id = dp.order_id
    join public.businesses as b on b.id = o.business_id
    join public.listings as l on l.id = o.listing_id
    left join public.campaigns as c on c.id = o.campaign_id
    where dp.status = 'awaiting_proof' and dp.due_at <= now()
      and o.status = 'pending_confirmation'
      and ((target_campaign is not null and o.campaign_id = target_campaign)
           or (target_campaign is null and o.campaign_id is null and o.listing_id = target_listing))
    order by o.id
  loop
    perform public.cancel_order_hold(r.id, 'system');
    perform public.notify(r.buyer_id, 'order_payment_expired', 'Payment time ran out',
      format('You didn''t send proof for %s × %s in time, so the order was cancelled.', r.qty, r.title),
      'order:' || r.id);
    perform public.notify(r.owner_id, 'order_payment_expired', 'Order cancelled: no payment',
      format('%s × %s went back on sale.', r.qty, r.title), 'order:' || r.id);
    n := n + 1;
  end loop;
  return n;
end;
$$;

-- Same as Phase 2, and it closes the reservation's payment too, telling the
-- buyer why. The caller holds the listing's row lock.
create or replace function public.expire_listing_reservations(target_listing uuid)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  returned integer;
  r record;
  pay_status text;
begin
  returned := 0;
  for r in
    update public.reservations as rv
    set status = 'expired'
    where rv.listing_id = target_listing
      and rv.status in ('requested', 'accepted')
      and rv.expires_at <= now()
    returning rv.id, rv.qty, rv.buyer_id, rv.seller_id
  loop
    returned := returned + r.qty;
    select dp.status into pay_status from public.deal_payments as dp where dp.reservation_id = r.id for update;
    if pay_status in ('awaiting_proof', 'submitted') then
      update public.deal_payments as dp set status = 'expired' where dp.reservation_id = r.id;
    end if;

    if pay_status = 'awaiting_proof' then
      perform public.notify(r.buyer_id, 'reservation_payment_expired', 'Payment time ran out',
        'You didn''t send your payment proof in time, so the item went back on sale.', 'reservation:' || r.id);
    elsif pay_status = 'submitted' then
      perform public.notify(r.buyer_id, 'reservation_expired', 'Reservation expired',
        'The seller didn''t check your payment in time. Contact them about a refund.', 'reservation:' || r.id);
      perform public.notify(r.seller_id, 'reservation_expired', 'Reservation expired',
        'You didn''t check a buyer''s payment in time. Refund them if they paid.', 'reservation:' || r.id);
    else
      perform public.notify(r.buyer_id, 'reservation_expired', 'Reservation expired',
        'A reservation of yours expired before pickup.', 'reservation:' || r.id);
    end if;
  end loop;

  if returned > 0 then
    update public.listings as l
    set stock = l.stock + returned,
        status = case when l.status = 'reserved' then 'available' else l.status end
    where l.id = target_listing;
  end if;
  return returned;
end;
$$;

-- Expires every overdue unpaid payment, for read functions to call first.
-- It never waits: a listing or campaign another transaction holds is
-- skipped (that transaction expires it itself, or the next read does).
create function public.expire_overdue_payments()
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
    select distinct coalesce(o.campaign_id, o.listing_id, rv.listing_id) as target,
           o.campaign_id is not null as is_campaign,
           o.id is not null as is_order
    from public.deal_payments as dp
    left join public.orders as o on o.id = dp.order_id
    left join public.reservations as rv on rv.id = dp.reservation_id
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
          n := n + public.expire_listing_reservations(p.target);
        end if;
      end if;
    end if;
  end loop;
  return n;
end;
$$;

------------------------------------------------------------------------------
-- Reservations: choose cash or transfer
------------------------------------------------------------------------------

drop function public.request_reservation(uuid, integer, text);

-- Same as Phase 2, plus payment_method. A transfer reservation has 30
-- minutes for the proof instead of the seller's 48 hours to respond.
create function public.request_reservation(
  listing_id uuid,
  qty integer default 1,
  pickup_note text default null,
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
  note text := nullif(btrim(coalesce(request_reservation.pickup_note, '')), '');
  listing public.listings;
  seller_active boolean;
  new_id uuid;
  v_payment uuid;
  transfer boolean := request_reservation.payment_method = 'transfer';
  deadline timestamptz;
begin
  -- 1. Caller
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to reserve.');
  end if;

  -- 2. Input
  if request_reservation.qty is null or request_reservation.qty not between 1 and 999 then
    perform public.raise_app_error('INVALID_INPUT', 'Reserve between 1 and 999 units.');
  end if;
  if char_length(note) > 200 then
    perform public.raise_app_error('INVALID_INPUT', 'The pickup note can be up to 200 characters.');
  end if;
  if request_reservation.payment_method is null or request_reservation.payment_method not in ('cash', 'transfer') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose cash or transfer.');
  end if;
  if (select count(*) from public.reservations as rv
      where rv.buyer_id = uid and rv.created_at > now() - interval '1 hour') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve made a lot of reservations. Try again in an hour.');
  end if;

  -- 3. Lock the listing: everything below sees a stable stock
  select * into listing from public.listings as l where l.id = request_reservation.listing_id for update;
  if not found or listing.status = 'draft' then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t reserve your own listing.');
  end if;
  select p.account_status = 'active' into seller_active from public.profiles as p where p.id = listing.owner_id;
  if listing.hidden or not seller_active then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'This item is no longer available.');
  end if;
  if transfer and (public.payment_details_for(listing.owner_id, null)).id is null then
    perform public.raise_app_error('INVALID_INPUT', 'This seller takes cash on pickup only.');
  end if;

  -- 4. Free units held by overdue reservations, then decide
  if public.expire_listing_reservations(listing.id) > 0 then
    select * into listing from public.listings as l where l.id = listing.id;
  end if;
  if exists (select 1 from public.reservations as rv
             where rv.listing_id = listing.id and rv.buyer_id = uid and rv.status in ('requested', 'accepted')) then
    perform public.raise_app_error('ALREADY_EXISTS', 'You already have a reservation for this item.');
  end if;
  if listing.status <> 'available' or listing.stock < request_reservation.qty then
    perform public.raise_app_error('ITEM_UNAVAILABLE',
      case when listing.status = 'available' and listing.stock > 0
           then format('Only %s left.', listing.stock)
           else 'This item is no longer available.' end);
  end if;

  -- 5. Hold the units and record the request (and its payment)
  update public.listings as l
  set stock = l.stock - request_reservation.qty,
      status = case when l.stock - request_reservation.qty = 0 then 'reserved' else l.status end
  where l.id = listing.id;

  deadline := now() + case when transfer then interval '30 minutes' else interval '48 hours' end;
  insert into public.reservations (listing_id, buyer_id, seller_id, qty, pickup_note, status, expires_at)
  values (listing.id, uid, listing.owner_id, request_reservation.qty, note, 'requested', deadline)
  returning id into new_id;

  if transfer then
    insert into public.deal_payments (reservation_id, buyer_id, seller_id, amount_sen, due_at)
    values (new_id, uid, listing.owner_id, listing.price_sen::bigint * request_reservation.qty, deadline)
    returning id into v_payment;
  end if;

  perform public.notify(listing.owner_id, 'reservation_requested',
    case when transfer then 'New reservation (paying by transfer)' else 'New reservation request' end,
    format('Someone wants %s × %s.', request_reservation.qty, listing.title), 'reservation:' || new_id);

  return jsonb_build_object('reservation_id', new_id, 'status', 'requested', 'expires_at', deadline,
                            'payment_id', v_payment);
end;
$$;

-- Same as Phase 2, with the payment rules: a transfer reservation is
-- accepted by accepting its payment (review_payment), and a buyer who has
-- sent proof can't cancel (the seller cancels and refunds).
create or replace function public.resolve_reservation(reservation_id uuid, action text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  rv public.reservations;
  listing public.listings;
  pay public.deal_payments;
  new_status text;
  listing_status text;
  other uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if action is null or action not in ('accept', 'decline', 'cancel', 'collect') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown action.');
  end if;

  select * into rv from public.reservations as r where r.id = resolve_reservation.reservation_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Reservation not found.');
  end if;
  if uid not in (rv.buyer_id, rv.seller_id) then
    perform public.raise_app_error('FORBIDDEN', 'This isn''t your reservation.');
  end if;

  -- Lock listing, then reservation, then payment; expire overdue ones; re-read.
  select * into listing from public.listings as l where l.id = rv.listing_id for update;
  perform public.expire_listing_reservations(listing.id);
  select * into rv from public.reservations as r where r.id = rv.id for update;
  select * into pay from public.deal_payments as dp where dp.reservation_id = rv.id for update;

  if action in ('accept', 'decline', 'collect') and uid <> rv.seller_id then
    perform public.raise_app_error('FORBIDDEN', 'Only the seller can do that.');
  end if;
  if rv.status = 'expired' then
    perform public.raise_app_error('INVALID_TRANSITION', 'This reservation has expired.');
  end if;
  if action = 'accept' and pay.id is not null then
    perform public.raise_app_error('INVALID_TRANSITION',
      'The buyer is paying by transfer. Check their payment proof to accept.');
  end if;
  if action = 'cancel' and uid = rv.buyer_id and pay.status in ('submitted', 'accepted') then
    perform public.raise_app_error('INVALID_TRANSITION',
      'You''ve sent your payment. Ask the seller to cancel and refund you.');
  end if;
  if (action, rv.status) not in (
    ('accept', 'requested'), ('decline', 'requested'),
    ('cancel', 'requested'), ('cancel', 'accepted'),
    ('collect', 'accepted')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This reservation is %s, so it can''t be %s.', rv.status,
        case action when 'accept' then 'accepted' when 'decline' then 'declined'
                    when 'cancel' then 'cancelled' else 'collected' end));
  end if;

  new_status := case action when 'accept' then 'accepted' when 'decline' then 'declined'
                            when 'cancel' then 'cancelled' else 'collected' end;

  update public.reservations as r
  set status = new_status,
      -- An accepted reservation has a week for pickup.
      expires_at = case when new_status = 'accepted' then now() + interval '7 days'
                        when new_status in ('declined', 'cancelled', 'collected') then null
                        else r.expires_at end
  where r.id = rv.id;

  if new_status in ('declined', 'cancelled') then
    -- Units go back on sale; a payment still open is closed.
    update public.listings as l
    set stock = l.stock + rv.qty,
        status = case when l.status = 'reserved' then 'available' else l.status end
    where l.id = listing.id;
    update public.deal_payments as dp set status = 'cancelled'
    where dp.id = pay.id and dp.status in ('awaiting_proof', 'submitted');
  elsif new_status = 'collected' then
    -- Sold out once nothing is left and nobody else is waiting.
    update public.listings as l
    set status = 'sold'
    where l.id = listing.id
      and l.stock = 0
      and not exists (select 1 from public.reservations as r
                      where r.listing_id = l.id and r.status in ('requested', 'accepted'));
  end if;

  select l.status into listing_status from public.listings as l where l.id = listing.id;

  other := case when uid = rv.buyer_id then rv.seller_id else rv.buyer_id end;
  perform public.notify(other, 'reservation_' || new_status,
    case new_status when 'accepted' then 'Reservation accepted'
                    when 'declined' then 'Reservation declined'
                    when 'cancelled' then 'Reservation cancelled'
                    else 'Marked as collected' end,
    format('%s × %s', rv.qty, listing.title), 'reservation:' || rv.id);

  return jsonb_build_object('reservation_id', rv.id, 'status', new_status, 'listing_status', listing_status);
end;
$$;

------------------------------------------------------------------------------
-- Orders: choose cash or transfer
------------------------------------------------------------------------------

drop function public.place_order(uuid, integer, uuid, text);

-- Same as Phase 4, plus payment_method; overdue unpaid orders on the same
-- stock are expired first.
create function public.place_order(
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
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'Personal items are reserved, not ordered.');
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

-- Same as Phase 4, with the payment rules: a transfer order is confirmed by
-- accepting its payment (review_payment), and a buyer who has sent proof
-- can't cancel (the business cancels and refunds).
create or replace function public.transition_order(order_id uuid, action text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  o public.orders;
  business public.businesses;
  pay public.deal_payments;
  item_title text;
  new_status text;
  other uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  new_status := case transition_order.action
    when 'confirm' then 'confirmed'
    when 'prepare' then 'preparing'
    when 'ready' then 'ready_for_pickup'
    when 'complete' then 'completed'
    when 'cancel' then 'cancelled'
  end;
  if new_status is null then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown action.');
  end if;

  select * into o from public.orders as ord where ord.id = transition_order.order_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Order not found.');
  end if;
  select * into business from public.businesses as b where b.id = o.business_id;
  if uid not in (o.buyer_id, business.owner_id) then
    perform public.raise_app_error('FORBIDDEN', 'This isn''t your order.');
  end if;

  -- Lock what the order holds, expire overdue unpaid orders on it, then lock
  -- the order and its payment; re-read.
  if o.campaign_id is not null then
    perform 1 from public.campaigns as c where c.id = o.campaign_id for update;
    perform public.expire_unpaid_orders(null, o.campaign_id);
  else
    perform 1 from public.listings as l where l.id = o.listing_id for update;
    perform public.expire_unpaid_orders(o.listing_id, null);
  end if;
  select * into o from public.orders as ord where ord.id = o.id for update;
  select * into pay from public.deal_payments as dp where dp.order_id = o.id for update;

  if new_status <> 'cancelled' then
    if uid <> business.owner_id then
      perform public.raise_app_error('FORBIDDEN', 'Only the seller can do that.');
    end if;
    if not public.owns_business(business.id) then
      perform public.raise_app_error('FORBIDDEN', 'Your business isn''t approved, so it can''t progress orders.');
    end if;
  end if;
  if not ((o.status, new_status) in (
            ('pending_confirmation', 'confirmed'),
            ('confirmed', 'preparing'),
            ('preparing', 'ready_for_pickup'),
            ('ready_for_pickup', 'completed'))
          or (new_status = 'cancelled' and o.status not in ('completed', 'cancelled'))) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This order is %s, so it can''t be %s.', replace(o.status, '_', ' '), replace(new_status, '_', ' ')));
  end if;
  if new_status = 'confirmed' and pay.id is not null then
    perform public.raise_app_error('INVALID_TRANSITION',
      'The buyer is paying by transfer. Check their payment proof to confirm.');
  end if;
  if new_status = 'cancelled' and uid = o.buyer_id and pay.status in ('submitted', 'accepted') then
    perform public.raise_app_error('INVALID_TRANSITION',
      'You''ve sent your payment. Ask the business to cancel and refund you.');
  end if;

  if new_status = 'cancelled' then
    perform public.cancel_order_hold(o.id, case when uid = o.buyer_id then 'buyer' else 'seller' end);
  else
    update public.orders as ord
    set status = new_status,
        completed_at = case when new_status = 'completed' then now() end
    where ord.id = o.id;
  end if;

  select coalesce(c.title, l.title) into item_title
  from public.listings as l left join public.campaigns as c on c.id = o.campaign_id
  where l.id = o.listing_id;
  other := case when uid = o.buyer_id then business.owner_id else o.buyer_id end;
  perform public.notify(other, 'order_' || new_status,
    case new_status
      when 'confirmed' then 'Order confirmed'
      when 'preparing' then 'Order being prepared'
      when 'ready_for_pickup' then 'Order ready for pickup'
      when 'completed' then 'Order completed'
      else 'Order cancelled'
    end,
    format('%s × %s', o.qty, item_title), 'order:' || o.id);

  return jsonb_build_object('order_id', o.id, 'status', new_status);
end;
$$;

------------------------------------------------------------------------------
-- The payment itself: the buyer's page, sending proof, the seller's decision
------------------------------------------------------------------------------

-- Locks what a payment's deal holds (listing or campaign), expires overdue
-- payments on it, then locks the payment and returns it. Internal.
create function public.lock_payment(target_payment uuid)
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
    select rv.listing_id into v_listing from public.reservations as rv where rv.id = pay.reservation_id;
    perform 1 from public.listings as l where l.id = v_listing for update;
    perform public.expire_listing_reservations(v_listing);
    perform 1 from public.reservations as rv where rv.id = pay.reservation_id for update;
  end if;
  select * into pay from public.deal_payments as dp where dp.id = target_payment for update;
  return pay;
end;
$$;

-- What the payment page shows. The buyer sees where to pay while the
-- payment is open; the seller sees the proof.
create function public.get_payment(payment_id uuid)
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
    select l.title, rv.qty, rv.status, p.name
    into v_title, v_qty, v_deal_status, v_seller
    from public.reservations as rv
    join public.listings as l on l.id = rv.listing_id
    join public.profiles as p on p.id = rv.seller_id
    where rv.id = pay.reservation_id;
  end if;

  if uid = pay.buyer_id and pay.status in ('awaiting_proof', 'submitted') then
    details := public.payment_details_for(pay.seller_id, pay.business_id);
  end if;

  return jsonb_build_object(
    'payment_id', pay.id,
    'order_id', pay.order_id,
    'reservation_id', pay.reservation_id,
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

-- The buyer sends the proof they uploaded (payment-proofs/{buyer}/{payment}/…)
-- before the deadline. The hold then stays until the seller decides
-- (a reservation gets 7 days).
create function public.submit_payment_proof(payment_id uuid, proof_path text)
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
  if pay.reservation_id is not null then
    update public.reservations as rv set expires_at = now() + interval '7 days' where rv.id = pay.reservation_id;
    select l.title into v_title from public.reservations as rv join public.listings as l on l.id = rv.listing_id
    where rv.id = pay.reservation_id;
  else
    select coalesce(c.title, l.title) into v_title
    from public.orders as o join public.listings as l on l.id = o.listing_id
    left join public.campaigns as c on c.id = o.campaign_id where o.id = pay.order_id;
  end if;

  perform public.notify(pay.seller_id, 'payment_submitted', 'Payment proof received',
    format('Check your bank for %s, then accept or reject the payment for %s.',
           'RM ' || to_char(pay.amount_sen / 100.0, 'FM999999990.00'), v_title),
    coalesce('order:' || pay.order_id, 'reservation:' || pay.reservation_id));

  return jsonb_build_object('payment_id', pay.id, 'status', 'submitted');
end;
$$;

-- The seller accepts (the order is confirmed / the reservation accepted) or
-- rejects with a reason (cancelled / declined, units back on sale).
create function public.review_payment(payment_id uuid, accept boolean, reason text default null)
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
  rv public.reservations;
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
    select * into rv from public.reservations as r where r.id = pay.reservation_id;
    select l.title into v_title from public.listings as l where l.id = rv.listing_id;
    if review_payment.accept then
      update public.reservations as r set status = 'accepted', expires_at = now() + interval '7 days'
      where r.id = rv.id;
      v_deal_status := 'accepted';
    else
      update public.reservations as r set status = 'declined', expires_at = null where r.id = rv.id;
      update public.listings as l
      set stock = l.stock + rv.qty,
          status = case when l.status = 'reserved' then 'available' else l.status end
      where l.id = rv.listing_id;
      v_deal_status := 'declined';
    end if;
  end if;

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, case when review_payment.accept then 'payment.accepted' else 'payment.rejected' end,
          'deal_payment', pay.id::text,
          jsonb_strip_nulls(jsonb_build_object('order_id', pay.order_id, 'reservation_id', pay.reservation_id,
                                               'reason', case when review_payment.accept then null else v_reason end)));

  perform public.notify(pay.buyer_id,
    case when review_payment.accept then 'payment_accepted' else 'payment_rejected' end,
    case when review_payment.accept then 'Payment accepted' else 'Payment rejected' end,
    case when review_payment.accept then format('The seller confirmed your payment for %s.', v_title)
         else format('The seller rejected your payment for %s: %s', v_title, v_reason) end,
    coalesce('order:' || pay.order_id, 'reservation:' || pay.reservation_id));

  return jsonb_build_object('payment_id', pay.id,
                            'status', case when review_payment.accept then 'accepted' else 'rejected' end,
                            'deal_status', v_deal_status);
end;
$$;

-- Whether a buyer can choose transfer for a listing (without seeing the
-- details themselves).
create function public.seller_accepts_transfer(listing_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  listing public.listings;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to browse.');
  end if;
  select * into listing from public.listings as l
  where l.id = seller_accepts_transfer.listing_id and l.status <> 'draft' and not l.hidden;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  return (public.payment_details_for(listing.owner_id, listing.business_id)).id is not null;
end;
$$;

------------------------------------------------------------------------------
-- My Orders and Bookings show the payment
------------------------------------------------------------------------------

alter type public.reservation_card
  add attribute payment_id uuid,
  add attribute payment_status text,
  add attribute payment_due_at timestamptz,
  add attribute payment_reject_reason text;

alter type public.order_card
  add attribute payment_id uuid,
  add attribute payment_status text,
  add attribute payment_due_at timestamptz,
  add attribute payment_reject_reason text;

-- Same as Phase 2, plus the payment; overdue payments are swept first, and
-- the per-user expiry skips listings another transaction holds.
create or replace function public.my_reservations(side text default 'buying')
returns setof public.reservation_card
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  stale uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if side is null or side not in ('buying', 'selling') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose buying or selling.');
  end if;

  perform public.expire_overdue_payments();
  -- Lazy expiry for the listings this user is involved with.
  for stale in
    select distinct rv.listing_id from public.reservations as rv
    where (rv.buyer_id = uid or rv.seller_id = uid)
      and rv.status in ('requested', 'accepted') and rv.expires_at <= now()
  loop
    perform 1 from public.listings as l where l.id = stale for update skip locked;
    if found then
      perform public.expire_listing_reservations(stale);
    end if;
  end loop;

  return query
  select rv.id, rv.listing_id, l.title, l.photo_paths[1], l.pickup_area, l.price_sen,
         rv.qty, rv.pickup_note, rv.status, rv.expires_at, rv.created_at, rv.updated_at,
         rv.buyer_id = uid,
         p.name,
         case when rv.status in ('accepted', 'collected') then p.email end,
         dp.id, dp.status, dp.due_at, dp.reject_reason
  from public.reservations as rv
  join public.listings as l on l.id = rv.listing_id
  join public.profiles as p on p.id = case when rv.buyer_id = uid then rv.seller_id else rv.buyer_id end
  left join public.deal_payments as dp on dp.reservation_id = rv.id
  where case when side = 'buying' then rv.buyer_id = uid else rv.seller_id = uid end
  order by (rv.status in ('requested', 'accepted')) desc, rv.created_at desc;
end;
$$;

-- Same as Phase 6, plus the payment; overdue payments are swept first.
create or replace function public.my_orders(side text default 'buying', page_size integer default 50, page_offset integer default 0)
returns setof public.order_card
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
  if my_orders.side is null or my_orders.side not in ('buying', 'selling') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose buying or selling.');
  end if;
  if my_orders.page_size is null or my_orders.page_size not between 1 and 100
     or my_orders.page_offset is null or my_orders.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 100 orders from a non-negative offset.');
  end if;

  perform public.expire_overdue_payments();

  return query
  select o.id, o.listing_id, l.title, l.photo_paths[1], o.business_id, b.name, o.campaign_id, c.title,
         o.qty, o.unit_price_sen, o.total_sen, o.status, o.buyer_note, o.collection_details, o.cancelled_by,
         o.created_at, o.updated_at, o.completed_at,
         o.buyer_id = uid,
         p.name,
         case when o.status in ('confirmed', 'preparing', 'ready_for_pickup', 'completed') then p.email end,
         case when my_orders.side = 'selling' then o.cost_sen end,
         dp.id, dp.status, dp.due_at, dp.reject_reason
  from public.orders as o
  join public.listings as l on l.id = o.listing_id
  join public.businesses as b on b.id = o.business_id
  left join public.campaigns as c on c.id = o.campaign_id
  join public.profiles as p on p.id = case when my_orders.side = 'buying' then b.owner_id else o.buyer_id end
  left join public.deal_payments as dp on dp.order_id = o.id
  where case when my_orders.side = 'buying' then o.buyer_id = uid else b.owner_id = uid end
  order by (o.status not in ('completed', 'cancelled')) desc, o.created_at desc, o.id
  limit my_orders.page_size
  offset my_orders.page_offset;
end;
$$;

------------------------------------------------------------------------------
-- Browsing sweeps overdue payments first, so held units come back on sale
------------------------------------------------------------------------------

-- Same as the pickup-pins version; volatile, and it sweeps first.
create or replace function public.search_listings(
  search text default null,
  category text default null,
  condition text default null,
  min_price_sen integer default null,
  max_price_sen integer default null,
  sort text default 'newest',
  page_size integer default 20,
  page_offset integer default 0
)
returns setof public.listing_card
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  ts_query tsquery;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to browse.');
  end if;
  if search_listings.sort is null or search_listings.sort not in ('newest', 'price_asc', 'price_desc', 'relevance') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown sort order.');
  end if;
  if search_listings.page_size is null or search_listings.page_size not between 1 and 50
     or search_listings.page_offset is null or search_listings.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 50 results from a non-negative offset.');
  end if;
  if nullif(btrim(search_listings.search), '') is not null then
    ts_query := websearch_to_tsquery('english'::regconfig, search_listings.search);
  end if;

  perform public.expire_overdue_payments();

  return query
  select l.id, l.owner_id, p.name, l.mode, l.title, l.description, l.category,
         l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at,
         b.id, b.name, l.pickup_lat, l.pickup_lng
  from public.listings as l
  join public.profiles as p on p.id = l.owner_id and p.account_status = 'active'
  left join public.businesses as b on b.id = l.business_id
  where l.status = 'available'
    and not l.hidden
    and (l.business_id is null or b.status = 'approved')
    and (ts_query is null or l.search_vector @@ ts_query)
    and (search_listings.category is null or l.category = search_listings.category)
    and (search_listings.condition is null or l.condition = search_listings.condition)
    and (search_listings.min_price_sen is null or l.price_sen >= search_listings.min_price_sen)
    and (search_listings.max_price_sen is null or l.price_sen <= search_listings.max_price_sen)
  order by
    case when search_listings.sort = 'relevance' and ts_query is not null then ts_rank(l.search_vector, ts_query) end desc nulls last,
    case when search_listings.sort = 'price_asc' then l.price_sen end asc,
    case when search_listings.sort = 'price_desc' then l.price_sen end desc,
    l.created_at desc,
    l.id
  limit search_listings.page_size
  offset search_listings.page_offset;
end;
$$;

-- Same as the pickup-pins version; volatile, and it sweeps first.
create or replace function public.get_listing(listing_id uuid)
returns setof public.listing_card
language plpgsql
volatile
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
  student boolean := public.is_student();
  admin boolean := public.is_admin();
begin
  if not student and not admin then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to browse.');
  end if;

  perform public.expire_overdue_payments();

  return query
  select l.id, l.owner_id, p.name, l.mode, l.title, l.description, l.category,
         l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at,
         b.id, b.name, l.pickup_lat, l.pickup_lng
  from public.listings as l
  join public.profiles as p on p.id = l.owner_id
  left join public.businesses as b on b.id = l.business_id
  where l.id = get_listing.listing_id
    and (
      l.owner_id = uid
      or admin
      or (student and l.status <> 'draft' and not l.hidden and p.account_status = 'active'
          and (l.business_id is null or b.status = 'approved'))
    );

  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
end;
$$;

-- Same as the pickup-pins version; volatile, and it sweeps first.
create or replace function public.get_storefront(business_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  admin boolean := public.is_admin();
  business public.businesses;
  owner_name text;
  owner_active boolean;
  v_listings jsonb;
  v_campaigns jsonb;
  v_categories jsonb;
begin
  if not public.is_student() and not admin then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to browse.');
  end if;

  perform public.expire_overdue_payments();

  select * into business from public.businesses as b where b.id = get_storefront.business_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Business not found.');
  end if;
  select p.name, p.account_status = 'active' into owner_name, owner_active
  from public.profiles as p where p.id = business.owner_id;
  -- Suspended businesses (or owners) disappear for everyone else.
  if (business.status <> 'approved' or not owner_active) and business.owner_id <> uid and not admin then
    perform public.raise_app_error('NOT_FOUND', 'Business not found.');
  end if;

  select coalesce(jsonb_agg(to_jsonb(card) order by card.created_at desc), '[]'::jsonb),
         coalesce(jsonb_agg(distinct card.category), '[]'::jsonb)
  into v_listings, v_categories
  from (
    select l.id, l.owner_id, owner_name as seller_name, l.mode, l.title, l.description, l.category,
           l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at,
           business.id as business_id, business.name as business_name, l.pickup_lat, l.pickup_lng
    from public.listings as l
    where l.business_id = business.id and l.status = 'available' and not l.hidden
    order by l.created_at desc
    limit 50
  ) as card;

  select coalesce(jsonb_agg(jsonb_build_object(
           'campaign_id', c.id,
           'listing_id', c.listing_id,
           'listing_title', l.title,
           'listing_photo', l.photo_paths[1],
           'title', c.title,
           'price_sen', c.price_sen,
           'start_at', c.start_at,
           'close_at', c.close_at,
           'capacity', c.capacity,
           'allocated_qty', c.allocated_qty,
           'remaining', c.capacity - c.allocated_qty,
           'per_order_limit', c.per_order_limit,
           'pickup_details', c.pickup_details,
           'status', c.status
         ) order by c.close_at), '[]'::jsonb)
  into v_campaigns
  from public.campaigns as c
  join public.listings as l on l.id = c.listing_id
  where c.business_id = business.id
    and c.status = 'open'
    and c.close_at > now()
    and not l.hidden;

  return jsonb_build_object(
    'business', jsonb_build_object(
      'business_id', business.id,
      'name', business.name,
      'description', business.description,
      'logo_path', business.logo_path,
      'pickup_details', business.pickup_details,
      'pickup_lat', business.pickup_lat,
      'pickup_lng', business.pickup_lng,
      'status', business.status,
      'owner_name', owner_name
    ),
    'is_owner', business.owner_id = uid,
    'categories', v_categories,
    'listings', v_listings,
    'campaigns', v_campaigns
  );
end;
$$;

------------------------------------------------------------------------------
-- Storage: payment-qr/{owner_id}/{file} and
-- payment-proofs/{buyer_id}/{payment_id}/{file}, both private
------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types) values
  ('payment-qr', 'payment-qr', false, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('payment-proofs', 'payment-proofs', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']);

-- QR code: its owner, and a buyer whose payment to that seller is open.
create function public.can_read_payment_qr(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select split_part(object_name, '/', 1) = auth.uid()::text
    or exists (
      select 1 from public.deal_payments as dp
      where dp.buyer_id = auth.uid()
        and dp.status in ('awaiting_proof', 'submitted')
        and (public.payment_details_for(dp.seller_id, dp.business_id)).qr_path = object_name
    );
$$;

-- Proof upload: the buyer, into their open payment's folder, up to 3 files.
create function public.can_upload_payment_proof(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_student()
    and coalesce(array_length(string_to_array(object_name, '/'), 1), 0) = 3
    and exists (
      select 1 from public.deal_payments as dp
      where dp.buyer_id = auth.uid()
        and dp.buyer_id::text = split_part(object_name, '/', 1)
        and dp.id::text = split_part(object_name, '/', 2)
        and dp.status = 'awaiting_proof'
        and dp.due_at > now()
    )
    and (select count(*) from storage.objects as o
         where o.bucket_id = 'payment-proofs'
           and o.name like split_part(object_name, '/', 1) || '/' || split_part(object_name, '/', 2) || '/%') < 3;
$$;

-- Proof read: the buyer and the seller of that payment, and admins.
create function public.can_read_payment_proof(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.deal_payments as dp
    where dp.buyer_id::text = split_part(object_name, '/', 1)
      and dp.id::text = split_part(object_name, '/', 2)
      and (dp.buyer_id = auth.uid() or dp.seller_id = auth.uid() or public.is_admin())
  );
$$;

-- Proof delete: the buyer, before sending it.
create function public.can_delete_payment_proof(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.deal_payments as dp
    where dp.buyer_id = auth.uid()
      and dp.buyer_id::text = split_part(object_name, '/', 1)
      and dp.id::text = split_part(object_name, '/', 2)
      and dp.status = 'awaiting_proof'
  );
$$;

create policy "Students upload their own payment QR code"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'payment-qr' and (select public.is_student())
              and coalesce(array_length(string_to_array(name, '/'), 1), 0) = 2
              and split_part(name, '/', 1) = (select auth.uid())::text);

create policy "Owners and paying buyers read a payment QR code"
  on storage.objects for select to authenticated
  using (bucket_id = 'payment-qr' and public.can_read_payment_qr(name));

create policy "Owners delete their payment QR code"
  on storage.objects for delete to authenticated
  using (bucket_id = 'payment-qr' and split_part(name, '/', 1) = (select auth.uid())::text);

create policy "Buyers upload proof for their open payment"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'payment-proofs' and public.can_upload_payment_proof(name));

create policy "Buyers, sellers and admins read payment proof"
  on storage.objects for select to authenticated
  using (bucket_id = 'payment-proofs' and public.can_read_payment_proof(name));

create policy "Buyers delete proof they haven't sent"
  on storage.objects for delete to authenticated
  using (bucket_id = 'payment-proofs' and public.can_delete_payment_proof(name));

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.payment_details enable row level security;
alter table public.deal_payments enable row level security;

-- Written only by the functions above.
revoke all on public.payment_details, public.deal_payments from anon, authenticated;
grant select on public.payment_details, public.deal_payments to authenticated;

-- Bank details are personal data (PDPA): only their owner reads the row;
-- buyers get them through get_payment while a payment is open.
create policy "Owners read their own payment details"
  on public.payment_details for select to authenticated
  using (profile_id = (select auth.uid())
         or exists (select 1 from public.businesses as b
                    where b.id = payment_details.business_id and b.owner_id = (select auth.uid())));

create policy "Buyers and sellers read their payments; admins read all"
  on public.deal_payments for select to authenticated
  using (buyer_id = (select auth.uid()) or seller_id = (select auth.uid()) or (select public.is_admin()));

revoke execute on function
  public.payment_details_for(uuid, uuid),
  public.cancel_order_hold(uuid, text),
  public.expire_unpaid_orders(uuid, uuid),
  public.expire_overdue_payments(),
  public.lock_payment(uuid)
from public, anon, authenticated;

revoke execute on function
  public.set_payment_details(boolean, text, text, text, text),
  public.request_reservation(uuid, integer, text, text),
  public.place_order(uuid, integer, uuid, text, text),
  public.get_payment(uuid),
  public.submit_payment_proof(uuid, text),
  public.review_payment(uuid, boolean, text),
  public.seller_accepts_transfer(uuid),
  public.can_read_payment_qr(text),
  public.can_upload_payment_proof(text),
  public.can_read_payment_proof(text),
  public.can_delete_payment_proof(text)
from public, anon;

grant execute on function
  public.set_payment_details(boolean, text, text, text, text),
  public.request_reservation(uuid, integer, text, text),
  public.place_order(uuid, integer, uuid, text, text),
  public.get_payment(uuid),
  public.submit_payment_proof(uuid, text),
  public.review_payment(uuid, boolean, text),
  public.seller_accepts_transfer(uuid),
  public.can_read_payment_qr(text),
  public.can_upload_payment_proof(text),
  public.can_read_payment_proof(text),
  public.can_delete_payment_proof(text)
to authenticated;
