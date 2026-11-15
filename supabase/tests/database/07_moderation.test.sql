-- Reports and moderation: report_listing, moderate_listing, dismiss_report,
-- set_account_status, and who may read reports.
begin;
create extension if not exists pgtap with schema extensions;
select plan(46);

-- Returns the reason (error DETAIL) an SQL statement fails with, or 'no error'.
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

-- Ali sells something dodgy; Siti and Amin report it; Ben uses gmail.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');

insert into public.listings (id, owner_id, title, normalized_title, category, price_sen, condition, photo_paths, pickup_area, status) values
  ('cccccccc-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'Brand new iPhone RM50', 'brand new iphone rm50', 'Electronics', 5000, 'new', array['p/1.jpg'], 'Tekun', 'available'),
  ('cccccccc-0000-0000-0000-000000000002', '11111111-1111-1111-1111-111111111111', 'Draft thing', 'draft thing', 'Others', 100, 'good', '{}', 'Tekun', 'draft');

-- Reporting -------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam', ' Price too good to be true ') ->> 'status', 'open', 'a student reports a listing');
reset role;
select is((select reported_user_id::text || '/' || details from public.reports), '11111111-1111-1111-1111-111111111111/Price too good to be true', 'the report records the seller and the trimmed details');

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'offensive') $$), 'ALREADY_EXISTS', 'a student cannot report the same listing twice while it is open');
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000002', 'scam') $$), 'NOT_FOUND', 'a draft cannot be reported');
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'boring') $$), 'INVALID_INPUT', 'an unknown reason is rejected');
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'other', '  ') $$), 'INVALID_INPUT', '"other" needs details');
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam', repeat('a', 501)) $$), 'INVALID_INPUT', 'details over 500 characters are rejected');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam') $$), 'FORBIDDEN', 'a seller cannot report their own listing');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam') $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot report');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam') $$), '42501', 'signed-out visitors cannot report');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is((select count(*)::int from public.reports), 0, 'a student cannot see other people''s reports');
select lives_ok($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'misleading') $$, 'a second student reports the same listing');
select is((select count(*)::int from public.reports), 1, 'a reporter sees their own report');
select is(pg_temp.error_reason($$ insert into public.reports (reporter_id, listing_id, reason) values ('44444444-4444-4444-4444-444444444444', 'cccccccc-0000-0000-0000-000000000001', 'scam') $$), '42501', 'reports cannot be inserted directly');
select is(pg_temp.error_reason($$ update public.reports set status = 'actioned' $$), '42501', 'reports cannot be updated directly');

-- Hiding a listing ----------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.moderate_listing('cccccccc-0000-0000-0000-000000000001', true) $$), 'FORBIDDEN', 'a student cannot hide listings');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.reports where status = 'open'), 2, 'an admin sees every open report');
select is(public.moderate_listing('cccccccc-0000-0000-0000-000000000001', true, 'Likely scam') ->> 'changed', 'true', 'an admin hides a reported listing');
select is((select count(*)::int from public.reports where status = 'actioned' and action = 'listing_hidden'), 2, 'hiding closes the listing''s open reports as actioned');
select is((select action from public.audit_logs order by id desc limit 1), 'listing.hidden', 'hiding is written to the audit log');
select is(public.moderate_listing('cccccccc-0000-0000-0000-000000000001', true) ->> 'changed', 'false', 'hiding a hidden listing changes nothing');
select is(pg_temp.error_reason($$ select public.moderate_listing('99999999-9999-9999-9999-999999999999', true) $$), 'NOT_FOUND', 'hiding a missing listing fails');
select is(pg_temp.error_reason($$ select public.moderate_listing('cccccccc-0000-0000-0000-000000000001', null) $$), 'INVALID_INPUT', 'hide must be true or false');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.notifications where type = 'listing_hidden'), 1, 'the seller is told their listing was hidden');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.search_listings('iphone')), 0, 'a hidden listing leaves the feed');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.moderate_listing('cccccccc-0000-0000-0000-000000000001', false) ->> 'hidden', 'false', 'an admin restores a listing');
select is((select action from public.audit_logs order by id desc limit 1), 'listing.restored', 'restoring is written to the audit log');

-- Dismissing a report ---------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
do $$ begin
  perform set_config('test.report', public.report_listing('cccccccc-0000-0000-0000-000000000001', 'other', 'Seller was rude') ->> 'report_id', true);
end $$;
select is(pg_temp.error_reason($$ select public.dismiss_report(current_setting('test.report')::uuid) $$), 'FORBIDDEN', 'a student cannot dismiss reports');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.dismiss_report(current_setting('test.report')::uuid, 'Not a listing problem') ->> 'status', 'reviewed', 'an admin dismisses a report');
select is((select action from public.audit_logs order by id desc limit 1), 'report.dismissed', 'dismissing is written to the audit log');
select is(pg_temp.error_reason($$ select public.dismiss_report(current_setting('test.report')::uuid) $$), 'INVALID_TRANSITION', 'a closed report cannot be dismissed again');
select is(pg_temp.error_reason($$ select public.dismiss_report('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'dismissing a missing report fails');

-- Suspending an account --------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select lives_ok($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam') $$, 'another report comes in');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_account_status('11111111-1111-1111-1111-111111111111', 'suspended') $$), 'FORBIDDEN', 'a student cannot suspend accounts');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.set_account_status('11111111-1111-1111-1111-111111111111', 'suspended', 'Repeated scams') ->> 'changed', 'true', 'an admin suspends an account');
select is((select count(*)::int from public.reports where reported_user_id = '11111111-1111-1111-1111-111111111111' and status = 'open'), 0, 'suspending closes the open reports about that user');
select is((select action from public.audit_logs order by id desc limit 1), 'account.suspended', 'suspending is written to the audit log');
select is(pg_temp.error_reason($$ select public.set_account_status('33333333-3333-3333-3333-333333333333', 'suspended') $$), 'FORBIDDEN', 'an admin cannot suspend themselves');
select is(pg_temp.error_reason($$ select public.set_account_status('11111111-1111-1111-1111-111111111111', 'banned') $$), 'INVALID_INPUT', 'an unknown account status is rejected');
select is(pg_temp.error_reason($$ select public.set_account_status('99999999-9999-9999-9999-999999999999', 'suspended') $$), 'NOT_FOUND', 'suspending a missing user fails');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_student', 'false', 'a suspended student loses student access');
select is(pg_temp.error_reason($$ select public.upsert_listing(null, 'Another one', '', 'Others', 100, 'good', 1, '{}', 'Tekun') $$), 'NOT_VERIFIED_STUDENT', 'a suspended student cannot list');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.search_listings('iphone')), 0, 'a suspended seller''s listings leave the feed');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.set_account_status('11111111-1111-1111-1111-111111111111', 'active') ->> 'account_status', 'active', 'an admin reactivates an account');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_student', 'true', 'reactivation restores student access at once');
reset role;

-- Rate limit ----------------------------------------------------------------------------------------
insert into public.reports (reporter_id, listing_id, reason, status, action)
select '44444444-4444-4444-4444-444444444444', 'cccccccc-0000-0000-0000-000000000001', 'scam', 'reviewed', 'dismissed'
from generate_series(1, 10 - (select count(*)::int from public.reports where reporter_id = '44444444-4444-4444-4444-444444444444'));
set local role authenticated;
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.report_listing('cccccccc-0000-0000-0000-000000000001', 'scam') $$), 'RATE_LIMITED', 'an 11th report in a day is refused');
reset role;

select * from finish();
rollback;
