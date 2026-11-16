-- Opportunities (M4): the score formula and its caps, medians and the price
-- gap, what counts as supply, the explanations, insufficient data, ranking,
-- versioning, triggers keeping results current, and who reads them.
begin;
create extension if not exists pgtap with schema extensions;
select plan(40);

create function pg_temp.error_reason(statement text) returns text language plpgsql as $$
declare reason text;
begin
  execute statement;
  return 'no error';
exception when others then
  get stacked diagnostics reason = pg_exception_detail;
  return coalesce(nullif(reason, ''), sqlstate);
end;
$$;

create function pg_temp.as_user(id text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

-- The brownie cluster's current numbers, "D/S/sellers/listed/preferred/gap/score/insufficient".
create function pg_temp.brownie() returns text language sql as $$
  select unique_interest_count || '/' || active_supply_count || '/' || distinct_seller_count || '/'
         || coalesce(median_listed_price_sen::text, '-') || '/' || coalesce(median_preferred_price_sen::text, '-') || '/'
         || price_gap || '/' || score || '/' || insufficient_data
  from public.opportunities where cluster_key = 'Food & Beverage|brownie';
$$;

-- Students A-D, a seller with a personal shop, and a business owner.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('a0000000-0000-0000-0000-00000000000a', 'a@student.usm.my', now(), '{"name": "A"}'),
  ('b0000000-0000-0000-0000-00000000000b', 'b@student.usm.my', now(), '{"name": "B"}'),
  ('c0000000-0000-0000-0000-00000000000c', 'c@student.usm.my', now(), '{"name": "C"}'),
  ('d0000000-0000-0000-0000-00000000000d', 'd@student.usm.my', now(), '{"name": "D"}'),
  ('50000000-0000-0000-0000-000000000005', 'seller@student.usm.my', now(), '{"name": "Seller"}'),
  ('60000000-0000-0000-0000-000000000006', 'biz@student.usm.my', now(), '{"name": "Biz"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- One request: one student, no supply --------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a');
do $$ begin
  perform set_config('test.a', public.create_product_request('brownie', 'Food & Beverage', 'Tekun', 500) ->> 'request_id', true);
end $$;
reset role;
select is(pg_temp.brownie(), '1/0/0/-/500/false/5/true', 'one student: D = 1, no supply, score 5 x 1, insufficient data');
select is((select reasons from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  array['1 student interested', 'No active matching listings', 'No listing prices to compare', 'Insufficient data: fewer than 2 interested students'],
  'the explanation says so, including that the data is insufficient');
select is((select category || '/' || head_term || '/' || algo_version from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  'Food & Beverage/brownie/m4-v1', 'the result names its category, head term and algorithm version');
select is((select params from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  '{"demand_weight": 5, "demand_cap": 20, "supply_weight": 8, "supply_cap": 10, "price_gap_bonus": 10, "min_students": 2}'::jsonb,
  'and stores the parameters it used');

-- Demand -------------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('b0000000-0000-0000-0000-00000000000b');
select lives_ok($$ select public.toggle_request_interest(current_setting('test.a')::uuid) $$, 'B is interested');
reset role;
select is(pg_temp.brownie(), '2/0/0/-/500/false/10/false', 'two students: D = 2, score 10, enough data');
set local role authenticated;
select pg_temp.as_user('b0000000-0000-0000-0000-00000000000b');
do $$ begin
  perform set_config('test.b', public.create_product_request('Brownies', 'Food & Beverage', 'Aman', 700) ->> 'request_id', true);
end $$;
reset role;
select is((select cardinality(request_ids) from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 2, 'B''s own request joins the cluster');
select is(pg_temp.brownie(), '2/0/0/-/600/false/10/false', 'B is still one student; the preferred median is now RM 6');
select is((select keywords from public.opportunities where cluster_key = 'Food & Beverage|brownie'), array['brownie'], 'the cluster''s keywords');

-- Supply ----------------------------------------------------------------------------------------------------------
insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('f0000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000005', 'Fudgy Brownies Box', 'fudgy brownies box', 'Food & Beverage', 800, 'new', array['p/1.jpg'], 3, 'Tekun', 'available');
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 'a matching listing: S = 1, and its price is above what students want: 10 - 8 + 10 = 12');
select is((select reasons from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  array['2 students interested', '1 active matching listing from 1 seller', 'Listings (median RM 8) are above requested prices (median RM 6)'],
  'the explanation uses exactly these numbers');

insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('50000000-0000-0000-0000-000000000005', 'Brownie mould', 'brownie mould', 'Hostel Essentials', 900, 'new', array['p/2.jpg'], 1, 'Tekun', 'available'),
  ('50000000-0000-0000-0000-000000000005', 'Chocolate cake', 'chocolate cake', 'Food & Beverage', 900, 'new', array['p/3.jpg'], 1, 'Tekun', 'available'),
  ('50000000-0000-0000-0000-000000000005', 'Brownie draft', 'brownie draft', 'Food & Beverage', 100, 'new', '{}', 1, 'Tekun', 'draft');
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 'other categories, other products and drafts are not supply');

update public.listings set price_sen = 500 where id = 'f0000000-0000-0000-0000-000000000001';
select is(pg_temp.brownie(), '2/1/1/500/600/false/2/false', 'cheaper listings remove the price gap: 10 - 8 = 2');
select is((select reasons[3] from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  'Listings (median RM 5) are within requested prices (median RM 6)', 'and the explanation changes with it');
update public.listings set price_sen = 800 where id = 'f0000000-0000-0000-0000-000000000001';

-- Hidden, sold, suspended and business supply
update public.listings set hidden = true where id = 'f0000000-0000-0000-0000-000000000001';
select is(pg_temp.brownie(), '2/0/0/-/600/false/10/false', 'a hidden listing is not supply');
update public.listings set hidden = false where id = 'f0000000-0000-0000-0000-000000000001';
update public.listings set status = 'closed' where id = 'f0000000-0000-0000-0000-000000000001';
select is(pg_temp.brownie(), '2/0/0/-/600/false/10/false', 'nor is a closed one');
update public.listings set status = 'available' where id = 'f0000000-0000-0000-0000-000000000001';
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 're-opening restores it');
update public.profiles set account_status = 'suspended' where id = '50000000-0000-0000-0000-000000000005';
select is(pg_temp.brownie(), '2/0/0/-/600/false/10/false', 'a suspended seller''s listings are not supply');
update public.profiles set account_status = 'active' where id = '50000000-0000-0000-0000-000000000005';
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 'and count again after reactivation');

insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000006', '60000000-0000-0000-0000-000000000006', 'Biz Bakes', 'Food & Beverage', 'Brownies and more, every week.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000006', '60000000-0000-0000-0000-000000000006', 'aaaaaaaa-0000-0000-0000-000000000006', 'Biz Bakes', 'Tekun lobby');
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('f0000000-0000-0000-0000-000000000002', '60000000-0000-0000-0000-000000000006', 'business', 'bbbbbbbb-0000-0000-0000-000000000006', 'Walnut brownie', 'walnut brownie', 'Food & Beverage', 1000, 'new', array['p/4.jpg'], 5, 'Tekun', 'available');
select is(pg_temp.brownie(), '2/2/2/900/600/true/4/false', 'a business product is supply too: S = 2 from 2 sellers, median RM 9: 10 - 16 + 10 = 4');
update public.businesses set status = 'suspended' where id = 'bbbbbbbb-0000-0000-0000-000000000006';
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 'a suspended business''s products are not supply');
update public.businesses set status = 'approved' where id = 'bbbbbbbb-0000-0000-0000-000000000006';
delete from public.listings where id = 'f0000000-0000-0000-0000-000000000002';
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 'deleting a listing removes its supply');

-- Caps and the floor -----------------------------------------------------------------------------------------------
insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status)
select '50000000-0000-0000-0000-000000000005', 'Brownie ' || n, 'brownie ' || n, 'Food & Beverage', 300, 'new', array['p/x.jpg'], 1, 'Tekun', 'available'
from generate_series(1, 11) as n;
select is((select active_supply_count || '/' || score from public.opportunities where cluster_key = 'Food & Beverage|brownie'), '12/0',
  'supply counts every listing, the score caps it at 10 and never goes below 0');
delete from public.listings where title ~ '^Brownie [0-9]+$';

insert into auth.users (id, email, email_confirmed_at)
select ('70000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, 'fan' || n || '@student.usm.my', now()
from generate_series(1, 24) as n;
set local role authenticated;
select pg_temp.as_user('c0000000-0000-0000-0000-00000000000c');
do $$ begin
  perform set_config('test.c', public.create_product_request('Lanyard', 'Others', 'Tekun', 300) ->> 'request_id', true);
end $$;
reset role;
insert into public.request_interests (request_id, user_id)
select current_setting('test.c')::uuid, ('70000000-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid from generate_series(1, 24) as n;
select is((select unique_interest_count || '/' || score from public.opportunities where cluster_key = 'Others|lanyard'), '25/100',
  'demand counts every student, the score caps it at 20 (5 x 20 = 100)');
insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status)
select '50000000-0000-0000-0000-000000000005', 'Lanyard ' || n, 'lanyard ' || n, 'Others', 200, 'new', array['p/l.jpg'], 1, 'Tekun', 'available'
from generate_series(1, 11) as n;
select is((select unique_interest_count || '/' || active_supply_count || '/' || score from public.opportunities where cluster_key = 'Others|lanyard'), '25/11/20',
  'supply is capped at 10 in the score: 100 - 8 x 10 = 20, not 100 - 88');
delete from public.listings where title ~ '^Lanyard [0-9]+$';

-- Ranking and tie-breaks ---------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('d0000000-0000-0000-0000-00000000000d');
do $$ begin
  perform set_config('test.d', public.create_product_request('Phone stand', 'Electronics', 'Tekun') ->> 'request_id', true);
  perform public.create_product_request('Desk lamp', 'Hostel Essentials', 'Tekun');
end $$;
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a');
select lives_ok($$ select public.toggle_request_interest(current_setting('test.d')::uuid) $$, 'A is interested in the phone stand');
reset role;
-- Same score (10) for the lamp and the phone stand would need two students
-- each; give the lamp one more and let the phone stand's interest be newer.
update public.request_interests set created_at = now() + interval '1 minute' where request_id = current_setting('test.d')::uuid;
select public.recompute_opportunities();
set local role authenticated;
select pg_temp.as_user('b0000000-0000-0000-0000-00000000000b');
select results_eq($$ select cluster_key || '=' || score from public.opportunities order by score desc, last_interest_at desc, cluster_key $$,
  $$ values ('Others|lanyard=100'), ('Food & Beverage|brownie=12'), ('Electronics|stand=10'), ('Hostel Essentials|lamp=5') $$,
  'opportunities rank by score, then by the most recent interest');
reset role;

-- Determinism: recomputing changes nothing but the time
select is(public.recompute_opportunities(), 4, 'recomputing everything refreshes each cluster');
select is(pg_temp.brownie(), '2/1/1/800/600/true/12/false', 'and gives the same result');
select is(public.recompute_opportunities('Food & Beverage|brownie'), 1, 'one cluster can be refreshed on its own');

-- Closing requests --------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('a0000000-0000-0000-0000-00000000000a');
select lives_ok($$ select public.close_product_request(current_setting('test.a')::uuid) $$, 'A closes her request');
reset role;
select is(pg_temp.brownie(), '1/1/1/800/700/true/7/true', 'its creator and its interested student leave the cluster: only B remains (5 - 8 + 10 = 7)');
set local role authenticated;
select pg_temp.as_user('b0000000-0000-0000-0000-00000000000b');
select lives_ok($$ select public.close_product_request(current_setting('test.b')::uuid) $$, 'B closes his');
reset role;
select is((select count(*)::int from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 0, 'a cluster without active requests disappears');

-- Who reads opportunities ---------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('c0000000-0000-0000-0000-00000000000c');
select is((select count(*)::int from public.opportunities), 3, 'every verified student reads opportunities, not only businesses');
select is(pg_temp.error_reason($$ update public.opportunities set score = 999 $$), '42501', 'nobody writes them directly');
select is(pg_temp.error_reason($$ delete from public.opportunities $$), '42501', 'or deletes them');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.opportunities), 3, 'staff read them too');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is((select count(*)::int from public.opportunities), 0, 'a non-USM account reads none');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select count(*) from public.opportunities $$), '42501', 'signed-out visitors read none');
reset role;

select * from finish();
rollback;
