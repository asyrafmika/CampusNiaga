-- Phase 1 pass condition, as one journey: a USM student signs up and gets in,
-- a non-USM email is refused, and a student can't open staff features.
-- The rules are tested one by one in files 01-03; this file checks they work
-- together in the order a real user meets them.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

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

-- Aisyah (USM) and Ben (gmail) sign up; neither has confirmed yet. One admin exists.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('a1111111-1111-1111-1111-111111111111', 'aisyah@student.usm.my', null, '{"name": "Aisyah"}'),
  ('b2222222-2222-2222-2222-222222222222', 'ben@gmail.com', null, '{"name": "Ben"}'),
  ('c3333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}');
insert into public.staff_roles (user_id, role) values ('c3333333-3333-3333-3333-333333333333', 'admin');

-- 1. Sign-up creates an active profile ------------------------------------------
select is(
  (select account_status from public.profiles where id = 'a1111111-1111-1111-1111-111111111111'),
  'active',
  'signing up creates an active profile'
);

-- 2. Before confirming, the app holds the student at "verify your email" -------
set local role authenticated;
set local request.jwt.claims to '{"sub": "a1111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'email_confirmed', 'false', 'before confirming, access reports an unconfirmed email');
select is(public.get_my_access() ->> 'is_student', 'false', 'before confirming, the USM email is not a student yet');
reset role;

-- 3. After confirming, the USM student gets in ---------------------------------
update auth.users set email_confirmed_at = now()
where id in ('a1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');

set local role authenticated;
set local request.jwt.claims to '{"sub": "a1111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_student', 'true', 'after confirming, the USM student gets in');
select is(public.get_my_access() ->> 'is_reviewer', 'false', 'the student is not a reviewer');
select is(public.get_my_access() ->> 'is_admin', 'false', 'the student is not an admin');

-- 4. The student can't open staff features --------------------------------------
select is(
  pg_temp.error_reason($$ select public.set_staff_role('a1111111-1111-1111-1111-111111111111', 'admin', true) $$),
  'FORBIDDEN',
  'the student cannot make themselves admin'
);
select is(
  pg_temp.error_reason($$ insert into public.staff_roles (user_id, role) values ('a1111111-1111-1111-1111-111111111111', 'admin') $$),
  '42501',
  'the student cannot write a staff role directly'
);
select is((select count(*)::int from public.staff_roles), 0, 'the student cannot see who is staff');
select is((select count(*)::int from public.audit_logs), 0, 'the student cannot read the audit log');
select is((select count(*)::int from public.app_config), 0, 'the student cannot read app settings');
select is((select count(*)::int from public.profiles), 1, 'the student sees only their own profile');
select is(public.get_my_access() ->> 'is_admin', 'false', 'after all that, the student is still not an admin');

-- 5. A confirmed non-USM email is refused ---------------------------------------
set local request.jwt.claims to '{"sub": "b2222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(public.get_my_access() ->> 'email_confirmed', 'true', 'the gmail account has confirmed its email');
select is(public.get_my_access() ->> 'is_student', 'false', 'a confirmed non-USM email is still refused');
select is(
  pg_temp.error_reason($$ select public.set_staff_role('b2222222-2222-2222-2222-222222222222', 'reviewer', true) $$),
  'FORBIDDEN',
  'the non-USM account cannot give itself a staff role'
);

-- 6. Staff access comes only from an admin, and changes take effect live --------
set local request.jwt.claims to '{"sub": "c3333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(
  public.set_staff_role('a1111111-1111-1111-1111-111111111111', 'reviewer', true) ->> 'changed',
  'true',
  'an admin makes the student a reviewer'
);

set local request.jwt.claims to '{"sub": "a1111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_reviewer', 'true', 'the reviewer role works on the next request, without signing in again');
select is(public.get_my_access() ->> 'is_admin', 'false', 'being a reviewer does not make the student an admin');

set local request.jwt.claims to '{"sub": "c3333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select lives_ok(
  $$ select public.set_staff_role('a1111111-1111-1111-1111-111111111111', 'reviewer', false) $$,
  'the admin removes the reviewer role'
);
select results_eq(
  $$ select action from public.audit_logs where target_id = 'a1111111-1111-1111-1111-111111111111' order by id $$,
  array['role.granted', 'role.revoked'],
  'both changes are in the audit log'
);

set local request.jwt.claims to '{"sub": "a1111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_reviewer', 'false', 'the removed role stops working on the next request');
reset role;

select * from finish();
rollback;
