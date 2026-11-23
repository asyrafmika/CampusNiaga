-- Business applications (M2): drafts and column privileges, who reads what,
-- document storage rules, submit_business_application,
-- review_business_application and every (status, action) pair.
begin;
create extension if not exists pgtap with schema extensions;
select plan(91);

-- Returns the reason (error DETAIL) an SQL statement fails with, or the
-- SQLSTATE when there is no reason, or 'no error'.
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

-- Ali applies; Siti and Amin are other students; Rina is the HDC
-- administrator who reviews; Sam is a student who is also an administrator;
-- Ben uses gmail; there is one more admin.
insert into auth.users (id, email, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@student.usm.my', now(), '{"name": "Ali"}'),
  ('22222222-2222-2222-2222-222222222222', 'siti@student.usm.my', now(), '{"name": "Siti"}'),
  ('44444444-4444-4444-4444-444444444444', 'amin@student.usm.my', now(), '{"name": "Amin"}'),
  ('33333333-3333-3333-3333-333333333333', 'admin@campusniaga.test', now(), '{}'),
  ('88888888-8888-8888-8888-888888888888', 'rina@campusniaga.test', now(), '{"name": "Rina"}'),
  ('77777777-7777-7777-7777-777777777777', 'sam@student.usm.my', now(), '{"name": "Sam"}'),
  ('55555555-5555-5555-5555-555555555555', 'ben@gmail.com', now(), '{}');
insert into public.staff_roles (user_id, role) values
  ('33333333-3333-3333-3333-333333333333', 'admin'),
  ('88888888-8888-8888-8888-888888888888', 'admin'),
  ('77777777-7777-7777-7777-777777777777', 'admin');

-- Drafts --------------------------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$
declare new_id uuid;
begin
  insert into public.business_applications (business_name) values ('Ali Bakes') returning id into new_id;
  perform set_config('test.app', new_id::text, true);
end $$;
reset role;
select is((select applicant_id::text || '/' || status from public.business_applications where id = current_setting('test.app')::uuid),
  '11111111-1111-1111-1111-111111111111/draft', 'a student starts a draft as themselves');

set local role authenticated;
select is(pg_temp.error_reason($$ insert into public.business_applications (business_name) values ('Second') $$), '23505', 'a student cannot have two unfinished applications');
select is(pg_temp.error_reason($$ insert into public.business_applications (business_name, status) values ('Sneaky', 'approved') $$), '42501', 'a client cannot choose the status');
select is(pg_temp.error_reason($$ insert into public.business_applications (applicant_id, business_name) values ('22222222-2222-2222-2222-222222222222', 'For Siti') $$), '42501', 'a client cannot choose the applicant');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ insert into public.business_applications (business_name) values ('Ben Co') $$), '42501', 'a non-USM account cannot apply');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ insert into public.business_applications (business_name) values ('Anon Co') $$), '42501', 'signed-out visitors cannot apply');
reset role;

-- Who sees a draft
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 1, 'the applicant sees their draft');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 0, 'another student cannot see it');
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 0, 'a reviewer cannot see a draft');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 0, 'an admin cannot see a draft either');

-- Editing a draft
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select lives_ok($$ update public.business_applications set category = 'Food & Beverage', description = 'Homemade brownies and cookies, baked fresh every week.',
  contact_details = '012-3456789', collection_details = 'Desasiswa Tekun lobby, 6-8pm' $$, 'the applicant edits their draft');
-- info_requested would pass the update policy, so only the column privilege stops it.
select is(pg_temp.error_reason($$ update public.business_applications set status = 'info_requested' $$), '42501', 'the applicant cannot change the status');
select is(pg_temp.error_reason($$ update public.business_applications set admin_id = '88888888-8888-8888-8888-888888888888' $$), '42501', 'the applicant cannot set the administrator');
select is(pg_temp.error_reason($$ update public.business_applications set remarks = 'Looks great' $$), '42501', 'the applicant cannot write reviewer remarks');
select is(pg_temp.error_reason($$ update public.business_applications set submitted_at = now() $$), '42501', 'the applicant cannot set the dates');
select is(pg_temp.error_reason($$ update public.business_applications set applicant_id = '22222222-2222-2222-2222-222222222222' $$), '42501', 'the applicant cannot hand the application to someone else');
select is(pg_temp.error_reason($$ delete from public.business_applications $$), '42501', 'applications cannot be deleted');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
update public.business_applications set business_name = 'Hijacked';
reset role;
select is((select business_name from public.business_applications where id = current_setting('test.app')::uuid), 'Ali Bakes', 'another student cannot edit it');

-- Documents -----------------------------------------------------------------------------------
select is((select public from storage.buckets where id = 'application-documents'), false, 'the application-documents bucket is private');
select is((select allowed_mime_types from storage.buckets where id = 'application-documents'), array['application/pdf', 'image/jpeg', 'image/png'], 'only PDF, JPEG and PNG are accepted');
select is((select file_size_limit from storage.buckets where id = 'application-documents'), 5242880::bigint, 'documents are limited to 5 MB');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.can_upload_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'the applicant may upload to their draft');
select ok(not public.can_upload_application_document('11111111-1111-1111-1111-111111111111/99999999-9999-9999-9999-999999999999/menu.pdf'), 'uploads need an application the student owns');
select ok(not public.can_upload_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/extra/menu.pdf'), 'uploads sit directly in the application folder');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select ok(not public.can_upload_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'another student cannot upload to it');
reset role;

-- Ali's upload lands (Storage writes the object row).
insert into storage.objects (bucket_id, name) values
  ('application-documents', '11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf');
update public.app_config set max_application_documents = 1;
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(not public.can_upload_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/extra.pdf'), 'no upload beyond the document limit');
reset role;
update public.app_config set max_application_documents = 5;

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select ok(public.can_read_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'the applicant may read their document');
select ok(public.can_delete_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'the applicant may delete it while drafting');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select ok(not public.can_read_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'another student cannot read it');
select ok(not public.can_delete_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'another student cannot delete it');
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select ok(not public.can_read_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'a reviewer cannot read a draft''s documents');
reset role;

-- Submitting: validation ----------------------------------------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
update public.business_applications set business_name = 'AB';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'a business name under 3 characters is refused');
update public.business_applications set business_name = 'Ali Bakes', category = 'Pets';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'an unknown category is refused');
update public.business_applications set category = 'Food & Beverage', description = 'Brownies';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'a description under 20 characters is refused');
update public.business_applications set description = 'Homemade brownies and cookies, baked fresh every week.', contact_details = '012';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'contact details under 5 characters are refused');
update public.business_applications set contact_details = '012-3456789', collection_details = '  ';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'collection details are required');
update public.business_applications set collection_details = 'Desasiswa Tekun lobby, 6-8pm',
  document_paths = array['11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/missing.pdf'];
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'a document that was never uploaded is refused');
update public.business_applications set document_paths = array['22222222-2222-2222-2222-222222222222/' || current_setting('test.app') || '/menu.pdf'];
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'a document from someone else''s folder is refused');
update public.business_applications set document_paths = array['11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf',
                                                               '11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'];
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'the same document twice is refused');
-- Two real uploads against a limit of one.
reset role;
insert into storage.objects (bucket_id, name) values
  ('application-documents', '11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/photo.jpg');
update public.app_config set max_application_documents = 1;
set local role authenticated;
update public.business_applications set document_paths = array['11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf',
                                                               '11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/photo.jpg'];
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_INPUT', 'more documents than the limit are refused');
reset role;
update public.app_config set max_application_documents = 5;
set local role authenticated;
update public.business_applications set document_paths = array['11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'];
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid, repeat('x', 501)) $$), 'INVALID_INPUT', 'a reply over 500 characters is refused');

-- Submitting: who may
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'FORBIDDEN', 'another student cannot submit it');
set local request.jwt.claims to '{"sub": "55555555-5555-5555-5555-555555555555", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'NOT_VERIFIED_STUDENT', 'a non-USM account cannot submit');
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.submit_business_application('99999999-9999-9999-9999-999999999999') $$), 'NOT_FOUND', 'submitting a missing application fails');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), '42501', 'signed-out visitors cannot submit');
reset role;

-- Submitting: success
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.submit_business_application(current_setting('test.app')::uuid) ->> 'status', 'submitted', 'the applicant submits a complete application');
reset role;
select ok((select submitted_at is not null from public.business_applications where id = current_setting('test.app')::uuid), 'the submission time is recorded');
select is((select from_status || '>' || to_status || '/' || actor_role || '/' || actor_id from public.application_status_history where application_id = current_setting('test.app')::uuid),
  'draft>submitted/applicant/11111111-1111-1111-1111-111111111111', 'the submission is in the history');
select is((select action || '/' || (metadata ->> 'from') from public.audit_logs where target_id = current_setting('test.app') order by id desc limit 1),
  'application.submitted/draft', 'the submission is in the audit log');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.submit_business_application(current_setting('test.app')::uuid) $$), 'INVALID_TRANSITION', 'a submitted application cannot be submitted again');
update public.business_applications set business_name = 'Changed after submitting';
select is((select business_name from public.business_applications), 'Ali Bakes', 'a submitted application can no longer be edited');
select ok(not public.can_upload_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/late.pdf'), 'no uploads after submitting');
select ok(not public.can_delete_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'no deletions after submitting');
select is(pg_temp.error_reason($$ insert into public.business_applications (business_name) values ('Second') $$), '23505', 'no new draft while an application is open');

-- History is append-only and private
select is((select count(*)::int from public.application_status_history), 1, 'the applicant reads their history');
select is(pg_temp.error_reason($$ insert into public.application_status_history (application_id, from_status, to_status, actor_role)
  values (current_setting('test.app')::uuid, 'submitted', 'approved', 'reviewer') $$), '42501', 'nobody can write history directly');
select is(pg_temp.error_reason($$ update public.application_status_history set note = 'edited' $$), '42501', 'history cannot be edited');
select is(pg_temp.error_reason($$ delete from public.application_status_history $$), '42501', 'history cannot be deleted');
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 0, 'another student still cannot see the application');
select is((select count(*)::int from public.application_status_history), 0, 'nor its history');

-- Staff see it now
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 1, 'a reviewer sees a submitted application');
select is((select count(*)::int from public.application_status_history), 1, 'and its history');
select ok(public.can_read_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/menu.pdf'), 'and its documents');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is((select count(*)::int from public.business_applications), 1, 'an admin sees it too');

-- Reviewing: who may and input --------------------------------------------------------------------
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.app')::uuid, 'start_review') $$), 'FORBIDDEN', 'a student cannot review');
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.app')::uuid, 'fast_track') $$), 'INVALID_INPUT', 'an unknown action is refused');
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.app')::uuid, 'request_info', '   ') $$), 'INVALID_INPUT', 'requesting info needs a note');
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.app')::uuid, 'reject') $$), 'INVALID_INPUT', 'rejecting needs a note');
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.app')::uuid, 'start_review', repeat('x', 1001)) $$), 'INVALID_INPUT', 'a note over 1,000 characters is refused');
select is(pg_temp.error_reason($$ select public.review_business_application('99999999-9999-9999-9999-999999999999', 'start_review') $$), 'NOT_FOUND', 'reviewing a missing application fails');
reset role;
set local role anon;
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.app')::uuid, 'start_review') $$), '42501', 'signed-out visitors cannot review');
reset role;

-- Reviewing: request info, edit, resubmit
set local role authenticated;
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(public.review_business_application(current_setting('test.app')::uuid, 'start_review') ->> 'status', 'under_review', 'a reviewer starts the review');
select is(public.review_business_application(current_setting('test.app')::uuid, 'request_info', ' Please attach your food handling certificate. ') ->> 'status', 'info_requested', 'the reviewer asks for more information');
reset role;
select is((select admin_id::text || '/' || remarks from public.business_applications where id = current_setting('test.app')::uuid),
  '88888888-8888-8888-8888-888888888888/Please attach your food handling certificate.', 'the administrator and their trimmed note are recorded');
-- The column says who decides since ADR 0009 (migration 20261123000400).
select has_column('public', 'business_applications', 'admin_id', 'business_applications records the deciding administrator in admin_id');
select hasnt_column('public', 'business_applications', 'reviewer_id', 'the old reviewer_id column is gone');
select is((select note from public.application_status_history where application_id = current_setting('test.app')::uuid order by id desc limit 1),
  'Please attach your food handling certificate.', 'the note is in the history');
select is((select actor_role from public.application_status_history where application_id = current_setting('test.app')::uuid order by id desc limit 1),
  'admin', 'the history records the administrator role');

set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select string_agg(type, ',' order by id) from public.notifications), 'application_under_review,application_info_requested', 'the applicant is told about each step');
select is((select remarks from public.business_applications), 'Please attach your food handling certificate.', 'the applicant reads the reviewer''s note');
select lives_ok($$ update public.business_applications set description = 'Homemade brownies and cookies, baked fresh every week. Certified food handler.' $$, 'the applicant edits after a request for information');
select ok(public.can_upload_application_document('11111111-1111-1111-1111-111111111111/' || current_setting('test.app') || '/certificate.pdf'), 'and may upload again');
select is(public.submit_business_application(current_setting('test.app')::uuid, 'Certificate attached.') ->> 'status', 'submitted', 'the applicant resubmits');
reset role;
select is((select from_status || '>' || to_status || '/' || note from public.application_status_history where application_id = current_setting('test.app')::uuid order by id desc limit 1),
  'info_requested>submitted/Certificate attached.', 'the resubmission and the reply are in the history');

-- Staff never review drafts or their own applications
set local role authenticated;
set local request.jwt.claims to '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}';
do $$
declare new_id uuid;
begin
  insert into public.business_applications (business_name) values ('Siti Prints') returning id into new_id;
  perform set_config('test.siti_draft', new_id::text, true);
end $$;
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.review_business_application(current_setting('test.siti_draft')::uuid, 'start_review') $$), 'NOT_FOUND', 'a draft cannot be reviewed');
reset role;
insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at)
values ('aaaaaaaa-0000-0000-0000-000000000077', '77777777-7777-7777-7777-777777777777', 'Sam Snacks', 'Food & Beverage',
        'Snacks for late-night study sessions.', '011-1111111', 'Desasiswa Restu', 'submitted', now());
set local role authenticated;
set local request.jwt.claims to '{"sub": "77777777-7777-7777-7777-777777777777", "role": "authenticated"}';
select is(pg_temp.error_reason($$ select public.review_business_application('aaaaaaaa-0000-0000-0000-000000000077', 'start_review') $$), 'FORBIDDEN', 'an administrator cannot review their own application');
set local request.jwt.claims to '{"sub": "33333333-3333-3333-3333-333333333333", "role": "authenticated"}';
select is(public.review_business_application('aaaaaaaa-0000-0000-0000-000000000077', 'start_review') ->> 'status', 'under_review', 'an admin may review too');
reset role;
select is((select actor_role from public.application_status_history where application_id = 'aaaaaaaa-0000-0000-0000-000000000077'), 'admin', 'the history records the admin role');

-- Every (status, action) pair ----------------------------------------------------------------------
-- Each case puts a fresh application in the starting status (as Amin), runs
-- the action as Rina, records the outcome, then rolls the case back.
create function pg_temp.review_outcome(from_status text, review_action text) returns text language plpgsql as $$
declare outcome text; reason text;
begin
  begin
    insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at)
    values ('aaaaaaaa-0000-0000-0000-000000000044', '44444444-4444-4444-4444-444444444444', 'Amin Tech', 'Electronics',
            'Phone repairs and accessories for students.', '013-3333333', 'Desasiswa Saujana',
            from_status, case when from_status <> 'draft' then now() end,
            case when from_status in ('approved', 'rejected') then now() end);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}', true);
    outcome := public.review_business_application('aaaaaaaa-0000-0000-0000-000000000044', review_action, 'A note') ->> 'status';
    raise exception using errcode = 'P0001', message = 'roll back this case', detail = 'ROLLBACK_CASE';
  exception when others then
    get stacked diagnostics reason = pg_exception_detail;
    if reason is distinct from 'ROLLBACK_CASE' then
      outcome := coalesce(nullif(reason, ''), sqlstate);
    end if;
  end;
  return outcome;
end;
$$;

create function pg_temp.submit_outcome(from_status text) returns text language plpgsql as $$
declare outcome text; reason text;
begin
  begin
    insert into public.business_applications (id, applicant_id, business_name, category, description, contact_details, collection_details, status, submitted_at, decided_at)
    values ('aaaaaaaa-0000-0000-0000-000000000044', '44444444-4444-4444-4444-444444444444', 'Amin Tech', 'Electronics',
            'Phone repairs and accessories for students.', '013-3333333', 'Desasiswa Saujana',
            from_status, case when from_status <> 'draft' then now() end,
            case when from_status in ('approved', 'rejected') then now() end);
    perform set_config('role', 'authenticated', true);
    perform set_config('request.jwt.claims', '{"sub": "44444444-4444-4444-4444-444444444444", "role": "authenticated"}', true);
    outcome := public.submit_business_application('aaaaaaaa-0000-0000-0000-000000000044') ->> 'status';
    raise exception using errcode = 'P0001', message = 'roll back this case', detail = 'ROLLBACK_CASE';
  exception when others then
    get stacked diagnostics reason = pg_exception_detail;
    if reason is distinct from 'ROLLBACK_CASE' then
      outcome := coalesce(nullif(reason, ''), sqlstate);
    end if;
  end;
  return outcome;
end;
$$;

select results_eq(
  $$ select s || ' + ' || a || ' = ' || pg_temp.review_outcome(s, a)
     from unnest(array['draft', 'submitted', 'under_review', 'info_requested', 'approved', 'rejected']) with ordinality as st (s, i)
     cross join unnest(array['start_review', 'request_info', 'approve', 'reject']) with ordinality as ac (a, j)
     order by i, j $$,
  $$ values
     ('draft + start_review = NOT_FOUND'), ('draft + request_info = NOT_FOUND'), ('draft + approve = NOT_FOUND'), ('draft + reject = NOT_FOUND'),
     ('submitted + start_review = under_review'), ('submitted + request_info = INVALID_TRANSITION'), ('submitted + approve = INVALID_TRANSITION'), ('submitted + reject = INVALID_TRANSITION'),
     ('under_review + start_review = INVALID_TRANSITION'), ('under_review + request_info = info_requested'), ('under_review + approve = approved'), ('under_review + reject = rejected'),
     ('info_requested + start_review = INVALID_TRANSITION'), ('info_requested + request_info = INVALID_TRANSITION'), ('info_requested + approve = INVALID_TRANSITION'), ('info_requested + reject = INVALID_TRANSITION'),
     ('approved + start_review = INVALID_TRANSITION'), ('approved + request_info = INVALID_TRANSITION'), ('approved + approve = INVALID_TRANSITION'), ('approved + reject = INVALID_TRANSITION'),
     ('rejected + start_review = INVALID_TRANSITION'), ('rejected + request_info = INVALID_TRANSITION'), ('rejected + approve = INVALID_TRANSITION'), ('rejected + reject = INVALID_TRANSITION') $$,
  'reviewers may only start a submitted review and decide one under review; drafts are invisible'
);

select results_eq(
  $$ select s || ' = ' || pg_temp.submit_outcome(s)
     from unnest(array['draft', 'submitted', 'under_review', 'info_requested', 'approved', 'rejected']) with ordinality as st (s, i)
     order by i $$,
  $$ values ('draft = submitted'), ('submitted = INVALID_TRANSITION'), ('under_review = INVALID_TRANSITION'),
            ('info_requested = submitted'), ('approved = INVALID_TRANSITION'), ('rejected = INVALID_TRANSITION') $$,
  'applicants may submit only a draft or an application that needs changes'
);
select is((select count(*)::int from public.business_applications where applicant_id = '44444444-4444-4444-4444-444444444444'), 0, 'the transition cases leave nothing behind');

select * from finish();
rollback;
