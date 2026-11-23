-- Phase 3 pass condition, as one journey: a student submits a business
-- application, the HDC administrator requests information, the student edits
-- and resubmits, and the administrator approves. Business features are refused before
-- approval and available after, and every step is in the history and the
-- audit log.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

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
  ('88888888-8888-8888-8888-888888888888', 'rina@campusniaga.test', now(), '{"name": "Rina"}');
insert into public.staff_roles (user_id, role) values ('88888888-8888-8888-8888-888888888888', 'admin');

-- 1. Ali drafts an application and uploads a document --------------------------------------
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
do $$
declare new_id uuid;
begin
  insert into public.business_applications (business_name, category, description, contact_details, collection_details)
  values ('Ali Bakes', 'Food & Beverage', 'Homemade brownies and cookies, baked fresh every week.', '012-3456789', 'Desasiswa Tekun lobby, 6-8pm')
  returning id into new_id;
  perform set_config('test.app', new_id::text, true);
  perform set_config('test.doc', '11111111-1111-1111-1111-111111111111/' || new_id || '/menu.pdf', true);
end $$;
select ok(public.can_upload_application_document(current_setting('test.doc')), 'Ali may upload a document to his draft');
reset role;
insert into storage.objects (bucket_id, name) values ('application-documents', current_setting('test.doc'));

set local role authenticated;
update public.business_applications set document_paths = array[current_setting('test.doc')];

-- 2. Business features are refused before approval ------------------------------------------
select is(pg_temp.error_reason('select public.get_my_business()'), 'FORBIDDEN', 'before approval, business features are refused');
select is(public.get_my_access() ->> 'is_business_owner', 'false', 'before approval, Ali is not a business owner');

-- 3. Ali submits; Rina starts the review and asks for more information -------------------------
select is(public.submit_business_application(current_setting('test.app')::uuid) ->> 'status', 'submitted', 'Ali submits the application');
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(public.review_business_application(current_setting('test.app')::uuid, 'start_review') ->> 'status', 'under_review', 'Rina starts the review');
select is(public.review_business_application(current_setting('test.app')::uuid, 'request_info', 'Please add your price list to the description.') ->> 'status',
  'info_requested', 'Rina asks for more information');

-- 4. Ali reads the note, edits and resubmits ----------------------------------------------------
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is((select remarks from public.business_applications), 'Please add your price list to the description.', 'Ali sees what to change');
select is(pg_temp.error_reason('select public.get_my_business()'), 'FORBIDDEN', 'still no business features while changes are requested');
update public.business_applications
set description = 'Homemade brownies (RM 3) and cookies (RM 1.50), baked fresh every week.';
select is(public.submit_business_application(current_setting('test.app')::uuid, 'Price list added.') ->> 'status', 'submitted', 'Ali edits and resubmits');

-- 5. Rina reviews again and approves ------------------------------------------------------------
set local request.jwt.claims to '{"sub": "88888888-8888-8888-8888-888888888888", "role": "authenticated"}';
select is(public.review_business_application(current_setting('test.app')::uuid, 'start_review') ->> 'status', 'under_review', 'Rina reviews the resubmission');
do $$ begin
  perform set_config('test.business', public.review_business_application(current_setting('test.app')::uuid, 'approve') ->> 'business_id', true);
end $$;
reset role;

-- 6. The business exists and business features work at once ------------------------------------
select is((select owner_id::text || '/' || name || '/' || status from public.businesses where id = current_setting('test.business')::uuid),
  '11111111-1111-1111-1111-111111111111/Ali Bakes/approved', 'approval creates Ali''s business');
select is((select description from public.businesses where id = current_setting('test.business')::uuid),
  'Homemade brownies (RM 3) and cookies (RM 1.50), baked fresh every week.', 'the business carries the edited details');
set local role authenticated;
set local request.jwt.claims to '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';
select is(public.get_my_business() ->> 'business_id', current_setting('test.business'), 'after approval, business features work');
select is(public.get_my_access() ->> 'is_business_owner', 'true', 'after approval, Ali is a business owner');
select ok(public.owns_business(current_setting('test.business')::uuid), 'Ali can act for the business');
reset role;

-- 7. Every step is in the history and the audit log ---------------------------------------------
select results_eq(
  $$ select from_status || '>' || to_status || ' by ' || actor_role || coalesce(': ' || note, '')
     from public.application_status_history where application_id = current_setting('test.app')::uuid order by id $$,
  $$ values ('draft>submitted by applicant'),
            ('submitted>under_review by admin'),
            ('under_review>info_requested by admin: Please add your price list to the description.'),
            ('info_requested>submitted by applicant: Price list added.'),
            ('submitted>under_review by admin'),
            ('under_review>approved by admin') $$,
  'the history has every step, in order, with who did it'
);
select results_eq(
  $$ select action || ' by ' || actor_id from public.audit_logs
     where target_type = 'business_application' and target_id = current_setting('test.app') order by id $$,
  $$ values ('application.submitted by 11111111-1111-1111-1111-111111111111'),
            ('application.under_review by 88888888-8888-8888-8888-888888888888'),
            ('application.info_requested by 88888888-8888-8888-8888-888888888888'),
            ('application.submitted by 11111111-1111-1111-1111-111111111111'),
            ('application.under_review by 88888888-8888-8888-8888-888888888888'),
            ('application.approved by 88888888-8888-8888-8888-888888888888') $$,
  'the audit log has every step, in order, with who did it'
);

select * from finish();
rollback;
