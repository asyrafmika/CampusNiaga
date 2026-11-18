-- Transfer payments (ADR 0005): payment details (set_payment_details, their
-- privacy), choosing cash or transfer (request_reservation, place_order,
-- seller_accepts_transfer), the payment page (get_payment), proof
-- (submit_payment_proof and its storage), the seller's decision
-- (review_payment), the guards on resolve_reservation / transition_order,
-- the 30-minute hold and its expiry (on the locked stock and by the read
-- sweep), and who reads what.
begin;
create extension if not exists pgtap with schema extensions;
select plan(94);

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

-- Ali runs Ali Bakes; Sam sells personal items and takes transfers; Lee
-- sells for cash only; Siti and Amin buy; Ben uses gmail; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('66666666-6666-6666-6666-666666666666', 'sam@student.usm.my', now(), '{"name": "Sam"}'),
  ('77777777-7777-7777-7777-777777777777', 'lee@student.usm.my', now(), '{"name": "Lee"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, description, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Brownies.', 'Tekun lobby, 6-8pm');
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 500, 'new', array['p/1.jpg'], 2, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000002', '66666666-6666-6666-6666-666666666666', 'personal', null, 'Calculator', 'calculator', 'Electronics', 3000, 'good', array['p/2.jpg'], 1, 'Aman Damai', 'available'),
  ('cccccccc-0000-0000-0000-000000000003', '66666666-6666-6666-6666-666666666666', 'personal', null, 'Lecture notes', 'lecture notes', 'Books', 1000, 'good', array['p/3.jpg'], 1, 'Aman Damai', 'available'),
  ('cccccccc-0000-0000-0000-000000000004', '77777777-7777-7777-7777-777777777777', 'personal', null, 'Desk lamp', 'desk lamp', 'Hostel Essentials', 1500, 'good', array['p/4.jpg'], 1, 'Tekun', 'available');
insert into public.campaigns (id, business_id, listing_id, title, price_sen, start_at, close_at, capacity, pickup_details, status) values
  ('dddddddd-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now() - interval '1 hour', now() + interval '7 days', 3, 'Tekun lobby, Sat 10am', 'open');

-- Schema and privileges -------------------------------------------------------------------------
select has_table('public', 'payment_details', 'payment details have a table');
select has_table('public', 'deal_payments', 'deal payments have a table');
select hasnt_function('public', 'place_order', array['uuid', 'integer', 'uuid', 'text'], 'the cash-only place_order is gone');
select hasnt_function('public', 'request_reservation', array['uuid', 'integer', 'text'], 'the cash-only request_reservation is gone');
select ok(has_function_privilege('authenticated', 'public.place_order(uuid, integer, uuid, text, text)', 'execute'), 'signed-in users can call place_order');
select ok(not has_function_privilege('anon', 'public.place_order(uuid, integer, uuid, text, text)', 'execute'), 'signed-out callers cannot');
select ok(not has_function_privilege('anon', 'public.review_payment(uuid, boolean, text)', 'execute'), 'signed-out callers cannot review payments');
select ok(not has_function_privilege('authenticated', 'public.expire_overdue_payments()', 'execute'), 'the expiry sweep is internal');
select ok(not has_function_privilege('authenticated', 'public.payment_details_for(uuid, uuid)', 'execute'), 'reading anyone''s details directly is internal');
select throws_ok($$ insert into public.payment_details (profile_id, bank_name, account_number) values ('66666666-6666-6666-6666-666666666666', 'Maybank', '1234567890') $$,
  '23514', null, 'the table refuses bank details without the holder''s name');
select throws_ok($$ insert into public.payment_details (profile_id) values ('66666666-6666-6666-6666-666666666666') $$,
  '23514', null, 'the table refuses a row with neither an account nor a QR code');

-- Saving payment details ------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(public.set_payment_details(false, ' Maybank ', ' Sam Tan ', '1234-5678 90') ->> 'saved', 'true', 'a student saves their bank details');
select is((select account_number || '/' || bank_name from public.payment_details), '1234567890/Maybank', 'stored as digits, trimmed, and the owner can read them');
select is(pg_temp.error_reason($$ select public.set_payment_details(false, 'Maybank', null, '1234567890') $$), 'INVALID_INPUT', 'the bank fields go together');
select is(pg_temp.error_reason($$ select public.set_payment_details(false, 'Maybank', 'Sam Tan', '12ab') $$), 'INVALID_INPUT', 'an account number is 6 to 20 digits');
select is(pg_temp.error_reason($$ select public.set_payment_details(false, null, null, null, '11111111-1111-1111-1111-111111111111/qr.png') $$),
  'INVALID_INPUT', 'a QR path in someone else''s folder is refused');
select is(pg_temp.error_reason($$ select public.set_payment_details(false, null, null, null, '66666666-6666-6666-6666-666666666666/missing.png') $$),
  'INVALID_INPUT', 'a QR image that was never uploaded is refused');
select is(pg_temp.error_reason($$ select public.set_payment_details(true, 'Maybank', 'Sam Tan', '1234567890') $$),
  'FORBIDDEN', 'a student without an approved business cannot save business details');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.set_payment_details(false, 'Maybank', 'Ben', '1234567890') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.payment_details), 0, 'nobody else reads Sam''s bank details');
select throws_ok($$ insert into storage.objects (bucket_id, name) values ('payment-qr', '11111111-1111-1111-1111-111111111111/qr.png') $$,
  '42501', null, 'a student cannot upload a QR code into someone else''s folder');

-- Ali's business takes a QR code; Lee saves and then removes details.
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ insert into storage.objects (bucket_id, name) values ('payment-qr', '11111111-1111-1111-1111-111111111111/qr.png') $$,
  'an owner uploads their QR code');
select is(public.set_payment_details(true, null, null, null, '11111111-1111-1111-1111-111111111111/qr.png') ->> 'saved', 'true',
  'an approved business saves a QR code of its own');
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select is(pg_temp.error_reason($$ select public.set_payment_details(false, null, null, null, '11111111-1111-1111-1111-111111111111/qr.png') $$),
  'INVALID_INPUT', 'a seller can''t point their QR code at someone else''s uploaded image');
select lives_ok($$ select public.set_payment_details(false, 'CIMB', 'Lee', '9876543210') $$, 'Lee saves details');
select is(public.set_payment_details(false) ->> 'saved', 'false', 'saving with nothing removes them');
select is((select count(*)::int from public.payment_details), 0, 'and they are gone');
reset role;
select is((select qr_path from public.payment_details where business_id = 'bbbbbbbb-0000-0000-0000-000000000011'),
  '11111111-1111-1111-1111-111111111111/qr.png', 'the business row holds the QR code');

-- Can the buyer choose transfer? -----------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select ok(public.seller_accepts_transfer('cccccccc-0000-0000-0000-000000000002'), 'Sam''s item takes transfers');
select ok(not public.seller_accepts_transfer('cccccccc-0000-0000-0000-000000000004'), 'Lee''s lamp is cash only');
select ok(public.seller_accepts_transfer('cccccccc-0000-0000-0000-000000000001'), 'Ali''s product takes transfers (the business''s QR code)');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.seller_accepts_transfer('cccccccc-0000-0000-0000-000000000002') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot ask');

-- Reserving by transfer -------------------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.request_reservation('cccccccc-0000-0000-0000-000000000004', 1, null, 'transfer') $$),
  'INVALID_INPUT', 'transfer is refused when the seller has no payment details');
select is(pg_temp.error_reason($$ select public.request_reservation('cccccccc-0000-0000-0000-000000000002', 1, null, 'card') $$),
  'INVALID_INPUT', 'only cash or transfer');
do $$ begin
  perform set_config('test.res', public.request_reservation('cccccccc-0000-0000-0000-000000000002', 1, 'After class', 'transfer')::text, true);
end $$;
select ok((current_setting('test.res')::jsonb ->> 'payment_id') is not null, 'a transfer reservation returns its payment');
select is(public.request_reservation('cccccccc-0000-0000-0000-000000000004') ->> 'payment_id', null, 'a cash reservation has no payment');
reset role;
select is((select stock || '/' || status from public.listings where id = 'cccccccc-0000-0000-0000-000000000002'), '0/reserved',
  'the unit is held for the buyer while they pay');
select ok((select dp.status = 'awaiting_proof' and dp.amount_sen = 3000
             and dp.due_at between now() + interval '29 minutes' and now() + interval '31 minutes'
             and rv.expires_at = dp.due_at
           from public.deal_payments as dp join public.reservations as rv on rv.id = dp.reservation_id
           where dp.id = (current_setting('test.res')::jsonb ->> 'payment_id')::uuid),
  'the buyer has 30 minutes to send proof, and the hold ends with it');

-- The payment page
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.get_payment((current_setting('test.res')::jsonb ->> 'payment_id')::uuid) #>> '{pay_to,account_number}', '1234567890',
  'the buyer sees where to pay');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(public.get_payment((current_setting('test.res')::jsonb ->> 'payment_id')::uuid) -> 'pay_to', 'null'::jsonb,
  'the seller doesn''t get the pay-to block');
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select is(pg_temp.error_reason(format('select public.get_payment(%L)', current_setting('test.res')::jsonb ->> 'payment_id')), 'NOT_FOUND',
  'a stranger can''t see the payment');
select is((select count(*)::int from public.deal_payments), 0, 'or read it from the table');

-- Guards on the reservation
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason(format('select public.resolve_reservation(%L, ''accept'')', current_setting('test.res')::jsonb ->> 'reservation_id')),
  'INVALID_TRANSITION', 'the seller accepts a transfer reservation by checking its payment, not directly');
select is(pg_temp.error_reason(format('select public.review_payment(%L, true)', current_setting('test.res')::jsonb ->> 'payment_id')),
  'INVALID_TRANSITION', 'there is nothing to check before the proof arrives');

-- Proof ----------------------------------------------------------------------------------------
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('payment-proofs', '22222222-2222-2222-2222-222222222222/%s/proof.png') $$,
  current_setting('test.res')::jsonb ->> 'payment_id'), '42501', null, 'nobody else uploads proof for the buyer');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason(format('select public.submit_payment_proof(%L, %L)', current_setting('test.res')::jsonb ->> 'payment_id',
  '22222222-2222-2222-2222-222222222222/' || (current_setting('test.res')::jsonb ->> 'payment_id') || '/proof.png')),
  'INVALID_INPUT', 'proof must be uploaded before it is sent');
select lives_ok(format($$ insert into storage.objects (bucket_id, name) values ('payment-proofs', '22222222-2222-2222-2222-222222222222/%s/proof.png') $$,
  current_setting('test.res')::jsonb ->> 'payment_id'), 'the buyer uploads a screenshot');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason(format('select public.submit_payment_proof(%L, %L)', current_setting('test.res')::jsonb ->> 'payment_id',
  '22222222-2222-2222-2222-222222222222/' || (current_setting('test.res')::jsonb ->> 'payment_id') || '/proof.png')),
  'FORBIDDEN', 'only the buyer sends proof');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.submit_payment_proof((current_setting('test.res')::jsonb ->> 'payment_id')::uuid,
  '22222222-2222-2222-2222-222222222222/' || (current_setting('test.res')::jsonb ->> 'payment_id') || '/proof.png') ->> 'status', 'submitted',
  'the buyer sends proof in time');
select is(pg_temp.error_reason(format('select public.submit_payment_proof(%L, %L)', current_setting('test.res')::jsonb ->> 'payment_id',
  '22222222-2222-2222-2222-222222222222/' || (current_setting('test.res')::jsonb ->> 'payment_id') || '/proof.png')),
  'INVALID_TRANSITION', 'proof is sent once');
select is(pg_temp.error_reason(format('select public.resolve_reservation(%L, ''cancel'')', current_setting('test.res')::jsonb ->> 'reservation_id')),
  'INVALID_TRANSITION', 'a buyer who has paid can''t cancel on their own');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('payment-proofs', '22222222-2222-2222-2222-222222222222/%s/again.png') $$,
  current_setting('test.res')::jsonb ->> 'payment_id'), '42501', null, 'no more proof uploads once it is sent');
reset role;
select ok((select expires_at > now() + interval '6 days' from public.reservations where id = (current_setting('test.res')::jsonb ->> 'reservation_id')::uuid),
  'once proof is sent, the hold waits for the seller (7 days)');
set local role authenticated;
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is((select count(*)::int from storage.objects where bucket_id = 'payment-proofs'), 1, 'the seller can open the proof');
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select is((select count(*)::int from storage.objects where bucket_id = 'payment-proofs'), 0, 'a stranger cannot');

-- The seller's decision ------------------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason(format('select public.review_payment(%L, true)', current_setting('test.res')::jsonb ->> 'payment_id')),
  'FORBIDDEN', 'the buyer can''t accept their own payment');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason(format('select public.review_payment(%L, false, ''  '')', current_setting('test.res')::jsonb ->> 'payment_id')),
  'INVALID_INPUT', 'rejecting needs a reason');
select is(public.review_payment((current_setting('test.res')::jsonb ->> 'payment_id')::uuid, true) ->> 'deal_status', 'accepted',
  'accepting the payment accepts the reservation');
select is(pg_temp.error_reason(format('select public.review_payment(%L, false, ''Not received'')', current_setting('test.res')::jsonb ->> 'payment_id')),
  'INVALID_TRANSITION', 'a decision is final');
select is((select payment_status || '/' || status from public.my_reservations('selling') where id = (current_setting('test.res')::jsonb ->> 'reservation_id')::uuid),
  'accepted/accepted', 'Bookings shows the payment');
reset role;
select is((select count(*)::int from public.audit_logs where action = 'payment.accepted' and target_id = current_setting('test.res')::jsonb ->> 'payment_id'), 1,
  'the decision is audited');

-- A business order paid by transfer, rejected --------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.order', public.place_order('cccccccc-0000-0000-0000-000000000001', 1, null, 'Evening', 'transfer')::text, true);
end $$;
select is((current_setting('test.order')::jsonb ->> 'status'), 'pending_confirmation', 'a transfer order waits for payment');
select is((select count(*)::int from storage.objects where bucket_id = 'payment-qr'), 1, 'the paying buyer can open the business''s QR code');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from storage.objects where bucket_id = 'payment-qr'), 0, 'other students cannot');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason(format('select public.transition_order(%L, ''confirm'')', current_setting('test.order')::jsonb ->> 'order_id')),
  'INVALID_TRANSITION', 'the business confirms a transfer order by checking its payment, not directly');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok(format($$ insert into storage.objects (bucket_id, name) values ('payment-proofs', '22222222-2222-2222-2222-222222222222/%s/receipt.jpg') $$,
  current_setting('test.order')::jsonb ->> 'payment_id'), 'the buyer uploads proof for the order');
select lives_ok(format('select public.submit_payment_proof(%L, %L)', current_setting('test.order')::jsonb ->> 'payment_id',
  '22222222-2222-2222-2222-222222222222/' || (current_setting('test.order')::jsonb ->> 'payment_id') || '/receipt.jpg'), 'and sends it');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.review_payment((current_setting('test.order')::jsonb ->> 'payment_id')::uuid, false, 'Nothing arrived in my account') ->> 'deal_status',
  'cancelled', 'rejecting the payment cancels the order');
reset role;
select is((select status || '/' || cancelled_by from public.orders where id = (current_setting('test.order')::jsonb ->> 'order_id')::uuid),
  'cancelled/seller', 'cancelled by the business');
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 2, 'and the unit is back on sale');
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select payment_status || '/' || payment_reject_reason from public.my_orders('buying') where id = (current_setting('test.order')::jsonb ->> 'order_id')::uuid),
  'rejected/Nothing arrived in my account', 'My orders shows why');
select is(public.get_payment((current_setting('test.order')::jsonb ->> 'payment_id')::uuid) -> 'pay_to', 'null'::jsonb,
  'a closed payment no longer shows where to pay');
select is((select count(*)::int from storage.objects where bucket_id = 'payment-qr'), 0,
  'once the payment closes, the QR code is private again');

-- Ready stock: an unpaid order's hold expires when the stock is next locked ---------------------
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.unpaid', public.place_order('cccccccc-0000-0000-0000-000000000001', 2, null, null, 'transfer')::text, true);
end $$;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 1) $$), 'ITEM_UNAVAILABLE',
  'while Amin pays, his units are his: nobody can take them');
reset role;
update public.deal_payments set due_at = now() - interval '1 minute'
where id = (current_setting('test.unpaid')::jsonb ->> 'payment_id')::uuid;
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.place_order('cccccccc-0000-0000-0000-000000000001', 1) ->> 'status', 'pending_confirmation',
  'after 30 minutes without proof, the units come back and Siti can order');
reset role;
select is((select o.status || '/' || o.cancelled_by || '/' || dp.status from public.orders as o join public.deal_payments as dp on dp.order_id = o.id
           where o.id = (current_setting('test.unpaid')::jsonb ->> 'order_id')::uuid), 'cancelled/system/expired',
  'the unpaid order was cancelled by the system');
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 1, 'stock: 2 returned, 1 taken');
select is((select count(*)::int from public.notifications where recipient_id = '44444444-4444-4444-4444-444444444444' and type = 'order_payment_expired'), 1,
  'the buyer is told time ran out');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select throws_ok(format($$ insert into storage.objects (bucket_id, name) values ('payment-proofs', '44444444-4444-4444-4444-444444444444/%s/late.png') $$,
  current_setting('test.unpaid')::jsonb ->> 'payment_id'), '42501', null, 'no proof upload after the hold ended');

-- Pre-orders: capacity is held, and the read sweep releases it ----------------------------------
do $$ begin
  perform set_config('test.pre', public.place_order('cccccccc-0000-0000-0000-000000000001', 3, 'dddddddd-0000-0000-0000-000000000001', null, 'transfer')::text, true);
end $$;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 1, 'dddddddd-0000-0000-0000-000000000001') $$), 'CAPACITY_FULL',
  'an unpaid pre-order still holds its places: capacity can''t be exceeded');
reset role;
update public.deal_payments set due_at = now() - interval '1 minute'
where id = (current_setting('test.pre')::jsonb ->> 'payment_id')::uuid;
set local role authenticated;
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select lives_ok($$ select * from public.search_listings() $$, 'anyone browsing runs the sweep');
reset role;
select is((select allocated_qty from public.campaigns where id = 'dddddddd-0000-0000-0000-000000000001'), 0, 'the expired pre-order''s places are free again');
select is((select status from public.orders where id = (current_setting('test.pre')::jsonb ->> 'order_id')::uuid), 'cancelled', 'and the pre-order is cancelled');

-- Reservations: an unpaid hold expires through the read sweep ------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.late', public.request_reservation('cccccccc-0000-0000-0000-000000000003', 1, null, 'transfer')::text, true);
end $$;
reset role;
update public.deal_payments set due_at = now() - interval '1 minute' where id = (current_setting('test.late')::jsonb ->> 'payment_id')::uuid;
update public.reservations set expires_at = now() - interval '1 minute' where id = (current_setting('test.late')::jsonb ->> 'reservation_id')::uuid;
-- A proof file that slipped in (written directly) can't revive it.
insert into storage.objects (bucket_id, name) values
  ('payment-proofs', '44444444-4444-4444-4444-444444444444/' || (current_setting('test.late')::jsonb ->> 'payment_id') || '/late.png');
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select * from public.get_listing('cccccccc-0000-0000-0000-000000000003') $$, 'opening the listing runs the sweep');
reset role;
select is((select rv.status || '/' || dp.status from public.reservations as rv join public.deal_payments as dp on dp.reservation_id = rv.id
           where rv.id = (current_setting('test.late')::jsonb ->> 'reservation_id')::uuid), 'expired/expired', 'the unpaid reservation expired');
select is((select stock || '/' || status from public.listings where id = 'cccccccc-0000-0000-0000-000000000003'), '1/available', 'and the notes are back on sale');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason(format('select public.submit_payment_proof(%L, %L)', current_setting('test.late')::jsonb ->> 'payment_id',
  '44444444-4444-4444-4444-444444444444/' || (current_setting('test.late')::jsonb ->> 'payment_id') || '/late.png')),
  'INVALID_TRANSITION', 'proof after the deadline is refused');

-- A buyer may back out before paying ------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.backout', public.request_reservation('cccccccc-0000-0000-0000-000000000003', 1, null, 'transfer')::text, true);
end $$;
select is(public.resolve_reservation((current_setting('test.backout')::jsonb ->> 'reservation_id')::uuid, 'cancel') ->> 'status', 'cancelled',
  'a buyer who hasn''t paid can cancel');
reset role;
select is((select status from public.deal_payments where id = (current_setting('test.backout')::jsonb ->> 'payment_id')::uuid), 'cancelled',
  'and the payment closes with it');

-- A business order paid by transfer, accepted ------------------------------------------------
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.paid', public.place_order('cccccccc-0000-0000-0000-000000000001', 1, null, null, 'transfer')::text, true);
end $$;
select lives_ok(format($$ insert into storage.objects (bucket_id, name) values ('payment-proofs', '44444444-4444-4444-4444-444444444444/%s/paid.png') $$,
  current_setting('test.paid')::jsonb ->> 'payment_id'), 'Amin uploads proof');
select lives_ok(format('select public.submit_payment_proof(%L, %L)', current_setting('test.paid')::jsonb ->> 'payment_id',
  '44444444-4444-4444-4444-444444444444/' || (current_setting('test.paid')::jsonb ->> 'payment_id') || '/paid.png'), 'and sends it');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.review_payment((current_setting('test.paid')::jsonb ->> 'payment_id')::uuid, true) ->> 'deal_status', 'confirmed',
  'accepting the payment confirms the order');
reset role;
select is((select status from public.orders where id = (current_setting('test.paid')::jsonb ->> 'order_id')::uuid), 'confirmed',
  'the order is confirmed, ready to prepare');
set local role authenticated;

-- Admins can open proof for disputes ------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select ok((select count(*)::int from storage.objects where bucket_id = 'payment-proofs') >= 2, 'an admin can open payment proof');

select * from finish();
rollback;
