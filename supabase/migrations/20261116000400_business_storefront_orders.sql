-- CampusNiaga Phase 4 (M3): business products, storefronts, pre-order
-- campaigns and orders. See docs/data-dictionary.md ("listings",
-- "campaigns", "orders", "businesses") and docs/api-contracts.md.
--
-- Security and consistency model:
--   * Business products are ordinary listings with mode = 'business'. Only
--     the owner of an approved business may create or edit them
--     (owns_business, read live, so suspension takes effect at once).
--   * Personal items are reserved (M1); business products are ordered (M3).
--     A trigger stops reservations on business listings; place_order()
--     refuses personal ones.
--   * Quantity is held when an order is placed. place_order() locks the
--     listing (ready stock) or the campaign (pre-order), checks what is
--     left and takes it in the same transaction; cancelling gives it back.
--     Check constraints (stock >= 0, allocated_qty <= capacity) are the last
--     line of defence.
--   * Lock order is always listing or campaign first, then the order, as in
--     the reservations migration, so no two functions deadlock on a pair.
--   * Clients never write campaigns, orders or businesses directly.

------------------------------------------------------------------------------
-- Reservations are for personal items only
------------------------------------------------------------------------------

create function public.reservations_personal_only()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if exists (select 1 from public.listings as l where l.id = new.listing_id and l.mode = 'business') then
    perform public.raise_app_error('ITEM_UNAVAILABLE', 'Business products are ordered, not reserved.');
  end if;
  return new;
end;
$$;

create trigger reservations_personal_only
  before insert on public.reservations
  for each row execute function public.reservations_personal_only();

------------------------------------------------------------------------------
-- Listings: business mode, and business attribution in the feed
------------------------------------------------------------------------------

-- The listing card gains the business, so the apps can link to its
-- storefront. The functions returning it are replaced below.
alter type public.listing_card
  add attribute business_id uuid,
  add attribute business_name text;

-- Replaced (not edited, the Phase 2 migration is applied) to add `mode`.
drop function public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text);

create function public.upsert_listing(
  listing_id uuid,
  title text,
  description text,
  category text,
  price_sen integer,
  condition text,
  quantity integer,
  photo_paths text[],
  pickup_area text,
  mode text default 'personal'
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
    if v_mode = 'personal' and existing.status in ('reserved', 'sold') then
      perform public.raise_app_error('INVALID_TRANSITION', 'A reserved or sold listing can''t be edited.');
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
      price_sen, condition, photo_paths, stock, pickup_area, status
    ) values (
      v_id, uid, v_mode, v_business, v_title, public.normalize_text(v_title), v_description,
      upsert_listing.category, upsert_listing.price_sen, upsert_listing.condition,
      v_photos, upsert_listing.quantity, v_pickup, 'draft'
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
      status = v_status
    where l.id = v_id;
  end if;

  return jsonb_build_object('listing_id', v_id, 'status', v_status);
end;
$$;

-- Same as Phase 2, plus the business, and business products only while
-- their business is approved.
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
stable
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

  return query
  select l.id, l.owner_id, p.name, l.mode, l.title, l.description, l.category,
         l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at,
         b.id, b.name
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

create or replace function public.get_listing(listing_id uuid)
returns setof public.listing_card
language plpgsql
stable
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

  return query
  select l.id, l.owner_id, p.name, l.mode, l.title, l.description, l.category,
         l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at,
         b.id, b.name
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

------------------------------------------------------------------------------
-- Campaigns (pre-orders)
------------------------------------------------------------------------------

create table public.campaigns (
  id uuid primary key default gen_random_uuid(),
  business_id uuid not null references public.businesses (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  title text not null check (char_length(title) between 3 and 80),
  price_sen integer not null check (price_sen between 0 and 10000000),
  start_at timestamptz not null,
  close_at timestamptz not null,
  capacity integer not null check (capacity between 1 and 10000),
  per_order_limit integer check (per_order_limit is null or per_order_limit between 1 and capacity),
  -- Units held by orders that aren't cancelled. Changed only under this
  -- row's lock; the check makes overselling impossible even if a function
  -- were wrong.
  allocated_qty integer not null default 0 check (allocated_qty between 0 and capacity),
  pickup_details text not null check (char_length(pickup_details) between 5 and 200),
  status text not null default 'draft' check (status in ('draft', 'open', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (close_at > start_at)
);

create trigger campaigns_set_updated_at
  before update on public.campaigns
  for each row execute function public.set_updated_at();

create index campaigns_business_idx on public.campaigns (business_id, status, close_at);
create index campaigns_listing_idx on public.campaigns (listing_id);

------------------------------------------------------------------------------
-- Orders
------------------------------------------------------------------------------

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  business_id uuid not null references public.businesses (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  campaign_id uuid references public.campaigns (id) on delete cascade,
  qty integer not null check (qty between 1 and 999),
  -- Snapshots: later price or pickup changes never rewrite an order.
  unit_price_sen integer not null check (unit_price_sen between 0 and 10000000),
  total_sen bigint not null,
  status text not null default 'pending_confirmation'
    check (status in ('pending_confirmation', 'confirmed', 'preparing', 'ready_for_pickup', 'completed', 'cancelled')),
  buyer_note text check (buyer_note is null or char_length(buyer_note) <= 200),
  collection_details text not null check (char_length(collection_details) <= 200),
  cancelled_by text check (cancelled_by in ('buyer', 'seller')),
  cost_sen integer check (cost_sen is null or cost_sen >= 0),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (total_sen = unit_price_sen::bigint * qty),
  check ((status = 'cancelled') = (cancelled_by is not null)),
  check ((status = 'completed') = (completed_at is not null))
);

create trigger orders_set_updated_at
  before update on public.orders
  for each row execute function public.set_updated_at();

create index orders_buyer_idx on public.orders (buyer_id, created_at desc);
create index orders_business_idx on public.orders (business_id, status, created_at desc);
create index orders_campaign_idx on public.orders (campaign_id) where campaign_id is not null;
create index orders_listing_idx on public.orders (listing_id);

------------------------------------------------------------------------------
-- Storefront
------------------------------------------------------------------------------

-- Same as Phase 3, plus the logo.
create or replace function public.get_my_business()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  business public.businesses;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;

  select * into business from public.businesses as b where b.owner_id = auth.uid();
  if not found then
    perform public.raise_app_error('FORBIDDEN', 'You need an approved business application first.');
  end if;

  return jsonb_build_object(
    'business_id', business.id,
    'application_id', business.application_id,
    'name', business.name,
    'description', business.description,
    'pickup_details', business.pickup_details,
    'logo_path', business.logo_path,
    'status', business.status,
    'created_at', business.created_at
  );
end;
$$;

-- A business's public page: details, products and open pre-orders.
create function public.get_storefront(business_id uuid)
returns jsonb
language plpgsql
stable
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
           business.id as business_id, business.name as business_name
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

create function public.update_storefront(description text, pickup_details text, logo_path text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_description text := btrim(coalesce(update_storefront.description, ''));
  v_pickup text := btrim(coalesce(update_storefront.pickup_details, ''));
  v_logo text := nullif(btrim(coalesce(update_storefront.logo_path, '')), '');
  business public.businesses;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  select * into business from public.businesses as b where b.owner_id = uid for update;
  if not found or not public.owns_business(business.id) then
    perform public.raise_app_error('FORBIDDEN', 'Only an approved business can change its storefront.');
  end if;

  if char_length(v_description) > 1000 then
    perform public.raise_app_error('INVALID_INPUT', 'The description can be up to 1,000 characters.');
  end if;
  if char_length(v_pickup) not between 5 and 200 then
    perform public.raise_app_error('INVALID_INPUT', 'Say where and when buyers collect (5 to 200 characters).');
  end if;
  -- The logo must be this business's own upload.
  if v_logo is not null and (
       v_logo !~* ('^' || business.id::text || '/[^/]+\.(jpe?g|png|webp)$')
       or not exists (select 1 from storage.objects as o where o.bucket_id = 'business-logos' and o.name = v_logo)
     ) then
    perform public.raise_app_error('INVALID_INPUT', 'The logo isn''t one of this business''s uploads.');
  end if;

  update public.businesses as b
  set description = v_description, pickup_details = v_pickup, logo_path = v_logo
  where b.id = business.id;

  return jsonb_build_object('business_id', business.id);
end;
$$;

------------------------------------------------------------------------------
-- Managing campaigns
------------------------------------------------------------------------------

create function public.upsert_campaign(
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
    if listing.status = 'draft' or listing.hidden then
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

create function public.set_campaign_status(campaign_id uuid, new_status text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  campaign public.campaigns;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if new_status is null or new_status not in ('draft', 'open', 'closed') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown pre-order status.');
  end if;

  select * into campaign from public.campaigns as c where c.id = set_campaign_status.campaign_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Pre-order not found.');
  end if;
  if not public.owns_business(campaign.business_id) then
    perform public.raise_app_error('FORBIDDEN', 'Only its approved business can change this pre-order.');
  end if;
  if (campaign.status, new_status) not in (('draft', 'open'), ('open', 'closed'), ('draft', 'closed')) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This pre-order is %s, so it can''t be changed to %s.', campaign.status, new_status));
  end if;
  if new_status = 'open' and campaign.close_at <= now() then
    perform public.raise_app_error('INVALID_INPUT', 'Its closing date has passed. Change the dates first.');
  end if;

  update public.campaigns as c set status = new_status where c.id = campaign.id;
  return jsonb_build_object('campaign_id', campaign.id, 'status', new_status);
end;
$$;

------------------------------------------------------------------------------
-- Ordering
------------------------------------------------------------------------------

create function public.place_order(
  listing_id uuid,
  qty integer default 1,
  campaign_id uuid default null,
  buyer_note text default null
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
  listing public.listings;
  business public.businesses;
  campaign public.campaigns;
  owner_active boolean;
  v_price integer;
  v_collection text;
  v_total bigint;
  new_id uuid;
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
  if (select count(*) from public.orders as o
      where o.buyer_id = uid and o.created_at > now() - interval '1 hour') >= 20 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve placed a lot of orders. Try again in an hour.');
  end if;

  -- 2. Lock what the order takes from: the campaign (pre-order) or the
  --    listing (ready stock). Everything below sees a stable quantity.
  if place_order.campaign_id is not null then
    select * into campaign from public.campaigns as c where c.id = place_order.campaign_id for update;
    if not found or campaign.status = 'draft' then
      perform public.raise_app_error('NOT_FOUND', 'Pre-order not found.');
    end if;
    if campaign.listing_id <> place_order.listing_id then
      perform public.raise_app_error('INVALID_INPUT', 'That pre-order is for another product.');
    end if;
    select * into listing from public.listings as l where l.id = campaign.listing_id;
  else
    select * into listing from public.listings as l where l.id = place_order.listing_id for update;
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

  -- 4. Record the order (prices and pickup details are snapshots)
  v_total := v_price::bigint * place_order.qty;
  insert into public.orders (buyer_id, business_id, listing_id, campaign_id, qty, unit_price_sen, total_sen,
                             status, buyer_note, collection_details)
  values (uid, business.id, listing.id, campaign.id, place_order.qty, v_price, v_total,
          'pending_confirmation', v_note, v_collection)
  returning id into new_id;

  perform public.notify(business.owner_id, 'order_placed',
    case when campaign.id is null then 'New order' else 'New pre-order' end,
    format('%s × %s', place_order.qty, coalesce(campaign.title, listing.title)), 'order:' || new_id);

  return jsonb_build_object('order_id', new_id, 'status', 'pending_confirmation', 'total_sen', v_total);
end;
$$;

-- The seller moves an order forward one step; either side cancels before
-- completion, which returns the quantity.
create function public.transition_order(order_id uuid, action text)
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

  -- Lock what the order holds, then the order itself; re-read it.
  if o.campaign_id is not null then
    perform 1 from public.campaigns as c where c.id = o.campaign_id for update;
  else
    perform 1 from public.listings as l where l.id = o.listing_id for update;
  end if;
  select * into o from public.orders as ord where ord.id = o.id for update;

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

  update public.orders as ord
  set status = new_status,
      completed_at = case when new_status = 'completed' then now() end,
      cancelled_by = case when new_status = 'cancelled'
                          then case when uid = o.buyer_id then 'buyer' else 'seller' end end
  where ord.id = o.id;

  if new_status = 'cancelled' then
    if o.campaign_id is not null then
      update public.campaigns as c set allocated_qty = c.allocated_qty - o.qty where c.id = o.campaign_id;
    else
      update public.listings as l
      set stock = l.stock + o.qty,
          status = case when l.status = 'sold' then 'available' else l.status end
      where l.id = o.listing_id;
    end if;
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

-- What My Orders shows. Contact email only once the seller confirms.
create type public.order_card as (
  id uuid,
  listing_id uuid,
  listing_title text,
  listing_photo text,
  business_id uuid,
  business_name text,
  campaign_id uuid,
  campaign_title text,
  qty integer,
  unit_price_sen integer,
  total_sen bigint,
  status text,
  buyer_note text,
  collection_details text,
  cancelled_by text,
  created_at timestamptz,
  updated_at timestamptz,
  completed_at timestamptz,
  i_am_buyer boolean,
  other_party_name text,
  other_party_email text
);

create function public.my_orders(side text default 'buying', page_size integer default 50, page_offset integer default 0)
returns setof public.order_card
language plpgsql
stable
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

  return query
  select o.id, o.listing_id, l.title, l.photo_paths[1], o.business_id, b.name, o.campaign_id, c.title,
         o.qty, o.unit_price_sen, o.total_sen, o.status, o.buyer_note, o.collection_details, o.cancelled_by,
         o.created_at, o.updated_at, o.completed_at,
         o.buyer_id = uid,
         p.name,
         case when o.status in ('confirmed', 'preparing', 'ready_for_pickup', 'completed') then p.email end
  from public.orders as o
  join public.listings as l on l.id = o.listing_id
  join public.businesses as b on b.id = o.business_id
  left join public.campaigns as c on c.id = o.campaign_id
  join public.profiles as p on p.id = case when my_orders.side = 'buying' then b.owner_id else o.buyer_id end
  where case when my_orders.side = 'buying' then o.buyer_id = uid else b.owner_id = uid end
  order by (o.status not in ('completed', 'cancelled')) desc, o.created_at desc, o.id
  limit my_orders.page_size
  offset my_orders.page_offset;
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.campaigns enable row level security;
alter table public.orders enable row level security;

-- Written only by the functions above.
revoke all on public.campaigns, public.orders from anon, authenticated;
grant select on public.campaigns, public.orders to authenticated;

create policy "Business owners read their campaigns; admins read all"
  on public.campaigns for select to authenticated
  using (exists (select 1 from public.businesses as b
                 where b.id = campaigns.business_id and b.owner_id = (select auth.uid()))
         or (select public.is_admin()));

-- The owner keeps reading orders while the business is suspended, so the
-- history stays available.
create policy "Buyers and business owners read their orders; admins read all"
  on public.orders for select to authenticated
  using (buyer_id = (select auth.uid())
         or exists (select 1 from public.businesses as b
                    where b.id = orders.business_id and b.owner_id = (select auth.uid()))
         or (select public.is_admin()));

------------------------------------------------------------------------------
-- Logo storage: business-logos/{business_id}/{file}
------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('business-logos', 'business-logos', false, 2097152, array['image/jpeg', 'image/png', 'image/webp']);

-- Upload: the owner of an approved business, into its folder.
create function public.can_upload_business_logo(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_length(string_to_array(object_name, '/'), 1), 0) = 2
    and exists (
      select 1 from public.businesses as b
      where b.id::text = split_part(object_name, '/', 1)
        and public.owns_business(b.id)
    );
$$;

create policy "Approved businesses upload their logo"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'business-logos' and public.can_upload_business_logo(name));

create policy "Students and staff can view business logos"
  on storage.objects for select to authenticated
  using (bucket_id = 'business-logos' and ((select public.is_student()) or (select public.is_staff())));

create policy "Owners delete their business logos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'business-logos'
         and exists (select 1 from public.businesses as b
                     where b.id::text = split_part(name, '/', 1) and b.owner_id = (select auth.uid())));

------------------------------------------------------------------------------
-- Function privileges
------------------------------------------------------------------------------

revoke execute on function public.reservations_personal_only() from public, anon, authenticated;

revoke execute on function
  public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text),
  public.get_storefront(uuid),
  public.update_storefront(text, text, text),
  public.upsert_campaign(uuid, uuid, text, integer, timestamptz, timestamptz, integer, integer, text),
  public.set_campaign_status(uuid, text),
  public.place_order(uuid, integer, uuid, text),
  public.transition_order(uuid, text),
  public.my_orders(text, integer, integer),
  public.can_upload_business_logo(text)
from public, anon;

grant execute on function
  public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text),
  public.get_storefront(uuid),
  public.update_storefront(text, text, text),
  public.upsert_campaign(uuid, uuid, text, integer, timestamptz, timestamptz, integer, integer, text),
  public.set_campaign_status(uuid, text),
  public.place_order(uuid, integer, uuid, text),
  public.transition_order(uuid, text),
  public.my_orders(text, integer, integer),
  public.can_upload_business_logo(text)
to authenticated;
