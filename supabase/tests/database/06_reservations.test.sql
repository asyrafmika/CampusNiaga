-- Reservations: request_reservation, resolve_reservation, my_reservations,
-- lazy expiry, notifications and the rules that keep units from being
-- handed out twice.
begin;
create extension if not exists pgtap with schema extensions;
select plan(56);

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

-- Ali sells; Siti and Amin buy; Ben uses gmail; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- A single calculator, a pack of 5 notebooks, a hidden item and a draft.
insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status, hidden) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Casio calculator', 'casio calculator', 'Stationery', 2500, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Notebook', 'notebook', 'Stationery', 300, 'new', array['p/1.jpg'], 5, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Hidden item', 'hidden item', 'Others', 100, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', true),
  ('bbbbbbbb-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Draft item', 'draft item', 'Others', 100, 'good', '{}', 1, 'Tekun', 'draft', false);

-- Requesting -------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
do $$ begin
  perform set_config('test.siti_calc', public.request_reservation('bbbbbbbb-0000-0000-0000-000000000001', 1, ' After 5pm at Tekun ') ->> 'reservation_id', true);
end $$;
reset role;
select is((select status || '/' || pickup_note from public.reservations where id = current_setting('test.siti_calc')::uuid), 'requested/After 5pm at Tekun', 'a student requests a reservation with a pickup note');
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'reserved/0', 'the request holds the only unit, so the listing is reserved');

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000001') $$), 'ITEM_UNAVAILABLE', 'a second student cannot reserve the same single item');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000001') $$), 'ALREADY_EXISTS', 'a buyer cannot reserve the same listing twice');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002') $$), 'FORBIDDEN', 'a seller cannot reserve their own listing');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot reserve');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002') $$), '42501', 'signed-out visitors cannot reserve');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 0) $$), 'INVALID_INPUT', 'a quantity of 0 is rejected');
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 1, repeat('a', 201)) $$), 'INVALID_INPUT', 'a pickup note over 200 characters is rejected');
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000003') $$), 'ITEM_UNAVAILABLE', 'a hidden listing cannot be reserved');
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000004') $$), 'NOT_FOUND', 'a draft cannot be reserved');
select is(pg_temp.error_reason($$ select public.request_reservation('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing listing cannot be reserved');

-- Several units --------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
do $$ begin
  perform set_config('test.siti_notes', public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 3) ->> 'reservation_id', true);
end $$;
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'available/2', 'reserving 3 of 5 leaves 2 on sale');

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 3) $$), 'ITEM_UNAVAILABLE', 'a buyer cannot reserve more units than are left');
do $$ begin
  perform set_config('test.amin_notes', public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 2) ->> 'reservation_id', true);
end $$;
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'reserved/0', 'reserving the last 2 units makes the listing reserved');

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is((select count(*)::int from public.search_listings('notebook')), 0, 'a fully reserved listing leaves the feed');

-- Notifications ------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.notifications where type = 'reservation_requested'), 3, 'the seller is notified of each request');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.notifications where recipient_id = '11111111-1111-1111-1111-111111111111'), 0, 'a student cannot read someone else''s notifications');

-- Resolving ----------------------------------------------------------------------------------
select is(pg_temp.error_reason($$ select public.resolve_reservation(current_setting('test.siti_calc')::uuid, 'accept') $$), 'FORBIDDEN', 'a buyer cannot accept their own request');
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.resolve_reservation(current_setting('test.siti_calc')::uuid, 'cancel') $$), 'FORBIDDEN', 'a stranger cannot cancel someone else''s reservation');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.resolve_reservation(current_setting('test.siti_calc')::uuid, 'accept') ->> 'status', 'accepted', 'the seller accepts a request');
select is(pg_temp.error_reason($$ select public.resolve_reservation(current_setting('test.siti_calc')::uuid, 'accept') $$), 'INVALID_TRANSITION', 'an accepted reservation cannot be accepted again');
select is(pg_temp.error_reason($$ select public.resolve_reservation(current_setting('test.siti_calc')::uuid, 'refund') $$), 'INVALID_INPUT', 'an unknown action is rejected');
select is(pg_temp.error_reason($$ select public.resolve_reservation('99999999-9999-9999-9999-999999999999', 'accept') $$), 'NOT_FOUND', 'a missing reservation is reported');
select is(pg_temp.error_reason($$ select public.resolve_reservation(current_setting('test.siti_notes')::uuid, 'collect') $$), 'INVALID_TRANSITION', 'a request cannot be collected before it is accepted');

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select other_party_email from public.my_reservations('buying') where id = current_setting('test.siti_calc')::uuid), 'ali@student.usm.my', 'once accepted, the buyer sees the seller''s email');
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is((select coalesce(other_party_email, 'hidden') from public.my_reservations('buying') where id = current_setting('test.amin_notes')::uuid), 'hidden', 'before acceptance, contact details stay hidden');
select is((select other_party_name from public.my_reservations('buying') where id = current_setting('test.amin_notes')::uuid), 'Ali', 'the buyer sees the seller''s name');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.resolve_reservation(current_setting('test.amin_notes')::uuid, 'decline') ->> 'listing_status', 'available', 'declining puts the units back on sale');
reset role;
select is((select stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 2, 'the declined units are returned');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.resolve_reservation(current_setting('test.siti_calc')::uuid, 'collect') ->> 'listing_status', 'sold', 'collecting the last unit sells the listing');

set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.resolve_reservation(current_setting('test.siti_notes')::uuid, 'cancel') ->> 'status', 'cancelled', 'a buyer cancels their request');
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'available/5', 'cancelling returns the units');

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.notifications where type in ('reservation_accepted', 'reservation_collected')), 2, 'the buyer is notified when accepted and collected');
select lives_ok($$ update public.notifications set read = true $$, 'a user marks their notifications read');
select is((select bool_and(read) from public.notifications), true, 'the notifications are now read');
select is(pg_temp.error_reason($$ update public.notifications set title = 'Changed' $$), '42501', 'a user cannot rewrite a notification');
select is(pg_temp.error_reason($$ insert into public.notifications (recipient_id, type, title) values ('22222222-2222-2222-2222-222222222222', 'x', 'Fake') $$), '42501', 'a user cannot create notifications');

-- No closing or selling while reservations are open --------------------------------------
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
do $$ begin
  perform set_config('test.amin_one', public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 1) ->> 'reservation_id', true);
end $$;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_listing_status('bbbbbbbb-0000-0000-0000-000000000002', 'closed') $$), 'INVALID_TRANSITION', 'a listing with an open reservation cannot be closed');
select is(pg_temp.error_reason($$ select public.set_listing_status('bbbbbbbb-0000-0000-0000-000000000002', 'sold') $$), 'INVALID_TRANSITION', 'a listing with an open reservation cannot be marked sold');
reset role;

-- Expiry ----------------------------------------------------------------------------------------
update public.reservations set expires_at = now() - interval '1 minute' where id = current_setting('test.amin_one')::uuid;

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
do $$ begin
  perform set_config('test.siti_five', public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 5) ->> 'reservation_id', true);
end $$;
reset role;
select is((select status from public.reservations where id = current_setting('test.amin_one')::uuid), 'expired', 'an overdue request expires when the listing is next reserved');
select ok(current_setting('test.siti_five', true) is not null, 'its unit went back on sale, so all 5 could be reserved');

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is((select count(*)::int from public.notifications where type = 'reservation_expired'), 1, 'the buyer is told the reservation expired');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.resolve_reservation(current_setting('test.amin_one')::uuid, 'accept') $$), 'INVALID_TRANSITION', 'an expired reservation cannot be accepted');
reset role;

update public.reservations set expires_at = now() - interval '1 minute' where id = current_setting('test.siti_five')::uuid;
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select status from public.my_reservations('selling') where id = current_setting('test.siti_five')::uuid), 'expired', 'opening My Reservations expires overdue ones');
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'available/5', 'and returns their units');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select * from public.my_reservations('both') $$), 'INVALID_INPUT', 'My Reservations needs buying or selling');
select is((select count(*)::int from public.my_reservations('selling')), 5, 'the seller sees every reservation on their listings');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.my_reservations('buying')), 3, 'a buyer sees only their own reservations');

-- Direct table access ---------------------------------------------------------------------------
select is((select count(*)::int from public.reservations), 3, 'a buyer reads only their own reservations directly');
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is((select count(*)::int from public.reservations where buyer_id = '22222222-2222-2222-2222-222222222222'), 0, 'a student cannot read other people''s reservations');
select is(pg_temp.error_reason($$ insert into public.reservations (listing_id, buyer_id, seller_id, qty, status, expires_at)
  values ('bbbbbbbb-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 1, 'accepted', now()) $$), '42501', 'reservations cannot be inserted directly');
select is(pg_temp.error_reason($$ update public.reservations set status = 'collected' $$), '42501', 'reservations cannot be updated directly');
select is(pg_temp.error_reason($$ select public.expire_listing_reservations('bbbbbbbb-0000-0000-0000-000000000002') $$), '42501', 'the expiry helper is not callable by apps');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.reservations), 5, 'an admin reads every reservation');
reset role;

-- Rate limit ------------------------------------------------------------------------------------
insert into public.reservations (listing_id, buyer_id, seller_id, qty, status)
select 'bbbbbbbb-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 1, 'declined'
from generate_series(1, 10 - (select count(*)::int from public.reservations where buyer_id = '44444444-4444-4444-4444-444444444444'));

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.request_reservation('bbbbbbbb-0000-0000-0000-000000000002', 1) $$), 'RATE_LIMITED', 'an 11th reservation within an hour is refused');
reset role;

select * from finish();
rollback;
