-- business_applications.reviewer_id becomes admin_id: since ADR 0009 the
-- HDC administrator is the only one who reviews, so the name says who it is.
-- Column privileges and policies follow a rename by themselves; the one
-- function that writes the column is replaced below with the new name.

alter table public.business_applications rename column reviewer_id to admin_id;
alter table public.business_applications
  rename constraint business_applications_reviewer_id_fkey to business_applications_admin_id_fkey;

-- The only writer of the column; unchanged apart from its name.
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
      admin_id = uid,
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
