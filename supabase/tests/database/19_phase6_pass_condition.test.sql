-- Phase 6 pass condition, as one journey: completed orders update the
-- estimated analytics, and seller A cannot read seller B's data.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

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

-- "completed/revenue/costs/profit" from the caller's dashboard.
create function pg_temp.figures() returns text language sql as $$
  select d ->> 'completed_count' || '/' || (d ->> 'estimated_revenue_sen') || '/'
         || (d ->> 'recorded_cost_sen') || '/' || (d ->> 'estimated_profit_sen')
  from (select public.business_dashboard() as d) as x;
$$;

-- Seller A (Ali Bakes) and seller B (Nina Crafts), approved; Siti buys.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('77777777-7777-7777-7777-777777777777', 'nina@student.usm.my', now(), '{"name": "Nina"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies, baked weekly.', '012-3456789', 'Tekun', 'approved', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'Nina Crafts', 'Others', 'Handmade bookmarks and cards.', '013-3333333', 'Aman', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Tekun lobby'),
  ('bbbbbbbb-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'aaaaaaaa-0000-0000-0000-000000000077', 'Nina Crafts', 'Aman Damai');
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 1200, 'new', array['p/1.jpg'], 5, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000007', '77777777-7777-7777-7777-777777777777', 'business', 'bbbbbbbb-0000-0000-0000-000000000077', 'Bookmark set', 'bookmark set', 'Others', 500, 'new', array['p/7.jpg'], 9, 'Aman', 'available');

-- 1. Orders that aren't completed don't count as sales -------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.a1', public.place_order('cccccccc-0000-0000-0000-000000000001', 2) ->> 'order_id', true);
  perform set_config('test.a2', public.place_order('cccccccc-0000-0000-0000-000000000001', 1) ->> 'order_id', true);
  perform set_config('test.b1', public.place_order('cccccccc-0000-0000-0000-000000000007', 3) ->> 'order_id', true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.figures(), '0/0/0/0', 'before anything is completed, Ali has no sales');
select is((public.business_dashboard() -> 'orders_by_status' ->> 'pending_confirmation')::int, 2, 'but sees his two pending orders');

-- 2. Completing an order updates the analytics ---------------------------------------------------
select lives_ok($$ select public.transition_order(current_setting('test.a1')::uuid, 'confirm');
                   select public.transition_order(current_setting('test.a1')::uuid, 'prepare');
                   select public.transition_order(current_setting('test.a1')::uuid, 'ready');
                   select public.transition_order(current_setting('test.a1')::uuid, 'complete') $$,
  'Ali confirms, prepares, readies and completes Siti''s order of 2');
select is(pg_temp.figures(), '1/2400/0/2400', 'the sale appears: 1 completed, RM 24 estimated revenue');
select lives_ok($$ select public.set_order_cost(current_setting('test.a1')::uuid, 900) $$, 'Ali records RM 9 of costs for it');
select is(pg_temp.figures(), '1/2400/900/1500', 'estimated profit is RM 24 - RM 9 = RM 15');
select lives_ok($$ select public.transition_order(current_setting('test.a2')::uuid, 'confirm');
                   select public.transition_order(current_setting('test.a2')::uuid, 'prepare');
                   select public.transition_order(current_setting('test.a2')::uuid, 'ready');
                   select public.transition_order(current_setting('test.a2')::uuid, 'complete') $$,
  'Ali completes the second order');
select is(pg_temp.figures(), '2/3600/900/2700', 'the figures update again: 2 sales, RM 36, profit RM 27');
select is(public.business_dashboard() -> 'top_products',
  '[{"listing_id": "cccccccc-0000-0000-0000-000000000001", "title": "Brownie box", "units": 3, "revenue_sen": 3600}]'::jsonb,
  'and the top product shows 3 units for RM 36');
select is((select x ->> 'stock' from jsonb_array_elements(public.business_dashboard() -> 'stock') as x), '2', 'the stock overview shows 2 boxes left');

-- 3. Seller A cannot read seller B's data, nor B A's ---------------------------------------------------
select is((select count(*)::int from public.orders), 2, 'Ali reads only his own business''s orders');
select is((select count(*)::int from public.my_orders('selling')), 2, 'and My Orders shows only his');
select is(pg_temp.error_reason($$ select public.set_order_cost(current_setting('test.b1')::uuid, 100) $$), 'FORBIDDEN', 'he cannot touch Nina''s order');
select is(pg_temp.error_reason($$ select public.transition_order(current_setting('test.b1')::uuid, 'confirm') $$), 'FORBIDDEN', 'or progress it');
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select is(pg_temp.figures(), '0/0/0/0', 'Nina''s dashboard shows none of Ali''s sales');
select is((public.business_dashboard() ->> 'total_orders')::int, 1, 'only her own order');
select is((select count(*)::int from public.orders), 1, 'and she reads only her own order');
reset role;
select is((select count(*)::int from public.orders), 3, 'while all three orders exist');

select * from finish();
rollback;
