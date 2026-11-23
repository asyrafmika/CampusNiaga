-- Deleting listings (ADR 0008): who may delete, what a deleted listing still
-- shows and to whom, what stays working (purchases, orders, chats), and that
-- nothing brings it back.
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

-- Ali sells and runs Ali Bakes; Siti buys; Amin is another student; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies, baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Tekun lobby');
-- 1 lamp (2 units), 2 draft, 3 sold, 4 brownies (business), 5 fan.
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Desk lamp', 'desk lamp', 'Others', 1500, 'good', array['p/1.jpg'], 2, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Draft chair', 'draft chair', 'Others', 1500, 'good', '{}', 1, 'Tekun', 'draft'),
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Old kettle', 'old kettle', 'Others', 1500, 'good', array['p/3.jpg'], 0, 'Tekun', 'sold'),
  ('cccccccc-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 1000, 'new', array['p/4.jpg'], 5, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000005', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Fan', 'fan', 'Others', 4000, 'good', array['p/5.jpg'], 1, 'Tekun', 'available');
insert into public.campaigns (id, business_id, listing_id, title, price_sen, start_at, close_at, capacity, pickup_details, status) values
  ('dddddddd-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000004', 'Raya brownies', 900, now() - interval '1 day', now() + interval '7 days', 10, 'Tekun lobby', 'open'),
  ('dddddddd-0000-0000-0000-000000000002', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000004', 'Next batch', 900, now() + interval '1 day', now() + interval '9 days', 10, 'Tekun lobby', 'draft');

-- Siti buys one lamp, asks about the fan, and orders brownies.
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.purchase', public.buy_item('cccccccc-0000-0000-0000-000000000001') ->> 'purchase_id', true);
  perform set_config('test.chat', public.open_conversation('cccccccc-0000-0000-0000-000000000001') ->> 'conversation_id', true);
  perform set_config('test.order', public.place_order('cccccccc-0000-0000-0000-000000000004', 2) ->> 'order_id', true);
end $$;

-- Who may delete ---------------------------------------------------------------------
select is(pg_temp.error_reason($$ select public.set_listing_status('cccccccc-0000-0000-0000-000000000001', 'deleted') $$), 'FORBIDDEN', 'a buyer cannot delete someone else''s listing');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.set_listing_status('cccccccc-0000-0000-0000-000000000001', 'deleted') $$), '42501', 'signed-out visitors cannot delete');
reset role;
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.set_listing_status('cccccccc-0000-0000-0000-000000000001', 'closed') $$), 'INVALID_TRANSITION', 'listings can no longer be closed');
select is(public.set_listing_status('cccccccc-0000-0000-0000-000000000002', 'deleted') ->> 'status', 'deleted', 'the owner deletes a draft');
select is(public.set_listing_status('cccccccc-0000-0000-0000-000000000003', 'deleted') ->> 'status', 'deleted', 'a sold one');
select is(public.set_listing_status('cccccccc-0000-0000-0000-000000000001', 'deleted') ->> 'status', 'deleted', 'and one with a purchase in progress');
select is(public.set_listing_status('cccccccc-0000-0000-0000-000000000004', 'deleted') ->> 'status', 'deleted', 'and a business product with orders');
select is(pg_temp.error_reason($$ select public.set_listing_status('cccccccc-0000-0000-0000-000000000001', 'deleted') $$), 'NOT_FOUND', 'deleting twice finds nothing');
select is(pg_temp.error_reason($$ select public.set_listing_status('cccccccc-0000-0000-0000-000000000001', 'available') $$), 'NOT_FOUND', 'nothing brings it back');
select is(pg_temp.error_reason($$ select public.upsert_listing('cccccccc-0000-0000-0000-000000000001', 'Desk lamp', '', 'Others', 1500, 'good', 1, array['11111111-1111-1111-1111-111111111111/cccccccc-0000-0000-0000-000000000001/1.jpg'], 'Tekun') $$),
  'NOT_FOUND', 'or edits it');
select is(pg_temp.error_reason($$ select public.upsert_campaign(null, 'cccccccc-0000-0000-0000-000000000004', 'Again', 900, now(), now() + interval '2 days', 5, null, 'Tekun lobby') $$),
  'INVALID_INPUT', 'a deleted product takes no new pre-order');
reset role;
select is((select string_agg(status, ',' order by title) from public.campaigns), 'closed,closed', 'its draft and open pre-orders closed with it');
select is((select stock from public.listings where id = 'cccccccc-0000-0000-0000-000000000001'), 1, 'the rows stay, for the purchases and chats that point at them');

-- Who still sees it --------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.search_listings('lamp')), 0, 'it leaves the marketplace');
select is(pg_temp.error_reason($$ select * from public.get_listing('cccccccc-0000-0000-0000-000000000001') $$), 'NOT_FOUND', 'other students cannot open it');
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000005', 'scam') $$), 'no error', '(a live listing can be reported)');
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam') $$), 'NOT_FOUND', 'or report it');
select is(pg_temp.error_reason($$ select public.seller_accepts_transfer('cccccccc-0000-0000-0000-000000000001') $$), 'NOT_FOUND', 'or see how to pay');
select is(pg_temp.error_reason($$ select public.open_conversation('cccccccc-0000-0000-0000-000000000001') $$), 'ITEM_UNAVAILABLE', 'or start a chat about it');
select is(jsonb_array_length(public.get_storefront('bbbbbbbb-0000-0000-0000-000000000011') -> 'listings'), 0, 'a deleted product leaves its storefront');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select status from public.get_listing('cccccccc-0000-0000-0000-000000000001')), 'deleted', 'the student who bought it still opens it');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.buy_item('cccccccc-0000-0000-0000-000000000001') $$), 'ITEM_UNAVAILABLE', 'nobody can buy it');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select can_send from public.get_conversation(current_setting('test.chat')::uuid)), true, 'the buyer and seller keep their chat');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select status from public.get_listing('cccccccc-0000-0000-0000-000000000001')), 'deleted', 'the owner still opens it from a sale');
select is(jsonb_array_length(public.business_dashboard() -> 'stock'), 0, 'and it is no longer stock on the dashboard');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select status from public.get_listing('cccccccc-0000-0000-0000-000000000001')), 'deleted', 'admins still see it');

-- What carries on --------------------------------------------------------------------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.complete_purchase(current_setting('test.purchase')::uuid) ->> 'status', 'completed', 'the purchase in progress completes');
select is(public.transition_order(current_setting('test.order')::uuid, 'confirm') ->> 'status', 'confirmed', 'and the order carries on');
select is(public.transition_order(current_setting('test.order')::uuid, 'cancel') ->> 'status', 'cancelled', 'a cancelled order returns its units');
reset role;
select is((select status from public.listings where id = 'cccccccc-0000-0000-0000-000000000004'), 'deleted', 'without bringing the product back');

-- A seller who cancels a sale may delete the listing ----------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.fan', public.buy_item('cccccccc-0000-0000-0000-000000000005') ->> 'purchase_id', true);
end $$;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.cancel_purchase(current_setting('test.fan')::uuid, 'It broke', false) ->> 'listing_status', 'deleted', 'cancelling a sale can delete the listing');
reset role;
-- A relist of an old sale can't revive it either.
update public.purchases set status = 'awaiting_handover', cancelled_by = null, cancel_reason = null,
  created_at = now() - interval '2 days' where id = current_setting('test.fan')::uuid;
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.relist_purchase(current_setting('test.fan')::uuid) ->> 'status', 'cancelled', 'relisting a purchase of a deleted listing cancels it');
reset role;
select is((select status from public.listings where id = 'cccccccc-0000-0000-0000-000000000005'), 'deleted', 'and leaves the listing deleted');

select * from finish();
rollback;
