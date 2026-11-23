-- One staff role: the HDC administrator (ADR 0009). The reviewer role is
-- gone; administrators already could do everything reviewers could, so the
-- review workflow itself doesn't change.
--
-- Existing reviewers become administrators, each recorded in the audit log.
-- Past entries in application_status_history keep actor_role 'reviewer', so
-- the history stays true to who acted then; new ones say 'admin'.
-- is_staff() stays: it now means "has the administrator role".

-- 1. Reviewers become administrators.
insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
select null, 'role.granted', 'user', r.user_id::text,
       jsonb_build_object('role', 'admin', 'reason', 'The reviewer role merged into administrator (ADR 0009).')
from public.staff_roles as r
where r.role = 'reviewer'
  and not exists (select 1 from public.staff_roles as a where a.user_id = r.user_id and a.role = 'admin');

insert into public.staff_roles (user_id, role, granted_by)
select r.user_id, 'admin', r.granted_by from public.staff_roles as r where r.role = 'reviewer'
on conflict do nothing;

delete from public.staff_roles where role = 'reviewer';

alter table public.staff_roles drop constraint staff_roles_role_check;
alter table public.staff_roles add constraint staff_roles_role_check check (role = 'admin');

-- 2. Administrators already read every profile.
drop policy "Reviewers read the profiles of applicants" on public.profiles;

-- 3. What the apps read: no reviewer flag.
create or replace function public.get_my_access()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  result jsonb;
  my_business public.businesses;
  student boolean := public.is_student();
begin
  if auth.uid() is null then
    perform public.raise_app_error('FORBIDDEN', 'Sign in to continue.');
  end if;

  select * into my_business from public.businesses as b where b.owner_id = auth.uid();

  select jsonb_build_object(
    'user_id', u.id,
    'email', u.email,
    'email_confirmed', u.email_confirmed_at is not null,
    'account_status', coalesce(p.account_status, 'active'),
    'is_student', student,
    'is_admin', public.is_admin(),
    'is_business_owner', student and coalesce(my_business.status = 'approved', false),
    'business_status', my_business.status
  )
  into result
  from auth.users as u
  left join public.profiles as p on p.id = u.id
  where u.id = auth.uid();

  return result;
end;
$$;

-- 4. Only administrators review.
create or replace function public.review_business_application(application_id uuid, action text, note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(review_business_application.note, '')), '');
  v_role text;
  app public.business_applications;
  new_status text;
  new_business uuid;
begin
  -- 1. Caller
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  v_role := 'admin';

  -- 2. Input
  new_status := case review_business_application.action
    when 'start_review' then 'under_review'
    when 'request_info' then 'info_requested'
    when 'approve' then 'approved'
    when 'reject' then 'rejected'
  end;
  if new_status is null then
    perform public.raise_app_error('INVALID_INPUT', 'Choose start_review, request_info, approve or reject.');
  end if;
  if char_length(v_note) > 1000 then
    perform public.raise_app_error('INVALID_INPUT', 'The note can be up to 1,000 characters.');
  end if;
  if new_status in ('info_requested', 'rejected') and v_note is null then
    perform public.raise_app_error('INVALID_INPUT', 'Tell the applicant why in a note.');
  end if;

  -- 3. The application, locked. Drafts are private, so they don't exist here.
  select * into app from public.business_applications as a
  where a.id = review_business_application.application_id
  for update;
  if not found or app.status = 'draft' then
    perform public.raise_app_error('NOT_FOUND', 'Application not found.');
  end if;
  if app.applicant_id = uid then
    perform public.raise_app_error('FORBIDDEN', 'You can''t review your own application.');
  end if;
  if (app.status, new_status) not in (
    ('submitted', 'under_review'),
    ('under_review', 'info_requested'),
    ('under_review', 'approved'),
    ('under_review', 'rejected')
  ) then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This application is %s, so it can''t be moved to %s.',
             replace(app.status, '_', ' '), replace(new_status, '_', ' ')));
  end if;

  -- 4. Approval effect: the business, in the same transaction
  if new_status = 'approved' then
    if exists (select 1 from public.businesses as b where b.owner_id = app.applicant_id) then
      perform public.raise_app_error('ALREADY_EXISTS', 'This student already has a business.');
    end if;
    insert into public.businesses (owner_id, application_id, name, description, pickup_details)
    values (app.applicant_id, app.id, btrim(app.business_name), btrim(app.description), btrim(app.collection_details))
    returning id into new_business;
  end if;

  -- 5. Change, history, audit and the applicant's notification
  update public.business_applications as a
  set status = new_status,
      reviewer_id = uid,
      remarks = coalesce(v_note, a.remarks),
      decided_at = case when new_status in ('approved', 'rejected') then now() end
  where a.id = app.id;

  insert into public.application_status_history (application_id, from_status, to_status, actor_id, actor_role, note)
  values (app.id, app.status, new_status, uid, v_role, v_note);

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'application.' || new_status, 'business_application', app.id::text,
          jsonb_strip_nulls(jsonb_build_object('from', app.status, 'business_id', new_business)));

  perform public.notify(
    app.applicant_id,
    'application_' || new_status,
    case new_status
      when 'under_review' then 'Your business application is under review'
      when 'info_requested' then 'Your business application needs changes'
      when 'approved' then 'Your business is approved'
      else 'Your business application was not approved'
    end,
    coalesce(v_note, btrim(app.business_name)),
    'application:' || app.id
  );

  return jsonb_build_object('application_id', app.id, 'status', new_status, 'business_id', new_business);
end;
$$;

-- 5. The administrator role is the only one to grant or remove.
create or replace function public.set_staff_role(target_user_id uuid, role text, enabled boolean)
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
  if target_user_id is null or enabled is null or role is null or role <> 'admin' then
    perform public.raise_app_error('INVALID_INPUT', 'Give a user, the role admin and enabled true/false.');
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

-- 6. Nothing calls it any more.
drop function public.is_reviewer();
