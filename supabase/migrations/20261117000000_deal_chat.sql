-- Deal chat (ADR 0004): text messages between the buyer and the seller of an
-- accepted reservation or a confirmed business order, and nobody else.
--
-- conversations  one per reservation or order, created by open_conversation
-- messages       written only by send_message; read by the two participants
--                (Row Level Security), live through Supabase Realtime
-- reports        gains conversation_id, so chat reports use the existing
--                moderation flow (dismiss_report, set_account_status)
--
-- A chat can send while its deal is active (reservation accepted and not
-- overdue; order confirmed, preparing or ready for pickup at an approved
-- business) and nobody has closed it. Afterwards it stays readable.

------------------------------------------------------------------------------
-- Tables
------------------------------------------------------------------------------

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  reservation_id uuid unique references public.reservations (id) on delete cascade,
  order_id uuid unique references public.orders (id) on delete cascade,
  listing_id uuid not null references public.listings (id) on delete cascade,
  buyer_id uuid not null references public.profiles (id) on delete cascade,
  seller_id uuid not null references public.profiles (id) on delete cascade,
  -- The newest message each participant has seen (ids only grow, so
  -- "unread" is exact even for messages sent in the same instant).
  buyer_last_read_id bigint not null default 0,
  seller_last_read_id bigint not null default 0,
  last_message_at timestamptz,
  closed_at timestamptz,
  closed_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Exactly one deal per conversation.
  check (num_nonnulls(reservation_id, order_id) = 1),
  check (buyer_id <> seller_id),
  check (closed_by is null or closed_at is not null)
);

create trigger conversations_set_updated_at
  before update on public.conversations
  for each row execute function public.set_updated_at();

create index conversations_buyer_idx on public.conversations (buyer_id, last_message_at desc);
create index conversations_seller_idx on public.conversations (seller_id, last_message_at desc);

create table public.messages (
  id bigint generated always as identity primary key,
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  body text not null check (char_length(body) between 1 and 1000 and btrim(body) <> ''),
  created_at timestamptz not null default now()
);

create index messages_conversation_idx on public.messages (conversation_id, id);
create index messages_sender_idx on public.messages (sender_id, created_at desc);

-- Chat reports point at the conversation; the reported user is the other
-- participant. One open report per reporter per conversation.
alter table public.reports
  add column conversation_id uuid references public.conversations (id) on delete set null;

create unique index reports_one_open_per_conversation
  on public.reports (reporter_id, conversation_id)
  where status = 'open' and conversation_id is not null;

------------------------------------------------------------------------------
-- Internal helpers (no grants)
------------------------------------------------------------------------------

-- True while the conversation's deal is active, nobody has closed it and
-- neither participant is suspended. Overdue accepted reservations count as
-- ended (lazy expiry).
create function public.conversation_can_send(c public.conversations)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select c.closed_at is null
    and not exists (
      select 1 from public.profiles as p
      where p.id in (c.buyer_id, c.seller_id) and p.account_status <> 'active')
    and case
    when c.reservation_id is not null then exists (
      select 1 from public.reservations as r
      where r.id = c.reservation_id and r.status = 'accepted' and r.expires_at > now())
    else exists (
      select 1 from public.orders as o
      join public.businesses as b on b.id = o.business_id
      where o.id = c.order_id
        and o.status in ('confirmed', 'preparing', 'ready_for_pickup')
        and b.status = 'approved')
  end;
$$;

revoke all on function public.conversation_can_send(public.conversations) from public, anon, authenticated;

-- Loads a conversation the caller takes part in, optionally locked; raises
-- NOT_FOUND otherwise, so outsiders can't tell whether it exists.
create function public.participant_conversation(conversation_id uuid, lock_row boolean)
returns public.conversations
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  conv public.conversations;
begin
  if lock_row then
    select * into conv from public.conversations as c
    where c.id = participant_conversation.conversation_id for update;
  else
    select * into conv from public.conversations as c
    where c.id = participant_conversation.conversation_id;
  end if;
  if not found or uid is null or uid not in (conv.buyer_id, conv.seller_id) then
    perform public.raise_app_error('NOT_FOUND', 'Chat not found.');
  end if;
  return conv;
end;
$$;

revoke all on function public.participant_conversation(uuid, boolean) from public, anon, authenticated;

------------------------------------------------------------------------------
-- What the apps read
------------------------------------------------------------------------------

create type public.conversation_card as (
  conversation_id uuid,
  kind text,                -- 'reservation' or 'order'
  reservation_id uuid,
  order_id uuid,
  listing_id uuid,
  listing_title text,
  listing_photo text,
  other_party_name text,
  i_am_buyer boolean,
  last_message text,
  last_message_at timestamptz,
  last_message_mine boolean,
  unread_count integer,
  can_send boolean,
  closed boolean,
  created_at timestamptz
);

create function public.conversation_cards(uid uuid)
returns setof public.conversation_card
language sql
stable
security definer
set search_path = ''
as $$
  select c.id,
         case when c.reservation_id is not null then 'reservation' else 'order' end,
         c.reservation_id, c.order_id, c.listing_id, l.title, l.photo_paths[1],
         p.name,
         c.buyer_id = uid,
         last.body, c.last_message_at, last.sender_id = uid,
         (select count(*)::integer from public.messages as m
          where m.conversation_id = c.id and m.sender_id <> uid
            and m.id > case when c.buyer_id = uid then c.buyer_last_read_id else c.seller_last_read_id end),
         public.conversation_can_send(c),
         c.closed_at is not null,
         c.created_at
  from public.conversations as c
  join public.listings as l on l.id = c.listing_id
  join public.profiles as p on p.id = case when c.buyer_id = uid then c.seller_id else c.buyer_id end
  left join lateral (
    select m.body, m.sender_id from public.messages as m
    where m.conversation_id = c.id order by m.id desc limit 1
  ) as last on true
  where uid in (c.buyer_id, c.seller_id);
$$;

revoke all on function public.conversation_cards(uuid) from public, anon, authenticated;

-- The caller's chats, newest activity first.
create function public.my_conversations(page_size integer default 30, page_offset integer default 0)
returns setof public.conversation_card
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if my_conversations.page_size is null or my_conversations.page_size not between 1 and 100
     or my_conversations.page_offset is null or my_conversations.page_offset < 0 then
    perform public.raise_app_error('INVALID_INPUT', 'Ask for 1 to 100 chats from a non-negative offset.');
  end if;

  return query
  select * from public.conversation_cards(auth.uid()) as card
  order by coalesce(card.last_message_at, card.created_at) desc, card.conversation_id
  limit my_conversations.page_size
  offset my_conversations.page_offset;
end;
$$;

-- One chat's header (title, the other person, whether it can send).
create function public.get_conversation(conversation_id uuid)
returns public.conversation_card
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  card public.conversation_card;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  select * into card from public.conversation_cards(auth.uid()) as c
  where c.conversation_id = get_conversation.conversation_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Chat not found.');
  end if;
  return card;
end;
$$;

------------------------------------------------------------------------------
-- What the apps do
------------------------------------------------------------------------------

-- Returns the chat for a reservation or an order, creating it when the deal
-- is active. Either participant may open it; an existing chat is returned
-- whatever the deal's state, so its history stays readable.
create function public.open_conversation(reservation_id uuid default null, order_id uuid default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  existing uuid;
  v_listing uuid;
  v_buyer uuid;
  v_seller uuid;
  v_status text;
  v_active boolean;
  new_id uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if num_nonnulls(open_conversation.reservation_id, open_conversation.order_id) <> 1 then
    perform public.raise_app_error('INVALID_INPUT', 'Open a chat for one reservation or one order.');
  end if;

  if open_conversation.reservation_id is not null then
    select r.listing_id, r.buyer_id, r.seller_id, r.status, r.status = 'accepted' and r.expires_at > now()
    into v_listing, v_buyer, v_seller, v_status, v_active
    from public.reservations as r where r.id = open_conversation.reservation_id;
  else
    select o.listing_id, o.buyer_id, b.owner_id, o.status,
           o.status in ('confirmed', 'preparing', 'ready_for_pickup') and b.status = 'approved'
    into v_listing, v_buyer, v_seller, v_status, v_active
    from public.orders as o join public.businesses as b on b.id = o.business_id
    where o.id = open_conversation.order_id;
  end if;
  if v_buyer is null or uid not in (v_buyer, v_seller) then
    perform public.raise_app_error('NOT_FOUND', 'Booking not found.');
  end if;

  select c.id into existing from public.conversations as c
  where c.reservation_id is not distinct from open_conversation.reservation_id
    and c.order_id is not distinct from open_conversation.order_id;
  if existing is not null then
    return jsonb_build_object('conversation_id', existing, 'created', false);
  end if;

  if not v_active then
    perform public.raise_app_error('INVALID_TRANSITION', case
      when open_conversation.reservation_id is not null
        then 'Chat opens once the seller accepts the reservation.'
      else 'Chat opens once the business confirms the order.' end);
  end if;

  insert into public.conversations (reservation_id, order_id, listing_id, buyer_id, seller_id)
  values (open_conversation.reservation_id, open_conversation.order_id, v_listing, v_buyer, v_seller)
  on conflict do nothing
  returning id into new_id;

  if new_id is null then
    -- The other participant opened it at the same moment.
    select c.id into new_id from public.conversations as c
    where c.reservation_id is not distinct from open_conversation.reservation_id
      and c.order_id is not distinct from open_conversation.order_id;
    return jsonb_build_object('conversation_id', new_id, 'created', false);
  end if;
  return jsonb_build_object('conversation_id', new_id, 'created', true);
end;
$$;

create function public.send_message(conversation_id uuid, body text)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_body text := btrim(coalesce(send_message.body, ''));
  conv public.conversations;
  new_id bigint;
  sent_at timestamptz;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if v_body = '' or char_length(v_body) > 1000 then
    perform public.raise_app_error('INVALID_INPUT', 'Write a message of up to 1,000 characters.');
  end if;

  -- The lock orders messages and read markers per conversation.
  conv := public.participant_conversation(send_message.conversation_id, true);
  if conv.closed_at is not null then
    perform public.raise_app_error('INVALID_TRANSITION', 'This chat was closed.');
  end if;
  if not public.conversation_can_send(conv) then
    perform public.raise_app_error('INVALID_TRANSITION', 'This chat is read-only because the booking has ended.');
  end if;
  if (select count(*) from public.messages as m
      where m.sender_id = uid and m.created_at > now() - interval '1 minute') >= 20 then
    perform public.raise_app_error('RATE_LIMITED', 'You''re sending messages very fast. Wait a moment.');
  end if;

  insert into public.messages (conversation_id, sender_id, body)
  values (conv.id, uid, v_body)
  returning id, created_at into new_id, sent_at;

  update public.conversations as c
  set last_message_at = sent_at,
      buyer_last_read_id = case when c.buyer_id = uid then new_id else c.buyer_last_read_id end,
      seller_last_read_id = case when c.seller_id = uid then new_id else c.seller_last_read_id end
  where c.id = conv.id;

  return jsonb_build_object('message_id', new_id, 'created_at', sent_at);
end;
$$;

-- Marks everything in the chat as read for the caller.
create function public.mark_conversation_read(conversation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  conv public.conversations;
  newest bigint;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  conv := public.participant_conversation(mark_conversation_read.conversation_id, true);
  select coalesce(max(m.id), 0) into newest from public.messages as m where m.conversation_id = conv.id;

  update public.conversations as c
  set buyer_last_read_id = case when c.buyer_id = uid then greatest(c.buyer_last_read_id, newest) else c.buyer_last_read_id end,
      seller_last_read_id = case when c.seller_id = uid then greatest(c.seller_last_read_id, newest) else c.seller_last_read_id end
  where c.id = conv.id;

  return jsonb_build_object('conversation_id', conv.id, 'last_read_id', newest);
end;
$$;

-- Either participant ends the chat for both (the "block"). It can't be
-- reopened; the history stays readable.
create function public.close_conversation(conversation_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  conv public.conversations;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  conv := public.participant_conversation(close_conversation.conversation_id, true);
  if conv.closed_at is not null then
    perform public.raise_app_error('INVALID_TRANSITION', 'This chat is already closed.');
  end if;

  update public.conversations as c set closed_at = now(), closed_by = uid where c.id = conv.id;

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'chat.closed', 'conversation', conv.id::text, '{}'::jsonb);

  return jsonb_build_object('conversation_id', conv.id, 'closed', true);
end;
$$;

-- Reports the other participant's messages to the administrators.
create function public.report_conversation(conversation_id uuid, reason text, details text default '')
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_details text := btrim(coalesce(report_conversation.details, ''));
  conv public.conversations;
  new_id uuid;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;
  if report_conversation.reason is null
     or report_conversation.reason not in ('scam', 'offensive', 'other') then
    perform public.raise_app_error('INVALID_INPUT', 'Choose a reason.');
  end if;
  if char_length(v_details) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Details can be up to 500 characters.');
  end if;
  if report_conversation.reason = 'other' and v_details = '' then
    perform public.raise_app_error('INVALID_INPUT', 'Tell us what''s wrong.');
  end if;

  conv := public.participant_conversation(report_conversation.conversation_id, false);
  if exists (select 1 from public.reports as r
             where r.reporter_id = uid and r.conversation_id = conv.id and r.status = 'open') then
    perform public.raise_app_error('ALREADY_EXISTS', 'You''ve already reported this chat.');
  end if;
  if (select count(*) from public.reports as r
      where r.reporter_id = uid and r.created_at > now() - interval '1 day') >= 10 then
    perform public.raise_app_error('RATE_LIMITED', 'You''ve sent a lot of reports today. Try again tomorrow.');
  end if;

  insert into public.reports (reporter_id, conversation_id, reported_user_id, reason, details)
  values (uid, conv.id, case when conv.buyer_id = uid then conv.seller_id else conv.buyer_id end,
          report_conversation.reason, v_details)
  returning id into new_id;

  return jsonb_build_object('report_id', new_id, 'status', 'open');
end;
$$;

------------------------------------------------------------------------------
-- Administrators
------------------------------------------------------------------------------

-- The messages of a reported chat. Admins can't browse chats; they see one
-- only through a report about it, and every view is audited.
create function public.get_reported_conversation(report_id uuid)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  report public.reports;
  conv public.conversations;
  result jsonb;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  select * into report from public.reports as r where r.id = get_reported_conversation.report_id;
  if not found or report.conversation_id is null then
    perform public.raise_app_error('NOT_FOUND', 'No chat is attached to this report.');
  end if;
  select * into conv from public.conversations as c where c.id = report.conversation_id;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'That chat no longer exists.');
  end if;

  select jsonb_build_object(
    'conversation_id', conv.id,
    'listing_title', (select l.title from public.listings as l where l.id = conv.listing_id),
    'buyer', (select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email)
              from public.profiles as p where p.id = conv.buyer_id),
    'seller', (select jsonb_build_object('id', p.id, 'name', p.name, 'email', p.email)
               from public.profiles as p where p.id = conv.seller_id),
    'closed_at', conv.closed_at,
    'messages', coalesce((
      select jsonb_agg(jsonb_build_object(
               'id', m.id,
               'from', case when m.sender_id = conv.buyer_id then 'buyer' else 'seller' end,
               'body', m.body,
               'created_at', m.created_at) order by m.id)
      from (select * from public.messages as mm
            where mm.conversation_id = conv.id order by mm.id desc limit 500) as m), '[]'::jsonb)
  ) into result;

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'chat.viewed', 'conversation', conv.id::text, jsonb_build_object('report_id', report.id));

  return result;
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.conversations enable row level security;
alter table public.messages enable row level security;

-- Written only by the functions above.
revoke all on public.conversations, public.messages from anon, authenticated;
grant select on public.conversations, public.messages to authenticated;

create policy "Participants see their conversations"
  on public.conversations for select to authenticated
  using ((select auth.uid()) in (buyer_id, seller_id));

-- Also what Supabase Realtime checks before sending a new message to a
-- subscriber.
create policy "Participants see their conversations' messages"
  on public.messages for select to authenticated
  using (exists (
    select 1 from public.conversations as c
    where c.id = messages.conversation_id
      and (select auth.uid()) in (c.buyer_id, c.seller_id)));

revoke execute on function public.my_conversations(integer, integer) from public, anon;
revoke execute on function public.get_conversation(uuid) from public, anon;
revoke execute on function public.open_conversation(uuid, uuid) from public, anon;
revoke execute on function public.send_message(uuid, text) from public, anon;
revoke execute on function public.mark_conversation_read(uuid) from public, anon;
revoke execute on function public.close_conversation(uuid) from public, anon;
revoke execute on function public.report_conversation(uuid, text, text) from public, anon;
revoke execute on function public.get_reported_conversation(uuid) from public, anon;

grant execute on function public.my_conversations(integer, integer) to authenticated;
grant execute on function public.get_conversation(uuid) to authenticated;
grant execute on function public.open_conversation(uuid, uuid) to authenticated;
grant execute on function public.send_message(uuid, text) to authenticated;
grant execute on function public.mark_conversation_read(uuid) to authenticated;
grant execute on function public.close_conversation(uuid) to authenticated;
grant execute on function public.report_conversation(uuid, text, text) to authenticated;
grant execute on function public.get_reported_conversation(uuid) to authenticated;

------------------------------------------------------------------------------
-- Live updates
------------------------------------------------------------------------------

-- New messages reach the chat screen through Supabase Realtime, which sends
-- each change only to subscribers the select policy above allows.
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table public.messages;
  end if;
end;
$$;
