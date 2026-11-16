-- Discovery terms, product requests and interests (M4): normalisation and
-- clustering rules, create/close/toggle/list, and who reads what.
begin;
create extension if not exists pgtap with schema extensions;
select plan(67);

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

-- Discovery terms ------------------------------------------------------------------------------------
select is(public.discovery_terms('Chocolate Brownies!'), array['chocolate', 'brownie'], 'lowercase, punctuation removed, curated plural');
select is(public.discovery_terms('brownie'), array['brownie'], 'a singular word stays');
select is(public.discovery_terms('Nak cari brownies murah pls'), array['brownie'], 'English and campus Malay stop words are dropped');
select is(public.discovery_terms('Casio calcs'), array['casio', 'calculator'], 'singularised, then mapped through the synonyms');
select is(public.discovery_terms('Batteries'), array['battery'], '-ies becomes -y');
select is(public.discovery_terms('lunch boxes'), array['lunch', 'box'], '-xes loses -es');
select is(public.discovery_terms('phone chargers'), array['phone', 'charger'], 'a plain -s is removed');
select is(public.discovery_terms('Earbuds'), array['earphone'], 'synonyms meet after singularising');
select is(public.discovery_terms('glasses'), array['glasses'], 'a curated entry is final (not singularised again)');
select is(public.discovery_terms('bus pass'), array['bus', 'pass'], 'short words and -ss endings stay');
select is(public.discovery_terms('the a  ,  for'), '{}'::text[], 'only stop words and punctuation leave nothing');
select is(public.discovery_cluster_key('Food & Beverage', 'chocolate brownie'), 'Food & Beverage|brownie', 'the cluster is the category and the head (last) term');
select is(public.discovery_cluster_key('Food & Beverage', 'Brownies!!'), 'Food & Beverage|brownie', 'plural and punctuation map to the same cluster');
select is(public.discovery_cluster_key('Others', 'brownie'), 'Others|brownie', 'another category is another cluster');
select is(public.discovery_cluster_key('Food & Beverage', 'cheap new'), null, 'a name without a product word has no cluster');
select is(public.discovery_rm(450) || ' / ' || public.discovery_rm(1200) || ' / ' || public.discovery_rm(5), 'RM 4.50 / RM 12 / RM 0.05', 'prices in explanations are RM');

-- People --------------------------------------------------------------------------------------------
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Creating requests ------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin
  perform set_config('test.req', public.create_product_request('  Chocolate Brownie ', 'Food & Beverage', ' Desasiswa Tekun ', 500, ' Fudgy please ') ->> 'request_id', true);
end $$;
reset role;
select is((select name || ' | ' || normalized_name || ' | ' || cluster_key || ' | ' || campus_area || ' | ' || notes || ' | ' || status from public.product_requests where id = current_setting('test.req')::uuid),
  'Chocolate Brownie | chocolate brownie | Food & Beverage|brownie | Desasiswa Tekun | Fudgy please | active', 'a student requests a product; the server derives the terms and the cluster');
select is((select creator_id from public.product_requests where id = current_setting('test.req')::uuid), '11111111-1111-1111-1111-111111111111'::uuid, 'the caller is the creator');

set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.create_product_request('Brownies', 'Food & Beverage', 'Tekun') $$), 'ALREADY_EXISTS', 'a student cannot have two active requests in one cluster');
select is(public.create_product_request('Brownie tin', 'Others', 'Tekun') ->> 'cluster_key', 'Others|tin', 'a different head term is a different cluster');
select is(pg_temp.error_reason($$ select public.create_product_request('ab', 'Food & Beverage', 'Tekun') $$), 'INVALID_INPUT', 'a name under 3 characters is refused');
select is(pg_temp.error_reason($$ select public.create_product_request('cheap new', 'Food & Beverage', 'Tekun') $$), 'INVALID_INPUT', 'a name without a product word is refused');
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Snacks', 'Tekun') $$), 'INVALID_INPUT', 'an unknown category is refused');
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Food & Beverage', 'T') $$), 'INVALID_INPUT', 'a campus area under 2 characters is refused');
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Food & Beverage', 'Tekun', -1) $$), 'INVALID_INPUT', 'a negative preferred price is refused');
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Food & Beverage', 'Tekun', null, repeat('x', 301)) $$), 'INVALID_INPUT', 'notes over 300 characters are refused');
select is(pg_temp.error_reason($$ insert into public.product_requests (creator_id, name, normalized_name, category, campus_area, cluster_key)
  values ('11111111-1111-1111-1111-111111111111', 'Fake', 'fake', 'Others', 'Tekun', 'Others|fake') $$), '42501', 'requests cannot be inserted directly');
select is(pg_temp.error_reason($$ update public.product_requests set status = 'closed' $$), '42501', 'nor updated directly');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Food & Beverage', 'Tekun') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot request');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Food & Beverage', 'Tekun') $$), '42501', 'signed-out visitors cannot request');
reset role;

-- Interest ------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.toggle_request_interest(current_setting('test.req')::uuid) ->> 'interested', 'true', 'Siti taps Interested');
select is((public.toggle_request_interest(current_setting('test.req')::uuid) ->> 'interest_count')::int, 0, 'tapping again removes it: taps never add up');
select is((public.toggle_request_interest(current_setting('test.req')::uuid) ->> 'interest_count')::int, 1, 'and again adds it back, once');
select is((select count(*)::int from public.request_interests), 1, 'Siti reads her own interest');
select is(pg_temp.error_reason($$ insert into public.request_interests (request_id, user_id) values (current_setting('test.req')::uuid, '44444444-4444-4444-4444-444444444444') $$), '42501', 'interests cannot be inserted directly');
select is(pg_temp.error_reason($$ delete from public.request_interests $$), '42501', 'nor deleted directly');
select is(pg_temp.error_reason($$ select public.toggle_request_interest('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing request is reported');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.request_interests), 0, 'Amin cannot see who else is interested');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.toggle_request_interest(current_setting('test.req')::uuid) $$), 'FORBIDDEN', 'the creator is already counted and cannot add interest');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.toggle_request_interest(current_setting('test.req')::uuid) $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot show interest');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.toggle_request_interest(current_setting('test.req')::uuid) $$), '42501', 'signed-out visitors cannot show interest');
reset role;

-- Listing requests --------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select name || '/' || interest_count || '/' || i_am_interested || '/' || is_mine from public.list_product_requests() where id = current_setting('test.req')::uuid),
  'Chocolate Brownie/1/true/false', 'the list shows the interest count and whether Siti is interested, not who asked');
select is((select count(*)::int from public.list_product_requests('Food & Beverage')), 1, 'it filters by category');
select is((select count(*)::int from public.list_product_requests(cluster_key => 'Food & Beverage|brownie')), 1, 'and by cluster');
select is((select count(*)::int from public.list_product_requests(mine => true)), 0, 'Siti has no requests of her own');
select is(pg_temp.error_reason($$ select * from public.list_product_requests(page_size => 0) $$), 'INVALID_INPUT', 'the page size must be sensible');
select is((select count(*)::int from public.product_requests), 2, 'students read active requests');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select is_mine::text from public.list_product_requests() where id = current_setting('test.req')::uuid), 'true', 'the creator sees it is theirs');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select * from public.list_product_requests() $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot list requests');
select is((select count(*)::int from public.product_requests), 0, 'nor read them directly');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select count(*) from public.product_requests $$), '42501', 'signed-out visitors read no requests');
reset role;

-- Closing ------------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.close_product_request(current_setting('test.req')::uuid) $$), 'FORBIDDEN', 'only the creator can close a request');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.close_product_request(current_setting('test.req')::uuid) ->> 'status', 'closed', 'the creator closes it');
select is(pg_temp.error_reason($$ select public.close_product_request(current_setting('test.req')::uuid) $$), 'INVALID_TRANSITION', 'a closed request cannot be closed again');
select is(pg_temp.error_reason($$ select public.close_product_request('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing request is reported');
select is((select status from public.list_product_requests(mine => true) where id = current_setting('test.req')::uuid), 'closed', 'the creator still sees their closed request');
select ok(public.create_product_request('Brownies', 'Food & Beverage', 'Tekun') ->> 'cluster_key' = 'Food & Beverage|brownie', 'after closing, the creator may ask again in that cluster');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.toggle_request_interest(current_setting('test.req')::uuid) $$), 'INVALID_TRANSITION', 'a closed request takes no interest');
select is((select count(*)::int from public.list_product_requests() where id = current_setting('test.req')::uuid), 0, 'a closed request leaves the list');
select is((select count(*)::int from public.product_requests where id = current_setting('test.req')::uuid), 0, 'others cannot read a closed request');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.product_requests), 3, 'admins read every request');
reset role;

-- Rate limits ---------------------------------------------------------------------------------------------------
insert into public.product_requests (creator_id, name, normalized_name, category, campus_area, cluster_key, status)
select '44444444-4444-4444-4444-444444444444', 'Thing ' || n, 'thing ' || n, 'Others', 'Tekun', 'Others|thing' || n, 'closed'
from generate_series(1, 10) as n;
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.create_product_request('Kuih lapis', 'Food & Beverage', 'Tekun') $$), 'RATE_LIMITED', 'an 11th request in a day is refused');
reset role;
insert into public.product_requests (id, creator_id, name, normalized_name, category, campus_area, cluster_key)
select ('eeeeeeee-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, '11111111-1111-1111-1111-111111111111', 'Gadget ' || n, 'gadget ' || n,
       'Electronics', 'Tekun', 'Electronics|gadget' || n
from generate_series(1, 31) as n;
insert into public.request_interests (request_id, user_id)
select ('eeeeeeee-0000-0000-0000-' || lpad(n::text, 12, '0'))::uuid, '22222222-2222-2222-2222-222222222222'
from generate_series(1, 30) as n;
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.toggle_request_interest('eeeeeeee-0000-0000-0000-000000000031') $$), 'RATE_LIMITED', 'a 31st interest in an hour is refused');
select is(public.toggle_request_interest('eeeeeeee-0000-0000-0000-000000000030') ->> 'interested', 'false', 'removing an interest is never rate-limited');
reset role;

-- Functions clients may not call
set local role authenticated;
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is(pg_temp.error_reason($$ select public.recompute_opportunities() $$), '42501', 'nobody can call the recompute directly, not even an admin');
select is(pg_temp.error_reason($$ select public.discovery_terms('brownie') $$), '42501', 'the term helpers are internal');
select is(pg_temp.error_reason($$ select count(*) from public.discovery_synonyms $$), '42501', 'the synonym list is not readable by clients');
reset role;

select * from finish();
rollback;
