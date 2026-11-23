-- QA scenario test: the handoff's minimal scenario fixture (section 9) through
-- every module in one run. 2 students, 1 applicant, 1 approved business
-- seller, 2 administrators (one reviews); 2 personal listings, 2 business products, a
-- capacity-3 pre-order, 3 similar requests ("brownie", "brownies",
-- "chocolate brownie") and a competing listing. It checks distinct-user
-- counting, the approval gate, stock conflicts and status transitions,
-- following the handoff's cross-module flows (casual, business, discovery).
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

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

-- The people. The administrators use staff addresses, not USM ones.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),   -- student 1
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),   -- student 2
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),     -- applicant
  ('77777777-7777-7777-7777-777777777777', 'nina@student.usm.my', now(), '{"name": "Nina"}'),   -- business seller
  ('88888888-8888-8888-8888-888888888888', 'rina@campusniaga.test', now(), '{"name": "Rina"}'), -- reviews applications
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{"name": "Admin"}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');                       -- not a USM student
insert into public.staff_roles (user_id, role) values
  ('88888888-8888-8888-8888-888888888888', 'admin'),
  ('33333333-3333-3333-3333-333333333333', 'admin');

-- Access ------------------------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.get_my_access() ->> 'is_student', 'true', 'a USM student is let in');
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(public.get_my_access() ->> 'is_student', 'false', 'a gmail account is not');

-- Casual flow: personal listing -> Buy now -> sold -> handover ---------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.calc', public.upsert_listing(null, 'Casio FX-570 calculator', 'One semester old.', 'Stationery', 2500, 'good', 1, '{}', 'Tekun') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.calc')::uuid, 'Casio FX-570 calculator', 'One semester old.', 'Stationery', 2500, 'good', 1,
    array['22222222-2222-2222-2222-222222222222/' || current_setting('test.calc') || '/1.jpg'], 'Tekun');
  perform public.set_listing_status(current_setting('test.calc')::uuid, 'available');
end $$;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin
  perform set_config('test.lamp', public.upsert_listing(null, 'Desk lamp', '', 'Hostel Essentials', 1500, 'like_new', 1, '{}', 'Aman') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.lamp')::uuid, 'Desk lamp', '', 'Hostel Essentials', 1500, 'like_new', 1,
    array['44444444-4444-4444-4444-444444444444/' || current_setting('test.lamp') || '/1.jpg'], 'Aman');
  perform public.set_listing_status(current_setting('test.lamp')::uuid, 'available');
end $$;
select is((select seller_name from public.search_listings('calculator')), 'Siti', 'Amin finds Siti''s calculator by searching');
do $$ begin
  perform set_config('test.res', public.buy_item(current_setting('test.calc')::uuid) ->> 'purchase_id', true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.buy_item(current_setting('test.calc')::uuid) $$), 'ITEM_UNAVAILABLE', 'a second buyer cannot buy the same calculator');
select is(pg_temp.error_reason($$ select public.buy_item(current_setting('test.lamp')::uuid, 1) $$), 'no error', 'Ali buys the lamp');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.open_conversation(purchase_id => current_setting('test.res')::uuid) ->> 'created', 'true', 'Siti opens the chat to arrange the handover with Amin');
select is(public.complete_purchase(current_setting('test.res')::uuid) ->> 'status', 'completed', 'and completes the sale');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.buy_item(current_setting('test.calc')::uuid) $$), 'ITEM_UNAVAILABLE', 'a sold item takes no more purchases');

-- Business flow: apply -> request edits -> resubmit -> approve -> storefront -> orders -> dashboard ---------------
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Brownie box', '', 'Food & Beverage', 1200, 'new', 2, '{}', 'Tekun', 'business') $$),
  'FORBIDDEN', 'before approval Nina cannot list business products');
do $$
declare app uuid;
begin
  insert into public.business_applications (business_name, category, description, contact_details, collection_details)
  values ('Nina Bakes', 'Food & Beverage', 'Brownies and cookies baked every Friday.', '013-3333333', 'Tekun lobby, Fri 6pm')
  returning id into app;
  perform set_config('test.nina_app', app::text, true);
  perform public.submit_business_application(app);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$
declare app uuid;
begin
  insert into public.business_applications (business_name, category, description, contact_details, collection_details)
  values ('Ali Prints', 'Stationery', 'Printed notes and planners for students.', '012-3456789', 'Restu, weekdays')
  returning id into app;
  perform set_config('test.ali_app', app::text, true);
  perform public.submit_business_application(app);
end $$;
select pg_temp.as_user('88888888-8888-8888-8888-888888888888');
select lives_ok($$ select public.review_business_application(current_setting('test.ali_app')::uuid, 'start_review');
                   select public.review_business_application(current_setting('test.ali_app')::uuid, 'request_info', 'Add your prices.') $$,
  'the administrator asks the applicant (Ali) for edits');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ update public.business_applications set description = 'Printed notes (RM 2) and planners (RM 8) for students.';
                   select public.submit_business_application(current_setting('test.ali_app')::uuid, 'Prices added.') $$,
  'Ali edits and resubmits');
select pg_temp.as_user('88888888-8888-8888-8888-888888888888');
select lives_ok($$ select public.review_business_application(current_setting('test.ali_app')::uuid, 'start_review');
                   select public.review_business_application(current_setting('test.ali_app')::uuid, 'approve');
                   select public.review_business_application(current_setting('test.nina_app')::uuid, 'start_review');
                   select public.review_business_application(current_setting('test.nina_app')::uuid, 'approve') $$,
  'the administrator approves both businesses');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.audit_logs where target_type = 'business_application'), 9,
  'the admin sees every application step in the audit log');
select is((select status || '=' || total from public.application_status_summary() where status = 'approved'), 'approved=2', 'and the status summary counts them');

-- Nina sets up her storefront: 2 business products and a capacity-3 pre-order
reset role;
select set_config('test.nina_biz', (select id::text from public.businesses where name = 'Nina Bakes'), true);
set local role authenticated;
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
do $$ begin
  perform public.update_storefront('Fresh brownies and cookies every Friday.', 'Tekun lobby, Fri 6-8pm');
  perform set_config('test.brownie', public.upsert_listing(null, 'Fudgy brownies box', 'Six brownies.', 'Food & Beverage', 900, 'new', 2, '{}', 'Tekun', 'business') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.brownie')::uuid, 'Fudgy brownies box', 'Six brownies.', 'Food & Beverage', 900, 'new', 2,
    array['77777777-7777-7777-7777-777777777777/' || current_setting('test.brownie') || '/1.jpg'], 'Tekun');
  perform public.set_listing_status(current_setting('test.brownie')::uuid, 'available');
  perform set_config('test.cookie', public.upsert_listing(null, 'Cookie jar', 'Twelve cookies.', 'Food & Beverage', 800, 'new', 5, '{}', 'Tekun', 'business') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.cookie')::uuid, 'Cookie jar', 'Twelve cookies.', 'Food & Beverage', 800, 'new', 5,
    array['77777777-7777-7777-7777-777777777777/' || current_setting('test.cookie') || '/1.jpg'], 'Tekun');
  perform public.set_listing_status(current_setting('test.cookie')::uuid, 'available');
  perform set_config('test.pre', public.upsert_campaign(null, current_setting('test.brownie')::uuid, 'Raya brownies', 1000,
    now() - interval '1 minute', now() + interval '7 days', 3, null, 'Tekun lobby, Sat 10am') ->> 'campaign_id', true);
  perform public.set_campaign_status(current_setting('test.pre')::uuid, 'open');
end $$;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from jsonb_array_elements(public.get_storefront(current_setting('test.nina_biz')::uuid) -> 'listings')), 2,
  'students see Nina''s storefront with her 2 products');
select is(pg_temp.error_reason($$ select public.buy_item(current_setting('test.brownie')::uuid) $$), 'ITEM_UNAVAILABLE', 'business products are ordered, not bought with Buy now');

-- Stock conflict on ready stock, and the capped pre-order
do $$ begin
  perform set_config('test.o1', public.place_order(current_setting('test.brownie')::uuid, 2) ->> 'order_id', true);
end $$;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.brownie')::uuid, 1) $$), 'ITEM_UNAVAILABLE', 'Amin cannot buy a box Siti already took: no overselling');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.brownie')::uuid, 2, current_setting('test.pre')::uuid) $$), 'no error', 'Amin pre-orders 2');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.brownie')::uuid, 2, current_setting('test.pre')::uuid) $$), 'CAPACITY_FULL', 'Siti cannot take 2 of the 1 place left');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.brownie')::uuid, 1, current_setting('test.pre')::uuid) $$), 'no error', 'Ali takes the last place');
select is((select (public.get_storefront(current_setting('test.nina_biz')::uuid) -> 'campaigns' -> 0 ->> 'remaining')::int), 0,
  'the pre-order is full: 3 of 3');

-- Nina fulfils Siti's order; the dashboard follows
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select lives_ok($$ select public.transition_order(current_setting('test.o1')::uuid, 'confirm');
                   select public.transition_order(current_setting('test.o1')::uuid, 'prepare');
                   select public.transition_order(current_setting('test.o1')::uuid, 'ready');
                   select public.transition_order(current_setting('test.o1')::uuid, 'complete');
                   select public.set_order_cost(current_setting('test.o1')::uuid, 700) $$,
  'Nina moves Siti''s order through every status and records her cost');
select is((select d ->> 'completed_count' || '/' || (d ->> 'estimated_revenue_sen') || '/' || (d ->> 'estimated_profit_sen') || '/' || (d -> 'orders_by_status' ->> 'pending_confirmation')
           from (select public.business_dashboard() as d) as x), '1/1800/1100/2',
  'her dashboard: 1 sale, RM 18 estimated revenue, RM 11 estimated profit, 2 pre-orders pending');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select d ->> 'business_name' || '/' || (d ->> 'total_orders') from (select public.business_dashboard() as d) as x), 'Ali Prints/0',
  'Ali''s dashboard shows none of Nina''s data');

-- Discovery flow: request -> unique interest -> supply comparison -> explained opportunity ----------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin perform set_config('test.r1', public.create_product_request('brownie', 'Food & Beverage', 'Tekun', 500) ->> 'request_id', true); end $$;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
do $$ begin perform set_config('test.r2', public.create_product_request('brownies', 'Food & Beverage', 'Aman', 600) ->> 'request_id', true); end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin perform set_config('test.r3', public.create_product_request('chocolate brownie', 'Food & Beverage', 'Restu', 700) ->> 'request_id', true); end $$;
select lives_ok($$ select public.toggle_request_interest(current_setting('test.r1')::uuid);
                   select public.toggle_request_interest(current_setting('test.r2')::uuid) $$,
  'Ali also taps Interested on the other two requests');
reset role;
select is((select count(distinct cluster_key)::int from public.product_requests), 1, 'the three similar requests form one cluster');
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select unique_interest_count from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 3,
  'three distinct students, however many taps');
-- Nina's brownie box sold out (Siti took both), so it is not supply; restock it to compete.
select pg_temp.as_user('77777777-7777-7777-7777-777777777777');
select lives_ok($$ select public.upsert_listing(current_setting('test.brownie')::uuid, 'Fudgy brownies box', 'Six brownies.', 'Food & Beverage', 900, 'new', 4,
  array['77777777-7777-7777-7777-777777777777/' || current_setting('test.brownie') || '/1.jpg'], 'Tekun') $$, 'Nina restocks her brownie box');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select active_supply_count || '/' || score from public.opportunities where cluster_key = 'Food & Beverage|brownie'), '1/17',
  'the competing listing is supply and lowers the score; its RM 9 price is above the RM 6 wanted: 15 - 8 + 10 = 17');
select is((select reasons from public.opportunities where cluster_key = 'Food & Beverage|brownie'),
  array['3 students interested', '1 active matching listing from 1 seller', 'Listings (median RM 9) are above requested prices (median RM 6)'],
  'and the reasons say exactly that');

-- Moderation: a report, a hidden listing, and supply follows
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select public.report_listing(current_setting('test.brownie')::uuid, 'misleading', 'Says six, photo shows four') $$, 'Siti reports the brownie box');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select lives_ok($$ select public.moderate_listing(current_setting('test.brownie')::uuid, true, 'Fix the photo') $$, 'the admin hides it');
select is((select active_supply_count from public.opportunities where cluster_key = 'Food & Beverage|brownie'), 0, 'a hidden listing leaves the supply at once');
reset role;

select * from finish();
rollback;
