-- Business performance for administrators (ADR 0007): who may see it, the
-- figures, the date range, paging, the audit trail, and that a seller's cost
-- and profit never reach an admin or a buyer.
begin;
create extension if not exists pgtap with schema extensions;
select * from no_plan();

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

-- A saved result, as jsonb.
create function pg_temp.saved(name text) returns jsonb language sql as $$
  select current_setting('test.' || name)::jsonb;
$$;

-- Ali Bakes and Nina Crafts have orders; Zed Prints (suspended) has none;
-- Siti buys; Amin is another student; Ben uses gmail; Hana was an admin; an admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('77777777-7777-7777-7777-777777777777', 'nina@student.usm.my', now(), '{"name": "Nina"}'),
  ('88888888-8888-8888-8888-888888888888', 'zed@student.usm.my', now(), '{"name": "Zed"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}'),
  ('66666666-6666-6666-6666-666666666666', 'hana@campusniaga.test', now(), '{}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}');
insert into public.staff_roles (user_id, role) values
  ('33333333-3333-3333-3333-333333333333', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies, baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'Nina Crafts', 'Others', 'Handmade bookmarks and cards.', '013-3333333', 'Aman lobby', 'approved', now(), now()),
  ('aaaaaaaa-0000-0000-0000-000000000088', '88888888-8888-8888-8888-888888888888', 'Zed Prints', 'Stationery', 'Printing notes and posters.', '014-4444444', 'Library', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, pickup_details, status) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Tekun lobby', 'approved'),
  ('bbbbbbbb-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'aaaaaaaa-0000-0000-0000-000000000077', 'Nina Crafts', 'Aman lobby', 'approved'),
  ('bbbbbbbb-0000-0000-0000-000000000088', '88888888-8888-8888-8888-888888888888', 'aaaaaaaa-0000-0000-0000-000000000088', 'Zed Prints', 'Library', 'suspended');
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 1000, 'new', array['p/1.jpg'], 4, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000007', '77777777-7777-7777-7777-777777777777', 'business', 'bbbbbbbb-0000-0000-0000-000000000077', 'Bookmark', 'bookmark', 'Others', 500, 'new', array['p/2.jpg'], 9, 'Aman', 'available'),
  ('cccccccc-0000-0000-0000-000000000009', '77777777-7777-7777-7777-777777777777', 'personal', null, 'Old chair', 'old chair', 'Others', 99900, 'good', array['p/3.jpg'], 0, 'Aman', 'sold');
insert into public.campaigns (id, business_id, listing_id, title, price_sen, start_at, close_at, capacity, allocated_qty, pickup_details, status) values
  ('dddddddd-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 'Raya brownies', 900, now() - interval '1 day', now() + interval '7 days', 10, 4, 'Tekun lobby', 'open');
insert into public.orders (id, buyer_id, business_id, listing_id, qty, unit_price_sen, total_sen, status, collection_details, cancelled_by, completed_at, created_at, cost_sen) values
  ('eeeeeeee-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 3, 1000, 3000, 'completed', 'Tekun', null, '2026-11-10 12:00+08', '2026-11-09 12:00+08', 1700),
  ('eeeeeeee-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 2, 1000, 2000, 'completed', 'Tekun', null, '2026-10-10 12:00+08', '2026-10-09 12:00+08', null),
  ('eeeeeeee-0000-0000-0000-000000000003', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000001', 1, 1000, 1000, 'cancelled', 'Tekun', 'buyer', null, '2026-11-11 12:00+08', null),
  ('eeeeeeee-0000-0000-0000-000000000004', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000077', 'cccccccc-0000-0000-0000-000000000007', 8, 500, 4000, 'completed', 'Aman', null, '2026-11-05 12:00+08', '2026-11-04 12:00+08', 900);
-- A personal sale is not entrepreneurship.
insert into public.purchases (listing_id, buyer_id, seller_id, qty, unit_price_sen, total_sen, payment_method, status, completed_at) values
  ('cccccccc-0000-0000-0000-000000000009', '22222222-2222-2222-2222-222222222222', '77777777-7777-7777-7777-777777777777', 1, 99900, 99900, 'cash', 'completed', now());

-- Who may see it ---------------------------------------------------------------------
set local role anon;
select is(pg_temp.error_reason($$ select public.admin_business_performance_list() $$), '42501', 'signed-out visitors cannot list performance');
select is(pg_temp.error_reason($$ select public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000011') $$), '42501', 'or open a business''s');
reset role;

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list() $$), 'FORBIDDEN', 'a student cannot list performance');
select is(pg_temp.error_reason($$ select public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000011') $$), 'FORBIDDEN', 'a student cannot open a business''s');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list() $$), 'FORBIDDEN', 'a business owner cannot list others');
select is(pg_temp.error_reason($$ select public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000077') $$), 'FORBIDDEN', 'or open another business''s');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list() $$), 'FORBIDDEN', 'a non-USM account cannot');
select pg_temp.as_user('66666666-6666-6666-6666-666666666666');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list() $$), 'FORBIDDEN', 'staff without the administrator role cannot list performance');
select is(pg_temp.error_reason($$ select public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000011') $$), 'FORBIDDEN', 'or open a business''s');
select is(pg_temp.error_reason($$ select public.business_figures('bbbbbbbb-0000-0000-0000-000000000011', null, null) $$), '42501', 'the shared helper is internal');
reset role;
select is((select count(*)::int from public.audit_logs where action like 'performance.%'), 0, 'refused calls record nothing');

-- The list ---------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
do $$ begin
  perform set_config('test.list', public.admin_business_performance_list()::text, true);
end $$;
select is((select string_agg(r ->> 'business_name', ',') from jsonb_array_elements(pg_temp.saved('list') -> 'rows') as r),
  'Ali Bakes,Nina Crafts,Zed Prints', 'every business, highest revenue first, suspended ones included');
select is(pg_temp.saved('list') #>> '{rows,0,estimated_revenue_sen}', '5000', 'revenue adds up completed orders');
select is(pg_temp.saved('list') #>> '{rows,0,total_orders}', '3', 'orders count every status');
select is(pg_temp.saved('list') #>> '{rows,0,completed_count}', '2', 'and how many completed');
select is((pg_temp.saved('list') #>> '{rows,0,owner_name}') || '/' || (pg_temp.saved('list') #>> '{rows,0,category}'), 'Ali/Food & Beverage', 'with the owner and category');
select is((pg_temp.saved('list') #>> '{rows,2,estimated_revenue_sen}') || '/' || (pg_temp.saved('list') #>> '{rows,2,status}'), '0/suspended', 'a business with no orders shows zero');
select is(pg_temp.saved('list') -> 'totals',
  '{"businesses": 3, "approved_businesses": 2, "total_orders": 4, "completed_count": 3, "estimated_revenue_sen": 9000}'::jsonb,
  'the totals cover every business, and no personal sales');
select ok(current_setting('test.list') !~ '(cost|profit)', 'the list has no cost or profit');

select is(public.admin_business_performance_list('2026-11-01 00:00+08', '2026-12-01 00:00+08') #>> '{rows,0,business_name}', 'Nina Crafts', 'the range changes the ranking');
select is(public.admin_business_performance_list('2026-11-01 00:00+08', '2026-12-01 00:00+08') #>> '{totals,estimated_revenue_sen}', '7000', 'and the totals');
select is(jsonb_array_length(public.admin_business_performance_list(page_size => 2) -> 'rows'), 2, 'a page is as big as asked');
select is(public.admin_business_performance_list(page_size => 2, page_offset => 2) #>> '{rows,0,business_name}', 'Zed Prints', 'the next page follows on');
select is(public.admin_business_performance_list(page_size => 2, page_offset => 2) #>> '{totals,businesses}', '3', 'totals don''t depend on the page');
select is(jsonb_array_length(public.admin_business_performance_list(page_offset => 30) -> 'rows'), 0, 'past the end is empty');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list('2026-12-01', '2026-11-01') $$), 'INVALID_INPUT', 'a backwards range is refused');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list(page_size => 101) $$), 'INVALID_INPUT', 'a page over 100 is refused');
select is(pg_temp.error_reason($$ select public.admin_business_performance_list(page_offset => -1) $$), 'INVALID_INPUT', 'a negative offset is refused');

-- One business -----------------------------------------------------------------------
do $$ begin
  perform set_config('test.ali', public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000011')::text, true);
end $$;
select is(pg_temp.saved('ali') ->> 'business_name', 'Ali Bakes', 'an admin opens a business');
select is((pg_temp.saved('ali') ->> 'owner_name') || '/' || (pg_temp.saved('ali') ->> 'status'), 'Ali/approved', 'with its owner and status');
select is(pg_temp.saved('ali') #>> '{orders_by_status,cancelled}', '1', 'orders by status');
select is(pg_temp.saved('ali') ->> 'estimated_revenue_sen', '5000', 'estimated revenue');
select is((pg_temp.saved('ali') #>> '{top_products,0,title}') || '/' || (pg_temp.saved('ali') #>> '{top_products,0,units}'), 'Brownie box/5', 'best sellers');
select is(pg_temp.saved('ali') #>> '{stock,0,stock}', '4', 'stock');
select is(pg_temp.saved('ali') #>> '{campaigns,0,remaining}', '6', 'pre-order places left');
select ok(current_setting('test.ali') !~ '(cost|profit)', 'one business''s page has no cost or profit');
select is(public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000011', '2026-11-01 00:00+08', '2026-12-01 00:00+08') ->> 'estimated_revenue_sen', '3000', 'the range applies');
select is(public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000088') ->> 'status', 'suspended', 'a suspended business can still be opened');
select is(pg_temp.error_reason($$ select public.admin_business_performance('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'a missing business is reported');
select is(pg_temp.error_reason($$ select public.admin_business_performance('bbbbbbbb-0000-0000-0000-000000000011', '2026-12-01', '2026-11-01') $$), 'INVALID_INPUT', 'a backwards range is refused');

-- The audit trail --------------------------------------------------------------------
select ok((select count(*) from public.audit_logs where action = 'performance.list_viewed') >= 5, 'each view of the list is audited');
select is((select count(*)::int from public.audit_logs
           where action = 'performance.viewed' and target_id = 'bbbbbbbb-0000-0000-0000-000000000011'
             and actor_id = '33333333-3333-3333-3333-333333333333'), 2, 'each view of a business is audited');
select is((select min(metadata ->> 'business') from public.audit_logs where action = 'performance.viewed' and target_id = 'bbbbbbbb-0000-0000-0000-000000000011'),
  'Ali Bakes', 'naming the business');
select ok(not exists (select 1 from public.audit_logs where action like 'performance.%' and metadata::text ~ '(revenue|cost|profit)'), 'the audit log holds no figures');

-- The owner's dashboard agrees, and keeps its private figures --------------------------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin
  perform set_config('test.own', public.business_dashboard()::text, true);
end $$;
select is(pg_temp.saved('own') ->> 'estimated_revenue_sen', pg_temp.saved('ali') ->> 'estimated_revenue_sen', 'the owner sees the same revenue');
select is(pg_temp.saved('own') -> 'orders_by_status', pg_temp.saved('ali') -> 'orders_by_status', 'and the same orders');
select is((pg_temp.saved('own') ->> 'recorded_cost_sen') || '/' || (pg_temp.saved('own') ->> 'estimated_profit_sen'), '1700/3300', 'and still has their cost and profit');
select is((select cost_sen from public.my_orders('selling') where id = 'eeeeeeee-0000-0000-0000-000000000001'), 1700, 'and their cost in My Orders');

-- cost_sen can't be read from the table ------------------------------------------------
select is(pg_temp.error_reason($$ select cost_sen from public.orders $$), '42501', 'not even the owner selects the cost column');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select cost_sen from public.orders $$), '42501', 'a buyer cannot read the seller''s cost');
select is(pg_temp.error_reason($$ select * from public.orders $$), '42501', 'or get it through select *');
select is(pg_temp.error_reason($$ select 1 from public.orders where cost_sen > 1000 $$), '42501', 'or probe it with a filter');
select is((select count(id)::int from public.orders), 4, 'a buyer still reads the rest of their orders');
select is((select max(cost_sen) from public.my_orders('buying')), null, 'My Orders shows a buyer no cost');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is(pg_temp.error_reason($$ select cost_sen from public.orders $$), '42501', 'an admin cannot read costs either');
select is((select sum(total_sen)::int from public.orders), 10000, 'an admin still reads the other columns');
reset role;
select is((select array_agg(attname::text order by attname) from pg_attribute
           where attrelid = 'public.orders'::regclass and attnum > 0 and not attisdropped
             and not has_column_privilege('authenticated', 'public.orders', attname, 'select')),
  array['cost_sen'], 'cost_sen is the only column held back');

select * from finish();
rollback;
