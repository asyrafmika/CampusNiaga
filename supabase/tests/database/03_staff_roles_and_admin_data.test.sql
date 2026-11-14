-- set_staff_role() and access to staff-only data.
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

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

insert into auth.users (id, email, email_confirmed_at) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now()),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now()),
  ('44444444-4444-4444-4444-444444444444', 'reviewer@campusniaga.test', now());
insert into public.staff_roles (user_id, role) values
  ('33333333-3333-3333-3333-333333333333', 'admin'),
  ('44444444-4444-4444-4444-444444444444', 'reviewer');

set local role authenticated;

-- Granting and removing roles -------------------------------------------------
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(
  public.set_staff_role('11111111-1111-1111-1111-111111111111', 'reviewer', true),
  '{"user_id": "11111111-1111-1111-1111-111111111111", "role": "reviewer", "enabled": true, "changed": true}'::jsonb,
  'an admin can grant the reviewer role'
);
select is(
  (public.set_staff_role('11111111-1111-1111-1111-111111111111', 'reviewer', true)) ->> 'changed', 'false',
  'granting a role the user already has changes nothing'
);
select results_eq(
  $$ select action, target_id, metadata ->> 'role' from public.audit_logs order by id $$,
  $$ values ('role.granted', '11111111-1111-1111-1111-111111111111', 'reviewer') $$,
  'only the real change is written to the audit log'
);

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.is_reviewer(), 'the new role works immediately');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(
  (public.set_staff_role('11111111-1111-1111-1111-111111111111', 'reviewer', false)) ->> 'changed', 'true',
  'an admin can remove a role'
);
select is((select action from public.audit_logs order by id desc limit 1), 'role.revoked', 'the removal is written to the audit log');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(not public.is_reviewer(), 'the removed role stops working on the next request');

-- Who may call it ------------------------------------------------------------------
select is(pg_temp.error_reason($$ select public.set_staff_role('11111111-1111-1111-1111-111111111111', 'admin', true) $$), 'FORBIDDEN', 'a student cannot make themselves admin');
set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_staff_role('44444444-4444-4444-4444-444444444444', 'admin', true) $$), 'FORBIDDEN', 'a reviewer cannot make themselves admin');
set local request.jwt.claims to '{"role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_staff_role('11111111-1111-1111-1111-111111111111', 'admin', true) $$), 'FORBIDDEN', 'a request without a user is refused');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.set_staff_role('11111111-1111-1111-1111-111111111111', 'admin', true) $$), '42501', 'signed-out visitors cannot call it at all');
reset role;
set local role authenticated;

-- Input checks -------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.set_staff_role('33333333-3333-3333-3333-333333333333', 'admin', false) $$), 'FORBIDDEN', 'an admin cannot remove their own admin role');
select is(pg_temp.error_reason($$ select public.set_staff_role('11111111-1111-1111-1111-111111111111', 'superuser', true) $$), 'INVALID_INPUT', 'an unknown role is rejected');
select is(pg_temp.error_reason($$ select public.set_staff_role(null, 'reviewer', true) $$), 'INVALID_INPUT', 'a missing user is rejected');
select is(pg_temp.error_reason($$ select public.set_staff_role('11111111-1111-1111-1111-111111111111', 'reviewer', null) $$), 'INVALID_INPUT', 'a missing enabled flag is rejected');
select is(pg_temp.error_reason($$ select public.set_staff_role('99999999-9999-9999-9999-999999999999', 'reviewer', true) $$), 'NOT_FOUND', 'an unknown user is reported');
select ok(public.is_admin(), 'the admin still has their role after the refused calls');

-- Staff-only data ------------------------------------------------------------------
select is((select count(*)::int from public.app_config), 1, 'an admin can read the app settings');
select ok((select count(*) from public.audit_logs) > 0, 'an admin can read the audit log');
select is((select count(*)::int from public.staff_roles), 2, 'an admin can see all staff roles');

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.app_config), 0, 'a student cannot read the app settings or its allowlist');
select is((select count(*)::int from public.audit_logs), 0, 'a student cannot read the audit log');
select is((select count(*)::int from public.staff_roles), 0, 'a student sees no staff roles');

set local request.jwt.claims to '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}';
select is((select count(*)::int from public.audit_logs), 0, 'a reviewer cannot read the audit log yet (Phase 3 adds application history)');
select results_eq('select role from public.staff_roles', array['reviewer'], 'a reviewer sees only their own role');

-- Nobody writes these tables directly, not even an admin ------------------------------
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(pg_temp.error_reason($$ insert into public.staff_roles (user_id, role) values ('11111111-1111-1111-1111-111111111111', 'admin') $$), '42501', 'staff roles change only through set_staff_role');
select is(pg_temp.error_reason($$ insert into public.audit_logs (action, target_type, target_id) values ('forged', 'user', 'x') $$), '42501', 'the audit log cannot be forged');
select is(pg_temp.error_reason($$ update public.audit_logs set action = 'edited' $$), '42501', 'the audit log cannot be edited');
select is(pg_temp.error_reason($$ delete from public.audit_logs $$), '42501', 'the audit log cannot be deleted');
select is(pg_temp.error_reason($$ update public.app_config set test_allowlist = array['attacker@gmail.com'] $$), '42501', 'app settings cannot be changed from the app');

reset role;
set local role anon;
select is(pg_temp.error_reason('select count(*) from public.audit_logs'), '42501', 'signed-out visitors cannot read the audit log');
reset role;

select * from finish();
rollback;
