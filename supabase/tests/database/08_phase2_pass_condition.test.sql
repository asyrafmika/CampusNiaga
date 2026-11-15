-- Phase 2 pass condition, as one journey: a student publishes an item, a
-- second student finds and reserves it, a competing reservation can't
-- double-book it, and the seller marks it sold.
--
-- "Simultaneous" reservations are serialised by the row lock that
-- request_reservation() takes on the listing (select ... for update): the
-- second caller waits for the first to commit, then sees no units left.
-- A single test session can't open two connections, so this file checks the
-- outcome the lock guarantees: once the units are held, the next request fails.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}');

-- 1. Ali publishes a single calculator -----------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin
  perform set_config('test.listing', public.upsert_listing(null, 'Casio FX-570 calculator', 'One semester old.', 'Stationery', 2500, 'good', 1, '{}', 'Desasiswa Tekun') ->> 'listing_id', true);
end $$;
select lives_ok($$ select public.upsert_listing(current_setting('test.listing')::uuid, 'Casio FX-570 calculator', 'One semester old.', 'Stationery', 2500, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.listing') || '/1.jpg'], 'Desasiswa Tekun') $$, 'Ali adds a photo');
select is(public.set_listing_status(current_setting('test.listing')::uuid, 'available') ->> 'status', 'available', 'Ali publishes the listing');

-- 2. Siti finds it --------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select results_eq($$ select id::text from public.search_listings('calculator') $$, array[current_setting('test.listing')], 'Siti finds it by searching');
select is((select seller_name from public.get_listing(current_setting('test.listing')::uuid)), 'Ali', 'Siti opens it and sees who is selling');

-- 3. Siti reserves it; Amin's competing request is refused ---------------------------------
do $$ begin
  perform set_config('test.reservation', public.request_reservation(current_setting('test.listing')::uuid, 1, 'After class') ->> 'reservation_id', true);
end $$;
select ok(current_setting('test.reservation', true) is not null, 'Siti reserves it');
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation(current_setting('test.listing')::uuid) $$), 'ITEM_UNAVAILABLE', 'Amin cannot reserve the same item: no double-booking');
select is((select count(*)::int from public.search_listings('calculator')), 0, 'the reserved item leaves the feed');
reset role;
select is((select count(*)::int from public.reservations where listing_id = current_setting('test.listing')::uuid and status in ('requested', 'accepted')), 1, 'exactly one active reservation holds the item');

-- 4. Ali accepts, they meet, Ali marks it collected ----------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.resolve_reservation(current_setting('test.reservation')::uuid, 'accept') ->> 'status', 'accepted', 'Ali accepts the reservation');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select other_party_email from public.my_reservations('buying')), 'ali@student.usm.my', 'Siti now sees Ali''s email to arrange pickup');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.resolve_reservation(current_setting('test.reservation')::uuid, 'collect') ->> 'listing_status', 'sold', 'Ali marks it collected and the listing is sold');
reset role;
select is((select status || '/' || stock from public.listings where id = current_setting('test.listing')::uuid), 'sold/0', 'the listing is sold with no stock left');

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation(current_setting('test.listing')::uuid) $$), 'ITEM_UNAVAILABLE', 'a sold item cannot be reserved');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select status from public.my_reservations('buying')), 'collected', 'Siti''s reservation shows as collected');
reset role;

select * from finish();
rollback;
