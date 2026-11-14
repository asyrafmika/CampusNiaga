-- Profiles, the live student check and get_my_access().
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

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

insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali Bin Abu"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('55555555-5555-5555-5555-555555555555', 'outsider@gmail.com', now(), '{}'),
  ('66666666-6666-6666-6666-666666666666', 'new@student.usm.my', null, '{}'),
  ('77777777-7777-7777-7777-777777777777', 'examiner@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values ('33333333-3333-3333-3333-333333333333', 'admin');

-- Profile creation at sign-up ------------------------------------------------
select is((select name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'Ali Bin Abu', 'sign-up creates a profile using the name given');
select is((select name from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'siti', 'without a name, the profile uses the email name');
select is((select account_status from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'active', 'new accounts are active');

update auth.users set email = 'siti.new@student.usm.my' where id = '22222222-2222-2222-2222-222222222222';
select is((select email from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'siti.new@student.usm.my', 'an email change is copied to the profile');

-- Student check (live) -------------------------------------------------------
set local role authenticated;

set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.is_student(), 'a confirmed USM email is a student');
select is(public.get_my_access() ->> 'is_student', 'true', 'get_my_access reports the student');
select is(public.get_my_access() ->> 'is_admin', 'false', 'get_my_access reports no admin role');

set local request.jwt.claims to '{"sub": "66666666-6666-6666-6666-666666666666", "role": "authenticated"}';
select ok(not public.is_student(), 'an unconfirmed USM email is not a student yet');
select is(public.get_my_access() ->> 'email_confirmed', 'false', 'get_my_access reports the unconfirmed email');

set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select ok(not public.is_student(), 'a confirmed gmail address is not a student');

set local request.jwt.claims to '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}';
select ok(not public.is_student(), 'a non-USM email is not a student before it is allowlisted');
reset role;
update public.app_config set test_allowlist = array['examiner@gmail.com'];
set local role authenticated;
select ok(public.is_student(), 'the same email is a student once allowlisted');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.get_my_access() ->> 'is_admin', 'true', 'get_my_access reports the admin role');
select ok(not public.is_student(), 'staff with a non-USM email are not students');

reset role;
update public.profiles set account_status = 'suspended' where id = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(not public.is_student(), 'a suspended account is not a student');
select is(public.get_my_access() ->> 'account_status', 'suspended', 'get_my_access reports the suspension');
reset role;
update public.profiles set account_status = 'active' where id = '11111111-1111-1111-1111-111111111111';

-- Reading profiles -----------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select results_eq('select id::text from public.profiles', array['11111111-1111-1111-1111-111111111111'], 'a student sees only their own profile');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.profiles), 6, 'an admin sees every profile');

-- Changing profiles ----------------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ update public.profiles set name = 'Ali Abu' where id = '11111111-1111-1111-1111-111111111111' $$, 'a user can rename themselves');
select is((select name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'Ali Abu', 'the new name is saved');

select is(pg_temp.error_reason($$ update public.profiles set account_status = 'active' where id = '11111111-1111-1111-1111-111111111111' $$), '42501', 'a user cannot change their account status');
select is(pg_temp.error_reason($$ update public.profiles set email = 'x@student.usm.my' where id = '11111111-1111-1111-1111-111111111111' $$), '42501', 'a user cannot change the stored email');
select is(pg_temp.error_reason($$ update public.profiles set name = '' where id = '11111111-1111-1111-1111-111111111111' $$), '23514', 'an empty name is rejected');
select is(pg_temp.error_reason($$ update public.profiles set name = '   ' where id = '11111111-1111-1111-1111-111111111111' $$), '23514', 'a name of only spaces is rejected');
select is(pg_temp.error_reason($$ update public.profiles set name = repeat('a', 61) where id = '11111111-1111-1111-1111-111111111111' $$), '23514', 'a name over 60 characters is rejected');

update public.profiles set name = 'Hacked' where id = '22222222-2222-2222-2222-222222222222';
select is(pg_temp.error_reason($$ insert into public.profiles (id, name, email) values ('22222222-2222-2222-2222-222222222223', 'x', 'x') $$), '42501', 'a user cannot create profiles');
select is(pg_temp.error_reason($$ delete from public.profiles where id = '11111111-1111-1111-1111-111111111111' $$), '42501', 'a user cannot delete profiles');

set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
update public.profiles set name = 'Changed by admin' where id = '11111111-1111-1111-1111-111111111111';

reset role;
select is((select name from public.profiles where id = '22222222-2222-2222-2222-222222222222'), 'siti', 'a user cannot rename someone else');
select is((select name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'Ali Abu', 'an admin cannot edit profiles directly either');

update public.profiles set account_status = 'suspended' where id = '11111111-1111-1111-1111-111111111111';
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
update public.profiles set name = 'Suspended rename' where id = '11111111-1111-1111-1111-111111111111';
reset role;
select is((select name from public.profiles where id = '11111111-1111-1111-1111-111111111111'), 'Ali Abu', 'a suspended user cannot rename themselves');

-- Signed-out visitors --------------------------------------------------------
set local role anon;
select is(pg_temp.error_reason('select count(*) from public.profiles'), '42501', 'signed-out visitors cannot read profiles');
select is(pg_temp.error_reason('select public.get_my_access()'), '42501', 'signed-out visitors cannot call get_my_access');
reset role;

set local role authenticated;
set local request.jwt.claims to '{"role": "authenticated"}';
select is(pg_temp.error_reason('select public.get_my_access()'), 'FORBIDDEN', 'get_my_access refuses a request without a user');
reset role;

select * from finish();
rollback;
