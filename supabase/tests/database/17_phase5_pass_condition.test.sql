-- Phase 5 pass condition, as one journey with the handoff's fixture: three
-- similar requests ("brownie", "brownies", "chocolate brownie") and a
-- competing listing. Synonym requests cluster, one student counts once,
-- existing supply lowers the score, a price gap affects the result, and the
-- reasons match the data.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

create function pg_temp.as_user(id text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

create function pg_temp.score() returns integer language sql as $$
  select score from public.opportunities where cluster_key = 'Food & Beverage|brownie';
$$;

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('77777777-7777-7777-7777-777777777777', 'mei@student.usm.my', now(), '{"name": "Mei"}'),
  ('50000000-0000-0000-0000-000000000005', 'seller@student.usm.my', now(), '{"name": "Seller"}');

-- 1. Three students ask for the same thing in three ways ---------------------------------------------
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin perform set_config('test.r1', public.create_product_request('brownie', 'Food & Beverage', 'Tekun', 400) ->> 'request_id', true); end $$;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin perform set_config('test.r2', public.create_product_request('Brownies', 'Food & Beverage', 'Aman', 500) ->> 'request_id', true); end $$;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin perform set_config('test.r3', public.create_product_request('Chocolate brownie', 'Food & Beverage', 'Restu', 600) ->> 'request_id', true); end $$;
reset role;

select is((select count(distinct cluster_key)::int from public.product_requests), 1, 'the three requests form one cluster');
select is((select cluster_key from public.product_requests limit 1), 'Food & Beverage|brownie', 'keyed by category and head term');
select is((select cardinality(request_ids) from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 3, 'the opportunity maps every request to it');

-- 2. One student counts once ------------------------------------------------------------------------------
select is((select unique_interest_count from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 3, 'three students: D = 3');
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select public.toggle_request_interest(current_setting('test.r2')::uuid);
                   select public.toggle_request_interest(current_setting('test.r3')::uuid) $$,
  'Ali, who asked already, also taps Interested on the other two');
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select lives_ok($$ select public.toggle_request_interest(current_setting('test.r1')::uuid);
                   select public.toggle_request_interest(current_setting('test.r2')::uuid);
                   select public.toggle_request_interest(current_setting('test.r3')::uuid) $$,
  'Mei taps Interested on all three');
reset role;
select is((select unique_interest_count from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 4,
  'D = 4: Ali counts once, and Mei''s three taps count once');
select is(pg_temp.score(), 20, 'no supply yet: 5 x 4 = 20');

-- 3. Existing supply lowers the score ---------------------------------------------------------------------------
insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status)
values ('f0000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000005', 'Fudgy brownies (box of 6)', 'fudgy brownies box of 6',
        'Food & Beverage', 450, 'new', array['p/1.jpg'], 5, 'Tekun', 'available');
select is((select active_supply_count from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 1, 'the competing listing is matched: S = 1');
select is(pg_temp.score(), 12, 'and lowers the score by 8: 20 - 8 = 12 (RM 4.50 is within the RM 5 median wanted)');

-- 4. A price gap affects the result --------------------------------------------------------------------------------
update public.listings set price_sen = 900 where id = 'f0000000-0000-0000-0000-000000000001';
select ok((select price_gap from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 'at RM 9 the listing is above what students want');
select is(pg_temp.score(), 22, 'which adds 10: 20 - 8 + 10 = 22');

-- 5. The reasons match the data ---------------------------------------------------------------------------------------
select is((select reasons from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  array['4 students interested', '1 active matching listing from 1 seller', 'Listings (median RM 9) are above requested prices (median RM 5)'],
  'the explanation states the counts and prices');
select is((select unique_interest_count || '/' || active_supply_count || '/' || distinct_seller_count || '/' || median_listed_price_sen || '/' || median_preferred_price_sen
           from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  '4/1/1/900/500', 'and those are exactly the stored numbers');
select is((select score from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
          (select greatest(0, 5 * least(unique_interest_count, 20) - 8 * least(active_supply_count, 10) + case when price_gap then 10 else 0 end)
           from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  'the stored score follows the handoff formula from the stored numbers');
select is((select algo_version || ' / ' || (params ->> 'price_gap_bonus') from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  'm4-v1 / 10', 'the result records its algorithm version and parameters');

select * from finish();
rollback;
