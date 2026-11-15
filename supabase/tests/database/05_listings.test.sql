-- Listings: upsert_listing, set_listing_status, search_listings, get_listing,
-- direct-access rules and the listing-photos upload rule.
begin;
create extension if not exists pgtap with schema extensions;
select plan(84);

-- Returns the reason (error DETAIL) an SQL statement fails with, or 'no error'.
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

-- Ali sells, Siti buys and sells, Sam is a suspended student, Ben uses gmail,
-- Nora hasn't confirmed her email, and there is one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali Bin Abu"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}'),
  ('66666666-6666-6666-6666-666666666666', 'nora@student.usm.my', null, '{}'),
  ('77777777-7777-7777-7777-777777777777', 'sam@student.usm.my', now(), '{"name": "Sam"}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Categories -----------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok('Books' = any (public.listing_categories()), 'students can read the listing categories');
reset role;
set local role anon;
select is(pg_temp.error_reason('select public.listing_categories()'), '42501', 'signed-out visitors cannot read the categories');
reset role;

-- Creating a listing -----------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin
  perform set_config('test.calc', public.upsert_listing(
    null, '  Casio FX-570 calculator ', 'Used for one semester. Works perfectly.', 'Stationery',
    2500, 'good', 2, '{}', ' Desasiswa Tekun '
  ) ->> 'listing_id', true);
end $$;
reset role;

select is((select status from public.listings where id = current_setting('test.calc')::uuid), 'draft', 'a new listing starts as a draft');
select is((select owner_id from public.listings where id = current_setting('test.calc')::uuid), '11111111-1111-1111-1111-111111111111'::uuid, 'the caller owns the new listing');
select is((select title from public.listings where id = current_setting('test.calc')::uuid), 'Casio FX-570 calculator', 'the title is trimmed');
select is((select normalized_title from public.listings where id = current_setting('test.calc')::uuid), 'casio fx 570 calculator', 'the normalized title is lowercase without punctuation');
select is((select mode || '/' || stock from public.listings where id = current_setting('test.calc')::uuid), 'personal/2', 'a student listing is personal and its quantity becomes the stock');
select is((select pickup_area from public.listings where id = current_setting('test.calc')::uuid), 'Desasiswa Tekun', 'the pickup area is trimmed');

-- Who may create
set local role authenticated;
set local request.jwt.claims to '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), 'NOT_VERIFIED_STUDENT', 'an unconfirmed student cannot create a listing');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot create a listing');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), '42501', 'signed-out visitors cannot create a listing');
reset role;

-- Input checks
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, ' ab ', '', 'Others', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a title under 3 characters is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', repeat('a', 1001), 'Others', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a description over 1,000 characters is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Weapons', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'an unknown category is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', -1, 'good', 1, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a negative price is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 10000001, 'good', 1, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a price over RM 100,000 is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 0, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a quantity of 0 is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 1000, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a quantity over 999 is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', null, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a missing quantity is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'broken', 1, '{}', 'Desasiswa Aman') $$), 'INVALID_INPUT', 'an unknown condition is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 1, '{}', '   ') $$), 'INVALID_INPUT', 'a blank pickup area is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Desk fan', '', 'Others', 1000, 'good', 1, array['11111111-1111-1111-1111-111111111111/x/1.jpg'], 'Desasiswa Aman') $$), 'INVALID_INPUT', 'a new listing cannot point at photos outside its own folder');

-- Editing ------------------------------------------------------------------------
select lives_ok(
  $$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', 'Used for one semester. Works perfectly.', 'Stationery',
       2000, 'good', 3, array['11111111-1111-1111-1111-111111111111/' || current_setting('test.calc') || '/1.jpg'], 'Desasiswa Tekun') $$,
  'the owner can edit their draft and add photos'
);
reset role;
select is((select price_sen || '/' || cardinality(photo_paths) || '/' || stock from public.listings where id = current_setting('test.calc')::uuid), '2000/1/3', 'the edit is saved, including the new quantity');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', '', 'Stationery', 2000, 'good', 1,
  array['22222222-2222-2222-2222-222222222222/' || current_setting('test.calc') || '/1.jpg'], 'Desasiswa Tekun') $$), 'INVALID_INPUT', 'photos in another user''s folder are rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', '', 'Stationery', 2000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.calc') || '/1.exe'], 'Desasiswa Tekun') $$), 'INVALID_INPUT', 'a file that is not an image is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', '', 'Stationery', 2000, 'good', 1,
  array(select '11111111-1111-1111-1111-111111111111/' || current_setting('test.calc') || '/' || n || '.jpg' from generate_series(1, 6) as n), 'Desasiswa Tekun') $$), 'INVALID_INPUT', 'more than 5 photos are rejected');

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Mine now', '', 'Stationery', 1, 'good', 1, '{}', 'Desasiswa Aman') $$), 'FORBIDDEN', 'a student cannot edit someone else''s listing');
select is(pg_temp.error_reason($$ select public.upsert_listing('99999999-9999-9999-9999-999999999999', 'Desk fan', '', 'Others', 1000, 'good', 1, '{}', 'Desasiswa Aman') $$), 'NOT_FOUND', 'editing a listing that does not exist fails');

-- Publishing -------------------------------------------------------------------------
select is(pg_temp.error_reason($$ select public.set_listing_status(current_setting('test.calc')::uuid, 'available') $$), 'FORBIDDEN', 'a student cannot publish someone else''s listing');
do $$ begin
  perform set_config('test.note', public.upsert_listing(null, 'Lecture notes CAT404', '', 'Books', 500, 'good', 1, '{}', 'Library') ->> 'listing_id', true);
end $$;
select is(pg_temp.error_reason($$ select public.set_listing_status(current_setting('test.note')::uuid, 'available') $$), 'INVALID_INPUT', 'a listing without photos cannot be published');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.set_listing_status(current_setting('test.calc')::uuid, 'available') ->> 'status', 'available', 'the owner publishes a listing with a photo');
select is(pg_temp.error_reason($$ select public.set_listing_status(current_setting('test.calc')::uuid, 'draft') $$), 'INVALID_TRANSITION', 'a published listing cannot go back to draft');
select is(pg_temp.error_reason($$ select public.set_listing_status(current_setting('test.calc')::uuid, 'gone') $$), 'INVALID_INPUT', 'an unknown status is rejected');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', '', 'Stationery', 2000, 'good', 1, '{}', 'Desasiswa Tekun') $$), 'INVALID_INPUT', 'a published listing cannot have its photos removed');
select is(pg_temp.error_reason($$ select public.set_listing_status('99999999-9999-9999-9999-999999999999', 'available') $$), 'NOT_FOUND', 'changing a listing that does not exist fails');

-- Direct table access ---------------------------------------------------------------
select is(pg_temp.error_reason($$ insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, pickup_area)
  values ('11111111-1111-1111-1111-111111111111', 'Sneaky', 'sneaky', 'Others', 1, 'good', 'Here') $$), '42501', 'students cannot insert listings directly');
select is(pg_temp.error_reason($$ update public.listings set price_sen = 1 $$), '42501', 'students cannot update listings directly');
select is(pg_temp.error_reason($$ delete from public.listings $$), '42501', 'students cannot delete listings directly');
select is((select count(*)::int from public.listings), 1, 'a student reads only their own listings');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.listings where id = current_setting('test.calc')::uuid), 0, 'a student cannot read someone else''s listing directly');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.listings), 2, 'an admin reads every listing');
reset role;

-- The feed ------------------------------------------------------------------------------
-- More listings: two of Siti's, one hidden by moderation, one from a suspended seller.
insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, pickup_area, status, hidden) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'Introduction to Algorithms textbook', 'introduction to algorithms textbook', 'Books', 4500, 'like_new', array['p/1.jpg'], 'Library', 'available', false),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'Desk lamp', 'desk lamp', 'Hostel Essentials', 1500, 'good', array['p/1.jpg'], 'Desasiswa Aman', 'available', false),
  ('aaaaaaaa-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'Hidden lamp', 'hidden lamp', 'Hostel Essentials', 900, 'fair', array['p/1.jpg'], 'Desasiswa Aman', 'available', true),
  ('aaaaaaaa-0000-0000-0000-000000000004', '77777777-7777-7777-7777-777777777777', 'Mini fridge', 'mini fridge', 'Hostel Essentials', 15000, 'good', array['p/1.jpg'], 'Desasiswa Fajar', 'available', false);
update public.profiles set account_status = 'suspended' where id = '77777777-7777-7777-7777-777777777777';

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.search_listings()), 3, 'the feed shows the three available, visible listings');
select is((select count(*)::int from public.search_listings() where title = 'Hidden lamp'), 0, 'hidden listings are left out of the feed');
select is((select count(*)::int from public.search_listings() where title = 'Mini fridge'), 0, 'listings from suspended sellers are left out of the feed');
select is((select count(*)::int from public.search_listings() where title = 'Lecture notes CAT404'), 0, 'drafts are left out of the feed');
select results_eq($$ select title from public.search_listings('calculator') $$, array['Casio FX-570 calculator'], 'search finds a listing by a word in its title');
select results_eq($$ select title from public.search_listings('textbooks') $$, array['Introduction to Algorithms textbook'], 'search matches other forms of a word');
select results_eq($$ select title from public.search_listings(category => 'Books') $$, array['Introduction to Algorithms textbook'], 'the category filter works');
select is((select count(*)::int from public.search_listings(max_price_sen => 2000)), 2, 'the maximum price filter includes the limit');
select results_eq($$ select title from public.search_listings(min_price_sen => 2001) $$, array['Introduction to Algorithms textbook'], 'the minimum price filter works');
select results_eq($$ select title from public.search_listings(condition => 'like_new') $$, array['Introduction to Algorithms textbook'], 'the condition filter works');
select results_eq($$ select title from public.search_listings(sort => 'price_asc') $$, array['Desk lamp', 'Casio FX-570 calculator', 'Introduction to Algorithms textbook'], 'sorting by price, lowest first');
select results_eq($$ select title from public.search_listings(sort => 'price_desc', page_size => 1) $$, array['Introduction to Algorithms textbook'], 'sorting by price, highest first');
select is((select seller_name from public.search_listings('calculator')), 'Ali Bin Abu', 'the feed shows the seller''s name');
select results_eq($$ select title from public.search_listings(sort => 'price_asc', page_size => 1, page_offset => 1) $$, array['Casio FX-570 calculator'], 'results come in pages');
select is(pg_temp.error_reason($$ select * from public.search_listings(page_size => 51) $$), 'INVALID_INPUT', 'a page over 50 results is rejected');
select is(pg_temp.error_reason($$ select * from public.search_listings(sort => 'random') $$), 'INVALID_INPUT', 'an unknown sort order is rejected');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select * from public.search_listings() $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot browse');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select * from public.search_listings() $$), '42501', 'signed-out visitors cannot browse');
reset role;

-- The detail page -------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin
  perform set_config('test.draft', public.upsert_listing(null, 'Unfinished draft', '', 'Others', 100, 'fair', 1, '{}', 'Somewhere') ->> 'listing_id', true);
end $$;
select is((select title from public.get_listing(current_setting('test.draft')::uuid)), 'Unfinished draft', 'the owner can open their own draft');
select is(pg_temp.error_reason($$ select * from public.get_listing('aaaaaaaa-0000-0000-0000-000000000003') $$), 'NOT_FOUND', 'a student cannot open a hidden listing');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select title from public.get_listing(current_setting('test.calc')::uuid)), 'Casio FX-570 calculator', 'another student can open a published listing');
select is(pg_temp.error_reason($$ select * from public.get_listing(current_setting('test.draft')::uuid) $$), 'NOT_FOUND', 'another student cannot open a draft');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select title from public.get_listing('aaaaaaaa-0000-0000-0000-000000000003')), 'Hidden lamp', 'an admin can open a hidden listing');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select * from public.get_listing(current_setting('test.calc')::uuid) $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot open a listing');

-- Selling, closing, re-opening -----------------------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.set_listing_status(current_setting('test.calc')::uuid, 'sold') ->> 'status', 'sold', 'the owner marks a listing sold');
reset role;
select is((select stock from public.listings where id = current_setting('test.calc')::uuid), 0, 'marking sold clears every remaining unit');
select throws_ok($$ update public.listings set stock = 0 where id = 'aaaaaaaa-0000-0000-0000-000000000001' $$, '23514', null, 'an available listing always has a unit left');
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_listing_status(current_setting('test.calc')::uuid, 'available') $$), 'INVALID_TRANSITION', 'a sold listing cannot be re-opened');
select is(pg_temp.error_reason($$ select public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', '', 'Stationery', 2000, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.calc') || '/1.jpg'], 'Desasiswa Tekun') $$), 'INVALID_TRANSITION', 'a sold listing cannot be edited');
select is((select count(*)::int from public.search_listings('calculator')), 0, 'a sold listing leaves the feed');

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.set_listing_status('aaaaaaaa-0000-0000-0000-000000000002', 'closed') ->> 'status', 'closed', 'the owner closes a listing');
select is(public.set_listing_status('aaaaaaaa-0000-0000-0000-000000000002', 'available') ->> 'status', 'available', 'the owner re-opens a closed listing');
reset role;

-- Rate limit --------------------------------------------------------------------------------------
insert into public.listings (owner_id, title, normalized_title, category, price_sen, condition, pickup_area)
select '22222222-2222-2222-2222-222222222222', 'Filler ' || n, 'filler ' || n, 'Others', 100, 'good', 'Here'
from generate_series(1, 20 - (select count(*)::int from public.listings where owner_id = '22222222-2222-2222-2222-222222222222')) as n;

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'One too many', '', 'Others', 100, 'good', 1, '{}', 'Here') $$), 'RATE_LIMITED', 'a 21st new listing within an hour is refused');
select lives_ok($$ select public.upsert_listing(current_setting('test.note')::uuid, 'Lecture notes CAT404 (full set)', '', 'Books', 500, 'good', 1, '{}', 'Library') $$, 'editing still works while new listings are rate-limited');

-- Photo uploads ----------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.can_upload_listing_photo('11111111-1111-1111-1111-111111111111/' || current_setting('test.draft') || '/1.jpg'), 'the owner may upload a photo for their listing');
select ok(not public.can_upload_listing_photo('11111111-1111-1111-1111-111111111111/99999999-9999-9999-9999-999999999999/1.jpg'), 'uploads need a listing the student owns');
select ok(not public.can_upload_listing_photo('11111111-1111-1111-1111-111111111111/' || current_setting('test.draft') || '/extra/1.jpg'), 'uploads must sit directly in the listing folder');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select ok(not public.can_upload_listing_photo('11111111-1111-1111-1111-111111111111/' || current_setting('test.draft') || '/1.jpg'), 'a student cannot upload into someone else''s listing folder');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select ok(not public.can_upload_listing_photo('55555555-5555-5555-5555-555555555555/' || current_setting('test.draft') || '/1.jpg'), 'a non-USM account cannot upload photos');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.normalize_text('x') $$), '42501', 'internal helpers are not callable by apps');
reset role;

select is((select public from storage.buckets where id = 'listing-photos'), false, 'the listing-photos bucket is private');
select ok(exists (select 1 from pg_policies where schemaname = 'storage' and tablename = 'objects'
  and policyname = 'Students upload photos for their own listings'), 'the upload policy is in place');

select * from finish();
rollback;
