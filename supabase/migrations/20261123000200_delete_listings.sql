-- Listings are deleted, not closed. See docs/decisions/0008-listing-payment-and-delete.md.
--
-- Deleting is final and soft: the row stays, with status 'deleted', because
-- purchases, orders, chats and reports point at it. A deleted listing leaves
-- the marketplace and its owner's list; the owner, admins and anyone who
-- bought it can still open it from their purchase. Purchases and orders in
-- progress carry on. A business product's draft and open pre-orders close
-- with it.
--
-- Listings closed before this change keep the 'closed' status: their owner
-- can re-open or delete them, but nothing can be closed any more.

alter table public.listings drop constraint listings_status_check;
alter table public.listings
  add constraint listings_status_check check (status in ('draft', 'available', 'sold', 'closed', 'deleted'));

-- A draft deleted before it had a photo has none. The old rule ("anything
-- buyers can see has a photo") had no name of its own, so it is found by its
-- definition.
do $$
declare
  rule text;
begin
  select c.conname into strict rule from pg_constraint as c
  where c.conrelid = 'public.listings'::regclass and c.contype = 'c'
    and pg_get_constraintdef(c.oid) like '%cardinality(photo_paths) >= 1%';
  execute format('alter table public.listings drop constraint %I', rule);
end;
$$;
alter table public.listings
  add constraint listings_photo_when_visible check (status in ('draft', 'deleted') or cardinality(photo_paths) >= 1);

-- The owner publishes, marks sold, re-opens a closed listing, or deletes.
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
  if new_status is null or new_status not in ('draft', 'available', 'sold', 'closed', 'deleted') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown listing status.');
  end if;

  select * into listing from public.listings as l where l.id = set_listing_status.listing_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id <> auth.uid() then
    perform public.raise_app_error('FORBIDDEN', 'You can only change your own listings.');
  end if;
  if listing.status = 'deleted' then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;

  if public.expire_unpaid_purchases(listing.id) > 0 then
    select * into listing from public.listings as l where l.id = listing.id;
  end if;

  if (listing.status, new_status) not in (
    ('draft', 'available'), ('available', 'sold'), ('closed', 'available')
  ) and new_status <> 'deleted' then
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

  -- A deleted product takes no more pre-orders; orders already placed stay.
  if new_status = 'deleted' then
    update public.campaigns as c set status = 'closed'
    where c.listing_id = listing.id and c.status in ('draft', 'open');
  end if;

  return jsonb_build_object('listing_id', listing.id, 'status', new_status);
end;
$$;

-- A deleted listing can't be edited.
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
    if existing.status = 'deleted' then
      perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
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

-- A deleted listing is shown to its owner, admins, and a student who bought
-- it (so a purchase still opens its item); to nobody else.
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
      or (student and l.status not in ('draft', 'deleted') and not l.hidden and p.account_status = 'active'
          and (l.business_id is null or b.status = 'approved'))
      or (student and l.status = 'deleted' and public.has_bought_item(l.id, uid))
    );

  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
end;
$$;

-- Nothing to report once deleted.
create or replace function public.report_listing(listing_id uuid, reason text, details text default '')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_details text := btrim(coalesce(report_listing.details, ''));
  listing public.listings;
  new_id uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if report_listing.reason is null
     or report_listing.reason not in ('prohibited_item', 'scam', 'offensive', 'misleading', 'other') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose a reason.');
  end if;
  if char_length(v_details) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Details can be up to 500 characters.');
  end if;
  if report_listing.reason = 'other' and v_details = '' then
    perform public.raise_app_error('INVALID_INPUT', 'Tell us what''s wrong.');
  end if;

  select * into listing from public.listings as l where l.id = report_listing.listing_id;
  if not found or listing.status in ('draft', 'deleted') then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t report your own listing.');
  end if;
  if exists (select 1 from public.reports as r
             where r.reporter_id = uid and r.listing_id = listing.id and r.status = 'open') then
    perform public.raise_app_error('ALREADY_EXISTS', 'You''ve already reported this listing.');
  end if;
  if (select count(*) from public.reports as r
      where r.reporter_id = uid and r.created_at > now() - interval '1 day') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve sent a lot of reports today. Try again tomorrow.');
  end if;

  insert into public.reports (reporter_id, listing_id, reported_user_id, reason, details)
  values (uid, listing.id, listing.owner_id, report_listing.reason, v_details)
  returning id into new_id;

  return jsonb_build_object('report_id', new_id, 'status', 'open');
end;
$$;

-- No payment options for a deleted listing.
create or replace function public.seller_accepts_transfer(listing_id uuid)
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
  where l.id = seller_accepts_transfer.listing_id and l.status not in ('draft', 'deleted') and not l.hidden;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  return (public.payment_details_for(listing.owner_id, listing.business_id)).id is not null;
end;
$$;

-- No pre-order of a deleted product.
create or replace function public.upsert_campaign(
  campaign_id uuid,
  listing_id uuid,
  title text,
  price_sen integer,
  start_at timestamptz,
  close_at timestamptz,
  capacity integer,
  per_order_limit integer,
  pickup_details text
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_title text := btrim(coalesce(upsert_campaign.title, ''));
  v_pickup text := btrim(coalesce(upsert_campaign.pickup_details, ''));
  existing public.campaigns;
  listing public.listings;
  v_id uuid := upsert_campaign.campaign_id;
begin
  -- 1. Caller and the campaign or product, locked when editing
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;

  if v_id is not null then
    select * into existing from public.campaigns as c where c.id = v_id for update;
    if not found then
      perform public.raise_app_error('NOT_FOUND', 'Pre-order not found.');
    end if;
    if not public.owns_business(existing.business_id) then
      perform public.raise_app_error('FORBIDDEN', 'Only its approved business can change this pre-order.');
    end if;
    if existing.status = 'closed' then
      perform public.raise_app_error('INVALID_TRANSITION', 'A closed pre-order can''t be changed.');
    end if;
    if upsert_campaign.listing_id is not null and upsert_campaign.listing_id <> existing.listing_id then
      perform public.raise_app_error('INVALID_INPUT', 'A pre-order''s product can''t change.');
    end if;
  else
    select * into listing from public.listings as l where l.id = upsert_campaign.listing_id;
    if not found then
      perform public.raise_app_error('NOT_FOUND', 'Product not found.');
    end if;
    if listing.mode <> 'business' or not public.owns_business(listing.business_id) then
      perform public.raise_app_error('FORBIDDEN', 'Pre-orders are for your approved business''s products.');
    end if;
    if listing.status in ('draft', 'deleted') or listing.hidden then
      perform public.raise_app_error('INVALID_INPUT', 'Publish the product before taking pre-orders.');
    end if;
    if (select count(*) from public.campaigns as c
        where c.business_id = listing.business_id and c.created_at > now() - interval '1 hour') >= 20 then
      perform public.raise_app_error('RATE_LIMITED', 'You''ve created a lot of pre-orders. Try again in an hour.');
    end if;
  end if;

  -- 2. Input
  if char_length(v_title) not between 3 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'The title must be 3 to 80 characters.');
  end if;
  if upsert_campaign.price_sen is null or upsert_campaign.price_sen not between 0 and 10000000 then
    perform public.raise_app_error('INVALID_INPUT', 'The price must be between RM 0 and RM 100,000.');
  end if;
  if upsert_campaign.start_at is null or upsert_campaign.close_at is null
     or upsert_campaign.close_at <= upsert_campaign.start_at then
    perform public.raise_app_error('INVALID_INPUT', 'The pre-order must close after it opens.');
  end if;
  if upsert_campaign.close_at <= now() then
    perform public.raise_app_error('INVALID_INPUT', 'The closing date must be in the future.');
  end if;
  if upsert_campaign.capacity is null or upsert_campaign.capacity not between 1 and 10000 then
    perform public.raise_app_error('INVALID_INPUT', 'Capacity must be 1 to 10,000.');
  end if;
  if upsert_campaign.capacity < coalesce(existing.allocated_qty, 0) then
    perform public.raise_app_error('INVALID_INPUT',
      format('Capacity can''t be below the %s already ordered.', existing.allocated_qty));
  end if;
  if upsert_campaign.per_order_limit is not null
     and upsert_campaign.per_order_limit not between 1 and upsert_campaign.capacity then
    perform public.raise_app_error('INVALID_INPUT', 'The per-order limit must be between 1 and the capacity.');
  end if;
  if char_length(v_pickup) not between 5 and 200 then
    perform public.raise_app_error('INVALID_INPUT', 'Say where and when buyers collect (5 to 200 characters).');
  end if;

  -- 3. Write
  if existing.id is null then
    insert into public.campaigns (business_id, listing_id, title, price_sen, start_at, close_at,
                                  capacity, per_order_limit, pickup_details)
    values (listing.business_id, listing.id, v_title, upsert_campaign.price_sen, upsert_campaign.start_at,
            upsert_campaign.close_at, upsert_campaign.capacity, upsert_campaign.per_order_limit, v_pickup)
    returning id into v_id;
  else
    update public.campaigns as c set
      title = v_title,
      price_sen = upsert_campaign.price_sen,
      start_at = upsert_campaign.start_at,
      close_at = upsert_campaign.close_at,
      capacity = upsert_campaign.capacity,
      per_order_limit = upsert_campaign.per_order_limit,
      pickup_details = v_pickup
    where c.id = v_id;
  end if;

  return jsonb_build_object('campaign_id', v_id, 'status', coalesce(existing.status, 'draft'));
end;
$$;

-- Releasing units never brings a deleted listing back. 'closed' from the
-- seller's choice now deletes the listing.
create or replace function public.cancel_purchase_hold(
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
      status = case when l.status = 'deleted' then 'deleted'
                    else coalesce(listing_after, case when l.status = 'sold' then 'available' else l.status end) end
  where l.id = p.listing_id;

  update public.deal_payments as dp
  set status = case when by_whom = 'system' then 'expired' else 'cancelled' end
  where dp.purchase_id = p.id and dp.status in ('awaiting_proof', 'submitted');
end;
$$;

-- The seller relists the item, or deletes the listing.
create or replace function public.cancel_purchase(purchase_id uuid, reason text default null, relist boolean default true)
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
    perform public.raise_app_error('INVALID_INPUT', 'Choose relist or delete, with a reason of up to 200 characters.');
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
    case when not by_seller then null when cancel_purchase.relist then 'available' else 'deleted' end);

  select l.title, l.status into v_title, v_listing_status from public.listings as l where l.id = p.listing_id;
  perform public.notify(case when by_seller then p.buyer_id else p.seller_id end, 'purchase_cancelled',
    'Purchase cancelled',
    format('%s × %s', p.qty, v_title) || coalesce(': ' || v_reason, '')
      || case when pay_status in ('submitted', 'accepted') then ' Any refund is arranged outside the app.' else '' end,
    'purchase:' || p.id);

  return jsonb_build_object('purchase_id', p.id, 'status', 'cancelled', 'listing_status', v_listing_status);
end;
$$;

-- A deleted listing is no business stock.
create or replace function public.business_figures(target_business uuid, from_at timestamptz, to_at timestamptz)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  by_status jsonb;
  total_orders integer;
  completed_count integer;
  revenue bigint;
  cost bigint;
  costed integer;
  top jsonb;
  stock jsonb;
  campaigns jsonb;
begin
  -- Orders placed in the range, by status (zeros included).
  select jsonb_object_agg(s.status, coalesce(n.total, 0) order by s.ord), coalesce(sum(n.total), 0)::integer
  into by_status, total_orders
  from unnest(array['pending_confirmation', 'confirmed', 'preparing', 'ready_for_pickup', 'completed', 'cancelled'])
       with ordinality as s (status, ord)
  left join (
    select o.status, count(*)::integer as total
    from public.orders as o
    where o.business_id = target_business
      and (business_figures.from_at is null or o.created_at >= business_figures.from_at)
      and (business_figures.to_at is null or o.created_at < business_figures.to_at)
    group by o.status
  ) as n on n.status = s.status;

  -- Orders completed in the range: the estimated, self-reported figures.
  select count(*)::integer, coalesce(sum(o.total_sen), 0)::bigint,
         coalesce(sum(o.cost_sen), 0)::bigint, count(o.cost_sen)::integer
  into completed_count, revenue, cost, costed
  from public.orders as o
  where o.business_id = target_business
    and o.status = 'completed'
    and (business_figures.from_at is null or o.completed_at >= business_figures.from_at)
    and (business_figures.to_at is null or o.completed_at < business_figures.to_at);

  select coalesce(jsonb_agg(t order by t.revenue_sen desc, t.units desc, t.title), '[]'::jsonb) into top
  from (
    select o.listing_id, l.title, sum(o.qty)::integer as units, sum(o.total_sen)::bigint as revenue_sen
    from public.orders as o
    join public.listings as l on l.id = o.listing_id
    where o.business_id = target_business
      and o.status = 'completed'
      and (business_figures.from_at is null or o.completed_at >= business_figures.from_at)
      and (business_figures.to_at is null or o.completed_at < business_figures.to_at)
    group by o.listing_id, l.title
    order by revenue_sen desc, units desc, l.title
    limit 5
  ) as t;

  select coalesce(jsonb_agg(jsonb_build_object(
           'listing_id', l.id, 'title', l.title, 'status', l.status, 'stock', l.stock, 'hidden', l.hidden)
         order by l.stock, l.title), '[]'::jsonb)
  into stock
  from public.listings as l
  where l.business_id = target_business and l.status not in ('draft', 'deleted');

  select coalesce(jsonb_agg(jsonb_build_object(
           'campaign_id', c.id, 'title', c.title, 'status', c.status, 'capacity', c.capacity,
           'allocated_qty', c.allocated_qty, 'remaining', c.capacity - c.allocated_qty, 'close_at', c.close_at)
         order by c.close_at), '[]'::jsonb)
  into campaigns
  from public.campaigns as c
  where c.business_id = target_business and c.status in ('draft', 'open');

  return jsonb_build_object(
    'orders_by_status', by_status,
    'total_orders', total_orders,
    'completed_count', completed_count,
    'estimated_revenue_sen', revenue,
    'recorded_cost_sen', cost,
    'costed_completed_count', costed,
    'estimated_profit_sen', revenue - cost,
    'top_products', top,
    'stock', stock,
    'campaigns', campaigns
  );
end;
$$;
