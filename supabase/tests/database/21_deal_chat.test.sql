-- Deal chat (ADR 0004): who can open a chat and when, sending (input,
-- participants, rate limit, read-only after the deal, closed chats,
-- suspended accounts and businesses), what each person can read, unread
-- counts, reports and the administrators' audited view.
begin;
create extension if not exists pgtap with schema extensions;
select plan(74);

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

-- Ali sells (personal items and Ali Bakes); Siti and Amin buy; Ben uses
-- gmail; one admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'Ali Bakes', 'Food & Beverage', 'Brownies and cookies baked weekly.', '012-3456789', 'Tekun lobby', 'approved', now(), now());
insert into public.businesses (id, owner_id, application_id, name, description, pickup_details) values
  ('bbbbbbbb-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Ali Bakes', 'Brownies.', 'Tekun lobby, 6-8pm');
insert into public.listings (id, owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, photo_paths, stock, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Calculator', 'calculator', 'Stationery', 2500, 'good', array['p/1.jpg'], 1, 'Tekun', 'reserved'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Desk lamp', 'desk lamp', 'Electronics', 1500, 'good', array['p/2.jpg'], 1, 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000003', '11111111-1111-1111-1111-111111111111', 'personal', null, 'Rice cooker', 'rice cooker', 'Electronics', 3500, 'good', array['p/3.jpg'], 1, 'Tekun', 'reserved'),
  ('cccccccc-0000-0000-0000-000000000004', '11111111-1111-1111-1111-111111111111', 'business', 'bbbbbbbb-0000-0000-0000-000000000011', 'Brownie box', 'brownie box', 'Food & Beverage', 500, 'new', array['p/4.jpg'], 5, 'Tekun', 'available');
-- r1: Siti's accepted reservation; r2: Amin's request, not yet accepted;
-- r3: Amin's accepted reservation that is overdue.
insert into public.reservations (id, listing_id, buyer_id, seller_id, qty, status, expires_at) values
  ('dddddddd-0000-0000-0000-000000000001', 'cccccccc-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', '11111111-1111-1111-1111-111111111111', 1, 'accepted', now() + interval '2 days'),
  ('dddddddd-0000-0000-0000-000000000002', 'cccccccc-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 1, 'requested', now() + interval '2 days'),
  ('dddddddd-0000-0000-0000-000000000003', 'cccccccc-0000-0000-0000-000000000003', '44444444-4444-4444-4444-444444444444', '11111111-1111-1111-1111-111111111111', 1, 'accepted', now() - interval '1 hour');
-- o1: Siti's confirmed order; o2: Amin's order awaiting confirmation.
insert into public.orders (id, buyer_id, business_id, listing_id, qty, unit_price_sen, total_sen, status, collection_details) values
  ('eeeeeeee-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000004', 2, 500, 1000, 'confirmed', 'Tekun lobby'),
  ('eeeeeeee-0000-0000-0000-000000000002', '44444444-4444-4444-4444-444444444444', 'bbbbbbbb-0000-0000-0000-000000000011', 'cccccccc-0000-0000-0000-000000000004', 1, 500, 500, 'pending_confirmation', 'Tekun lobby');

-- Opening a chat ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.open_conversation('dddddddd-0000-0000-0000-000000000001') $$), 'NOT_VERIFIED_STUDENT', 'a non-student cannot open a chat');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.open_conversation() $$), 'INVALID_INPUT', 'a chat needs a reservation or an order');
select is(pg_temp.error_reason($$ select public.open_conversation('dddddddd-0000-0000-0000-000000000001', 'eeeeeeee-0000-0000-0000-000000000001') $$), 'INVALID_INPUT', 'a chat is for one deal, not two');
select is(pg_temp.error_reason($$ select public.open_conversation('dddddddd-0000-0000-0000-000000000009') $$), 'NOT_FOUND', 'an unknown reservation is not found');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.open_conversation('dddddddd-0000-0000-0000-000000000001') $$), 'NOT_FOUND', 'an outsider cannot open someone else''s chat');
select is(pg_temp.error_reason($$ select public.open_conversation('dddddddd-0000-0000-0000-000000000002') $$), 'INVALID_TRANSITION', 'no chat before the seller accepts');
select is(pg_temp.error_reason($$ select public.open_conversation('dddddddd-0000-0000-0000-000000000003') $$), 'INVALID_TRANSITION', 'no chat on an overdue reservation');
select is(pg_temp.error_reason($$ select public.open_conversation(order_id => 'eeeeeeee-0000-0000-0000-000000000002') $$), 'INVALID_TRANSITION', 'no chat before the business confirms the order');

select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform set_config('test.chat', public.open_conversation('dddddddd-0000-0000-0000-000000000001') ->> 'conversation_id', true);
  perform set_config('test.order_chat', public.open_conversation(order_id => 'eeeeeeee-0000-0000-0000-000000000001') ->> 'conversation_id', true);
end $$;
select isnt(current_setting('test.chat'), '', 'the buyer opens the chat of an accepted reservation');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(public.open_conversation('dddddddd-0000-0000-0000-000000000001') ->> 'conversation_id', current_setting('test.chat'), 'the seller gets the same chat');
select is(public.open_conversation('dddddddd-0000-0000-0000-000000000001') ->> 'created', 'false', 'opening again creates nothing');
reset role;
select is((select buyer_id::text || '/' || seller_id::text || '/' || listing_id::text from public.conversations where id = current_setting('test.chat')::uuid),
  '22222222-2222-2222-2222-222222222222/11111111-1111-1111-1111-111111111111/cccccccc-0000-0000-0000-000000000001',
  'the chat records the buyer, the seller and the item');
select is((select seller_id::text from public.conversations where id = current_setting('test.order_chat')::uuid),
  '11111111-1111-1111-1111-111111111111', 'an order''s seller is the business owner');
select is((select count(*)::int from public.conversations), 2, 'one chat per deal');

-- Sending ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('55555555-5555-5555-5555-555555555555');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'Hello') $$), 'NOT_VERIFIED_STUDENT', 'a non-student cannot send');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, '   ') $$), 'INVALID_INPUT', 'a blank message is refused');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, repeat('a', 1001)) $$), 'INVALID_INPUT', 'a message over 1,000 characters is refused');
select is(pg_temp.error_reason($$ select public.send_message('99999999-9999-9999-9999-999999999999', 'Hello') $$), 'NOT_FOUND', 'an unknown chat is not found');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'Hello') $$), 'NOT_FOUND', 'an outsider cannot send into someone else''s chat');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select ok((public.send_message(current_setting('test.chat')::uuid, '  Can I collect at 5pm?  ') ->> 'message_id') is not null, 'the buyer sends a message');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select ok((public.send_message(current_setting('test.chat')::uuid, 'Yes, Tekun lobby.') ->> 'message_id') is not null, 'the seller replies');
reset role;
select is((select body from public.messages where sender_id = '22222222-2222-2222-2222-222222222222' order by id limit 1), 'Can I collect at 5pm?', 'messages are stored trimmed');
select ok((select last_message_at is not null from public.conversations where id = current_setting('test.chat')::uuid), 'the chat records its last activity');

-- Who reads what ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.messages where conversation_id = current_setting('test.chat')::uuid), 2, 'the buyer reads the chat');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.messages where conversation_id = current_setting('test.chat')::uuid), 2, 'the seller reads the chat');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.messages), 0, 'an outsider reads no messages');
select is((select count(*)::int from public.conversations), 0, 'an outsider sees no chats');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is((select count(*)::int from public.messages), 0, 'an administrator cannot browse messages either');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ insert into public.messages (conversation_id, sender_id, body) values (current_setting('test.chat')::uuid, '22222222-2222-2222-2222-222222222222', 'sneaky') $$), '42501', 'messages cannot be inserted directly');
select is(pg_temp.error_reason($$ update public.messages set body = 'edited' $$), '42501', 'messages cannot be edited');
select is(pg_temp.error_reason($$ delete from public.messages $$), '42501', 'messages cannot be deleted');
select is(pg_temp.error_reason($$ update public.conversations set closed_at = null $$), '42501', 'chats cannot be changed directly');
select is(pg_temp.error_reason($$ select public.conversation_can_send(c) from public.conversations as c $$), '42501', 'the internal helpers are not callable');
set local role anon;
select is(pg_temp.error_reason($$ select count(*) from public.messages $$), '42501', 'signed-out visitors read no messages');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'Hi') $$), '42501', 'signed-out visitors cannot send');

-- The chat list and unread counts ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is((select count(*)::int from public.my_conversations()), 2, 'the buyer lists both her chats');
select is((select kind || '/' || listing_title || '/' || other_party_name || '/' || i_am_buyer || '/' || last_message || '/' || last_message_mine || '/' || unread_count || '/' || can_send || '/' || closed
           from public.my_conversations() where conversation_id = current_setting('test.chat')::uuid),
  'reservation/Calculator/Ali/true/Yes, Tekun lobby./false/1/true/false', 'her card shows the item, Ali, his reply and 1 unread');
select is(pg_temp.error_reason($$ select * from public.my_conversations(0) $$), 'INVALID_INPUT', 'a page size of 0 is refused');
select is(public.mark_conversation_read(current_setting('test.chat')::uuid) ->> 'conversation_id', current_setting('test.chat'), 'the buyer marks the chat read');
select is((select unread_count from public.get_conversation(current_setting('test.chat')::uuid)), 0, 'nothing unread after reading');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select other_party_name || '/' || i_am_buyer || '/' || unread_count from public.get_conversation(current_setting('test.chat')::uuid)), 'Siti/false/0',
  'the seller sees Siti, and his own reply left nothing unread');
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is((select count(*)::int from public.my_conversations()), 0, 'an outsider lists no chats');
select is(pg_temp.error_reason($$ select public.get_conversation(current_setting('test.chat')::uuid) $$), 'NOT_FOUND', 'an outsider cannot read a chat''s header');
select is(pg_temp.error_reason($$ select public.mark_conversation_read(current_setting('test.chat')::uuid) $$), 'NOT_FOUND', 'an outsider cannot mark a chat read');

-- Rate limit: 20 messages a minute per sender ------------------------------------------------------------------------------
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  for i in 1..19 loop
    perform public.send_message(current_setting('test.chat')::uuid, 'Message ' || i);
  end loop;
end $$;
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'One too many') $$), 'RATE_LIMITED', 'the 21st message within a minute is refused');
reset role;
select is((select count(*)::int from public.messages where sender_id = '22222222-2222-2222-2222-222222222222'), 20, 'exactly 20 of her messages were sent');
delete from public.messages where body like 'Message %';

-- Read-only once the deal ends ------------------------------------------------------------------------------
update public.reservations set expires_at = now() - interval '1 minute' where id = 'dddddddd-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'Still there?') $$), 'INVALID_TRANSITION', 'no new messages once the accepted reservation is overdue');
reset role;
update public.reservations set status = 'collected' where id = 'dddddddd-0000-0000-0000-000000000001';
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.chat')::uuid, 'Thanks!') $$), 'INVALID_TRANSITION', 'no new messages after collection');
select is((select can_send::text || '/' || closed::text from public.get_conversation(current_setting('test.chat')::uuid)), 'false/false', 'the chat is read-only, not closed');
select is((select count(*)::int from public.messages where conversation_id = current_setting('test.chat')::uuid), 2, 'the history stays readable');
select is(public.open_conversation('dddddddd-0000-0000-0000-000000000001') ->> 'conversation_id', current_setting('test.chat'), 'the ended deal''s chat still opens to read');

-- Order chats, suspended businesses and accounts ------------------------------------------------------------------------------
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select ok((public.send_message(current_setting('test.order_chat')::uuid, 'Your brownies are being baked.') ->> 'message_id') is not null, 'the business owner messages the buyer');
reset role;
update public.businesses set status = 'suspended' where id = 'bbbbbbbb-0000-0000-0000-000000000011';
set local role authenticated;
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.order_chat')::uuid, 'Hello?') $$), 'INVALID_TRANSITION', 'a suspended business''s chats are read-only');
reset role;
update public.businesses set status = 'approved' where id = 'bbbbbbbb-0000-0000-0000-000000000011';
update public.profiles set account_status = 'suspended' where id = '22222222-2222-2222-2222-222222222222';
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.order_chat')::uuid, 'Hello?') $$), 'INVALID_TRANSITION', 'nobody can message a suspended account');
reset role;
update public.profiles set account_status = 'active' where id = '22222222-2222-2222-2222-222222222222';

-- Closing (the block) ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.close_conversation(current_setting('test.order_chat')::uuid) $$), 'NOT_FOUND', 'an outsider cannot close a chat');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(public.close_conversation(current_setting('test.order_chat')::uuid) ->> 'closed', 'true', 'the buyer closes the chat');
select is(pg_temp.error_reason($$ select public.close_conversation(current_setting('test.order_chat')::uuid) $$), 'INVALID_TRANSITION', 'a closed chat cannot be closed again');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.send_message(current_setting('test.order_chat')::uuid, 'Hello?') $$), 'INVALID_TRANSITION', 'nobody can send in a closed chat');
select throws_ok($$ select public.send_message(current_setting('test.order_chat')::uuid, 'Hello?') $$, 'P0001', 'This chat was closed.', 'and the refusal says the chat was closed');
select is((select can_send::text || '/' || closed::text from public.get_conversation(current_setting('test.order_chat')::uuid)), 'false/true', 'the other participant sees it closed');
reset role;
select is((select count(*)::int from public.audit_logs where action = 'chat.closed' and target_id = current_setting('test.order_chat') and actor_id = '22222222-2222-2222-2222-222222222222'), 1, 'closing is audited');

-- Reporting ------------------------------------------------------------------------------
set local role authenticated;
select pg_temp.as_user('44444444-4444-4444-4444-444444444444');
select is(pg_temp.error_reason($$ select public.report_conversation(current_setting('test.chat')::uuid, 'scam') $$), 'NOT_FOUND', 'an outsider cannot report a chat');
select pg_temp.as_user('22222222-2222-2222-2222-222222222222');
select is(pg_temp.error_reason($$ select public.report_conversation(current_setting('test.chat')::uuid, 'spam') $$), 'INVALID_INPUT', 'an unknown reason is refused');
select is(pg_temp.error_reason($$ select public.report_conversation(current_setting('test.chat')::uuid, 'other') $$), 'INVALID_INPUT', '"other" needs details');
do $$ begin
  perform set_config('test.report', public.report_conversation(current_setting('test.chat')::uuid, 'offensive', ' Rude replies ') ->> 'report_id', true);
end $$;
select is(pg_temp.error_reason($$ select public.report_conversation(current_setting('test.chat')::uuid, 'scam') $$), 'ALREADY_EXISTS', 'one open report per chat per person');
select is((select count(*)::int from public.reports where conversation_id is not null), 1, 'the reporter sees her report');
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is((select count(*)::int from public.reports), 0, 'the reported seller does not see it');
reset role;
select is((select reported_user_id::text || '/' || coalesce(listing_id::text, 'no listing') || '/' || reason || '/' || details || '/' || status
           from public.reports where id = current_setting('test.report')::uuid),
  '11111111-1111-1111-1111-111111111111/no listing/offensive/Rude replies/open', 'the report names the other participant and the chat');

-- Administrators ------------------------------------------------------------------------------
insert into public.reports (id, reporter_id, listing_id, reported_user_id, reason) values
  ('ffffffff-0000-0000-0000-000000000001', '44444444-4444-4444-4444-444444444444', 'cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'misleading');
set local role authenticated;
select pg_temp.as_user('11111111-1111-1111-1111-111111111111');
select is(pg_temp.error_reason($$ select public.get_reported_conversation(current_setting('test.report')::uuid) $$), 'FORBIDDEN', 'a student cannot read a reported chat');
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is(pg_temp.error_reason($$ select public.get_reported_conversation('ffffffff-0000-0000-0000-000000000001') $$), 'NOT_FOUND', 'a listing report opens no chat');
select is((select (r ->> 'listing_title') || '/' || (r -> 'buyer' ->> 'name') || '/' || (r -> 'seller' ->> 'name') || '/' || jsonb_array_length(r -> 'messages') || '/' || (r -> 'messages' -> 0 ->> 'from') || ': ' || (r -> 'messages' -> 0 ->> 'body')
           from public.get_reported_conversation(current_setting('test.report')::uuid) as r),
  'Calculator/Siti/Ali/2/buyer: Can I collect at 5pm?', 'an administrator reads the reported chat, oldest first');
reset role;
select is((select count(*)::int from public.audit_logs where action = 'chat.viewed' and actor_id = '33333333-3333-3333-3333-333333333333'), 1, 'each view of a reported chat is audited');
set local role authenticated;
select pg_temp.as_user('33333333-3333-3333-3333-333333333333');
select is(public.dismiss_report(current_setting('test.report')::uuid) ->> 'status', 'reviewed', 'a chat report is dismissed like any report');

select ok(not exists (select 1 from pg_publication where pubname = 'supabase_realtime')
          or exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'messages'),
  'new messages are published to Supabase Realtime');

select * from finish();
rollback;
