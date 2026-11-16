-- Business products (M3): upsert_listing in business mode, business
-- attribution and suspension in the feed, reservations refused for business
-- products, get_storefront, update_storefront and the business-logos rules.
begin;
create extension if not exists pgtap with schema extensions;
select plan(59);

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

-- Ali runs Ali Bakes (approved); Nina runs a suspended business; Sam is a
-- student without a business; Siti buys; Ben uses gmail; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('77777777-7777-7777-7777-777777777777', 'nina@student.usm.my', now(), '{"name": "Nina"}'),
  ('66666666-6666-6666-6666-666666666666', 'sam@student.usm.my', now(), '{"name": "Sam"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'Nina Crafts', 'Others', 'Handmade bookmarks and cards.', '013-3333333', 'Aman Damai', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, description, pickup_details, status) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Brownies and cookies baked weekly.', 'Tekun lobby, 6-8pm', 'approved'),
  ('bbbbbbbb-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'aaaaaaaa-0000-0000-0000-000000000077', 'Nina Crafts', 'Handmade bookmarks.', 'Aman Damai', 'suspended');

-- Creating business products ------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin
  perform set_config('test.product', public.upsert_listing(null, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 4, '{}', 'Tekun lobby', 'business') ->> 'listing_id', true);
  perform set_config('test.personal', public.upsert_listing(null, 'Old textbook', '', 'Books', 2000, 'good', 2, '{}', 'Tekun') ->> 'listing_id', true);
end $$;
reset role;
select is((select mode || '/' || business_id || '/' || status from public.listings where id = current_setting('test.product')::uuid),
  'business/bbbbbbbb-0000-0000-0000-000000000011/draft', 'an approved owner creates a business product for their business');
select is((select mode || '/' || coalesce(business_id::text, 'none') from public.listings where id = current_setting('test.personal')::uuid),
  'personal/none', 'the same owner still lists personal items by default');

set local role authenticated;
set local request.jwt.claims to '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Sam snacks', '', 'Others', 100, 'new', 1, '{}', 'Restu', 'business') $$), 'FORBIDDEN', 'a student without a business cannot list business products');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Sam snacks', '', 'Others', 100, 'new', 1, '{}', 'Restu', 'shop') $$), 'INVALID_INPUT', 'an unknown mode is refused');
set local request.jwt.claims to '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Bookmarks', '', 'Others', 300, 'new', 5, '{}', 'Aman', 'business') $$), 'FORBIDDEN', 'a suspended business cannot list business products');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Ben stuff', '', 'Others', 100, 'new', 1, '{}', 'Restu', 'business') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot list');

-- Editing keeps the mode; then publish
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ select public.upsert_listing(current_setting('test.product')::uuid, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 4,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.product') || '/1.jpg'], 'Tekun lobby') $$, 'the owner edits the product without passing a mode');
select is(public.set_listing_status(current_setting('test.product')::uuid, 'available') ->> 'status', 'available', 'the owner publishes it');
select lives_ok($$ select public.upsert_listing(current_setting('test.personal')::uuid, 'Old textbook', '', 'Books', 2000, 'good', 2,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.personal') || '/1.jpg'], 'Tekun') $$, 'and adds a photo to the personal item');
select lives_ok($$ select public.set_listing_status(current_setting('test.personal')::uuid, 'available') $$, 'and publishes it');
reset role;
select is((select mode from public.listings where id = current_setting('test.product')::uuid), 'business', 'an edit never changes the mode');

-- The feed ------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select business_name || '/' || business_id from public.search_listings('brownie')), 'Ali Bakes/bbbbbbbb-0000-0000-0000-000000000011',
  'a business product appears in the common feed with its business');
select is((select coalesce(business_name, 'none') from public.search_listings('textbook')), 'none', 'a personal item has no business');
select is((select business_name from public.get_listing(current_setting('test.product')::uuid)), 'Ali Bakes', 'the detail page names the business');

-- Reservations are for personal items only
select is(pg_temp.error_reason($$ select public.request_reservation(current_setting('test.product')::uuid) $$), 'ITEM_UNAVAILABLE', 'a business product cannot be reserved');
select is(public.request_reservation(current_setting('test.personal')::uuid) ->> 'status', 'requested', 'a personal item still can');
reset role;
select is((select stock from public.listings where id = current_setting('test.product')::uuid), 4, 'a refused reservation leaves the stock alone');

-- Suspension removes business products at once
update public.businesses set status = 'suspended' where id = 'bbbbbbbb-0000-0000-0000-000000000011';
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.search_listings('brownie')), 0, 'a suspended business''s products leave the feed');
select is(pg_temp.error_reason($$ select * from public.get_listing(current_setting('test.product')::uuid) $$), 'NOT_FOUND', 'and their detail pages');
select is((select count(*)::int from public.search_listings('textbook')), 1, 'the owner''s personal items stay');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select title from public.get_listing(current_setting('test.product')::uuid)), 'Brownie box', 'the owner still sees the product');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.product')::uuid, 'Brownie box', '', 'Food & Beverage', 1200, 'new', 4,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.product') || '/1.jpg'], 'Tekun lobby') $$), 'FORBIDDEN', 'but cannot edit it while suspended');
reset role;
update public.businesses set status = 'approved' where id = 'bbbbbbbb-0000-0000-0000-000000000011';

-- Restocking a sold-out product
update public.listings set stock = 0, status = 'sold' where id = current_setting('test.product')::uuid;
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.upsert_listing(current_setting('test.product')::uuid, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 5,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.product') || '/1.jpg'], 'Tekun lobby') ->> 'status', 'available',
  'restocking a sold-out business product puts it back on sale');
reset role;
select is((select status || '/' || stock from public.listings where id = current_setting('test.product')::uuid), 'available/5', 'with the new stock');
update public.listings set stock = 0, status = 'sold' where id = current_setting('test.personal')::uuid;
set local role authenticated;
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.personal')::uuid, 'Old textbook', '', 'Books', 2000, 'good', 2,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.personal') || '/1.jpg'], 'Tekun') $$), 'INVALID_TRANSITION', 'a sold personal item still cannot be edited');
reset role;

-- Storefronts ---------------------------------------------------------------------------------------
-- A hidden product and a draft never show on the storefront.
insert into public.listings (owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status, hidden) values
  ('11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Hidden cake', 'hidden cake', 'Food & Beverage', 900, 'new', array['p/1.jpg'], 2, 'Tekun', 'available', true),
  ('11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Draft tart', 'draft tart', 'Food & Beverage', 900, 'new', '{}', 2, 'Tekun', 'draft', false);

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'business' ->> 'name', 'Ali Bakes', 'a student opens a storefront');
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'business' ->> 'owner_name', 'Ali', 'it names the owner');
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') ->> 'is_owner', 'false', 'and knows the visitor is not the owner');
select is((select string_agg(x ->> 'title', ',') from jsonb_array_elements(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'listings') as x),
  'Brownie box', 'only published, visible business products are listed (no personal items, drafts or hidden ones)');
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'categories', '["Food & Beverage"]'::jsonb, 'with their categories');
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'campaigns', '[]'::jsonb, 'and no pre-orders yet');
select is(pg_temp.error_reason($$ select public.get_storefront('bbbbbbbb-0000-0000-0000-000000000077') $$), 'NOT_FOUND', 'a suspended business has no storefront for others');
select is(pg_temp.error_reason($$ select public.get_storefront('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing business has none');
set local request.jwt.claims to '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}';
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000077') -> 'business' ->> 'status', 'suspended', 'its owner still sees it');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') ->> 'is_owner', 'true', 'the owner is recognised');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000077') -> 'business' ->> 'name', 'Nina Crafts', 'admins see suspended storefronts');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot browse storefronts');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') $$), '42501', 'signed-out visitors cannot either');
reset role;

-- Students can't read the businesses table directly; the storefront is the way.
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.businesses), 0, 'students read storefronts only through get_storefront');
reset role;

-- Editing the storefront --------------------------------------------------------------------------------
select is((select public from storage.buckets where id = 'business-logos'), false, 'the business-logos bucket is private');
select is((select file_size_limit from storage.buckets where id = 'business-logos'), 2097152::bigint, 'logos are limited to 2 MB');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.can_upload_business_logo('bbbbbbbb-0000-0000-0000-000000000011/logo.png'), 'the owner may upload a logo into their business folder');
select ok(not public.can_upload_business_logo('bbbbbbbb-0000-0000-0000-000000000011/a/logo.png'), 'logos sit directly in the business folder');
select ok(not public.can_upload_business_logo('bbbbbbbb-0000-0000-0000-000000000077/logo.png'), 'not into another business''s folder');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select ok(not public.can_upload_business_logo('bbbbbbbb-0000-0000-0000-000000000011/logo.png'), 'another student cannot upload a logo');
set local request.jwt.claims to '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}';
select ok(not public.can_upload_business_logo('bbbbbbbb-0000-0000-0000-000000000077/logo.png'), 'a suspended business cannot upload a logo');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.update_storefront('  Fresh brownies every Friday.  ', '  Tekun lobby, Fri 6-8pm  ') ->> 'business_id', 'bbbbbbbb-0000-0000-0000-000000000011', 'the owner updates the storefront');
reset role;
select is((select description || ' | ' || pickup_details || ' | ' || coalesce(logo_path, 'no logo') from public.businesses where id = 'bbbbbbbb-0000-0000-0000-000000000011'),
  'Fresh brownies every Friday. | Tekun lobby, Fri 6-8pm | no logo', 'the trimmed details are saved');
select is((select name from public.businesses where id = 'bbbbbbbb-0000-0000-0000-000000000011'), 'Ali Bakes', 'the approved name stays');

set local role authenticated;
select is(pg_temp.error_reason($$ select public.update_storefront('Hi', 'Tek') $$), 'INVALID_INPUT', 'pickup details under 5 characters are refused');
select is(pg_temp.error_reason($$ select public.update_storefront(repeat('x', 1001), 'Tekun lobby') $$), 'INVALID_INPUT', 'a description over 1,000 characters is refused');
select is(pg_temp.error_reason($$ select public.update_storefront('Hi', 'Tekun lobby', 'bbbbbbbb-0000-0000-0000-000000000011/missing.png') $$), 'INVALID_INPUT', 'a logo that was never uploaded is refused');
select is(pg_temp.error_reason($$ select public.update_storefront('Hi', 'Tekun lobby', 'bbbbbbbb-0000-0000-0000-000000000077/logo.png') $$), 'INVALID_INPUT', 'another business''s logo is refused');
reset role;
insert into storage.objects (bucket_id, name) values ('business-logos', 'bbbbbbbb-0000-0000-0000-000000000011/logo.png');
set local role authenticated;
select lives_ok($$ select public.update_storefront('Fresh brownies every Friday.', 'Tekun lobby, Fri 6-8pm', 'bbbbbbbb-0000-0000-0000-000000000011/logo.png') $$, 'an uploaded logo is accepted');
select is(public.get_my_business() ->> 'logo_path', 'bbbbbbbb-0000-0000-0000-000000000011/logo.png', 'and get_my_business returns it');
select is(pg_temp.error_reason($$ update public.businesses set description = 'Direct' $$), '42501', 'the business row cannot be written directly');

set local request.jwt.claims to '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.update_storefront('Hi', 'Tekun lobby') $$), 'FORBIDDEN', 'a student without a business has no storefront to edit');
set local request.jwt.claims to '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.update_storefront('Hi', 'Aman Damai') $$), 'FORBIDDEN', 'a suspended business cannot edit its storefront');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.update_storefront('Hi', 'Tekun lobby') $$), '42501', 'signed-out visitors cannot edit storefronts');
reset role;

select * from finish();
rollback;
