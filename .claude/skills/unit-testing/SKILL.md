---
name: unit-testing
description: Write, organize, run or fix CampusNiaga tests, including pgTAP database tests for Supabase migrations, Row Level Security, privileges and database functions under supabase/tests/database, Dart unit and widget tests in mobile/, Vitest and React Testing Library tests in admin/, limit and concurrency checks for stock and capacity, and test data. Use when adding tests for new code, reproducing a bug with a failing test, proving a phase pass condition, or diagnosing failing tests or a red CI job.
---

# Testing: CampusNiaga

This skill covers **how** to test. CLAUDE.md lists **what** must be tested. Never weaken, skip or delete a test to make a build pass. Fix the code, or ask the user if the test itself is wrong.

## Test layers

| Layer | Location | Runs | Proves |
|---|---|---|---|
| Database (pgTAP) | `supabase/tests/database/NN_area.test.sql` | CI: `supabase db start` + `supabase test db` | Policies, privileges, functions, constraints, transitions, limits |
| Flutter unit/widget | `mobile/test/**` | `flutter test`, locally and in CI | Controllers, mappers, screen states |
| React component/hook | next to the source as `*.test.tsx` | Vitest | Rendering states, role-filtered actions |

Most tests should be database tests: that's where the rules live.

## pgTAP file template

```sql
begin;
create extension if not exists pgtap with schema extensions;
select plan(3);                                   -- must equal the number of assertions

-- Returns the reason (error DETAIL) a statement fails with, or 'no error'.
create function pg_temp.error_reason(statement text) returns text language plpgsql as $$
declare reason text;
begin
  execute statement;
  return 'no error';
exception when others then
  get stacked diagnostics reason = pg_exception_detail;
  return coalesce(nullif(reason, ''), sqlstate);  -- app reason, else the SQL state
end;
$$;

-- Test data, inserted as the owner (bypasses RLS).
insert into auth.users (id, email, email_confirmed_at) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now());

-- Act as a signed-in user.
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select ok(public.is_student(), 'a confirmed USM email is a student');
select is(pg_temp.error_reason($$ select public.set_staff_role(...) $$), 'FORBIDDEN', 'a student cannot ...');
reset role;                                       -- back to the owner to change setup
select is((select count(*)::int from public.audit_logs), 0, '...');

select * from finish();
rollback;
```

Conventions:

- **Names describe behavior:** `'a student cannot read the audit log'`.
- **Fixed UUIDs** with readable patterns (`1111…` = Ali, `3333…` = admin), so failures are easy to read.
- **Refused cases:**
  - A refused function call reports its reason (`FORBIDDEN`, `INVALID_INPUT`…).
  - A missing privilege reports `42501`.
  - A constraint violation reports `23514`.
  - An RLS-filtered read returns no rows, and an RLS-filtered update changes nothing. Check the data afterwards as the owner (`reset role`).
- **Cover the matrix:** for each policy and function, test the allowed user plus another student, a role-less staff account, signed out (`set local role anon`), unconfirmed and suspended where relevant.
- **Limits:** for stock and capacity, prove the limit holds by calling the function until it refuses (`CAPACITY_FULL`) and checking the totals never exceed it. Real parallel races need two connections, which pgTAP can't do in one transaction; row locks (`for update`) plus these sequential tests plus `check` constraints are the guarantee.
- **Check the tests can fail:** when adding a security rule, temporarily break it (e.g. change a policy to `using (true)`) and confirm a test goes red, then restore it.

## Flutter specifics

- Keep Supabase out of unit and widget tests. Repositories wrap `Supabase.instance.client`. Tests override the repository providers with `mocktail` fakes: `ProviderScope(overrides: [listingRepositoryProvider.overrideWithValue(fake)])`.
- Widget tests pump `MaterialApp` with the app theme and find widgets by constant `Key`s.

## React specifics

- Mock the `services/*` modules with `vi.mock`, not the Supabase client internals.
- Wrap renders in a test `QueryClientProvider` (retries off) and a `MemoryRouter`. Query by role and label.

## Test data

pgTAP files create their own users and rows inside their transaction. Nothing is seeded into the hosted project by tests. The handoff scenario (2 students, applicant, approved seller, reviewer, admin, listings, a capacity-3 pre-order, the brownie requests) is built in the phase tests that need it.

## Workflow

1. For a bug: write a failing test first.
2. For a feature: database tests first, then the Flutter or React tests.
3. Run what you can locally (`flutter test`, Vitest). Database tests run in CI. Read the CI log for failing assertions (`not ok N - …`) and plan mismatches (`planned X but ran Y`).
4. Report what ran and its result. Never report success without running it.

## Verification checklist

- [ ] Every new policy, privilege and function has allowed and refused tests.
- [ ] Limits (stock, capacity, purchase limits) are tested.
- [ ] `plan(N)` matches; no `skip` or `todo` left behind.
- [ ] At least one deliberate break of a new rule was caught by the tests.
