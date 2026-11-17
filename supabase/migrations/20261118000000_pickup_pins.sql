-- Map pins for pickup spots: a seller can pin where buyers collect a listing,
-- and a business where buyers collect its orders. The pin is optional and
-- sits next to the existing text (`listings.pickup_area`,
-- `businesses.pickup_details`), which stays required.
--
-- Privacy: a pin is shown to every verified student who can see the listing
-- or storefront, the same audience as the pickup text. The app asks sellers
-- to pin a public spot (cafeteria, library, desasiswa lobby), never a room.
--
-- Contracts: docs/data-dictionary.md ("Pickup pins") and docs/api-contracts.md.

------------------------------------------------------------------------------
-- Columns
------------------------------------------------------------------------------

-- Both coordinates or neither, and inside Malaysia's bounding box (every USM
-- campus is in it). Degrees, WGS 84, as map apps use.
alter table public.listings
  add column pickup_lat double precision,
  add column pickup_lng double precision,
  add constraint listings_pickup_pin_pair check ((pickup_lat is null) = (pickup_lng is null)),
  add constraint listings_pickup_pin_malaysia check (
    pickup_lat is null or (pickup_lat between 0.8 and 7.5 and pickup_lng between 99.5 and 119.5)
  );

alter table public.businesses
  add column pickup_lat double precision,
  add column pickup_lng double precision,
  add constraint businesses_pickup_pin_pair check ((pickup_lat is null) = (pickup_lng is null)),
  add constraint businesses_pickup_pin_malaysia check (
    pickup_lat is null or (pickup_lat between 0.8 and 7.5 and pickup_lng between 99.5 and 119.5)
  );

-- The same rule for function input, so callers get a readable reason
-- instead of a constraint error. Internal helper: no grants.
create function public.pickup_pin_problem(lat double precision, lng double precision)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when (lat is null) <> (lng is null) then 'Give both the latitude and the longitude of the pin, or neither.'
    when lat is null then null
    -- NaN sorts above every number in PostgreSQL, so the range refuses it too.
    when lat not between 0.8 and 7.5 or lng not between 99.5 and 119.5 then 'Pin a spot in Malaysia.'
  end;
$$;

revoke execute on function public.pickup_pin_problem(double precision, double precision) from public, anon, authenticated;

------------------------------------------------------------------------------
-- Listings
------------------------------------------------------------------------------

alter type public.listing_card
  add attribute pickup_lat double precision,
  add attribute pickup_lng double precision;

-- Replaced (not edited, the earlier migrations are applied) to take the pin.
-- The new parameters default to null, so a call without them saves no pin.
drop function public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text);

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

-- Same as Phase 4, plus the pin.
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

-- Same as Phase 4, plus the pin.
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

------------------------------------------------------------------------------
-- Storefront
------------------------------------------------------------------------------

-- Same as Phase 4, plus the pin.
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
    'pickup_lat', business.pickup_lat,
    'pickup_lng', business.pickup_lng,
    'logo_path', business.logo_path,
    'status', business.status,
    'created_at', business.created_at
  );
end;
$$;

-- Same as Phase 4, plus the business's pin and each product's pin.
create or replace function public.get_storefront(business_id uuid)
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

-- Replaced to take the pin; a call without it saves no pin.
drop function public.update_storefront(text, text, text);

create function public.update_storefront(
  description text,
  pickup_details text,
  logo_path text default null,
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
  v_description text := btrim(coalesce(update_storefront.description, ''));
  v_pickup text := btrim(coalesce(update_storefront.pickup_details, ''));
  v_logo text := nullif(btrim(coalesce(update_storefront.logo_path, '')), '');
  v_pin_problem text := public.pickup_pin_problem(update_storefront.pickup_lat, update_storefront.pickup_lng);
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
  if v_pin_problem is not null then
    perform public.raise_app_error('INVALID_INPUT', v_pin_problem);
  end if;
  -- The logo must be this business's own upload.
  if v_logo is not null and (
       v_logo !~* ('^' || business.id::text || '/[^/]+\.(jpe?g|png|webp)$')
       or not exists (select 1 from storage.objects as o where o.bucket_id = 'business-logos' and o.name = v_logo)
     ) then
    perform public.raise_app_error('INVALID_INPUT', 'The logo isn''t one of this business''s uploads.');
  end if;

  update public.businesses as b
  set description = v_description, pickup_details = v_pickup, logo_path = v_logo,
      pickup_lat = update_storefront.pickup_lat, pickup_lng = update_storefront.pickup_lng
  where b.id = business.id;

  return jsonb_build_object('business_id', business.id);
end;
$$;

------------------------------------------------------------------------------
-- Function privileges (the replaced functions are new objects)
------------------------------------------------------------------------------

revoke execute on function
  public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text, double precision, double precision),
  public.update_storefront(text, text, text, double precision, double precision)
from public, anon;

grant execute on function
  public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text, double precision, double precision),
  public.update_storefront(text, text, text, double precision, double precision)
to authenticated;
