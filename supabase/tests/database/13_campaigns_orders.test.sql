-- Pre-order campaigns and orders (M3): upsert_campaign, set_campaign_status,
-- place_order (ready stock and pre-orders, every limit), transition_order
-- (every status and action), my_orders privacy and who reads what.
begin;
create extension if not exists pgtap with schema extensions;
select plan(103);

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

-- Ali runs Ali Bakes; Siti and Amin buy; Sam has no business; Ben uses
-- gmail; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('66666666-6666-6666-6666-666666666666', 'sam@student.usm.my', now(), '{"name": "Sam"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, description, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Brownies.', 'Tekun lobby, 6-8pm');
-- Two published products (3 brownie boxes, 10 cookies), a draft product and
-- a personal item.
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 500, 'new', array['p/1.jpg'], 3, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Cookie jar', 'cookie jar', 'Food & Beverage', 800, 'new', array['p/2.jpg'], 10, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Draft tart', 'draft tart', 'Food & Beverage', 900, 'new', '{}', 2, 'Tekun', 'draft'),
  ('cccccccc-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Old textbook', 'old textbook', 'Books', 2000, 'good', array['p/4.jpg'], 1, 'Tekun', 'available');

-- Campaigns: who may create them ------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now(), now() + interval '7 days', 3, 2, 'Tekun lobby') $$),
  'FORBIDDEN', 'a student without an approved business cannot create a pre-order');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000004', 'Textbook pre-order', 450, now(), now() + interval '7 days', 3, null, 'Tekun lobby') $$),
  'FORBIDDEN', 'pre-orders are only for business products');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000003', 'Tart pre-order', 450, now(), now() + interval '7 days', 3, null, 'Tekun lobby') $$),
  'INVALID_INPUT', 'the product must be published first');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, '99999999-9999-9999-9999-999999999999', 'Ghost', 450, now(), now() + interval '7 days', 3, null, 'Tekun lobby') $$),
  'NOT_FOUND', 'the product must exist');

-- Campaigns: input
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Ra', 450, now(), now() + interval '7 days', 3, null, 'Tekun lobby') $$), 'INVALID_INPUT', 'a title under 3 characters is refused');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', -1, now(), now() + interval '7 days', 3, null, 'Tekun lobby') $$), 'INVALID_INPUT', 'a negative price is refused');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now() + interval '2 days', now() + interval '1 day', 3, null, 'Tekun lobby') $$), 'INVALID_INPUT', 'closing before opening is refused');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now() - interval '2 days', now() - interval '1 day', 3, null, 'Tekun lobby') $$), 'INVALID_INPUT', 'a closing date in the past is refused');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now(), now() + interval '7 days', 0, null, 'Tekun lobby') $$), 'INVALID_INPUT', 'a capacity of 0 is refused');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now(), now() + interval '7 days', 3, 4, 'Tekun lobby') $$), 'INVALID_INPUT', 'a per-order limit above the capacity is refused');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 450, now(), now() + interval '7 days', 3, null, 'Tek') $$), 'INVALID_INPUT', 'pickup details under 5 characters are refused');

-- Creating and opening the capacity-3 pre-order
do $$ begin
  perform set_config('test.campaign', public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000001', ' Raya brownies ', 450,
    now() - interval '1 hour', now() + interval '7 days', 3, 2, ' Tekun lobby, Sat 10am ') ->> 'campaign_id', true);
end $$;
reset role;
select is((select status || '/' || business_id || '/' || title || '/' || pickup_details from public.campaigns where id = current_setting('test.campaign')::uuid),
  'draft/bbbbbbbb-0000-0000-0000-000000000011/Raya brownies/Tekun lobby, Sat 10am', 'an approved owner creates a draft pre-order for their business');

set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 1, current_setting('test.campaign')::uuid) $$), 'NOT_FOUND', 'a draft pre-order takes no orders');
select is(pg_temp.error_reason($$ select public.set_campaign_status(current_setting('test.campaign')::uuid, 'open') $$), 'FORBIDDEN', 'a buyer cannot open a pre-order');
select is((select count(*)::int from public.campaigns), 0, 'buyers cannot read campaigns directly');
select is(pg_temp.error_reason($$ insert into public.campaigns (business_id, listing_id, title, price_sen, start_at, close_at, capacity, pickup_details)
  values ('bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 'Fake', 1, now(), now() + interval '1 day', 1, 'Tekun lobby') $$), '42501', 'campaigns cannot be inserted directly');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ update public.campaigns set allocated_qty = 0 $$), '42501', 'the owner cannot change allocation directly');
select is((select count(*)::int from public.campaigns), 1, 'the owner reads their campaigns');
select is(pg_temp.error_reason($$ select public.set_campaign_status(current_setting('test.campaign')::uuid, 'live') $$), 'INVALID_INPUT', 'an unknown campaign status is refused');
select is(public.set_campaign_status(current_setting('test.campaign')::uuid, 'open') ->> 'status', 'open', 'the owner opens the pre-order');
select is(pg_temp.error_reason($$ select public.set_campaign_status(current_setting('test.campaign')::uuid, 'open') $$), 'INVALID_TRANSITION', 'an open pre-order cannot be opened again');
select is(pg_temp.error_reason($$ select public.upsert_campaign(current_setting('test.campaign')::uuid, 'cccccccc-0000-0000-0000-000000000002', 'Raya brownies', 450, now() - interval '1 hour', now() + interval '7 days', 3, 2, 'Tekun lobby') $$),
  'INVALID_INPUT', 'a pre-order''s product cannot change');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.campaigns), 1, 'admins read campaigns');
reset role;

-- The storefront shows the open pre-order with what is left
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select x ->> 'title' || '/' || (x ->> 'remaining') from jsonb_array_elements(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'campaigns') as x),
  'Raya brownies/3', 'the storefront shows the open pre-order and its places left');

-- Ready stock ------------------------------------------------------------------------------------------------
select is(public.place_order('cccccccc-0000-0000-0000-000000000001', 2, null, ' After 6pm ') ->> 'total_sen', '1000', 'Siti orders 2 of the 3 brownie boxes');
reset role;
select is((select status || '/' || stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 'available/1', 'the units are taken at once');
select is((select unit_price_sen || '/' || total_sen || '/' || status || '/' || buyer_note || '/' || collection_details from public.orders where buyer_id = '22222222-2222-2222-2222-222222222222'),
  '500/1000/pending_confirmation/After 6pm/Tekun lobby, 6-8pm', 'the order snapshots price and pickup details');
select is((select type from public.notifications where recipient_id = '11111111-1111-1111-1111-111111111111' order by id desc limit 1), 'order_placed', 'the seller is told');

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 2) $$), 'ITEM_UNAVAILABLE', 'Amin cannot take more than the 1 left');
do $$ begin
  perform set_config('test.amin_order', public.place_order('cccccccc-0000-0000-0000-000000000001', 1) ->> 'order_id', true);
end $$;
reset role;
select is((select status || '/' || stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 'sold/0', 'Amin takes the last one and it sells out');
set local role authenticated;
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 1) $$), 'ITEM_UNAVAILABLE', 'a sold-out product cannot be ordered');

-- Ordering: refused cases
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000004', 1) $$), 'ITEM_UNAVAILABLE', 'a personal item is bought with Buy now, not ordered');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000003', 1) $$), 'NOT_FOUND', 'a draft product cannot be ordered');
select is(pg_temp.error_reason($$ select public.place_order('99999999-9999-9999-9999-999999999999', 1) $$), 'NOT_FOUND', 'a missing product cannot be ordered');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 0) $$), 'INVALID_INPUT', 'a quantity of 0 is refused');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1, null, repeat('x', 201)) $$), 'INVALID_INPUT', 'a note over 200 characters is refused');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1, current_setting('test.campaign')::uuid) $$), 'INVALID_INPUT', 'a pre-order for another product is refused');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1) $$), 'FORBIDDEN', 'a seller cannot order from their own business');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1) $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot order');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1) $$), '42501', 'signed-out visitors cannot order');
reset role;
update public.listings set hidden = true where id = 'cccccccc-0000-0000-0000-000000000002';
set local role authenticated;
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1) $$), 'ITEM_UNAVAILABLE', 'a hidden product cannot be ordered');
reset role;
update public.listings set hidden = false where id = 'cccccccc-0000-0000-0000-000000000002';

-- Cancelling frees the units ----------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(public.transition_order(current_setting('test.amin_order')::uuid, 'cancel') ->> 'status', 'cancelled', 'Amin cancels his order');
reset role;
select is((select status || '/' || stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 'available/1', 'the unit goes back on sale');
select is((select cancelled_by from public.orders where id = current_setting('test.amin_order')::uuid), 'buyer', 'the order records who cancelled');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.amin_order')::uuid, 'cancel') $$), 'INVALID_TRANSITION', 'a cancelled order cannot be cancelled again');
reset role;
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 1, 'and the unit is not returned twice');

-- Pre-orders: capacity 3, at most 2 per order ------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 3, current_setting('test.campaign')::uuid) $$), 'INVALID_INPUT', 'the per-order limit holds');
do $$ begin
  perform set_config('test.siti_pre', public.place_order('cccccccc-0000-0000-0000-000000000001', 2, current_setting('test.campaign')::uuid) ->> 'order_id', true);
end $$;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 2, current_setting('test.campaign')::uuid) $$), 'CAPACITY_FULL', 'Amin cannot pre-order more than the 1 place left');
select is(public.place_order('cccccccc-0000-0000-0000-000000000001', 1, current_setting('test.campaign')::uuid) ->> 'status', 'pending_confirmation', 'Amin pre-orders the last place');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 1, current_setting('test.campaign')::uuid) $$), 'CAPACITY_FULL', 'a full pre-order takes no more');
reset role;
select is((select allocated_qty || '/' || capacity from public.campaigns where id = current_setting('test.campaign')::uuid), '3/3', 'allocation reached capacity and no further');
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 1, 'pre-orders do not touch ready stock');
select is((select unit_price_sen || '/' || collection_details from public.orders where id = current_setting('test.siti_pre')::uuid), '450/Tekun lobby, Sat 10am', 'a pre-order takes the campaign''s price and pickup details');
select throws_ok($$ update public.campaigns set allocated_qty = 4 where id = current_setting('test.campaign')::uuid $$, '23514', null, 'the database refuses allocation above capacity even without the function');
select throws_ok($$ update public.orders set total_sen = 1 where id = current_setting('test.siti_pre')::uuid $$, '23514', null, 'a total must equal price times quantity');

-- Editing a running pre-order
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.upsert_campaign(current_setting('test.campaign')::uuid, null, 'Raya brownies', 450, now() - interval '1 hour', now() + interval '7 days', 2, 2, 'Tekun lobby') $$),
  'INVALID_INPUT', 'capacity cannot drop below what is already ordered');
select lives_ok($$ select public.upsert_campaign(current_setting('test.campaign')::uuid, null, 'Raya brownies', 600, now() - interval '1 hour', now() + interval '7 days', 4, 2, 'Tekun lobby, Sat 10am') $$,
  'the owner raises the price and the capacity');
reset role;
select is((select unit_price_sen from public.orders where id = current_setting('test.siti_pre')::uuid), 450, 'placed orders keep their price');

-- Cancelling a pre-order frees its places
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select public.transition_order(current_setting('test.siti_pre')::uuid, 'cancel') $$, 'Siti cancels her pre-order');
reset role;
select is((select allocated_qty from public.campaigns where id = current_setting('test.campaign')::uuid), 1, 'her 2 places are freed');
set local role authenticated;
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(public.place_order('cccccccc-0000-0000-0000-000000000001', 2, current_setting('test.campaign')::uuid) ->> 'total_sen', '1200', 'Sam takes 2 places at the new price');

-- Closed, not started and past pre-orders
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.set_campaign_status(current_setting('test.campaign')::uuid, 'closed') ->> 'status', 'closed', 'the owner closes the pre-order');
select is(pg_temp.error_reason($$ select public.set_campaign_status(current_setting('test.campaign')::uuid, 'open') $$), 'INVALID_TRANSITION', 'a closed pre-order cannot reopen');
select is(pg_temp.error_reason($$ select public.upsert_campaign(current_setting('test.campaign')::uuid, null, 'Raya brownies', 600, now(), now() + interval '7 days', 4, 2, 'Tekun lobby') $$), 'INVALID_TRANSITION', 'a closed pre-order cannot be edited');
do $$ begin
  perform set_config('test.later', public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000002', 'Cookie week', 700,
    now() + interval '1 day', now() + interval '8 days', 10, null, 'Tekun lobby') ->> 'campaign_id', true);
  perform public.set_campaign_status(current_setting('test.later')::uuid, 'open');
end $$;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000001', 1, current_setting('test.campaign')::uuid) $$), 'INVALID_TRANSITION', 'a closed pre-order takes no orders');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1, current_setting('test.later')::uuid) $$), 'INVALID_TRANSITION', 'a pre-order takes no orders before it opens');
reset role;
update public.campaigns set start_at = now() - interval '3 days', close_at = now() - interval '1 day' where id = current_setting('test.later')::uuid;
set local role authenticated;
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1, current_setting('test.later')::uuid) $$), 'INVALID_TRANSITION', 'nor after its closing date, even if still marked open');
select is(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'campaigns', '[]'::jsonb, 'closed and past pre-orders leave the storefront');
reset role;
update public.campaigns set status = 'draft' where id = current_setting('test.later')::uuid;
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.set_campaign_status(current_setting('test.later')::uuid, 'open') $$), 'INVALID_INPUT', 'a pre-order past its closing date cannot be opened');
reset role;

-- Moving an order forward ----------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.order', public.place_order('cccccccc-0000-0000-0000-000000000002', 2) ->> 'order_id', true);
end $$;
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.order')::uuid, 'confirm') $$), 'FORBIDDEN', 'the buyer cannot confirm their own order');
select is((select other_party_email from public.my_orders('buying') where id = current_setting('test.order')::uuid), null, 'the seller''s email stays hidden while pending');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.order')::uuid, 'cancel') $$), 'FORBIDDEN', 'a stranger cannot touch the order');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.order')::uuid, 'ship') $$), 'INVALID_INPUT', 'an unknown action is refused');
select is(pg_temp.error_reason($$ select public.transition_order('99999999-9999-9999-9999-999999999999', 'confirm') $$), 'NOT_FOUND', 'a missing order is reported');
select is(public.transition_order(current_setting('test.order')::uuid, 'confirm') ->> 'status', 'confirmed', 'the seller confirms');
select is(public.transition_order(current_setting('test.order')::uuid, 'prepare') ->> 'status', 'preparing', 'starts preparing');
select is(public.transition_order(current_setting('test.order')::uuid, 'ready') ->> 'status', 'ready_for_pickup', 'marks it ready');
select is((select other_party_name || '/' || other_party_email from public.my_orders('selling') where id = current_setting('test.order')::uuid), 'Siti/siti@student.usm.my', 'the seller sees the buyer once confirmed');
select is(public.transition_order(current_setting('test.order')::uuid, 'complete') ->> 'status', 'completed', 'and completes it after pickup');
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.order')::uuid, 'cancel') $$), 'INVALID_TRANSITION', 'a completed order cannot be cancelled');
reset role;
select ok((select completed_at is not null and cancelled_by is null from public.orders where id = current_setting('test.order')::uuid), 'completion is dated');
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000002'), 8, 'completing keeps the units taken');
select is((select string_agg(type, ',' order by id) from public.notifications where recipient_id = '22222222-2222-2222-2222-222222222222' and target = 'order:' || current_setting('test.order')),
  'order_confirmed,order_preparing,order_ready_for_pickup,order_completed', 'the buyer is told at every step');
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select status || '/' || other_party_email || '/' || business_name from public.my_orders('buying') where id = current_setting('test.order')::uuid),
  'completed/ali@student.usm.my/Ali Bakes', 'the buyer sees the business and the seller''s email once confirmed');
reset role;

-- A seller rejecting a pending order is a cancellation by the seller
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.reject', public.place_order('cccccccc-0000-0000-0000-000000000002', 3) ->> 'order_id', true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select public.transition_order(current_setting('test.reject')::uuid, 'cancel') $$, 'the seller rejects a pending order');
reset role;
select is((select cancelled_by from public.orders where id = current_setting('test.reject')::uuid), 'seller', 'recorded as cancelled by the seller');
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000002'), 8, 'and the 3 units are back');

-- A suspended business cannot progress orders, but its buyers can still cancel
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.suspended', public.place_order('cccccccc-0000-0000-0000-000000000002', 1) ->> 'order_id', true);
end $$;
reset role;
update public.businesses set status = 'suspended' where id = 'bbbbbbbb-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.suspended')::uuid, 'confirm') $$), 'FORBIDDEN', 'a suspended business cannot progress orders');
select is((select count(*)::int from public.my_orders('selling')), 8, 'but its owner still reads its order history');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.place_order('cccccccc-0000-0000-0000-000000000002', 1) $$), 'ITEM_UNAVAILABLE', 'nobody can order from a suspended business');
select is(public.transition_order(current_setting('test.suspended')::uuid, 'cancel') ->> 'status', 'cancelled', 'the buyer can still cancel');
reset role;
update public.businesses set status = 'approved' where id = 'bbbbbbbb-0000-0000-0000-000000000011';

-- Who reads orders ------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.orders), 3, 'a buyer reads only their own orders');
select is(pg_temp.error_reason($$ update public.orders set status = 'completed' $$), '42501', 'orders cannot be written directly');
select is(pg_temp.error_reason($$ select * from public.my_orders('renting') $$), 'INVALID_INPUT', 'my_orders needs buying or selling');
select is(pg_temp.error_reason($$ select * from public.my_orders('buying', 0) $$), 'INVALID_INPUT', 'and a sensible page size');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.orders), 8, 'the business owner reads every order of the business');
select is((select count(*)::int from public.my_orders('buying')), 0, 'and has none as a buyer');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.orders), 8, 'admins read all orders');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select * from public.my_orders() $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account has no orders view');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select count(*) from public.orders $$), '42501', 'signed-out visitors read no orders');
reset role;

-- Every (status, action) pair ---------------------------------------------------------------------------------------
-- Each case creates an order of 1 cookie jar in the starting status, runs
-- the action as the seller (or the buyer, for cancel), records the outcome
-- and rolls the case back.
create function pg_temp.order_outcome(from_status text, order_action text, actor text) returns text language plpgsql as $$
declare outcome text; reason text;
begin
  begin
    insert into public.orders (id, buyer_id, business_id, listing_id, qty, unit_price_sen, total_sen, status, collection_details, cancelled_by, completed_at)
    values ('dddddddd-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011',
            'cccccccc-0000-0000-0000-000000000002', 1, 800, 800, from_status, 'Tekun',
            case when from_status = 'cancelled' then 'buyer' end, case when from_status = 'completed' then now() end);
    perform set_config('role', 'authenticated', true);
    perform pg_temp.as_user(case when actor = 'buyer' then '22222222-2222-2222-2222-222222222222' else '11111111-1111-1111-1111-111111111111' end);
    outcome := public.transition_order('dddddddd-0000-0000-0000-000000000001', order_action) ->> 'status';
    raise exception using errcode = 'P0001', message = 'roll back this case', detail = 'ROLLBACK_CASE';
  exception when others then
    get stacked diagnostics reason = pg_exception_detail;
    if reason is distinct from 'ROLLBACK_CASE' then
      outcome := coalesce(nullif(reason, ''), sqlstate);
    end if;
  end;
  return outcome;
end;
$$;

select results_eq(
  $$ select s || ' + ' || a || ' = ' || pg_temp.order_outcome(s, a, 'seller')
     from unnest(array['pending_confirmation', 'confirmed', 'preparing', 'ready_for_pickup', 'completed', 'cancelled']) with ordinality as st (s, i)
     cross join unnest(array['confirm', 'prepare', 'ready', 'complete', 'cancel']) with ordinality as ac (a, j)
     order by i, j $$,
  $$ values
     ('pending_confirmation + confirm = confirmed'), ('pending_confirmation + prepare = INVALID_TRANSITION'), ('pending_confirmation + ready = INVALID_TRANSITION'), ('pending_confirmation + complete = INVALID_TRANSITION'), ('pending_confirmation + cancel = cancelled'),
     ('confirmed + confirm = INVALID_TRANSITION'), ('confirmed + prepare = preparing'), ('confirmed + ready = INVALID_TRANSITION'), ('confirmed + complete = INVALID_TRANSITION'), ('confirmed + cancel = cancelled'),
     ('preparing + confirm = INVALID_TRANSITION'), ('preparing + prepare = INVALID_TRANSITION'), ('preparing + ready = ready_for_pickup'), ('preparing + complete = INVALID_TRANSITION'), ('preparing + cancel = cancelled'),
     ('ready_for_pickup + confirm = INVALID_TRANSITION'), ('ready_for_pickup + prepare = INVALID_TRANSITION'), ('ready_for_pickup + ready = INVALID_TRANSITION'), ('ready_for_pickup + complete = completed'), ('ready_for_pickup + cancel = cancelled'),
     ('completed + confirm = INVALID_TRANSITION'), ('completed + prepare = INVALID_TRANSITION'), ('completed + ready = INVALID_TRANSITION'), ('completed + complete = INVALID_TRANSITION'), ('completed + cancel = INVALID_TRANSITION'),
     ('cancelled + confirm = INVALID_TRANSITION'), ('cancelled + prepare = INVALID_TRANSITION'), ('cancelled + ready = INVALID_TRANSITION'), ('cancelled + complete = INVALID_TRANSITION'), ('cancelled + cancel = INVALID_TRANSITION') $$,
  'the seller moves an order one step at a time and may cancel until it is completed'
);

select results_eq(
  $$ select s || ' = ' || pg_temp.order_outcome(s, 'cancel', 'buyer')
     from unnest(array['pending_confirmation', 'confirmed', 'preparing', 'ready_for_pickup', 'completed', 'cancelled']) with ordinality as st (s, i)
     order by i $$,
  $$ values ('pending_confirmation = cancelled'), ('confirmed = cancelled'), ('preparing = cancelled'),
            ('ready_for_pickup = cancelled'), ('completed = INVALID_TRANSITION'), ('cancelled = INVALID_TRANSITION') $$,
  'the buyer may cancel until the order is completed'
);
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000002'), 8, 'the transition cases leave the stock as it was');

select * from finish();
rollback;
