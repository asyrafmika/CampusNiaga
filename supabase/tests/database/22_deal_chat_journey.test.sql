-- Deal chat journey (ADR 0004) through the real marketplace and order
-- functions: no chat while a reservation or order waits for the seller; a
-- live chat once they agree; read-only when the deal ends.
begin;
create extension if not exists pgtap with schema extensions;
select plan(14);

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

-- A reservation: requested, accepted, collected.
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.reservation', public.request_reservation(current_setting('test.item')::uuid, 1, 'After class') ->> 'reservation_id', true);
end $$;
select is(pg_temp.error_reason($$ select public.open_conversation(current_setting('test.reservation')::uuid) $$), 'INVALID_TRANSITION', 'Siti cannot chat while her request waits');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.resolve_reservation(current_setting('test.reservation')::uuid, 'accept') ->> 'status', 'accepted', 'Ali accepts');
do $$ begin
  perform set_config('test.chat', public.open_conversation(current_setting('test.reservation')::uuid) ->> 'conversation_id', true);
end $$;
select ok((public.send_message(current_setting('test.chat')::uuid, 'Hi Siti, 5pm at Tekun?') ->> 'message_id') is not null, 'Ali opens the chat and suggests a time');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select unread_count || '/' || last_message from public.my_conversations() where conversation_id = current_setting('test.chat')::uuid),
  '1/Hi Siti, 5pm at Tekun?', 'Siti sees one unread message from Ali');
select ok((public.send_message(current_setting('test.chat')::uuid, 'See you then!') ->> 'message_id') is not null, 'Siti replies');
select is((select string_agg(body, ' | ' order by id) from public.messages where conversation_id = current_setting('test.chat')::uuid),
  'Hi Siti, 5pm at Tekun? | See you then!', 'both messages are in the chat, in order');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.resolve_reservation(current_setting('test.reservation')::uuid, 'collect') ->> 'listing_status', 'sold', 'Ali marks it collected');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'Thanks!') $$), 'INVALID_TRANSITION', 'the chat is read-only after collection');
select is((select can_send from public.get_conversation(current_setting('test.chat')::uuid)), false, 'and says so');

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
