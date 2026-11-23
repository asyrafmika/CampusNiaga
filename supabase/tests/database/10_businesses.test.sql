-- Businesses (M2): what approval creates, business access (owns_business,
-- get_my_access, get_my_business), rejection, set_business_status, the
-- status summary, and the administrator's view of applicant profiles.
begin;
create extension if not exists pgtap with schema extensions;
select plan(61);

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
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('88888888-8888-8888-8888-888888888888', 'rina@campusniaga.test', now(), '{"name": "Rina"}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values
  ('33333333-3333-3333-3333-333333333333', 'admin'),
  ('88888888-8888-8888-8888-888888888888', 'admin');

-- Ali's and Siti's applications are under review; Amin only has a draft.
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at) values
  ('aaaaaaaa-0000-0000-0000-000000000011', '11111111-1111-1111-1111-111111111111', ' Ali Bakes ', 'Food & Beverage',
   'Homemade brownies and cookies, baked fresh every week.', '012-3456789', ' Desasiswa Tekun lobby, 6-8pm ', 'under_review', now() - interval '2 days'),
  ('aaaaaaaa-0000-0000-0000-000000000022', '22222222-2222-2222-2222-222222222222', 'Siti Prints', 'Stationery',
   'Custom printed notebooks and planners for students.', '019-8765432', 'Bangunan Aman Damai', 'under_review', now() - interval '1 day');
insert into public.business_applications (id, applicant_id, business_name, status) values
  ('aaaaaaaa-0000-0000-0000-000000000044', '44444444-4444-4444-4444-444444444444', 'Amin Tech', 'draft');

-- Before approval -------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_business_owner', 'false', 'before approval the student is not a business owner');
select ok(public.get_my_access() ? 'business_status' and public.get_my_access() ->> 'business_status' is null, 'and has no business status');
select is(pg_temp.error_reason('select public.get_my_business()'), 'FORBIDDEN', 'business features are refused before approval');

-- Approval ----------------------------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
do $$ begin
  perform set_config('test.business', public.review_business_application('aaaaaaaa-0000-0000-0000-000000000011', 'approve') ->> 'business_id', true);
end $$;
reset role;
select ok(current_setting('test.business', true) <> '', 'approving returns the new business');
select is((select owner_id::text || '/' || application_id || '/' || status from public.businesses where id = current_setting('test.business')::uuid),
  '11111111-1111-1111-1111-111111111111/aaaaaaaa-0000-0000-0000-000000000011/approved', 'the business belongs to the applicant and is approved');
select is((select name || ' | ' || pickup_details from public.businesses where id = current_setting('test.business')::uuid),
  'Ali Bakes | Desasiswa Tekun lobby, 6-8pm', 'the business takes the trimmed name and collection details');
select is((select description from public.businesses where id = current_setting('test.business')::uuid),
  'Homemade brownies and cookies, baked fresh every week.', 'and the description');
select ok((select status = 'approved' and decided_at is not null from public.business_applications where id = 'aaaaaaaa-0000-0000-0000-000000000011'), 'the application is approved with a decision time');
select is((select metadata ->> 'business_id' from public.audit_logs where action = 'application.approved'), current_setting('test.business'), 'the approval and its business are audited');
select is((select type || '/' || target from public.notifications where recipient_id = '11111111-1111-1111-1111-111111111111'),
  'application_approved/application:aaaaaaaa-0000-0000-0000-000000000011', 'the applicant is told');

-- Business access follows at once
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_business_owner', 'true', 'the owner has business access immediately');
select is(public.get_my_access() ->> 'business_status', 'approved', 'and sees the business status');
select ok(public.owns_business(current_setting('test.business')::uuid), 'owns_business is true for the owner');
select is(public.get_my_business() ->> 'name', 'Ali Bakes', 'the owner reads their business');
select is((select count(*)::int from public.businesses), 1, 'the owner reads the businesses table row');
select is(pg_temp.error_reason($$ update public.businesses set status = 'approved', name = 'Renamed' $$), '42501', 'the owner cannot edit the business row directly');
select is(pg_temp.error_reason($$ insert into public.businesses (owner_id, application_id, name, pickup_details) values ('11111111-1111-1111-1111-111111111111', 'aaaaaaaa-0000-0000-0000-000000000011', 'Fake', 'Here') $$), '42501', 'nobody can create a business directly');
select is(pg_temp.error_reason($$ update public.business_applications set business_name = 'Edited after approval' $$), 'no error', 'an approved application ignores edits');
reset role;
select is((select business_name from public.business_applications where id = 'aaaaaaaa-0000-0000-0000-000000000011'), ' Ali Bakes ', 'and stays as approved');

set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select ok(not public.owns_business(current_setting('test.business')::uuid), 'owns_business is false for another student');
select is((select count(*)::int from public.businesses), 0, 'another student cannot read the business row (storefronts come in Phase 4)');
select is(public.get_my_access() ->> 'is_business_owner', 'false', 'another student is not a business owner');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason('select public.get_my_business()'), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot ask for a business');
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is((select count(*)::int from public.businesses), 1, 'the reviewing administrator reads businesses');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.businesses), 1, 'an admin reads businesses');
reset role;
set local role anon;
select is(pg_temp.error_reason('select public.get_my_business()'), '42501', 'signed-out visitors cannot ask for a business');
select is(pg_temp.error_reason('select count(*) from public.businesses'), '42501', 'signed-out visitors cannot read businesses');
reset role;

-- One business per student
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$
declare new_id uuid;
begin
  insert into public.business_applications (business_name, category, description, contact_details, collection_details)
  values ('Ali Bakes Two', 'Food & Beverage', 'A second bakery, because one is never enough.', '012-3456789', 'Desasiswa Tekun')
  returning id into new_id;
  perform set_config('test.second', new_id::text, true);
end $$;
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.second')::uuid) $$), 'ALREADY_EXISTS', 'a business owner cannot apply for a second business');
reset role;
update public.business_applications set status = 'under_review', submitted_at = now() where id = current_setting('test.second')::uuid;
set local role authenticated;
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.second')::uuid, 'approve') $$), 'ALREADY_EXISTS', 'a second business is never approved');
reset role;
select is((select count(*)::int from public.businesses where owner_id = '11111111-1111-1111-1111-111111111111'), 1, 'the student still has one business');
delete from public.business_applications where id = current_setting('test.second')::uuid;

-- Rejection -----------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(public.review_business_application('aaaaaaaa-0000-0000-0000-000000000022', 'reject', 'Printing services need a supplier agreement.') ->> 'status', 'rejected', 'a reviewer rejects an application');
reset role;
select is((select remarks from public.business_applications where id = 'aaaaaaaa-0000-0000-0000-000000000022'), 'Printing services need a supplier agreement.', 'the rejection reason is kept');
select ok((select decided_at is not null from public.business_applications where id = 'aaaaaaaa-0000-0000-0000-000000000022'), 'the rejection has a decision time');
select is((select count(*)::int from public.businesses where owner_id = '22222222-2222-2222-2222-222222222222'), 0, 'rejection creates no business');
select is((select count(*)::int from public.notifications where recipient_id = '22222222-2222-2222-2222-222222222222' and type = 'application_rejected'), 1, 'the applicant is told');
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason('select public.get_my_business()'), 'FORBIDDEN', 'a rejected applicant has no business features');
select lives_ok($$ insert into public.business_applications (business_name) values ('Siti Prints, again') $$, 'a rejected applicant may start a new application');
reset role;

-- Status summary ---------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select results_eq($$ select status || '=' || total from public.application_status_summary() $$,
  $$ values ('submitted=0'), ('under_review=0'), ('info_requested=0'), ('approved=1'), ('rejected=1') $$,
  'reviewers see a count per status, zeros included and drafts left out');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select sum(total)::int from public.application_status_summary()), 2, 'admins see the summary too');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason('select * from public.application_status_summary()'), 'FORBIDDEN', 'students cannot see the summary');
reset role;
set local role anon;
select is(pg_temp.error_reason('select * from public.application_status_summary()'), '42501', 'signed-out visitors cannot see the summary');
reset role;

-- Administrators see every profile; students only their own ---------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is((select count(*)::int from public.profiles), 6, 'an administrator reads every profile');
select ok(not exists (select 1 from pg_policies where tablename = 'profiles' and policyname = 'Reviewers read the profiles of applicants'), 'the reviewers'' own rule is gone');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select results_eq($$ select name from public.profiles $$, $$ values ('Siti') $$, 'students still read only their own profile');
reset role;

-- Suspending and reinstating a business -------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_business_status(current_setting('test.business')::uuid, 'suspended') $$), 'FORBIDDEN', 'an owner cannot change their business status');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_business_status(current_setting('test.business')::uuid, 'suspended') $$), 'FORBIDDEN', 'another student cannot suspend a business');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_business_status(current_setting('test.business')::uuid, 'closed') $$), 'INVALID_INPUT', 'an unknown business status is refused');
select is(pg_temp.error_reason($$ select public.set_business_status('99999999-9999-9999-9999-999999999999', 'suspended') $$), 'NOT_FOUND', 'suspending a missing business fails');
select is(public.set_business_status(current_setting('test.business')::uuid, 'suspended', 'Selling outside the approved category') ->> 'changed', 'true', 'an admin suspends a business');
select is(public.set_business_status(current_setting('test.business')::uuid, 'suspended') ->> 'changed', 'false', 'suspending again changes nothing');
reset role;
select is((select count(*)::int from public.audit_logs where action = 'business.suspended'), 1, 'the suspension is audited once');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(not public.owns_business(current_setting('test.business')::uuid), 'a suspended business loses business access at once');
select is(public.get_my_access() ->> 'is_business_owner' || '/' || (public.get_my_access() ->> 'business_status'), 'false/suspended', 'get_my_access reports the suspension');
select is(public.get_my_business() ->> 'status', 'suspended', 'the owner can still see why');
select is((select count(*)::int from public.notifications where type = 'business_suspended'), 1, 'the owner is told about the suspension');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.set_business_status(current_setting('test.business')::uuid, 'approved') ->> 'status', 'approved', 'an admin reinstates the business');
reset role;
select is((select action from public.audit_logs order by id desc limit 1), 'business.reinstated', 'reinstating is audited');
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.owns_business(current_setting('test.business')::uuid), 'reinstating restores business access at once');
reset role;

-- A suspended account loses business access too
update public.profiles set account_status = 'suspended' where id = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(not public.owns_business(current_setting('test.business')::uuid), 'a suspended account cannot act for its business');
select is(public.get_my_access() ->> 'is_business_owner', 'false', 'and is not reported as a business owner');
reset role;
update public.profiles set account_status = 'active' where id = '11111111-1111-1111-1111-111111111111';

-- Business listings must point at a real business
select throws_ok($$ insert into public.listings (owner_id, mode, business_id, title, normalized_title, category, price_sen, condition, pickup_area)
  values ('11111111-1111-1111-1111-111111111111', 'business', '99999999-9999-9999-9999-999999999999', 'Brownies', 'brownies', 'Food & Beverage', 500, 'new', 'Tekun') $$,
  '23503', null, 'a business listing needs an existing business');

select * from finish();
rollback;
