-- Phase 2 pass condition, as one journey (ADR 0006: Buy now replaced
-- reservations): a student publishes an item, a second student finds it,
-- asks about it and buys it, a competing purchase can't double-sell it, and
-- the seller completes the sale.
--
-- "Simultaneous" purchases are serialised by the row lock that buy_item()
-- takes on the listing (select ... for update): the second caller waits for
-- the first to commit, then sees no units left. A single test session can't
-- open two connections, so this file checks the outcome the lock guarantees
-- (supabase/tests/concurrency/purchase_race.sh does it with two).
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

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

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}');

-- 1. Ali publishes a single calculator -----------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$ begin
  perform set_config('test.listing', public.upsert_listing(null, 'Casio FX-570 calculator', 'One semester old.', 'Stationery', 2500, 'good', 1, '{}', 'Desasiswa Tekun') ->> 'listing_id', true);
end $$;
select lives_ok($$ select public.upsert_listing(current_setting('test.listing')::uuid, 'Casio FX-570 calculator', 'One semester old.', 'Stationery', 2500, 'good', 1,
  array['11111111-1111-1111-1111-111111111111/' || current_setting('test.listing') || '/1.jpg'], 'Desasiswa Tekun') $$, 'Ali adds a photo');
select is(public.set_listing_status(current_setting('test.listing')::uuid, 'available') ->> 'status', 'available', 'Ali publishes the listing');

-- 2. Siti finds it and asks about it, which holds nothing ---------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select results_eq($$ select id::text from public.search_listings('calculator') $$, array[current_setting('test.listing')], 'Siti finds it by searching');
select is((select seller_name from public.get_listing(current_setting('test.listing')::uuid)), 'Ali', 'Siti opens it and sees who is selling');
do $$ begin
  perform set_config('test.chat', public.open_conversation(listing_id => current_setting('test.listing')::uuid) ->> 'conversation_id', true);
end $$;
select lives_ok($$ select public.send_message(current_setting('test.chat')::uuid, 'Do all the keys work?') $$, 'Siti asks about its condition');
select is((select status || '/' || stock from public.get_listing(current_setting('test.listing')::uuid)), 'available/1', 'chatting does not hold it');

-- 3. Siti buys it; Amin's competing purchase is refused ----------------------------------
do $$ begin
  perform set_config('test.purchase', public.buy_item(current_setting('test.listing')::uuid) ->> 'purchase_id', true);
end $$;
select ok(current_setting('test.purchase', true) is not null, 'Siti buys it');
select is((select status || '/' || stock from public.get_listing(current_setting('test.listing')::uuid)), 'sold/0', 'it is sold the moment she confirms');
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.buy_item(current_setting('test.listing')::uuid) $$), 'ITEM_UNAVAILABLE', 'Amin cannot buy the same item: no double-selling');
select is((select count(*)::int from public.search_listings('calculator')), 0, 'the sold item leaves the feed');
reset role;
select is((select count(*)::int from public.purchases where listing_id = current_setting('test.listing')::uuid and status <> 'cancelled'), 1, 'exactly one purchase has the item');

-- 4. They meet, and Ali completes the sale -----------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.open_conversation(purchase_id => current_setting('test.purchase')::uuid) ->> 'conversation_id', current_setting('test.chat'), 'Ali opens the same chat from the sale');
select lives_ok($$ select public.send_message(current_setting('test.chat')::uuid, '5pm at Tekun?') $$, 'and arranges pickup there');
select is(public.complete_purchase(current_setting('test.purchase')::uuid) ->> 'status', 'completed', 'Ali completes the sale at handover');
reset role;
select is((select status || '/' || stock from public.listings where id = current_setting('test.listing')::uuid), 'sold/0', 'the listing is sold with no stock left');

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.buy_item(current_setting('test.listing')::uuid) $$), 'ITEM_UNAVAILABLE', 'a sold item cannot be bought');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select status from public.my_purchases('buying')), 'completed', 'Siti''s purchase shows as completed');
reset role;

select * from finish();
rollback;
