---
name: business-registration-workflow
description: Implement or change Module M2 Digital Business Registration & Approval end to end, including the business application lifecycle (draft, submitted, under_review, info_requested, approved, rejected), private document uploads, the submit_business_application and review_business_application database functions, approval effects (creating the business), suspension and revocation, status history and audit, the mobile Apply/Track/Respond screens, and the web reviewer queue, detail, decision and status summary. Use for any work touching business_applications, businesses, the approval gate, or the reviewer workflow.
---

# M2 business registration workflow

This is a **simulated** university reviewer workflow for the FYP. It is not an official USM/HDC approval, and the UI must say so. It is the only route by which a student gains business capabilities (M3 storefront, pre-orders, M5). Existing businesses go through the same gate.

This skill owns M2's **states, transitions and effects**. Implementation patterns come from `supabase-backend`, `flutter-development` and `react-dashboard`; permission helpers come from `authentication-authorization`.

## Data

Defined in `docs/data-dictionary.md`:
- `business_applications`
- `application_status_history`: append-only, one row per change
- `businesses`: created only on approval

Documents go in the private `application-documents` bucket at `{applicant_id}/{application_id}/{file}`. They can be PDF, JPEG or PNG, up to `app_config.max_upload_bytes` each and `app_config.max_application_documents` per application.

## State machine (enforced in the database functions)

| From | To | Actor | Via | Requirements |
|---|---|---|---|---|
| (new) | `draft` | applicant (student) | direct insert | `status = 'draft'`, `applicant_id = auth.uid()`, `is_student()` |
| `draft` | `submitted` | applicant | `submit_business_application` | required fields valid, documents within limits |
| `submitted` | `under_review` | reviewer | `review_business_application(action => 'start_review')` | sets `reviewer_id` |
| `under_review` | `info_requested` | reviewer | `… 'request_info'` | non-empty note |
| `info_requested` | `submitted` | applicant | `submit_business_application` (resubmit) | edited while `info_requested` |
| `under_review` | `approved` | reviewer | `… 'approve'` | approval effects (below) |
| `under_review` | `rejected` | reviewer | `… 'reject'` | non-empty note |

- `approved` and `rejected` are terminal. Every other transition fails with `INVALID_TRANSITION`.
- **One open application per student:** a student may have at most one non-draft application not in `{approved, rejected}`. `submit_business_application` checks this while holding a lock and fails with `ALREADY_EXISTS`. A partial unique index on `applicant_id`, covering the open non-draft statuses, backs it up.
- **Every transition** locks the application row (`for update`), checks the move, updates `status`/`updated_at`, inserts a `application_status_history` row and writes `audit_logs` (`application.<to>`), all in the same function. History is never edited or deleted.
- **One definition of allowed actions:** `allowedReviewActions(status)` in admin and `canEdit(status)` in mobile mirror this table. Keep them in one place per client.

## Applicant permissions

- Read: own applications and their history.
- Insert: only as `draft`, as themselves.
- Update directly: only the content columns (column-level grant), and only while `draft` or `info_requested` (policy). Never `status`, `reviewer_id`, `remarks` or `applicant_id`.
- Storage: upload or delete own files only while the application is editable; read own files.

## Reviewer permissions

- Read applications in any non-draft status (drafts stay private), their history, and documents through short-lived signed URLs.
- All decisions go through `review_business_application`; reviewers have no direct write grants.
- The Status Summary counts applications per status with a SQL `count … group by`. This is M2 only; M5 has no application counts.

## Approval effects (inside `review_business_application`, action `approve`)

In the same transaction:
1. Application `under_review` → `approved`, plus `decided_at`, history and audit.
2. Insert into `businesses` with `owner_id = applicant_id`, `application_id`, name, description and pickup details from the application, and `status = 'approved'`.
3. Insert a notification for the applicant.

Business access then follows from `businesses` immediately: `owns_business()` reads it live, so there are no claims to set or tokens to refresh.

**Suspension or revocation** (admin, `set_business_status`): `status = 'suspended'`, the business's listings leave feeds and ordering, and an audit entry is written. Existing orders stay readable for history.

## UI (handoff required screens)

**Mobile (`features/business/application`):**
- Apply (form)
- Draft (save and continue)
- Upload Documents
- Track Status (timeline from the history)
- Respond to Request (shows the reviewer note, allows edits, then resubmit)

Business entry points appear only when `get_my_access()` reports an approved business.

**Web (`features/applications`):**
- Reviewer Login
- Applications Queue (filter by status, paginated, oldest submitted first)
- Application Detail (fields, document preview, history)
- Decision & Notes (start review, request info, approve, reject, with confirmation and a required note where specified)
- Status Summary (counts per status)

Each decision screen shows the prototype disclaimer.

## Workflow

1. Contract first: the data dictionary entries; `submit_business_application`, `review_business_application` and `set_business_status` in `docs/api-contracts.md`.
2. Migration: tables, history, indexes, RLS and column grants, storage policies, functions.
3. pgTAP tests: every transition pair, permissions for applicant/reviewer/others, approval effects (`unit-testing`).
4. Mobile screens, then web screens (mirroring the transition table, not re-deriving it).
5. Run the Phase 3 pass condition below.

## Phase 3 pass condition (must be automated)

Submit → reviewer requests info → applicant edits and resubmits → reviewer approves. Then assert:
- the `businesses` row exists;
- every step is in the history and audit log;
- business-only functions (e.g. create campaign) fail with `FORBIDDEN` **before** approval and succeed after.

## Verification checklist

- [ ] Every (from, to) pair is tested: allowed ones succeed, all others fail with `INVALID_TRANSITION`.
- [ ] Applicants can't change status, history or reviewer columns (privilege tests).
- [ ] Reviewers can't read drafts; students can't read others' applications or documents.
- [ ] Approval creates the business and grants access immediately; suspension removes it; all of it is audited.
- [ ] Reject and request-info require a note; history is append-only.
- [ ] The disclaimer is shown on decision and status screens.
