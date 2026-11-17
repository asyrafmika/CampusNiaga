-- Pickup pins: the optional map pin on listings (upsert_listing,
-- search_listings, get_listing) and on storefronts (update_storefront,
-- get_my_business, get_storefront), its validation and its privileges.
begin;
create extension if not exists pgtap with schema extensions;
select plan(35);

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

-- Ali runs Ali Bakes (approved); Siti buys; Sam has no business; Ben uses gmail.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('66666666-6666-6666-6666-666666666666', 'sam@student.usm.my', now(), '{"name": "Sam"}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, description, pickup_details, status) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Brownies.', 'Tekun lobby, 6-8pm', 'approved');

-- Schema ---------------------------------------------------------------------------------------
select col_type_is('public', 'listings', 'pickup_lat', 'double precision', 'listings have a pin latitude');
select col_type_is('public', 'businesses', 'pickup_lng', 'double precision', 'businesses have a pin longitude');
select hasnt_function('public', 'update_storefront', array['text', 'text', 'text'], 'the pinless update_storefront is gone');
select throws_ok($$ insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, pickup_area, pickup_lat)
  values ('11111111-1111-1111-1111-111111111111', 'Half pin', 'half pin', 'Books', 100, 'good', 'Tekun', 5.35) $$,
  '23514', null, 'the table refuses a latitude without a longitude, whoever writes it');
select throws_ok($$ update public.businesses set pickup_lat = 51.5, pickup_lng = -0.12 where id = 'bbbbbbbb-0000-0000-0000-000000000011' $$,
  '23514', null, 'the table refuses a pin outside Malaysia');
select throws_ok($$ insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, pickup_area, pickup_lat, pickup_lng)
  values ('11111111-1111-1111-1111-111111111111', 'Far pin', 'far pin', 'Books', 100, 'good', 'Tekun', 5.3, 95.0) $$,
  '23514', null, 'the listings table refuses a pin outside Malaysia, even with a Malaysian latitude');

-- Privileges ------------------------------------------------------------------------------------
select ok(has_function_privilege('authenticated',
  'public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text, double precision, double precision)', 'execute'),
  'signed-in users can call upsert_listing with a pin');
select ok(not has_function_privilege('anon',
  'public.upsert_listing(uuid, text, text, text, integer, text, integer, text[], text, text, double precision, double precision)', 'execute'),
  'signed-out callers cannot');
select ok(has_function_privilege('authenticated', 'public.update_storefront(text, text, text, double precision, double precision)', 'execute'),
  'signed-in users can call update_storefront with a pin');
select ok(not has_function_privilege('anon', 'public.update_storefront(text, text, text, double precision, double precision)', 'execute'),
  'signed-out callers cannot');
select ok(not has_function_privilege('authenticated', 'public.pickup_pin_problem(double precision, double precision)', 'execute'),
  'the pin check helper is internal');

-- Listings --------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin
  perform set_config('test.item', public.upsert_listing(null, 'Casio calculator', 'fx-570', 'Electronics', 3000, 'good', 1, '{}', 'Desasiswa Tekun lobby',
    'personal', 5.3559, 100.3022) ->> 'listing_id', true);
end $$;
reset role;
select is((select pickup_lat::text || ',' || pickup_lng::text from public.listings where id = current_setting('test.item')::uuid),
  '5.3559,100.3022', 'the seller pins the pickup spot when creating a listing');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', 'fx-570', 'Electronics', 3000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Desasiswa Tekun lobby', null, 5.3563, 100.3031) $$,
  'and moves the pin when editing');
select lives_ok($$ select public.set_listing_status(current_setting('test.item')::uuid, 'available') $$, 'and publishes it');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', '', 'Electronics', 3000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Tekun', null, 5.3563, null) $$),
  'INVALID_INPUT', 'a latitude without a longitude is refused');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', '', 'Electronics', 3000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Tekun', null, 0, 0) $$),
  'INVALID_INPUT', 'a pin outside Malaysia is refused');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', '', 'Electronics', 3000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Tekun', null, 5.3, 95.0) $$),
  'INVALID_INPUT', 'so is one whose longitude alone is outside');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', '', 'Electronics', 3000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Tekun', null, 'NaN', 'NaN') $$),
  'INVALID_INPUT', 'a pin that is not a number is refused');

-- Another student sees the pin, but cannot move it
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select pickup_lat::text || ',' || pickup_lng::text from public.search_listings('calculator')),
  '5.3563,100.3031', 'buyers see the pin in the feed');
select is((select pickup_lat::text || ',' || pickup_lng::text from public.get_listing(current_setting('test.item')::uuid)),
  '5.3563,100.3031', 'and on the listing page');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', '', 'Electronics', 1, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Tekun', null, 5.4, 100.3) $$),
  'FORBIDDEN', 'another student cannot move the pin');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select * from public.get_listing(current_setting('test.item')::uuid) $$),
  'NOT_VERIFIED_STUDENT', 'a non-USM account cannot see the listing or its pin');

-- Removing the pin
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', 'fx-570', 'Electronics', 3000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Desasiswa Tekun lobby') $$,
  'the seller saves without a pin');
select is((select coalesce(pickup_lat::text, 'none') from public.get_listing(current_setting('test.item')::uuid)),
  'none', 'which removes it; the pickup text stays');
select is((select pickup_area from public.get_listing(current_setting('test.item')::uuid)),
  'Desasiswa Tekun lobby', 'the pickup text is unchanged');
reset role;

-- Storefront ------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.update_storefront('Brownies.', 'Tekun lobby, 6-8pm', null, 5.3561, 100.3025) $$,
  'the owner pins the storefront pickup spot');
select is((select (public.get_my_business() ->> 'pickup_lat') || ',' || (public.get_my_business() ->> 'pickup_lng')),
  '5.3561,100.3025', 'and sees it on their business');
select is(pg_temp.error_reason($$ select public.update_storefront('Brownies.', 'Tekun lobby, 6-8pm', null, null, 100.3025) $$),
  'INVALID_INPUT', 'a longitude without a latitude is refused');
select is(pg_temp.error_reason($$ select public.update_storefront('Brownies.', 'Tekun lobby, 6-8pm', null, 35.68, 139.69) $$),
  'INVALID_INPUT', 'a storefront pin outside Malaysia is refused');
do $$ begin
  perform set_config('test.product', public.upsert_listing(null, 'Brownie box', '', 'Food & Beverage', 1200, 'new', 4, '{}', 'Tekun lobby',
    'business', 5.3561, 100.3025) ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.product')::uuid, 'Brownie box', '', 'Food & Beverage', 1200, 'new', 4,
    array['11111111-1111-1111-1111-111111111111/' || current_setting('test.product') || '/1.jpg'], 'Tekun lobby', null, 5.3561, 100.3025);
  perform public.set_listing_status(current_setting('test.product')::uuid, 'available');
end $$;

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select (s -> 'business' ->> 'pickup_lat') || ',' || (s -> 'business' ->> 'pickup_lng')
  from public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') as s),
  '5.3561,100.3025', 'buyers see the storefront pin');
select is((select (s -> 'listings' -> 0 ->> 'pickup_lat') from public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') as s),
  '5.3561', 'and each product''s pin on the storefront');
select is(pg_temp.error_reason($$ select public.update_storefront('Hacked.', 'Somewhere else', null, 5.4, 100.3) $$),
  'FORBIDDEN', 'a buyer cannot pin a storefront');
set local request.jwt.claims to '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.update_storefront('Sam snacks.', 'Restu cafe', null, 5.4, 100.3) $$),
  'FORBIDDEN', 'neither can another student');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.update_storefront('Brownies.', 'Tekun lobby, 6-8pm') $$, 'the owner saves without a pin');
select is(public.get_my_business() ->> 'pickup_lat', null, 'which removes the storefront pin');
reset role;

select * from finish();
rollback;
