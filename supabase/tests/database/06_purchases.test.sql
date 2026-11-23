-- Buy now (ADR 0006): buy_item, complete_purchase, cancel_purchase,
-- relist_purchase, my_purchases, the limits, notifications and the rules
-- that keep units from being sold twice.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

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

create function pg_temp.as_user(id text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', id, 'role', 'authenticated')::text, true);
$$;

-- The id of a purchase saved by a test.
create function pg_temp.pid(name text) returns uuid language sql as $$
  select (current_setting('test.' || name)::jsonb ->> 'purchase_id')::uuid;
$$;

-- Ali sells; Siti and Amin buy; Ben uses gmail; Una hasn't confirmed her
-- email; Sue is suspended; Hana is staff, not a student; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}'),
  ('66666666-6666-6666-6666-666666666666', 'hana@campusniaga.test', now(), '{}'),
  ('88888888-8888-8888-8888-888888888888', 'una@student.usm.my', null, '{"name": "Una"}'),
  ('99999999-0000-0000-0000-000000000009', 'sue@student.usm.my', now(), '{"name": "Sue"}');
update public.profiles set account_status = 'suspended' where id = '99999999-0000-0000-0000-000000000009';
insert into public.staff_roles (user_id, role) values
  ('33333333-3333-3333-3333-333333333333', 'admin');

-- 1 a calculator, 2 a pack of 5 notebooks, 3 hidden, 4 draft, 5-8 items for
-- the cash limit, 9 closed, 10 the suspended seller's.
insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status, hidden) values
  ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Casio calculator', 'casio calculator', 'Stationery', 2500, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Notebook', 'notebook', 'Stationery', 300, 'new', array['p/1.jpg'], 5, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'Hidden item', 'hidden item', 'Others', 100, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', true),
  ('bbbbbbbb-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'Draft item', 'draft item', 'Others', 100, 'good', '{}', 1, 'Tekun', 'draft', false),
  ('bbbbbbbb-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'Desk lamp', 'desk lamp', 'Others', 1500, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000006', '11111111-1111-1111-1111-111111111111', 'Kettle', 'kettle', 'Others', 2000, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000007', '11111111-1111-1111-1111-111111111111', 'Fan', 'fan', 'Others', 4000, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000008', '11111111-1111-1111-1111-111111111111', 'Mirror', 'mirror', 'Others', 800, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false),
  ('bbbbbbbb-0000-0000-0000-000000000009', '11111111-1111-1111-1111-111111111111', 'Closed item', 'closed item', 'Others', 100, 'good', array['p/1.jpg'], 1, 'Tekun', 'closed', false),
  ('bbbbbbbb-0000-0000-0000-000000000010', '99999999-0000-0000-0000-000000000009', 'Suspended seller item', 'suspended seller item', 'Others', 100, 'good', array['p/1.jpg'], 1, 'Tekun', 'available', false);

-- Schema and privileges --------------------------------------------------------------
select hasnt_table('public', 'reservations', 'reservations are gone');
select hasnt_function('public', 'request_reservation', 'reserving is gone');
select hasnt_function('public', 'resolve_reservation', 'accepting and declining are gone');
select ok(not has_schema_privilege('authenticated', 'legacy', 'usage'), 'apps cannot reach the archived reservations');
select ok(not has_schema_privilege('anon', 'legacy', 'usage'), 'nor can signed-out visitors');
select throws_ok($$ update public.listings set status = 'reserved', stock = 0 where id = 'bbbbbbbb-0000-0000-0000-000000000001' $$,
  '23514', null, 'reserved is no longer a listing status');

set local role anon;
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), '42501', 'signed-out visitors cannot buy');
select is(pg_temp.error_reason($$ select public.complete_purchase(gen_random_uuid()) $$), '42501', 'or complete');
select is(pg_temp.error_reason($$ select public.cancel_purchase(gen_random_uuid()) $$), '42501', 'or cancel');
select is(pg_temp.error_reason($$ select public.relist_purchase(gen_random_uuid()) $$), '42501', 'or relist');
select is(pg_temp.error_reason($$ select * from public.my_purchases() $$), '42501', 'or list purchases');
select is(pg_temp.error_reason($$ select * from public.purchases $$), '42501', 'or read the table');
reset role;

set local role authenticated;
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot buy');
select is(pg_temp.error_reason($$ select public.complete_purchase(gen_random_uuid()) $$), 'NOT_VERIFIED_STUDENT', 'or complete');
select is(pg_temp.error_reason($$ select public.cancel_purchase(gen_random_uuid()) $$), 'NOT_VERIFIED_STUDENT', 'or cancel');
select is(pg_temp.error_reason($$ select public.relist_purchase(gen_random_uuid()) $$), 'NOT_VERIFIED_STUDENT', 'or relist');
select is(pg_temp.error_reason($$ select * from public.my_purchases() $$), 'NOT_VERIFIED_STUDENT', 'or list purchases');
select pg_temp.as_user('88888888-8888-8888-8888-888888888888');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), 'NOT_VERIFIED_STUDENT', 'an unconfirmed email cannot buy');
select pg_temp.as_user('99999999-0000-0000-0000-000000000009');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), 'NOT_VERIFIED_STUDENT', 'a suspended student cannot buy');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), 'NOT_VERIFIED_STUDENT', 'a staff address that is not a student cannot buy');

-- Buying -----------------------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.calc', public.buy_item('bbbbbbbb-0000-0000-0000-000000000001')::text, true);
end $$;
select is(current_setting('test.calc')::jsonb ->> 'status', 'awaiting_handover', 'a cash purchase waits for the handover, with no seller to accept');
select is(current_setting('test.calc')::jsonb ->> 'payment_id', null, 'and has no payment record');
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'sold/0', 'buying the only unit sells it at once');

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000001') $$), 'ITEM_UNAVAILABLE', 'first come, first served: a second student cannot buy it');
select throws_ok($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000001') $$, 'P0001', 'Sorry, this item has just been sold.', 'and is told it was just sold');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000001') $$), 'ALREADY_EXISTS', 'a double tap does not buy twice');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), 'FORBIDDEN', 'a seller cannot buy their own listing');

select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 0) $$), 'INVALID_INPUT', 'a quantity of 0 is rejected');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 1000) $$), 'INVALID_INPUT', 'a quantity over 999 is rejected');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 1, 'card') $$), 'INVALID_INPUT', 'only cash or transfer');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 1, null) $$), 'INVALID_INPUT', 'a payment method is needed');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 1, 'transfer') $$), 'INVALID_INPUT', 'transfer needs the seller''s payment details');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000003') $$), 'ITEM_UNAVAILABLE', 'a hidden listing cannot be bought');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000004') $$), 'NOT_FOUND', 'a draft cannot be bought');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000009') $$), 'ITEM_UNAVAILABLE', 'a closed listing cannot be bought');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000010') $$), 'ITEM_UNAVAILABLE', 'a suspended seller''s item cannot be bought');
select is(pg_temp.error_reason($$ select public.buy_item('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing listing cannot be bought');

-- Several units ----------------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.notes', public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 3)::text, true);
end $$;
select is(current_setting('test.notes')::jsonb ->> 'total_sen', '900', 'the total is the price times the quantity');
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'available/2', 'buying 3 of 5 leaves 2 on sale');
update public.listings set price_sen = 999 where id = 'bbbbbbbb-0000-0000-0000-000000000002';
select is((select unit_price_sen || '/' || total_sen from public.purchases where id = pg_temp.pid('notes')), '300/900', 'a later price change does not touch the purchase');

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 3) $$), 'ITEM_UNAVAILABLE', 'nobody can buy more units than are left');
select throws_ok($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 3) $$, 'P0001', 'Only 2 left.', 'and the message says how many are left');
do $$ begin
  perform set_config('test.amin_notes', public.buy_item('bbbbbbbb-0000-0000-0000-000000000002', 2)::text, true);
end $$;
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'sold/0', 'buying the last 2 units sells the listing');
select is((select sum(qty)::int from public.purchases where listing_id = 'bbbbbbbb-0000-0000-0000-000000000002' and status <> 'cancelled'), 5, 'no more units were sold than existed');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.search_listings('notebook')), 0, 'a sold-out listing leaves the feed');

-- Notifications ----------------------------------------------------------------------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.notifications where type = 'purchase_created'), 3, 'the seller is notified of each purchase');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.notifications where recipient_id = '11111111-1111-1111-1111-111111111111'), 0, 'a student cannot read someone else''s notifications');

-- Completing -------------------------------------------------------------------------
select is(pg_temp.error_reason($$ select public.complete_purchase(pg_temp.pid('calc')) $$), 'FORBIDDEN', 'a buyer cannot complete their own purchase');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.complete_purchase(pg_temp.pid('calc')) $$), 'NOT_FOUND', 'a stranger cannot complete it, or learn it exists');
select is(pg_temp.error_reason($$ select public.cancel_purchase(pg_temp.pid('calc')) $$), 'NOT_FOUND', 'a stranger cannot cancel it');
select is(pg_temp.error_reason($$ select public.relist_purchase(pg_temp.pid('calc')) $$), 'NOT_FOUND', 'a stranger cannot relist it');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.complete_purchase('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing purchase is reported');
select is(public.complete_purchase(pg_temp.pid('calc')) ->> 'status', 'completed', 'the seller completes the sale at handover');
select is(pg_temp.error_reason($$ select public.complete_purchase(pg_temp.pid('calc')) $$), 'INVALID_TRANSITION', 'a completed purchase cannot be completed again');
select is(pg_temp.error_reason($$ select public.cancel_purchase(pg_temp.pid('calc'), 'Too late') $$), 'INVALID_TRANSITION', 'or cancelled');
select is(pg_temp.error_reason($$ select public.relist_purchase(pg_temp.pid('calc')) $$), 'INVALID_TRANSITION', 'or relisted');
reset role;
select ok((select completed_at is not null from public.purchases where id = pg_temp.pid('calc')), 'completion records when');
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000001'), 'sold/0', 'a completed sale stays sold');

-- The buyer cancels ------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.cancel_purchase(pg_temp.pid('amin_notes'), repeat('a', 201)) $$), 'INVALID_INPUT', 'a reason over 200 characters is rejected');
select is(pg_temp.error_reason($$ select public.cancel_purchase(pg_temp.pid('amin_notes'), null, null) $$), 'INVALID_INPUT', 'relist or close must be said');
select is(public.cancel_purchase(pg_temp.pid('amin_notes'), null, false) ->> 'listing_status', 'available',
  'a cash buyer cancels without a reason, and cannot close the seller''s listing');
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'available/2', 'the cancelled units are back on sale');
select is((select status || '/' || cancelled_by from public.purchases where id = pg_temp.pid('amin_notes')), 'cancelled/buyer', 'and the purchase says who cancelled');

-- Relisting --------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.relist_purchase(pg_temp.pid('notes')) $$), 'INVALID_TRANSITION', 'no relisting in the first 24 hours');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.relist_purchase(pg_temp.pid('notes')) $$), 'FORBIDDEN', 'a buyer cannot relist');
reset role;
update public.purchases set created_at = now() - interval '23 hours 59 minutes' where id = pg_temp.pid('notes');
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.relist_purchase(pg_temp.pid('notes')) $$), 'INVALID_TRANSITION', 'not a minute early');
reset role;
update public.purchases set created_at = now() - interval '25 hours' where id = pg_temp.pid('notes');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select lives_ok($$ select * from public.search_listings() $$, 'browsing runs the sweep');
reset role;
select is((select status from public.purchases where id = pg_temp.pid('notes')), 'awaiting_handover', 'cash is never released automatically');
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.relist_purchase(pg_temp.pid('notes')) ->> 'status', 'cancelled', 'after 24 hours the seller relists');
reset role;
select is((select status || '/' || stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'available/5', 'relisting returns the units');
select is((select status || '/' || cancelled_by || '/' || cancel_reason from public.purchases where id = pg_temp.pid('notes')),
  'cancelled/seller/The buyer didn''t collect the item.', 'and says why');

-- The seller cancels -----------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.lamp', public.buy_item('bbbbbbbb-0000-0000-0000-000000000005')::text, true);
  perform set_config('test.kettle', public.buy_item('bbbbbbbb-0000-0000-0000-000000000006')::text, true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.cancel_purchase(pg_temp.pid('lamp'), '  ') $$), 'INVALID_INPUT', 'a seller cancels with a reason');
select is(public.cancel_purchase(pg_temp.pid('lamp'), 'It broke', false) ->> 'listing_status', 'deleted', 'and may delete the listing');
select is(public.cancel_purchase(pg_temp.pid('kettle'), 'Wrong buyer', true) ->> 'listing_status', 'available', 'or relist it');
select is(pg_temp.error_reason($$ select public.set_listing_status('bbbbbbbb-0000-0000-0000-000000000005', 'available') $$), 'NOT_FOUND', 'a deleted listing is gone for good');
reset role;
-- Test setup: the lamp is needed again below.
update public.listings set status = 'available' where id = 'bbbbbbbb-0000-0000-0000-000000000005';
set local role authenticated;

select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.notifications where type = 'purchase_cancelled'), 2, 'the buyer is told of each cancellation');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.notifications where type in ('purchase_completed', 'purchase_cancelled')), 2, 'the buyer is told of a completion and a relist');
select lives_ok($$ update public.notifications set read = true $$, 'a user marks their notifications read');
select is((select bool_and(read) from public.notifications), true, 'the notifications are now read');
select is(pg_temp.error_reason($$ update public.notifications set title = 'Changed' $$), '42501', 'a user cannot rewrite a notification');
select is(pg_temp.error_reason($$ insert into public.notifications (recipient_id, type, title) values ('22222222-2222-2222-2222-222222222222', 'x', 'Fake') $$), '42501', 'a user cannot create notifications');

-- Deleting with a purchase in progress --------------------------------------------------
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.one', public.buy_item('bbbbbbbb-0000-0000-0000-000000000002')::text, true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.set_listing_status('bbbbbbbb-0000-0000-0000-000000000002', 'deleted') ->> 'status', 'deleted', 'the seller can delete a listing with a purchase in progress');
reset role;
select is((select status from public.purchases where id = pg_temp.pid('one')), 'awaiting_handover', 'the purchase in progress carries on');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(public.cancel_purchase(pg_temp.pid('one')) ->> 'listing_status', 'deleted', 'a buyer cancelling does not bring a deleted listing back');
reset role;
select is((select status from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000002'), 'deleted', 'it stays deleted');
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.set_listing_status('bbbbbbbb-0000-0000-0000-000000000002', 'reserved') $$), 'INVALID_INPUT', 'a listing cannot be set reserved');

-- At most 3 unfinished cash purchases --------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.limit_one', public.buy_item('bbbbbbbb-0000-0000-0000-000000000005')::text, true);
  perform public.buy_item('bbbbbbbb-0000-0000-0000-000000000006');
  perform public.buy_item('bbbbbbbb-0000-0000-0000-000000000007');
end $$;
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000008') $$), 'RATE_LIMITED', 'a 4th unfinished cash purchase is refused');
select throws_ok($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000008') $$, 'P0001', 'Please complete your current purchases first.', 'and says what to do');
reset role;
select is((select stock from public.listings where id = 'bbbbbbbb-0000-0000-0000-000000000008'), 1, 'a refused purchase leaves the stock alone');
insert into public.payment_details (profile_id, bank_name, account_name, account_number)
values ('11111111-1111-1111-1111-111111111111', 'Maybank', 'Ali', '1234567890');
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.transfer', public.buy_item('bbbbbbbb-0000-0000-0000-000000000008', 1, 'transfer')::text, true);
end $$;
select is(current_setting('test.transfer')::jsonb ->> 'status', 'awaiting_payment', 'the limit is on cash only');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.complete_purchase(pg_temp.pid('transfer')) $$), 'INVALID_TRANSITION', 'a sale cannot complete before its payment is checked');
select is(pg_temp.error_reason($$ select public.relist_purchase(pg_temp.pid('transfer')) $$), 'INVALID_TRANSITION', 'a transfer cannot be relisted as uncollected cash');
select lives_ok($$ select public.complete_purchase(pg_temp.pid('limit_one')) $$, 'the seller completes one cash sale');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform public.cancel_purchase(pg_temp.pid('transfer'));
end $$;
select is(public.buy_item('bbbbbbbb-0000-0000-0000-000000000008') ->> 'status', 'awaiting_handover', 'finishing one frees a place');

-- My Purchases -----------------------------------------------------------------------
select is(pg_temp.error_reason($$ select * from public.my_purchases('both') $$), 'INVALID_INPUT', 'Purchases needs buying or selling');
select is(pg_temp.error_reason($$ select * from public.my_purchases('buying', 0) $$), 'INVALID_INPUT', 'a page size of 0 is refused');
select is(pg_temp.error_reason($$ select * from public.my_purchases('buying', 20, -1) $$), 'INVALID_INPUT', 'a negative offset is refused');
select is((select count(*)::int from public.my_purchases('buying')), 7, 'a buyer sees their own purchases');
select is((select count(*)::int from public.my_purchases('buying', 2)), 2, 'a page is as big as asked');
select is((select status from public.my_purchases('buying', 1)), 'awaiting_handover', 'unfinished ones come first');
select is((select other_party_name from public.my_purchases('buying', 1)), 'Ali', 'the buyer sees the seller''s name');
select ok((select relist_from between created_at + interval '23 hours' and created_at + interval '25 hours' from public.my_purchases('buying', 1)),
  'a cash purchase says when it may be relisted');
select ok(not exists (select 1 from pg_attribute as a join pg_class as c on c.oid = a.attrelid
                      where c.relname = 'purchase_card' and a.attname like '%email%'), 'no email is shared: the two sides use the chat');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.my_purchases('selling')), 11, 'the seller sees every sale of their items');
select is((select count(*)::int from public.my_purchases('buying')), 0, 'and no purchases of their own');

-- Direct table access ----------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.purchases), 7, 'a buyer reads only their own purchases directly');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.purchases where buyer_id = '22222222-2222-2222-2222-222222222222'), 0, 'a student cannot read other people''s purchases');
select is(pg_temp.error_reason($$ insert into public.purchases (listing_id, buyer_id, seller_id, qty, unit_price_sen, total_sen, payment_method, status)
  values ('bbbbbbbb-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 1, 1, 1, 'cash', 'awaiting_handover') $$),
  '42501', 'purchases cannot be inserted directly');
select is(pg_temp.error_reason($$ update public.purchases set status = 'completed' $$), '42501', 'purchases cannot be updated directly');
select is(pg_temp.error_reason($$ delete from public.purchases $$), '42501', 'purchases cannot be deleted');
select is(pg_temp.error_reason($$ select public.expire_unpaid_purchases('bbbbbbbb-0000-0000-0000-000000000002') $$), '42501', 'the expiry helper is not callable by apps');
select is(pg_temp.error_reason($$ select public.cancel_purchase_hold(gen_random_uuid(), 'system', 'x') $$), '42501', 'nor the release helper');
select is(pg_temp.error_reason($$ select public.lock_purchase(gen_random_uuid()) $$), '42501', 'nor the lock helper');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is((select count(*)::int from public.purchases), 0, 'nor read any purchases');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.purchases), 11, 'an admin reads every purchase');
reset role;

-- Rate limit -------------------------------------------------------------------------
insert into public.purchases (listing_id, buyer_id, seller_id, qty, unit_price_sen, total_sen, payment_method, status, cancelled_by)
select 'bbbbbbbb-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 1, 300, 300, 'cash', 'cancelled', 'buyer'
from generate_series(1, 10 - (select count(*)::int from public.purchases where buyer_id = '44444444-4444-4444-4444-444444444444'));
update public.listings set status = 'available' where id = 'bbbbbbbb-0000-0000-0000-000000000002';

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.buy_item('bbbbbbbb-0000-0000-0000-000000000002') $$), 'RATE_LIMITED', 'an 11th purchase within an hour is refused');
reset role;

select * from finish();
rollback;
