-- Phase 4 pass condition, as one journey: an approved seller creates a
-- storefront, a product and a pre-order campaign; two buyers can't exceed
-- the remaining stock or capacity; cancellations free the quantity.
--
-- "Two buyers at once" is serialised by the row lock place_order() takes on
-- the listing or the campaign. One test session can't open two connections,
-- so this file checks the outcome the lock guarantees; CI also runs
-- supabase/tests/concurrency/order_race.sh with two real connections.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

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

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('88888888-8888-8888-8888-888888888888', 'rina@campusniaga.test', now(), '{"name": "Rina"}');
insert into public.staff_roles (user_id, role) values ('88888888-8888-8888-8888-888888888888', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage',
   'Homemade brownies and cookies, baked fresh every week.', '012-3456789', 'Tekun lobby, 6-8pm', 'under_review', now());

-- 1. Before approval, no business features --------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Brownie box', '', 'Food & Beverage', 1200, 'new', 2, '{}', 'Tekun', 'business') $$),
  'FORBIDDEN', 'before approval Ali cannot list business products');
select is(pg_temp.error_reason($$ select public.update_storefront('Brownies', 'Tekun lobby') $$), 'FORBIDDEN', 'or set up a storefront');

-- 2. The administrator approves; Ali sets up the storefront, a product and a capacity-3 pre-order -------
select pg_temp.as_user('88888888-8888-8888-8888-888888888888');
do $$ begin
  perform set_config('test.business', public.review_business_application('aaaaaaaa-0000-0000-0000-000000000011', 'approve') ->> 'business_id', true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select public.update_storefront('Fudgy brownies every Friday.', 'Tekun lobby, Fri 6-8pm') $$, 'Ali sets up his storefront');
do $$ begin
  perform set_config('test.product', public.upsert_listing(null, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 2, '{}', 'Tekun lobby', 'business') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.product')::uuid, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 2,
    array['11111111-1111-1111-1111-111111111111/' || current_setting('test.product') || '/1.jpg'], 'Tekun lobby');
  perform public.set_listing_status(current_setting('test.product')::uuid, 'available');
  perform set_config('test.campaign', public.upsert_campaign(null, current_setting('test.product')::uuid, 'Raya brownie pre-order', 1000,
    now() - interval '1 minute', now() + interval '7 days', 3, null, 'Tekun lobby, Sat 10am') ->> 'campaign_id', true);
  perform public.set_campaign_status(current_setting('test.campaign')::uuid, 'open');
end $$;
select ok(current_setting('test.campaign', true) <> '', 'Ali creates a product (2 in stock) and opens a capacity-3 pre-order');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select business_name from public.search_listings('brownie')), 'Ali Bakes', 'the product is in the common feed under the business');
select is(public.get_storefront(current_setting('test.business')::uuid) -> 'business' ->> 'description', 'Fudgy brownies every Friday.', 'the storefront shows the business');
select is((select count(*)::int from jsonb_array_elements(public.get_storefront(current_setting('test.business')::uuid) -> 'listings')), 1, 'its product');
select is((select x ->> 'remaining' from jsonb_array_elements(public.get_storefront(current_setting('test.business')::uuid) -> 'campaigns') as x), '3', 'and the open pre-order with 3 places');

-- 3. Two buyers can't exceed the remaining stock -----------------------------------------------------
do $$ begin
  perform set_config('test.siti_stock', public.place_order(current_setting('test.product')::uuid, 2) ->> 'order_id', true);
end $$;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.product')::uuid, 1) $$), 'ITEM_UNAVAILABLE', 'after Siti takes both boxes, Amin is refused');
reset role;
select is((select status || '/' || stock from public.listings where id = current_setting('test.product')::uuid), 'sold/0', 'the product is sold out, never negative');

-- 4. Two buyers can't exceed the pre-order's capacity ----------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.siti_pre', public.place_order(current_setting('test.product')::uuid, 2, current_setting('test.campaign')::uuid) ->> 'order_id', true);
end $$;
select ok(current_setting('test.siti_pre', true) <> '', 'Siti pre-orders 2 of the 3 places');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.product')::uuid, 2, current_setting('test.campaign')::uuid) $$), 'CAPACITY_FULL', 'Amin cannot take 2 when 1 is left');
select lives_ok($$ select public.place_order(current_setting('test.product')::uuid, 1, current_setting('test.campaign')::uuid) $$, 'Amin takes the last place');
select is(pg_temp.error_reason($$ select public.place_order(current_setting('test.product')::uuid, 1, current_setting('test.campaign')::uuid) $$), 'CAPACITY_FULL', 'and nobody gets a fourth');
reset role;
select is((select allocated_qty || '/' || capacity from public.campaigns where id = current_setting('test.campaign')::uuid), '3/3', 'allocation equals capacity, never more');

-- 5. Cancellations free the quantity ------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select lives_ok($$ select public.transition_order(current_setting('test.siti_stock')::uuid, 'cancel') $$, 'Siti cancels her ready-stock order');
select lives_ok($$ select public.transition_order(current_setting('test.siti_pre')::uuid, 'cancel') $$, 'and her pre-order');
reset role;
select is((select status || '/' || stock from public.listings where id = current_setting('test.product')::uuid), 'available/2', 'both boxes are back on sale');
select is((select allocated_qty from public.campaigns where id = current_setting('test.campaign')::uuid), 1, 'and 2 pre-order places are free');

set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select lives_ok($$ select public.place_order(current_setting('test.product')::uuid, 2) $$, 'Amin now gets the boxes');
select lives_ok($$ select public.place_order(current_setting('test.product')::uuid, 2, current_setting('test.campaign')::uuid) $$, 'and the freed places');
reset role;

-- 6. The books balance ------------------------------------------------------------------------------------------
select is((select coalesce(sum(qty), 0)::int from public.orders where listing_id = current_setting('test.product')::uuid and campaign_id is null and status <> 'cancelled')
          + (select stock from public.listings where id = current_setting('test.product')::uuid), 2,
  'units ordered plus units left always equal the 2 in stock');
select is((select coalesce(sum(qty), 0)::int from public.orders where campaign_id = current_setting('test.campaign')::uuid and status <> 'cancelled'),
          (select allocated_qty from public.campaigns where id = current_setting('test.campaign')::uuid),
  'pre-ordered units always equal the allocation');
select is((select allocated_qty from public.campaigns where id = current_setting('test.campaign')::uuid), 3, 'which is back at the capacity of 3');

select * from finish();
rollback;
