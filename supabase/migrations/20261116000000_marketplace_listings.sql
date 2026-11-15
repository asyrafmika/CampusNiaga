-- CampusNiaga Phase 2 (M1): listings, their photos, and the marketplace feed.
-- See docs/data-dictionary.md ("listings") and docs/api-contracts.md.
--
-- Security model:
--   * Clients never write public.listings directly. upsert_listing() and
--     set_listing_status() check the caller, validate input and derive owner,
--     mode and status themselves.
--   * stock is the number of units still for sale (the seller's quantity).
--     Reservations (next migration) take units out of stock when accepted
--     and put them back when cancelled or expired.
--   * Direct reads are limited to the owner (My Listings) and admins. Other
--     students browse through search_listings() and get_listing(), which add
--     the seller's name (profiles are private) and apply the visibility rules:
--     no drafts, nothing hidden by moderation, no suspended sellers.
--   * Phase 2 creates personal listings only. Business listings (mode
--     'business') need an approved business, which arrives in Phase 3/4.

------------------------------------------------------------------------------
-- Helpers
------------------------------------------------------------------------------

-- Lowercase, punctuation replaced by spaces, spaces collapsed. M4 matching
-- builds on this.
create function public.normalize_text(value text)
returns text
language sql
immutable
set search_path = ''
as $$
  select btrim(regexp_replace(lower(coalesce(value, '')), '[^[:alnum:]]+', ' ', 'g'));
$$;

-- The categories a listing may use. app_config itself is admin-only (it holds
-- the test allowlist), so students read the list through this function.
create function public.listing_categories()
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select categories from public.app_config;
$$;

------------------------------------------------------------------------------
-- Listings
------------------------------------------------------------------------------

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  mode text not null default 'personal' check (mode in ('personal', 'business')),
  business_id uuid,
  title text not null check (char_length(title) between 3 and 80),
  normalized_title text not null,
  description text not null default '' check (char_length(description) <= 1000),
  category text not null,
  price_sen integer not null check (price_sen between 0 and 10000000),
  condition text not null check (condition in ('new', 'like_new', 'good', 'fair')),
  photo_paths text[] not null default '{}' check (cardinality(photo_paths) <= 5),
  stock integer not null default 1 check (stock >= 0),
  pickup_area text not null check (char_length(pickup_area) between 2 and 80),
  status text not null default 'draft' check (status in ('draft', 'available', 'reserved', 'sold', 'closed')),
  hidden boolean not null default false,
  search_vector tsvector generated always as (
    setweight(to_tsvector('english'::regconfig, title), 'A')
    || setweight(to_tsvector('english'::regconfig, description), 'B')
    || setweight(to_tsvector('english'::regconfig, category), 'C')
  ) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- A business listing belongs to exactly one business; a personal one to none.
  check ((mode = 'business') = (business_id is not null)),
  -- Something for sale has a unit left; a sold listing has none.
  check (status <> 'available' or stock >= 1),
  check (status <> 'sold' or stock = 0),
  -- Anything buyers can see has at least one photo.
  check (status = 'draft' or cardinality(photo_paths) >= 1)
);

create trigger listings_set_updated_at
  before update on public.listings
  for each row execute function public.set_updated_at();

create index listings_search_idx on public.listings using gin (search_vector);
create index listings_feed_idx on public.listings (status, category, price_sen) where not hidden;
create index listings_owner_idx on public.listings (owner_id, status, created_at desc);

------------------------------------------------------------------------------
-- Writing listings
------------------------------------------------------------------------------

-- Creates a draft (listing_id null) or edits one of the caller's listings.
-- Photos must already be uploaded to listing-photos/{owner}/{listing}/, so a
-- new listing is created without photos and then edited to add them.
create function public.upsert_listing(
  listing_id uuid,
  title text,
  description text,
  category text,
  price_sen integer,
  condition text,
  quantity integer,
  photo_paths text[],
  pickup_area text
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
  existing public.listings;
  path text;
begin
  -- 1. Caller
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to sell.');
  end if;

  -- 2. The listing being edited, if any (locked so a parallel edit or status
  --    change can't interleave)
  if v_id is not null then
    select * into existing from public.listings as l where l.id = v_id for update;
    if not found then
      perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
    end if;
    if existing.owner_id <> uid then
      perform public.raise_app_error('FORBIDDEN', 'You can only edit your own listings.');
    end if;
    if existing.status in ('reserved', 'sold') then
      perform public.raise_app_error('INVALID_TRANSITION', 'A reserved or sold listing can''t be edited.');
    end if;
  else
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
  -- Photos must be the caller's own uploads for this listing: no pointing at
  -- someone else's files.
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
    insert into public.listings (
      id, owner_id, mode, title, normalized_title, description, category,
      price_sen, condition, photo_paths, stock, pickup_area, status
    ) values (
      v_id, uid, 'personal', v_title, public.normalize_text(v_title), v_description,
      upsert_listing.category, upsert_listing.price_sen, upsert_listing.condition,
      v_photos, upsert_listing.quantity, v_pickup, 'draft'
    );
  else
    update public.listings as l set
      title = v_title,
      normalized_title = public.normalize_text(v_title),
      description = v_description,
      category = upsert_listing.category,
      price_sen = upsert_listing.price_sen,
      condition = upsert_listing.condition,
      stock = upsert_listing.quantity,
      photo_paths = v_photos,
      pickup_area = v_pickup
    where l.id = v_id;
  end if;

  return jsonb_build_object('listing_id', v_id, 'status', coalesce(existing.status, 'draft'));
end;
$$;

-- The owner publishes, closes, re-opens or marks a listing sold. Reserved
-- listings change through reservations instead (Phase 2, next migration).
create function public.set_listing_status(listing_id uuid, new_status text)
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
  if new_status is null or new_status not in ('draft', 'available', 'reserved', 'sold', 'closed') then
    perform public.raise_app_error('INVALID_INPUT', 'Unknown listing status.');
  end if;

  select * into listing from public.listings as l where l.id = set_listing_status.listing_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
  if listing.owner_id <> auth.uid() then
    perform public.raise_app_error('FORBIDDEN', 'You can only change your own listings.');
  end if;

  if (listing.status, new_status) not in (
    ('draft', 'available'), ('draft', 'closed'),
    ('available', 'closed'), ('available', 'sold'),
    ('closed', 'available')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('A %s listing can''t be changed to %s.', listing.status, new_status));
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

------------------------------------------------------------------------------
-- Reading listings
------------------------------------------------------------------------------

-- What buyers see of a listing: the listing plus only the seller's name.
create type public.listing_card as (
  id uuid,
  owner_id uuid,
  seller_name text,
  mode text,
  title text,
  description text,
  category text,
  price_sen integer,
  condition text,
  photo_paths text[],
  stock integer,
  pickup_area text,
  status text,
  created_at timestamptz
);

-- The searchable feed: available, visible listings from active sellers.
-- `search` uses web-search syntax ("calculator -broken"); results are ranked
-- by relevance when searching, otherwise by `sort`.
create function public.search_listings(
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
         l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at
  from public.listings as l
  join public.profiles as p on p.id = l.owner_id and p.account_status = 'active'
  where l.status = 'available'
    and not l.hidden
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

-- One listing for the detail page. Students see anything published and not
-- hidden; owners and admins also see drafts and hidden listings.
create function public.get_listing(listing_id uuid)
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
         l.price_sen, l.condition, l.photo_paths, l.stock, l.pickup_area, l.status, l.created_at
  from public.listings as l
  join public.profiles as p on p.id = l.owner_id
  where l.id = get_listing.listing_id
    and (
      l.owner_id = uid
      or admin
      or (student and l.status <> 'draft' and not l.hidden and p.account_status = 'active')
    );

  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Listing not found.');
  end if;
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.listings enable row level security;

-- Written only by the functions above.
revoke all on public.listings from anon, authenticated;
grant select on public.listings to authenticated;

create policy "Owners can read their own listings; admins can read all"
  on public.listings for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_admin()));

------------------------------------------------------------------------------
-- Photo storage: listing-photos/{owner_id}/{listing_id}/{file}
------------------------------------------------------------------------------

-- Private bucket: photos are fetched with the signed-in user's token, so
-- signed-out visitors can't read them. Size and type limits are enforced by
-- Storage itself; the app also resizes photos before upload.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('listing-photos', 'listing-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp']);

-- A verified student may upload only into a folder for a listing they own.
create function public.can_upload_listing_photo(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_student()
    and coalesce(array_length(string_to_array(object_name, '/'), 1), 0) = 3
    and exists (
      select 1 from public.listings as l
      where l.owner_id = auth.uid()
        and l.owner_id::text = split_part(object_name, '/', 1)
        and l.id::text = split_part(object_name, '/', 2)
    );
$$;

create policy "Students upload photos for their own listings"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'listing-photos' and public.can_upload_listing_photo(name));

create policy "Students and admins can view listing photos"
  on storage.objects for select to authenticated
  using (bucket_id = 'listing-photos' and ((select public.is_student()) or (select public.is_admin())));

create policy "Owners can delete their own listing photos"
  on storage.objects for delete to authenticated
  using (bucket_id = 'listing-photos' and split_part(name, '/', 1) = (select auth.uid())::text);

------------------------------------------------------------------------------
-- Function privileges
------------------------------------------------------------------------------

revoke execute on function public.normalize_text(text) from public, anon, authenticated;

revoke execute on function
  public.listing_categories(),
  public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text),
  public.set_listing_status(uuid, text),
  public.search_listings(text, text, text, integer, integer, text, integer, integer),
  public.get_listing(uuid),
  public.can_upload_listing_photo(text)
from public, anon;

grant execute on function
  public.listing_categories(),
  public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text),
  public.set_listing_status(uuid, text),
  public.search_listings(text, text, text, integer, integer, text, integer, integer),
  public.get_listing(uuid),
  public.can_upload_listing_photo(text)
to authenticated;
