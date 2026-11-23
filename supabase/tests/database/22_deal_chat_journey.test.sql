-- Chat journey (ADRs 0004 and 0006) through the real marketplace and order
-- functions: a student asks about an item before buying it and the same chat
-- carries the handover; an order's chat waits for the business and is
-- read-only when the order ends.
begin;
create extension if not exists pgtap with schema extensions;
select plan(15);

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
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, description, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Brownies.', 'Tekun lobby, 6-8pm');

-- Ali publishes a calculator and a brownie box.
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin
  perform set_config('test.item', public.upsert_listing(null, 'Casio calculator', 'One semester old.', 'Stationery', 2500, 'good', 1, '{}', 'Desasiswa Tekun') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.item')::uuid, 'Casio calculator', 'One semester old.', 'Stationery', 2500, 'good', 1,
    array['11111111-1111-1111-1111-111111111111/' || current_setting('test.item') || '/1.jpg'], 'Desasiswa Tekun');
  perform public.set_listing_status(current_setting('test.item')::uuid, 'available');
  perform set_config('test.product', public.upsert_listing(null, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 3, '{}', 'Tekun lobby', 'business') ->> 'listing_id', true);
  perform public.upsert_listing(current_setting('test.product')::uuid, 'Brownie box', 'Six fudgy brownies.', 'Food & Beverage', 1200, 'new', 3,
    array['11111111-1111-1111-1111-111111111111/' || current_setting('test.product') || '/1.jpg'], 'Tekun lobby');
  perform public.set_listing_status(current_setting('test.product')::uuid, 'available');
end $$;

-- An item: asked about, bought, handed over.
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.chat', public.open_conversation(listing_id => current_setting('test.item')::uuid) ->> 'conversation_id', true);
end $$;
select ok((public.send_message(current_setting('test.chat')::uuid, 'Do all the keys work?') ->> 'message_id') is not null, 'Siti asks before buying');
select is((select status from public.get_listing(current_setting('test.item')::uuid)), 'available', 'asking does not hold the item');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select kind || '/' || unread_count || '/' || last_message from public.my_conversations() where conversation_id = current_setting('test.chat')::uuid),
  'item/1/Do all the keys work?', 'Ali sees one unread question');
select ok((public.send_message(current_setting('test.chat')::uuid, 'Yes, all of them.') ->> 'message_id') is not null, 'Ali replies');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.purchase', public.buy_item(current_setting('test.item')::uuid) ->> 'purchase_id', true);
end $$;
select is((select status from public.get_listing(current_setting('test.item')::uuid)), 'sold', 'Siti buys it, so it is sold');
select is((select can_send from public.get_conversation(current_setting('test.chat')::uuid)), true, 'her chat stays open to arrange pickup');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.open_conversation(purchase_id => current_setting('test.purchase')::uuid) ->> 'conversation_id', current_setting('test.chat'), 'Ali reaches the same chat from the sale');
select ok((public.send_message(current_setting('test.chat')::uuid, '5pm at Tekun?') ->> 'message_id') is not null, 'and suggests a time');
select is(public.complete_purchase(current_setting('test.purchase')::uuid) ->> 'status', 'completed', 'Ali completes the sale');
select is((select string_agg(body, ' | ' order by id) from public.messages where conversation_id = current_setting('test.chat')::uuid),
  'Do all the keys work? | Yes, all of them. | 5pm at Tekun?', 'the messages are in the chat, in order');

-- A business order: pending, confirmed, completed.
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.order', public.place_order(current_setting('test.product')::uuid, 2) ->> 'order_id', true);
end $$;
select is(pg_temp.error_reason($$ select public.open_conversation(order_id => current_setting('test.order')::uuid) $$), 'INVALID_TRANSITION', 'no chat while the order waits for confirmation');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select lives_ok($$ select public.transition_order(current_setting('test.order')::uuid, 'confirm') $$, 'Ali Bakes confirms the order');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.order_chat', public.open_conversation(order_id => current_setting('test.order')::uuid) ->> 'conversation_id', true);
end $$;
select ok((public.send_message(current_setting('test.order_chat')::uuid, 'Can you add a note card?') ->> 'message_id') is not null, 'Siti messages the business');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
do $$ begin
  perform public.transition_order(current_setting('test.order')::uuid, 'prepare');
  perform public.transition_order(current_setting('test.order')::uuid, 'ready');
  perform public.transition_order(current_setting('test.order')::uuid, 'complete');
end $$;
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.order_chat')::uuid, 'Enjoy!') $$), 'INVALID_TRANSITION', 'the order chat is read-only once completed');
select is((select count(*)::int from public.my_conversations()), 2, 'Ali keeps both chats in his list');

select * from finish();
rollback;
