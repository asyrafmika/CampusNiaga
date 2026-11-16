-- CampusNiaga Phase 5 (M4): product requests, interest, and the
-- deterministic opportunity ranking. See docs/data-dictionary.md
-- ("product_requests", "request_interests", "opportunities", "Discovery
-- terms") and docs/api-contracts.md.
--
-- Design:
--   * No machine learning. Text is normalised by fixed rules and a small
--     curated synonym table; each request belongs to the cluster
--     `{category}|{head term}`, where the head term is the last discovery
--     term of its name ("chocolate brownie" -> brownie).
--   * Demand D = distinct students among a cluster's active requests'
--     creators and interested students (repeated taps never add up).
--     Supply S = matching visible listings. The score is the handoff's
--     heuristic, stored with algo_version and its parameters.
--   * Results are derived data, written only by recompute_opportunities(),
--     which triggers call whenever an input changes. Clients only read them.
--   * Requests and interests are written only through functions, which
--     check the caller, validate and rate-limit.

------------------------------------------------------------------------------
-- Discovery terms
------------------------------------------------------------------------------

-- Curated plural forms and synonyms. Edited in the Supabase dashboard only.
create table public.discovery_synonyms (
  term text primary key check (term = lower(term) and term ~ '^[a-z0-9]+$'),
  canonical text not null check (canonical = lower(canonical) and canonical ~ '^[a-z0-9]+$')
);

insert into public.discovery_synonyms (term, canonical) values
  -- Plurals the simple rules get wrong
  ('brownies', 'brownie'), ('cookies', 'cookie'), ('hoodies', 'hoodie'),
  ('smoothies', 'smoothie'), ('movies', 'movie'), ('selfies', 'selfie'),
  ('lanyards', 'lanyard'), ('glasses', 'glasses'), ('scissors', 'scissors'),
  ('shoes', 'shoe'), ('clothes', 'clothes'),
  -- Synonyms (campus English and Malay)
  ('calc', 'calculator'), ('kalkulator', 'calculator'),
  ('earbud', 'earphone'), ('headphone', 'earphone'), ('headset', 'earphone'),
  ('tshirt', 'shirt'), ('tee', 'shirt'), ('baju', 'shirt'),
  ('biscuit', 'cookie'), ('biskut', 'cookie'),
  ('mee', 'noodle'), ('mi', 'noodle'),
  ('buku', 'book'), ('textbook', 'book'),
  ('kek', 'cake'), ('roti', 'bread');

-- Words that never identify a product.
create function public.discovery_stop_words()
returns text[]
language sql
immutable
set search_path = ''
as $$
  select array[
    'a', 'an', 'and', 'any', 'the', 'for', 'of', 'with', 'in', 'on', 'to', 'at', 'or', 'my', 'some',
    'cheap', 'new', 'used', 'second', 'hand', 'secondhand', 'want', 'need', 'looking', 'please', 'pls',
    'good', 'nice', 'best', 'buy', 'sell', 'selling', 'wtb', 'wts',
    'nak', 'cari', 'murah', 'baru', 'terpakai', 'yang', 'untuk', 'dan', 'ada', 'tak'
  ];
$$;

-- Simple English singular forms. Exceptions live in discovery_synonyms.
create function public.discovery_singular(word text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when char_length(word) <= 3 then word
    when word ~ 'ies$' and char_length(word) > 4 then left(word, -3) || 'y'
    when word ~ '(ches|shes|xes|sses|zes)$' then left(word, -2)
    when word ~ 's$' and word !~ '(ss|us|is)$' then left(word, -1)
    else word
  end;
$$;

-- A text's discovery terms, in order: normalised, stop words removed, then
-- each word mapped through the synonyms (a curated entry is final) or else
-- singularised and mapped again ("calcs" -> calc -> calculator).
create function public.discovery_terms(value text)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(coalesce(s2.canonical, sg.word) order by w.ord), '{}')
  from unnest(string_to_array(public.normalize_text(value), ' ')) with ordinality as w (raw, ord)
  left join public.discovery_synonyms as s1 on s1.term = w.raw
  cross join lateral (
    select case when s1.term is not null then s1.canonical
                else public.discovery_singular(w.raw) end as word
  ) as sg
  left join public.discovery_synonyms as s2 on s2.term = sg.word
  where char_length(w.raw) >= 2
    and not (w.raw = any (public.discovery_stop_words()));
$$;

-- `{category}|{head term}`, or null when the name has no meaningful word.
create function public.discovery_cluster_key(category text, name text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select case when cardinality(t.terms) = 0 then null
              else category || '|' || t.terms[cardinality(t.terms)] end
  from (select public.discovery_terms(name) as terms) as t;
$$;

-- "RM 12" or "RM 4.50", for the explanations.
create function public.discovery_rm(sen integer)
returns text
language sql
immutable
set search_path = ''
as $$
  select 'RM ' || (sen / 100)::text
         || case when sen % 100 = 0 then '' else '.' || lpad((sen % 100)::text, 2, '0') end;
$$;

------------------------------------------------------------------------------
-- Requests and interests
------------------------------------------------------------------------------

create table public.product_requests (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles (id) on delete cascade,
  name text not null check (char_length(name) between 3 and 80),
  normalized_name text not null,
  category text not null,
  preferred_price_sen integer check (preferred_price_sen is null or preferred_price_sen between 0 and 10000000),
  campus_area text not null check (char_length(campus_area) between 2 and 80),
  notes text check (notes is null or char_length(notes) <= 300),
  cluster_key text not null,
  status text not null default 'active' check (status in ('active', 'closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger product_requests_set_updated_at
  before update on public.product_requests
  for each row execute function public.set_updated_at();

-- One active request per student per cluster.
create unique index product_requests_one_active_per_cluster
  on public.product_requests (creator_id, cluster_key)
  where status = 'active';
create index product_requests_cluster_idx on public.product_requests (cluster_key) where status = 'active';
create index product_requests_feed_idx on public.product_requests (status, category, created_at desc);

create table public.request_interests (
  request_id uuid not null references public.product_requests (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  -- One interest per student per request.
  primary key (request_id, user_id)
);

create index request_interests_user_idx on public.request_interests (user_id, created_at desc);

------------------------------------------------------------------------------
-- Opportunities (derived)
------------------------------------------------------------------------------

create table public.opportunities (
  cluster_key text primary key,
  category text not null,
  head_term text not null,
  keywords text[] not null default '{}',
  request_ids uuid[] not null default '{}',
  unique_interest_count integer not null check (unique_interest_count >= 0),
  active_supply_count integer not null check (active_supply_count >= 0),
  distinct_seller_count integer not null check (distinct_seller_count >= 0),
  median_listed_price_sen integer,
  median_preferred_price_sen integer,
  price_gap boolean not null,
  score integer not null check (score >= 0),
  reasons text[] not null,
  insufficient_data boolean not null,
  algo_version text not null,
  params jsonb not null,
  last_interest_at timestamptz not null,
  calculated_at timestamptz not null default now()
);

create index opportunities_rank_idx on public.opportunities (score desc, last_interest_at desc, cluster_key);

-- The M4 rule, version 1 (handoff section 7). Changing a weight means a new
-- version, so stored results stay reproducible.
create function public.discovery_params()
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select jsonb_build_object(
    'demand_weight', 5, 'demand_cap', 20,
    'supply_weight', 8, 'supply_cap', 10,
    'price_gap_bonus', 10, 'min_students', 2
  );
$$;

-- Recomputes one cluster: upserts its row, or deletes it when the cluster
-- has no active request.
create function public.recompute_opportunity(target_cluster text)
returns void
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  p jsonb := public.discovery_params();
  v_ids uuid[];
  v_category text;
  v_head text;
  v_keywords text[];
  v_last timestamptz;
  d integer;
  s integer;
  sellers integer;
  med_listed integer;
  med_preferred integer;
  gap boolean;
  v_score integer;
  v_reasons text[];
begin
  select array_agg(r.id order by r.created_at, r.id), min(r.category), max(r.created_at)
  into v_ids, v_category, v_last
  from public.product_requests as r
  where r.cluster_key = target_cluster and r.status = 'active';

  if v_ids is null then
    delete from public.opportunities as o where o.cluster_key = target_cluster;
    return;
  end if;
  v_head := regexp_replace(target_cluster, '^.*\|', '');

  select coalesce(array_agg(distinct t order by t), '{}') into v_keywords
  from public.product_requests as r, unnest(public.discovery_terms(r.name)) as t
  where r.id = any (v_ids);

  -- D: creators and interested students, each once.
  select count(*) into d from (
    select r.creator_id as student from public.product_requests as r where r.id = any (v_ids)
    union
    select i.user_id from public.request_interests as i where i.request_id = any (v_ids)
  ) as students;
  select greatest(v_last, coalesce(max(i.created_at), v_last)) into v_last
  from public.request_interests as i where i.request_id = any (v_ids);

  -- S: visible, available listings in the category whose title has the head term.
  select count(*), count(distinct l.owner_id),
         round(percentile_cont(0.5) within group (order by l.price_sen))::integer
  into s, sellers, med_listed
  from public.listings as l
  join public.profiles as pr on pr.id = l.owner_id and pr.account_status = 'active'
  left join public.businesses as b on b.id = l.business_id
  where l.status = 'available'
    and not l.hidden
    and (l.business_id is null or b.status = 'approved')
    and l.category = v_category
    and v_head = any (public.discovery_terms(l.title));

  select round(percentile_cont(0.5) within group (order by r.preferred_price_sen))::integer
  into med_preferred
  from public.product_requests as r
  where r.id = any (v_ids) and r.preferred_price_sen is not null;

  gap := med_listed is not null and med_preferred is not null and med_listed > med_preferred;
  v_score := greatest(0,
    (p ->> 'demand_weight')::integer * least(d, (p ->> 'demand_cap')::integer)
    - (p ->> 'supply_weight')::integer * least(s, (p ->> 'supply_cap')::integer)
    + case when gap then (p ->> 'price_gap_bonus')::integer else 0 end);

  -- The explanation, from exactly these numbers.
  v_reasons := array[
    format('%s %s interested', d, case when d = 1 then 'student' else 'students' end),
    case when s = 0 then 'No active matching listings'
         else format('%s active matching %s from %s %s', s,
                     case when s = 1 then 'listing' else 'listings' end,
                     sellers, case when sellers = 1 then 'seller' else 'sellers' end) end,
    case when gap then format('Listings (median %s) are above requested prices (median %s)',
                              public.discovery_rm(med_listed), public.discovery_rm(med_preferred))
         when med_listed is not null and med_preferred is not null
           then format('Listings (median %s) are within requested prices (median %s)',
                       public.discovery_rm(med_listed), public.discovery_rm(med_preferred))
         when med_listed is null then 'No listing prices to compare'
         else 'No preferred prices given' end
  ];
  if d < (p ->> 'min_students')::integer then
    v_reasons := v_reasons || 'Insufficient data: fewer than 2 interested students'::text;
  end if;

  insert into public.opportunities as o (
    cluster_key, category, head_term, keywords, request_ids, unique_interest_count, active_supply_count,
    distinct_seller_count, median_listed_price_sen, median_preferred_price_sen, price_gap, score, reasons,
    insufficient_data, algo_version, params, last_interest_at, calculated_at
  ) values (
    target_cluster, v_category, v_head, v_keywords, v_ids, d, s, sellers, med_listed, med_preferred, gap,
    v_score, v_reasons, d < (p ->> 'min_students')::integer, 'm4-v1', p, v_last, now()
  )
  on conflict (cluster_key) do update set
    category = excluded.category,
    head_term = excluded.head_term,
    keywords = excluded.keywords,
    request_ids = excluded.request_ids,
    unique_interest_count = excluded.unique_interest_count,
    active_supply_count = excluded.active_supply_count,
    distinct_seller_count = excluded.distinct_seller_count,
    median_listed_price_sen = excluded.median_listed_price_sen,
    median_preferred_price_sen = excluded.median_preferred_price_sen,
    price_gap = excluded.price_gap,
    score = excluded.score,
    reasons = excluded.reasons,
    insufficient_data = excluded.insufficient_data,
    algo_version = excluded.algo_version,
    params = excluded.params,
    last_interest_at = excluded.last_interest_at,
    calculated_at = excluded.calculated_at;
end;
$$;

-- Recomputes one cluster, or every cluster that has an opportunity or an
-- active request. Returns how many were refreshed.
create function public.recompute_opportunities(target_cluster text default null)
returns integer
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  k text;
  n integer := 0;
begin
  for k in
    select x.key from (
      select r.cluster_key as key from public.product_requests as r where r.status = 'active'
      union
      select o.cluster_key from public.opportunities as o
    ) as x
    where target_cluster is null or x.key = target_cluster
    union
    select target_cluster where target_cluster is not null
  loop
    perform public.recompute_opportunity(k);
    n := n + 1;
  end loop;
  return n;
end;
$$;

------------------------------------------------------------------------------
-- Keeping opportunities current (triggers)
------------------------------------------------------------------------------

create function public.product_requests_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recompute_opportunities(new.cluster_key);
  if tg_op = 'UPDATE' and old.cluster_key is distinct from new.cluster_key then
    perform public.recompute_opportunities(old.cluster_key);
  end if;
  return null;
end;
$$;

create trigger product_requests_recompute
  after insert or update of status, cluster_key, preferred_price_sen on public.product_requests
  for each row execute function public.product_requests_changed();

create function public.request_interests_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  key text;
begin
  select r.cluster_key into key from public.product_requests as r
  where r.id = case when tg_op = 'DELETE' then old.request_id else new.request_id end;
  if key is not null then
    perform public.recompute_opportunities(key);
  end if;
  return null;
end;
$$;

create trigger request_interests_recompute
  after insert or delete on public.request_interests
  for each row execute function public.request_interests_changed();

-- A listing affects the clusters of its category whose head term is in its
-- title, before or after the change.
create function public.listings_changed_for_discovery()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  key text;
  terms text[] := '{}';
  categories text[] := '{}';
begin
  if tg_op in ('UPDATE', 'DELETE') then
    terms := terms || public.discovery_terms(old.title);
    categories := categories || old.category;
  end if;
  if tg_op in ('INSERT', 'UPDATE') then
    terms := terms || public.discovery_terms(new.title);
    categories := categories || new.category;
  end if;

  for key in
    select distinct r.cluster_key from public.product_requests as r
    where r.status = 'active'
      and r.category = any (categories)
      and regexp_replace(r.cluster_key, '^.*\|', '') = any (terms)
  loop
    perform public.recompute_opportunities(key);
  end loop;
  return null;
end;
$$;

create trigger listings_discovery_insert_delete
  after insert or delete on public.listings
  for each row execute function public.listings_changed_for_discovery();

create trigger listings_discovery_update
  after update of status, hidden, title, category, price_sen on public.listings
  for each row
  when ((old.status, old.hidden, old.title, old.category, old.price_sen)
        is distinct from (new.status, new.hidden, new.title, new.category, new.price_sen))
  execute function public.listings_changed_for_discovery();

-- Suspending or reinstating a seller or a business changes supply anywhere.
create function public.supply_owner_changed()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform public.recompute_opportunities();
  return null;
end;
$$;

create trigger profiles_discovery_status
  after update of account_status on public.profiles
  for each row
  when (old.account_status is distinct from new.account_status)
  execute function public.supply_owner_changed();

create trigger businesses_discovery_status
  after update of status on public.businesses
  for each row
  when (old.status is distinct from new.status)
  execute function public.supply_owner_changed();

------------------------------------------------------------------------------
-- Client functions
------------------------------------------------------------------------------

create function public.create_product_request(
  name text,
  category text,
  campus_area text,
  preferred_price_sen integer default null,
  notes text default null
)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_name text := btrim(coalesce(create_product_request.name, ''));
  v_area text := btrim(coalesce(create_product_request.campus_area, ''));
  v_notes text := nullif(btrim(coalesce(create_product_request.notes, '')), '');
  v_key text;
  new_id uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;

  if char_length(v_name) not between 3 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'Name the product in 3 to 80 characters.');
  end if;
  if create_product_request.category is null
     or not (create_product_request.category = any (public.listing_categories())) then
    perform public.raise_app_error('INVALID_INPUT', 'Choose one of the listed categories.');
  end if;
  if char_length(v_area) not between 2 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'Say where on campus (2 to 80 characters).');
  end if;
  if create_product_request.preferred_price_sen is not null
     and create_product_request.preferred_price_sen not between 0 and 10000000 then
    perform public.raise_app_error('INVALID_INPUT', 'The price must be between RM 0 and RM 100,000.');
  end if;
  if char_length(v_notes) > 300 then
    perform public.raise_app_error('INVALID_INPUT', 'Notes can be up to 300 characters.');
  end if;
  v_key := public.discovery_cluster_key(create_product_request.category, v_name);
  if v_key is null then
    perform public.raise_app_error('INVALID_INPUT', 'Describe the product itself, e.g. "chocolate brownie".');
  end if;

  if (select count(*) from public.product_requests as r
      where r.creator_id = uid and r.created_at > now() - interval '1 day') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve made a lot of requests today. Try again tomorrow.');
  end if;
  if exists (select 1 from public.product_requests as r
             where r.creator_id = uid and r.cluster_key = v_key and r.status = 'active') then
    perform public.raise_app_error('ALREADY_EXISTS', 'You already have an active request like this.');
  end if;

  insert into public.product_requests (creator_id, name, normalized_name, category, preferred_price_sen,
                                       campus_area, notes, cluster_key)
  values (uid, v_name, array_to_string(public.discovery_terms(v_name), ' '), create_product_request.category,
          create_product_request.preferred_price_sen, v_area, v_notes, v_key)
  returning id into new_id;

  return jsonb_build_object('request_id', new_id, 'cluster_key', v_key);
end;
$$;

create function public.close_product_request(request_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  request public.product_requests;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  select * into request from public.product_requests as r where r.id = close_product_request.request_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Request not found.');
  end if;
  if request.creator_id <> auth.uid() then
    perform public.raise_app_error('FORBIDDEN', 'You can only close your own requests.');
  end if;
  if request.status <> 'active' then
    perform public.raise_app_error('INVALID_TRANSITION', 'This request is already closed.');
  end if;

  update public.product_requests as r set status = 'closed' where r.id = request.id;
  return jsonb_build_object('request_id', request.id, 'status', 'closed');
end;
$$;

create function public.toggle_request_interest(request_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  request public.product_requests;
  now_interested boolean;
  total integer;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  -- Locked so two taps from the same student can't interleave.
  select * into request from public.product_requests as r where r.id = toggle_request_interest.request_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Request not found.');
  end if;
  if request.creator_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'This is your request, so you''re already counted.');
  end if;
  if request.status <> 'active' then
    perform public.raise_app_error('INVALID_TRANSITION', 'This request is closed.');
  end if;

  delete from public.request_interests as i where i.request_id = request.id and i.user_id = uid;
  now_interested := not found;
  if now_interested then
    if (select count(*) from public.request_interests as i
        where i.user_id = uid and i.created_at > now() - interval '1 hour') >= 30 then
      perform public.raise_app_error('RATE_LIMITED', 'You''ve shown interest in a lot of requests. Try again in an hour.');
    end if;
    insert into public.request_interests (request_id, user_id) values (request.id, uid);
  end if;

  select count(*) into total from public.request_interests as i where i.request_id = request.id;
  return jsonb_build_object('request_id', request.id, 'interested', now_interested, 'interest_count', total);
end;
$$;

-- What the requests list shows: no identities, only counts and whether the
-- caller is interested or made it.
create type public.request_card as (
  id uuid,
  name text,
  category text,
  preferred_price_sen integer,
  campus_area text,
  notes text,
  status text,
  cluster_key text,
  created_at timestamptz,
  interest_count integer,
  i_am_interested boolean,
  is_mine boolean
);

create function public.list_product_requests(
  category text default null,
  cluster_key text default null,
  mine boolean default false,
  page_size integer default 20,
  page_offset integer default 0
)
returns setof public.request_card
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  uid uuid := auth.uid();
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if list_product_requests.page_size is null or list_product_requests.page_size not between 1 and 50
     or list_product_requests.page_offset is null or list_product_requests.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 50 requests from a non-negative offset.');
  end if;

  return query
  select r.id, r.name, r.category, r.preferred_price_sen, r.campus_area, r.notes, r.status, r.cluster_key,
         r.created_at,
         (select count(*)::integer from public.request_interests as i where i.request_id = r.id),
         exists (select 1 from public.request_interests as i where i.request_id = r.id and i.user_id = uid),
         r.creator_id = uid
  from public.product_requests as r
  where (case when coalesce(list_product_requests.mine, false) then r.creator_id = uid else r.status = 'active' end)
    and (list_product_requests.category is null or r.category = list_product_requests.category)
    and (list_product_requests.cluster_key is null or r.cluster_key = list_product_requests.cluster_key)
  order by r.created_at desc, r.id
  limit list_product_requests.page_size
  offset list_product_requests.page_offset;
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.discovery_synonyms enable row level security;
alter table public.product_requests enable row level security;
alter table public.request_interests enable row level security;
alter table public.opportunities enable row level security;

-- Written only by the functions above; the synonyms have no client access.
revoke all on public.discovery_synonyms, public.product_requests, public.request_interests, public.opportunities
from anon, authenticated;
grant select on public.product_requests, public.request_interests, public.opportunities to authenticated;

create policy "Students read active requests and their own; admins read all"
  on public.product_requests for select to authenticated
  using ((status = 'active' and (select public.is_student()))
         or creator_id = (select auth.uid())
         or (select public.is_admin()));

create policy "Students read their own interests"
  on public.request_interests for select to authenticated
  using (user_id = (select auth.uid()));

create policy "Students and staff read opportunities"
  on public.opportunities for select to authenticated
  using ((select public.is_student()) or (select public.is_staff()));

revoke execute on function
  public.discovery_stop_words(),
  public.discovery_singular(text),
  public.discovery_terms(text),
  public.discovery_cluster_key(text, text),
  public.discovery_rm(integer),
  public.discovery_params(),
  public.recompute_opportunity(text),
  public.recompute_opportunities(text),
  public.product_requests_changed(),
  public.request_interests_changed(),
  public.listings_changed_for_discovery(),
  public.supply_owner_changed()
from public, anon, authenticated;

revoke execute on function
  public.create_product_request(text, text, text, integer, text),
  public.close_product_request(uuid),
  public.toggle_request_interest(uuid),
  public.list_product_requests(text, text, boolean, integer, integer)
from public, anon;

grant execute on function
  public.create_product_request(text, text, text, integer, text),
  public.close_product_request(uuid),
  public.toggle_request_interest(uuid),
  public.list_product_requests(text, text, boolean, integer, integer)
to authenticated;
