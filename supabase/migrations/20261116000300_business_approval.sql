-- CampusNiaga Phase 3 (M2): business applications, the simulated reviewer
-- workflow, and approved businesses. See docs/data-dictionary.md
-- ("business_applications", "application_status_history", "businesses") and
-- docs/api-contracts.md.
--
-- Security model:
--   * The applicant inserts a draft and edits its content columns directly,
--     limited by column privileges (never status, reviewer or dates) and by
--     a policy (only while draft or info_requested).
--   * Every status change goes through submit_business_application() or
--     review_business_application(). Each one locks the application row,
--     checks the move against the state machine, and writes the history row
--     and the audit entry in the same transaction.
--   * A business is created only inside review_business_application('approve').
--     Business access is read live from public.businesses by owns_business(),
--     so approval and suspension take effect on the very next request.
--   * Drafts are private to the applicant; reviewers and admins see an
--     application once it is submitted.
--   * This is a simulated FYP workflow, not an official USM decision.

------------------------------------------------------------------------------
-- Applications
------------------------------------------------------------------------------

create table public.business_applications (
  id uuid primary key default gen_random_uuid(),
  -- Derived from the session; clients have no privilege on this column.
  applicant_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  business_name text not null default '' check (char_length(business_name) <= 80),
  category text not null default '' check (char_length(category) <= 60),
  description text not null default '' check (char_length(description) <= 1000),
  contact_details text not null default '' check (char_length(contact_details) <= 200),
  collection_details text not null default '' check (char_length(collection_details) <= 200),
  document_paths text[] not null default '{}' check (cardinality(document_paths) <= 20),
  status text not null default 'draft'
    check (status in ('draft', 'submitted', 'under_review', 'info_requested', 'approved', 'rejected')),
  reviewer_id uuid references public.profiles (id) on delete set null,
  remarks text check (remarks is null or char_length(remarks) <= 1000),
  submitted_at timestamptz,
  decided_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  -- Anything past draft has been submitted; only final decisions are dated.
  check (status = 'draft' or submitted_at is not null),
  check ((status in ('approved', 'rejected')) = (decided_at is not null))
);

create trigger business_applications_set_updated_at
  before update on public.business_applications
  for each row execute function public.set_updated_at();

-- At most one unfinished application (draft or open) per student. The
-- functions check this first with a friendly error; the index is the backstop.
create unique index business_applications_one_unfinished
  on public.business_applications (applicant_id)
  where status not in ('approved', 'rejected');
-- The review queue: by status, oldest submission first.
create index business_applications_queue_idx
  on public.business_applications (status, submitted_at);

------------------------------------------------------------------------------
-- Status history (append-only)
------------------------------------------------------------------------------

create table public.application_status_history (
  id bigint generated always as identity primary key,
  application_id uuid not null references public.business_applications (id) on delete cascade,
  from_status text not null,
  to_status text not null,
  actor_id uuid references public.profiles (id) on delete set null,
  actor_role text not null check (actor_role in ('applicant', 'reviewer', 'admin')),
  note text check (note is null or char_length(note) <= 1000),
  created_at timestamptz not null default now()
);

create index application_status_history_application_idx
  on public.application_status_history (application_id, id);

------------------------------------------------------------------------------
-- Businesses (created only on approval)
------------------------------------------------------------------------------

create table public.businesses (
  id uuid primary key default gen_random_uuid(),
  -- One business per student.
  owner_id uuid not null unique references public.profiles (id) on delete cascade,
  application_id uuid not null unique references public.business_applications (id) on delete restrict,
  name text not null check (char_length(name) between 3 and 80),
  description text not null default '' check (char_length(description) <= 1000),
  logo_path text,
  pickup_details text not null check (char_length(pickup_details) <= 200),
  status text not null default 'approved' check (status in ('approved', 'suspended')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create trigger businesses_set_updated_at
  before update on public.businesses
  for each row execute function public.set_updated_at();

-- Business listings (Phase 4) must point at a real business. Every existing
-- listing is personal (business_id null), so this applies cleanly.
alter table public.listings
  add constraint listings_business_id_fkey
  foreign key (business_id) references public.businesses (id) on delete restrict;

------------------------------------------------------------------------------
-- Access helpers
------------------------------------------------------------------------------

-- The caller may act as this business: a verified student who owns it, and it
-- is approved (not suspended). Phase 4 business functions call this first.
create function public.owns_business(business_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_student()
    and exists (
      select 1 from public.businesses as b
      where b.id = owns_business.business_id
        and b.owner_id = auth.uid()
        and b.status = 'approved'
    );
$$;

-- Reviewers and admins work the review queue.
create function public.is_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from public.staff_roles where user_id = auth.uid());
$$;

-- Same as Phase 1, plus the caller's business. Replaced (not edited) because
-- the Phase 1 migration has already been applied.
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
    'is_reviewer', public.is_reviewer(),
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

------------------------------------------------------------------------------
-- Applicant: submit or resubmit
------------------------------------------------------------------------------

create function public.submit_business_application(application_id uuid, response_note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(submit_business_application.response_note, '')), '');
  app public.business_applications;
  max_documents integer;
  path text;
begin
  -- 1. Caller
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email to apply.');
  end if;

  -- 2. The application, locked so a parallel edit or review can't interleave
  select * into app from public.business_applications as a
  where a.id = submit_business_application.application_id
  for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Application not found.');
  end if;
  if app.applicant_id <> uid then
    perform public.raise_app_error('FORBIDDEN', 'You can only submit your own application.');
  end if;
  if app.status not in ('draft', 'info_requested') then
    perform public.raise_app_error('INVALID_TRANSITION',
      format('This application is %s, so it can''t be submitted again.', replace(app.status, '_', ' ')));
  end if;
  if exists (select 1 from public.businesses as b where b.owner_id = uid) then
    perform public.raise_app_error('ALREADY_EXISTS', 'You already have a business.');
  end if;
  if exists (select 1 from public.business_applications as a
             where a.applicant_id = uid and a.id <> app.id
               and a.status in ('submitted', 'under_review', 'info_requested')) then
    perform public.raise_app_error('ALREADY_EXISTS', 'You already have an application in progress.');
  end if;

  -- 3. Input (stored content, checked now that it is final)
  if char_length(btrim(app.business_name)) not between 3 and 80 then
    perform public.raise_app_error('INVALID_INPUT', 'The business name must be 3 to 80 characters.');
  end if;
  if not (app.category = any (public.listing_categories())) then
    perform public.raise_app_error('INVALID_INPUT', 'Choose one of the listed categories.');
  end if;
  if char_length(btrim(app.description)) < 20 then
    perform public.raise_app_error('INVALID_INPUT', 'Describe the business in at least 20 characters.');
  end if;
  if char_length(btrim(app.contact_details)) < 5 then
    perform public.raise_app_error('INVALID_INPUT', 'Give contact details (at least 5 characters).');
  end if;
  if char_length(btrim(app.collection_details)) < 5 then
    perform public.raise_app_error('INVALID_INPUT', 'Say where and when buyers collect (at least 5 characters).');
  end if;
  if char_length(v_note) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Your reply can be up to 500 characters.');
  end if;

  select c.max_application_documents into max_documents from public.app_config as c;
  if cardinality(app.document_paths) > max_documents then
    perform public.raise_app_error('INVALID_INPUT', format('Attach up to %s documents.', max_documents));
  end if;
  if cardinality(app.document_paths) <> (select count(distinct d) from unnest(app.document_paths) as d) then
    perform public.raise_app_error('INVALID_INPUT', 'A document is attached twice.');
  end if;
  -- Documents must be the applicant's own uploads for this application.
  foreach path in array app.document_paths loop
    if path is null
       or path !~* ('^' || uid::text || '/' || app.id::text || '/[^/]+\.(pdf|jpe?g|png)$')
       or not exists (select 1 from storage.objects as o
                      where o.bucket_id = 'application-documents' and o.name = path) then
      perform public.raise_app_error('INVALID_INPUT', 'A document is missing or isn''t one of this application''s uploads.');
    end if;
  end loop;

  -- 4. Change, history and audit
  update public.business_applications as a
  set status = 'submitted', submitted_at = now()
  where a.id = app.id;

  insert into public.application_status_history (application_id, from_status, to_status, actor_id, actor_role, note)
  values (app.id, app.status, 'submitted', uid, 'applicant', v_note);

  insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
  values (uid, 'application.submitted', 'business_application', app.id::text,
          jsonb_build_object('from', app.status));

  return jsonb_build_object('application_id', app.id, 'status', 'submitted');
end;
$$;

------------------------------------------------------------------------------
-- Reviewer: start review, request info, approve or reject
------------------------------------------------------------------------------

create function public.review_business_application(application_id uuid, action text, note text default null)
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
  if public.is_reviewer() then
    v_role := 'reviewer';
  elsif public.is_admin() then
    v_role := 'admin';
  else
    perform public.raise_app_error('FORBIDDEN', 'Reviewer access required.');
  end if;

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

-- Number of applications in each non-draft status, zeros included.
create function public.application_status_summary()
returns table (status text, total integer)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not public.is_staff() then
    perform public.raise_app_error('FORBIDDEN', 'Reviewer access required.');
  end if;

  return query
  select s.status, count(a.id)::integer
  from unnest(array['submitted', 'under_review', 'info_requested', 'approved', 'rejected'])
       with ordinality as s (status, ord)
  left join public.business_applications as a on a.status = s.status
  group by s.status, s.ord
  order by s.ord;
end;
$$;

------------------------------------------------------------------------------
-- Admin: suspend or reinstate a business
------------------------------------------------------------------------------

create function public.set_business_status(business_id uuid, status text, note text default null)
returns jsonb
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  uid uuid := auth.uid();
  v_note text := nullif(btrim(coalesce(set_business_status.note, '')), '');
  business public.businesses;
  changed boolean;
begin
  if not public.is_admin() then
    perform public.raise_app_error('FORBIDDEN', 'Administrator access required.');
  end if;
  if set_business_status.status is null
     or set_business_status.status not in ('approved', 'suspended')
     or char_length(v_note) > 500 then
    perform public.raise_app_error('INVALID_INPUT', 'Choose approved or suspended, with a note of up to 500 characters.');
  end if;

  select * into business from public.businesses as b where b.id = set_business_status.business_id for update;
  if not found then
    perform public.raise_app_error('NOT_FOUND', 'Business not found.');
  end if;

  changed := business.status <> set_business_status.status;
  if changed then
    update public.businesses as b set status = set_business_status.status where b.id = business.id;
    insert into public.audit_logs (actor_id, action, target_type, target_id, metadata)
    values (uid,
            case when set_business_status.status = 'suspended' then 'business.suspended' else 'business.reinstated' end,
            'business', business.id::text, jsonb_build_object('note', v_note));
    perform public.notify(
      business.owner_id,
      case when set_business_status.status = 'suspended' then 'business_suspended' else 'business_reinstated' end,
      case when set_business_status.status = 'suspended' then 'Your business was suspended' else 'Your business was reinstated' end,
      coalesce(v_note, business.name),
      'business:' || business.id
    );
  end if;

  return jsonb_build_object('business_id', business.id, 'status', set_business_status.status, 'changed', changed);
end;
$$;

------------------------------------------------------------------------------
-- Business owner: their business
------------------------------------------------------------------------------

-- Refused until the caller has a business, so it doubles as the "business
-- features need approval" gate. A suspended business is still returned so
-- the app can explain the suspension.
create function public.get_my_business()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  business public.businesses;
begin
  if not public.is_student() then
    perform public.raise_app_error('NOT_VERIFIED_STUDENT', 'Verify your USM student email first.');
  end if;

  select * into business from public.businesses as b where b.owner_id = auth.uid();
  if not found then
    perform public.raise_app_error('FORBIDDEN', 'You need an approved business application first.');
  end if;

  return jsonb_build_object(
    'business_id', business.id,
    'application_id', business.application_id,
    'name', business.name,
    'description', business.description,
    'pickup_details', business.pickup_details,
    'status', business.status,
    'created_at', business.created_at
  );
end;
$$;

------------------------------------------------------------------------------
-- Row Level Security and privileges
------------------------------------------------------------------------------

alter table public.business_applications enable row level security;
alter table public.application_status_history enable row level security;
alter table public.businesses enable row level security;

revoke all on public.business_applications, public.application_status_history, public.businesses
from anon, authenticated;
grant select on public.business_applications, public.application_status_history, public.businesses
to authenticated;

-- The applicant may write only the content columns. applicant_id comes from
-- its default (auth.uid()) and status from 'draft'; reviewer, remarks and the
-- dates have no client privilege at all.
grant insert (business_name, category, description, contact_details, collection_details, document_paths)
  on public.business_applications to authenticated;
grant update (business_name, category, description, contact_details, collection_details, document_paths)
  on public.business_applications to authenticated;

create policy "Applicants read their own applications; staff read submitted ones"
  on public.business_applications for select to authenticated
  using (applicant_id = (select auth.uid())
         or (status <> 'draft' and (select public.is_staff())));

create policy "Students start their own draft"
  on public.business_applications for insert to authenticated
  with check (applicant_id = (select auth.uid()) and status = 'draft' and (select public.is_student()));

create policy "Applicants edit their application while it is a draft or needs changes"
  on public.business_applications for update to authenticated
  using (applicant_id = (select auth.uid()) and status in ('draft', 'info_requested') and (select public.is_student()))
  with check (applicant_id = (select auth.uid()) and status in ('draft', 'info_requested'));

-- History follows the application's own visibility (the subquery runs under
-- the business_applications policy above). No client can write it.
create policy "History is readable by whoever can read the application"
  on public.application_status_history for select to authenticated
  using (exists (select 1 from public.business_applications as a
                 where a.id = application_status_history.application_id));

create policy "Owners and staff read businesses"
  on public.businesses for select to authenticated
  using (owner_id = (select auth.uid()) or (select public.is_staff()));

-- Profiles are otherwise private: reviewers may see the name and email of a
-- student whose submitted application they can see, for the review queue.
create policy "Reviewers read the profiles of applicants"
  on public.profiles for select to authenticated
  using ((select public.is_reviewer())
         and exists (select 1 from public.business_applications as a
                     where a.applicant_id = profiles.id and a.status <> 'draft'));

------------------------------------------------------------------------------
-- Document storage: application-documents/{applicant_id}/{application_id}/{file}
------------------------------------------------------------------------------

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('application-documents', 'application-documents', false, 5242880,
        array['application/pdf', 'image/jpeg', 'image/png']);

-- Upload: the applicant's own application, while it is editable, below the
-- per-application document limit.
create function public.can_upload_application_document(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select public.is_student()
    and coalesce(array_length(string_to_array(object_name, '/'), 1), 0) = 3
    and exists (
      select 1 from public.business_applications as a
      where a.applicant_id = auth.uid()
        and a.applicant_id::text = split_part(object_name, '/', 1)
        and a.id::text = split_part(object_name, '/', 2)
        and a.status in ('draft', 'info_requested')
    )
    and (select count(*) from storage.objects as o
         where o.bucket_id = 'application-documents'
           and o.name like split_part(object_name, '/', 1) || '/' || split_part(object_name, '/', 2) || '/%')
        < (select c.max_application_documents from public.app_config as c);
$$;

-- Delete: the applicant's own files, while the application is editable.
create function public.can_delete_application_document(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_applications as a
    where a.applicant_id = auth.uid()
      and a.applicant_id::text = split_part(object_name, '/', 1)
      and a.id::text = split_part(object_name, '/', 2)
      and a.status in ('draft', 'info_requested')
  );
$$;

-- Read (and so signed URLs): the applicant; staff once it is submitted.
create function public.can_read_application_document(object_name text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.business_applications as a
    where a.applicant_id::text = split_part(object_name, '/', 1)
      and a.id::text = split_part(object_name, '/', 2)
      and (a.applicant_id = auth.uid() or (a.status <> 'draft' and public.is_staff()))
  );
$$;

create policy "Applicants upload documents to their editable application"
  on storage.objects for insert to authenticated
  with check (bucket_id = 'application-documents' and public.can_upload_application_document(name));

create policy "Applicants and staff read application documents"
  on storage.objects for select to authenticated
  using (bucket_id = 'application-documents' and public.can_read_application_document(name));

create policy "Applicants delete documents from their editable application"
  on storage.objects for delete to authenticated
  using (bucket_id = 'application-documents' and public.can_delete_application_document(name));

------------------------------------------------------------------------------
-- Function privileges
------------------------------------------------------------------------------

revoke execute on function
  public.owns_business(uuid),
  public.is_staff(),
  public.submit_business_application(uuid, text),
  public.review_business_application(uuid, text, text),
  public.application_status_summary(),
  public.set_business_status(uuid, text, text),
  public.get_my_business(),
  public.can_upload_application_document(text),
  public.can_delete_application_document(text),
  public.can_read_application_document(text)
from public, anon;

grant execute on function
  public.owns_business(uuid),
  public.is_staff(),
  public.submit_business_application(uuid, text),
  public.review_business_application(uuid, text, text),
  public.application_status_summary(),
  public.set_business_status(uuid, text, text),
  public.get_my_business(),
  public.can_upload_application_document(text),
  public.can_delete_application_document(text),
  public.can_read_application_document(text)
to authenticated;
