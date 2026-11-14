-- CampusNiaga Phase 1 foundation: profiles, the USM student gate, staff roles,
-- app settings and the audit log. See docs/data-dictionary.md and
-- docs/api-contracts.md.
--
-- Security model:
--   * Row Level Security is enabled on every table; a table with no policy
--     for an action denies it.
--   * Privileged changes go through SECURITY DEFINER functions that check the
--     caller first. Roles are read live from tables, so removing a role takes
--     effect on the caller's very next request.
--   * Every SECURITY DEFINER function pins search_path to '' and names every
--     object with its schema.

------------------------------------------------------------------------------
-- Shared helpers
------------------------------------------------------------------------------

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Raises an error the apps can recognise: the reason is in the error DETAIL,
-- which PostgREST returns as `details`. Reasons: docs/api-contracts.md.
create function public.raise_app_error(reason text, message text)
returns void
language plpgsql
set search_path = ''
as $$
begin
  raise exception using errcode = 'P0001', message = message, detail = reason;
end;
$$;

------------------------------------------------------------------------------
-- App settings (a single row)
------------------------------------------------------------------------------

create table public.app_config (
  id boolean primary key default true check (id),
  student_email_domains text[] not null default array['student.usm.my']
    check (cardinality(student_email_domains) > 0),
  test_allowlist text[] not null default '{}',
  categories text[] not null default array[
    'Books', 'Electronics', 'Fashion', 'Food & Beverage',
    'Hostel Essentials', 'Stationery', 'Others'
  ],
  max_application_documents integer not null default 5 check (max_application_documents > 0),
  max_upload_bytes integer not null default 5242880 check (max_upload_bytes > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger app_config_set_updated_at
  before update on public.app_config
  for each row execute function public.set_updated_at();

insert into public.app_config default values;

------------------------------------------------------------------------------
-- Profiles: one per Auth user, created automatically at sign-up
------------------------------------------------------------------------------

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  name text not null check (char_length(name) between 1 and 60 and btrim(name) <> ''),
  email text not null,
  account_status text not null default 'active' check (account_status in ('active', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute function public.set_updated_at();

create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, name, email)
  values (
    new.id,
    left(coalesce(nullif(btrim(new.raw_user_meta_data ->> 'name'), ''), split_part(new.email, '@', 1), 'CampusNiaga user'), 60),
    coalesce(new.email, '')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.handle_user_email_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.profiles set email = coalesce(new.email, '') where id = new.id;
  return new;
end;
$$;

create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row
  when (old.email is distinct from new.email)
  execute function public.handle_user_email_change();

------------------------------------------------------------------------------
-- Staff roles: reviewers and admins (web dashboard)
------------------------------------------------------------------------------

create table public.staff_roles (
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null check (role in ('reviewer', 'admin')),
  granted_by uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default now(),
  primary key (user_id, role)
);

------------------------------------------------------------------------------
-- Audit log: append-only, written only by functions in this file and later
------------------------------------------------------------------------------

create table public.audit_logs (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users (id) on delete set null,
  action text not null,
  target_type text not null,
  target_id text not null,
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index audit_logs_target_idx on public.audit_logs (target_type, target_id);

------------------------------------------------------------------------------
-- Access checks (live: read from tables on every request)
------------------------------------------------------------------------------

-- Pure eligibility rule: exact domain match (look-alike and sub-domains fail)
-- or an exact allowlisted email; case-insensitive.
create function public.is_eligible_student_email(email text, domains text[], allowlist text[])
returns boolean
language sql
immutable
set search_path = ''
as $$
  select coalesce(
    lower(substring(btrim(email) from '^[^@]+@([^@]+)$')) in (select lower(btrim(d)) from unnest(domains) as d)
    or lower(btrim(email)) in (select lower(btrim(e)) from unnest(allowlist) as e),
    false
  );
$$;

-- A verified USM student: confirmed email, eligible address, active account.
create function public.is_student()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from auth.users as u
    join public.profiles as p on p.id = u.id
    cross join public.app_config as c
    where u.id = auth.uid()
      and u.email_confirmed_at is not null
      and p.account_status = 'active'
      and public.is_eligible_student_email(u.email, c.student_email_domains, c.test_allowlist)
  );
$$;

create function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff_roles where user_id = auth.uid() and role = 'admin');
$$;

create function public.is_reviewer()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff_roles where user_id = auth.uid() and role = 'reviewer');
$$;

-- What the signed-in user may do; the apps use this for navigation.
create function public.get_my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
begin
  if auth.uid() is null then
    perform public.raise_app_error('FORBIDDEN', 'Sign in to continue.');
  end if;

  select jsonb_build_object(
    'user_id', u.id,
    'email', u.email,
    'email_confirmed', u.email_confirmed_at is not null,
    'account_status', coalesce(p.account_status, 'active'),
    'is_student', public.is_student(),
    'is_reviewer', public.is_reviewer(),
    'is_admin', public.is_admin()
  )
  into result
  from auth.users as u
  left join public.profiles as p on p.id = u.id
  where u.id = auth.uid();

  return result;
end;
$$;

------------------------------------------------------------------------------
-- Staff role management (admins only)
------------------------------------------------------------------------------

create function public.set_staff_role(target_user_id uuid, role text, enabled boolean)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  changed boolean;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if target_user_id is null or enabled is null or role is null or role not in ('reviewer', 'admin') then
    perform public.raise_app_error('INVALID_INPUT', 'Give a user, a role (reviewer or admin) and enabled true/false.');
  end if;
  if target_user_id = auth.uid() and role = 'admin' and not enabled then
    perform public.raise_app_error('FORBIDDEN', 'You can''t remove your own administrator role.');
  end if;
  if not exists (select 1 from auth.users where id = target_user_id) then
    perform public.raise_app_error('NOT_FOUND', 'User not found.');
  end if;

  if enabled then
    insert into public.staff_roles (user_id, role, granted_by)
    values (target_user_id, set_staff_role.role, auth.uid())
    on conflict do nothing;
  else
    delete from public.staff_roles as s
    where s.user_id = target_user_id and s.role = set_staff_role.role;
  end if;
  changed := found;

  if changed then
    insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
    values (
      auth.uid(),
      case when enabled then 'role.granted' else 'role.revoked' end,
      'user',
      target_user_id::text,
      jsonb_build_object('role', set_staff_role.role)
    );
  end if;

  return jsonb_build_object('user_id', target_user_id, 'role', set_staff_role.role, 'enabled', enabled, 'changed', changed);
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.app_config enable row level security;
alter table public.profiles enable row level security;
alter table public.staff_roles enable row level security;
alter table public.audit_logs enable row level security;

-- Clients get no write privileges at all except the profile name below.
revoke all on public.app_config, public.profiles, public.staff_roles, public.audit_logs from anon, authenticated;
grant select on public.app_config, public.profiles, public.staff_roles, public.audit_logs to authenticated;
grant update (name) on public.profiles to authenticated;

-- app_config holds the test allowlist: admins only.
create policy "Admins can read app settings"
  on public.app_config for select to authenticated
  using ((select public.is_admin()));

create policy "Users can read their own profile; admins can read all"
  on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select public.is_admin()));

-- Only the name column is granted, so this can't change email or status.
create policy "Active users can rename themselves"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()) and account_status = 'active')
  with check (id = (select auth.uid()));

create policy "Users can see their own staff roles; admins can see all"
  on public.staff_roles for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "Admins can read the audit log"
  on public.audit_logs for select to authenticated
  using ((select public.is_admin()));

-- Functions: by default anyone may execute them. Internal ones are locked to
-- the database owner; the rest are for signed-in users only.
revoke execute on function
  public.set_updated_at(),
  public.raise_app_error(text, text),
  public.handle_new_user(),
  public.handle_user_email_change()
from public, anon, authenticated;

revoke execute on function
  public.is_eligible_student_email(text, text[], text[]),
  public.is_student(),
  public.is_admin(),
  public.is_reviewer(),
  public.get_my_access(),
  public.set_staff_role(uuid, text, boolean)
from public, anon;

grant execute on function
  public.is_eligible_student_email(text, text[], text[]),
  public.is_student(),
  public.is_admin(),
  public.is_reviewer(),
  public.get_my_access(),
  public.set_staff_role(uuid, text, boolean)
to authenticated;
