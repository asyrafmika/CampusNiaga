-- The business dashboard (M5): set_order_cost, every dashboard figure, date
-- ranges, the cost in My Orders, and that a seller only ever sees their own
-- business.
begin;
create extension if not exists pgtap with schema extensions;
select plan(42);

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

-- Ali runs Ali Bakes, Nina runs Nina Crafts; Siti and Amin buy; Ben uses gmail.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('77777777-7777-7777-7777-777777777777', 'nina@student.usm.my', now(), '{"name": "Nina"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies, baked weekly.', '012-3456789', 'Tekun', 'approved', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'Nina Crafts', 'Others', 'Handmade bookmarks and cards.', '013-3333333', 'Aman', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Tekun lobby'),
  ('bbbbbbbb-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'aaaaaaaa-0000-0000-0000-000000000077', 'Nina Crafts', 'Aman Damai');
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 1200, 'new', array['p/1.jpg'], 4, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Cookie jar', 'cookie jar', 'Food & Beverage', 800, 'new', array['p/2.jpg'], 1, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Draft tart', 'draft tart', 'Food & Beverage', 900, 'new', '{}', 2, 'Tekun', 'draft'),
  ('cccccccc-0000-0000-0000-000000000007', '77777777-7777-7777-7777-777777777777', 'business', 'bbbbbbbb-0000-0000-0000-000000000077', 'Bookmark set', 'bookmark set', 'Others', 500, 'new', array['p/7.jpg'], 9, 'Aman', 'available');
insert into public.campaigns (id, business_id, listing_id, title, price_sen, start_at, close_at, capacity, allocated_qty, pickup_details, status) values
  ('dddddddd-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 1000, now() - interval '1 day', now() + interval '6 days', 10, 2, 'Tekun lobby', 'open'),
  ('dddddddd-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000002', 'Old cookie run', 700, now() - interval '9 days', now() - interval '2 days', 5, 5, 'Tekun lobby', 'closed');

-- Ali's orders: two completed in October (one placed in September), one completed now,
-- one confirmed, one pending, one cancelled. Nina has one completed order.
insert into public.orders (id, buyer_id, business_id, listing_id, campaign_id, qty, unit_price_sen, total_sen, status, collection_details, cancelled_by, completed_at, created_at) values
  ('eeeeeeee-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', null, 2, 1200, 2400, 'completed', 'Tekun', null, '2026-10-10 12:00+08', '2026-09-30 12:00+08'),
  ('eeeeeeee-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000002', null, 4, 800, 3200, 'completed', 'Tekun', null, '2026-10-20 12:00+08', '2026-10-19 12:00+08'),
  ('eeeeeeee-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 1, 1000, 1000, 'completed', 'Tekun', null, '2026-11-10 12:00+08', '2026-11-09 12:00+08'),
  ('eeeeeeee-0000-0000-0000-000000000004', '44444444-4444-4444-4444-444444444444', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', null, 1, 1200, 1200, 'confirmed', 'Tekun', null, null, '2026-11-11 12:00+08'),
  ('eeeeeeee-0000-0000-0000-000000000005', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 'dddddddd-0000-0000-0000-000000000001', 1, 1000, 1000, 'pending_confirmation', 'Tekun', null, null, '2026-11-12 12:00+08'),
  ('eeeeeeee-0000-0000-0000-000000000006', '44444444-4444-4444-4444-444444444444', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000002', null, 1, 800, 800, 'cancelled', 'Tekun', 'buyer', null, '2026-11-12 13:00+08'),
  ('eeeeeeee-0000-0000-0000-000000000007', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000077', 'cccccccc-0000-0000-0000-000000000007', null, 4, 500, 2000, 'completed', 'Aman', null, '2026-11-05 12:00+08', '2026-11-04 12:00+08');

-- Recording costs ----------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.set_order_cost('eeeeeeee-0000-0000-0000-000000000001', 1500) ->> 'cost_sen', '1500', 'the seller records the cost of an order');
select lives_ok($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000002', 1200) $$, 'and of another');
select lives_ok($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000004', 600) $$, 'a cost can be recorded before completion');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000006', 100) $$), 'INVALID_TRANSITION', 'not for a cancelled order');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000001', -1) $$), 'INVALID_INPUT', 'a negative cost is refused');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000001', 100000001) $$), 'INVALID_INPUT', 'a cost over RM 1,000,000 is refused');
select is(pg_temp.error_reason($$ select public.set_order_cost('99999999-9999-9999-9999-999999999999', 100) $$), 'NOT_FOUND', 'a missing order is reported');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000007', 100) $$), 'FORBIDDEN', 'Ali cannot record a cost on Nina''s order');
select is(pg_temp.error_reason($$ update public.orders set cost_sen = 1 $$), '42501', 'costs cannot be written directly');
select is((select cost_sen from public.my_orders('selling') where id = 'eeeeeeee-0000-0000-0000-000000000001'), 1500, 'the seller sees the cost in My Orders');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000001', 1) $$), 'FORBIDDEN', 'the buyer cannot record a cost');
select is((select cost_sen from public.my_orders('buying') where id = 'eeeeeeee-0000-0000-0000-000000000001'), null, 'and never sees the seller''s cost');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000001', 1) $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot record costs');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000001', 1) $$), '42501', 'signed-out visitors cannot either');
reset role;

-- Ali's dashboard, all time ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.business_dashboard() -> 'orders_by_status',
  '{"pending_confirmation": 1, "confirmed": 1, "preparing": 0, "ready_for_pickup": 0, "completed": 3, "cancelled": 1}'::jsonb,
  'orders by status, zeros included');
select is((public.business_dashboard() ->> 'total_orders')::int, 6, 'all six of Ali''s orders, none of Nina''s');
select is((public.business_dashboard() ->> 'completed_count')::int, 3, 'three completed sales');
select is((public.business_dashboard() ->> 'estimated_revenue_sen')::int, 6600, 'estimated revenue is the sum of completed totals (24 + 32 + 10)');
select is((public.business_dashboard() ->> 'recorded_cost_sen')::int, 2700, 'recorded costs count completed orders only (15 + 12, not the confirmed 6)');
select is((public.business_dashboard() ->> 'costed_completed_count')::int, 2, 'and say how many completed orders have a cost');
select is((public.business_dashboard() ->> 'estimated_profit_sen')::int, 3900, 'estimated profit is revenue minus recorded costs (66 - 27)');
select is(public.business_dashboard() -> 'top_products',
  '[{"listing_id": "cccccccc-0000-0000-0000-000000000001", "title": "Brownie box", "units": 3, "revenue_sen": 3400},
    {"listing_id": "cccccccc-0000-0000-0000-000000000002", "title": "Cookie jar", "units": 4, "revenue_sen": 3200}]'::jsonb,
  'top products by revenue (not units) from completed orders, ready stock and pre-orders together');
select is((select string_agg(x ->> 'title' || ':' || (x ->> 'stock'), ', ') from jsonb_array_elements(public.business_dashboard() -> 'stock') as x),
  'Cookie jar:1, Brownie box:4', 'stock overview: published products, lowest stock first, no drafts');
select is((select string_agg(x ->> 'title' || ':' || (x ->> 'remaining'), ', ') from jsonb_array_elements(public.business_dashboard() -> 'campaigns') as x),
  'Raya brownies:8', 'campaign overview: open and draft pre-orders with places left');
select is(public.business_dashboard() ->> 'business_name', 'Ali Bakes', 'it names the business');

-- Date ranges
select is((select d ->> 'completed_count' || '/' || (d ->> 'estimated_revenue_sen') || '/' || (d ->> 'estimated_profit_sen') || '/' || (d ->> 'total_orders')
           from (select public.business_dashboard('2026-10-01 00:00+08', '2026-11-01 00:00+08') as d) as x),
  '2/5600/2900/1', 'October: two sales completed in October (one placed in September), one order placed in October');
select is((select d ->> 'completed_count' || '/' || (d ->> 'estimated_revenue_sen') || '/' || (d ->> 'recorded_cost_sen')
           from (select public.business_dashboard('2026-11-01 00:00+08', null) as d) as x),
  '1/1000/0', 'from November: one sale, no recorded cost');
select is((select d ->> 'total_orders' from (select public.business_dashboard(null, '2026-10-01 00:00+08') as d) as x), '1',
  'before October: only the September order was placed');
select is((select d ->> 'total_orders' from (select public.business_dashboard(null, '2026-11-12 12:00+08') as d) as x), '4',
  'the end of a range is exclusive: an order placed exactly at the end is left out');
select is(pg_temp.error_reason($$ select public.business_dashboard('2026-11-01', '2026-10-01') $$), 'INVALID_INPUT', 'a range that ends before it starts is refused');
select is(pg_temp.error_reason($$ select public.business_dashboard('2026-11-01', '2026-11-01') $$), 'INVALID_INPUT', 'an empty range is refused');

-- Seller A never sees seller B ---------------------------------------------------------------------------------
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select is((select d ->> 'business_name' || '/' || (d ->> 'total_orders') || '/' || (d ->> 'estimated_revenue_sen') from (select public.business_dashboard() as d) as x),
  'Nina Crafts/1/2000', 'Nina''s dashboard has only Nina''s order');
select is((select count(*)::int from public.orders), 1, 'and Nina cannot read Ali''s orders directly');
select is((select string_agg(x ->> 'title', ',') from jsonb_array_elements(public.business_dashboard() -> 'stock') as x), 'Bookmark set', 'nor see his stock');
reset role;
select is((select array_agg(p.parameter_name::text order by p.ordinal_position) from information_schema.parameters as p
           join information_schema.routines as r on r.specific_name = p.specific_name
           where r.routine_schema = 'public' and r.routine_name = 'business_dashboard'),
  array['from_at', 'to_at'], 'the dashboard takes no business id: a seller cannot name another business');

-- Who may open a dashboard
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.business_dashboard() $$), 'FORBIDDEN', 'a student without a business has no dashboard');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.business_dashboard() $$), 'NOT_VERIFIED_STUDENT', 'nor a non-USM account');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.business_dashboard() $$), '42501', 'nor a signed-out visitor');
reset role;
update public.businesses set status = 'suspended' where id = 'bbbbbbbb-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.business_dashboard() $$), 'FORBIDDEN', 'a suspended business has no dashboard');
select is(pg_temp.error_reason($$ select public.set_order_cost('eeeeeeee-0000-0000-0000-000000000003', 100) $$), 'FORBIDDEN', 'and cannot record costs');
reset role;
update public.businesses set status = 'approved' where id = 'bbbbbbbb-0000-0000-0000-000000000011';

-- Clearing a cost
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.set_order_cost('eeeeeeee-0000-0000-0000-000000000002', null) ->> 'cost_sen', null, 'a cost can be cleared');
select is((public.business_dashboard() ->> 'estimated_profit_sen')::int, 5100, 'and profit follows (66 - 15)');
reset role;

select * from finish();
rollback;
