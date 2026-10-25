---
name: business-registration-workflow
description: Implement or change Module M2 Digital Business Registration & Approval end to end, including the business application lifecycle (draft, submitted, under_review, info_requested, approved, rejected), private document uploads, submitBusinessApplication and reviewBusinessApplication callables, approval effects (business profile creation and businessId claim), suspension and revocation, review history and audit, the mobile Apply/Track/Respond screens, and the web reviewer queue, detail, decision and status summary. Use for any work touching businessApplications, the approval gate, or the reviewer workflow.
---

# M2 business registration workflow

This is a **simulated** university reviewer workflow for the FYP. It is not an official USM/HDC approval, and the UI must say so. It is the only route by which a student gains business capabilities (M3 storefront, pre-orders, M5). Existing businesses go through the same gate.

This skill owns M2's **states, transitions and effects**. Implementation patterns come from `firebase-backend`, `flutter-development` and `react-dashboard`; permission helpers come from `authentication-authorization`.

## Data

`businessApplications/{id}`:
`applicantUid` (immutable), `businessName`, `category`, `description`, `contactDetails`, `collectionDetails`, `documentPaths[]`, `status`, `reviewerUid?`, `remarks?` (latest reviewer note), `statusHistory[]` (`{ from, to, byUid, role, note?, at }`), `createdAt`, `updatedAt`, `submittedAt?`, `decidedAt?`.

`businesses/{id}` (created only on approval): `ownerUid`, `applicationId`, `name`, `description`, `logoPath?`, `pickupDetails`, `status: 'approved' | 'suspended'`.

Documents in Storage: `applications/{applicantUid}/{applicationId}/{fileName}`. PDF, JPEG or PNG; at most 5 MB each and 5 files per application (the limits are configurable in `config/app`).

## State machine (single source: `functions/src/domain/businessApplication.ts`)

| From | To | Actor | Via | Requirements |
|---|---|---|---|---|
| (new) | `draft` | applicant (student) | direct create | `status == 'draft'`, `applicantUid == auth.uid` |
| `draft` | `submitted` | applicant | `submitBusinessApplication` | required fields valid, documents within limits |
| `submitted` | `under_review` | reviewer | `reviewBusinessApplication{action:'start_review'}` | sets `reviewerUid` |
| `under_review` | `info_requested` | reviewer | `...{action:'request_info', note}` | non-empty note |
| `info_requested` | `submitted` | applicant | `submitBusinessApplication` (resubmit) | applicant edited content while `info_requested` |
| `under_review` | `approved` | reviewer | `...{action:'approve', note?}` | approval effects (below) |
| `under_review` | `rejected` | reviewer | `...{action:'reject', note}` | non-empty note |

- `approved` and `rejected` are terminal. Every other transition is rejected with `INVALID_TRANSITION`.
- "Open application" = status not in `{approved, rejected}`. A student may have at most one open non-draft application. `submitBusinessApplication` enforces this with a query inside its transaction and fails with `ALREADY_EXISTS`; rules can't query, so they don't try.
- Each transition appends to `statusHistory`, sets `updatedAt`, and writes `auditLogs` (`action: 'application.<to>'`) **in the same transaction**. History is never edited or deleted.
- The client-visible list of allowed actions (`allowedReviewActions(status)` in admin, `canEdit(status)` in mobile) is derived from this same table.

## Applicant permissions (rules)

- Read: own applications only.
- Create: only as `draft` with the immutable fields set correctly.
- Update directly: **only content fields** (`businessName`, `category`, `description`, `contactDetails`, `collectionDetails`, `documentPaths`) and only while status is `draft` or `info_requested`. Never `status`, `statusHistory`, `reviewerUid`, `remarks` or `applicantUid`.
- Storage: write or delete own files only while the application is `draft`/`info_requested` (check via `firestore.get`); read own files.

## Reviewer permissions

- Read applications in any non-`draft` status (drafts stay private to the applicant), plus their documents through short-lived URLs.
- All decisions go through `reviewBusinessApplication`. Reviewers never write the document directly.
- Status counts for the Status Summary use aggregation queries per status (M2 only. M5 has no application counts).

## Approval effects (inside `reviewBusinessApplication`, action `approve`)

In **one transaction**:
1. Application `under_review` → `approved`, plus `decidedAt`, history and audit.
2. Create `businesses/{newId}` with `ownerUid = applicantUid`, `applicationId`, name, description and pickup details copied from the application, `status: 'approved'`.
3. Update `users/{applicantUid}.roleFlags.business = true` (display mirror).

**After commit** (idempotent, safe to retry): merge the `businessId` claim into the applicant's existing claims and write an in-app notification. The mobile app refreshes the ID token when it sees the application become `approved`.

**Suspension or revocation** (admin, `setBusinessStatus`): `businesses.status = 'suspended'`, remove the `businessId` claim, hide the business's listings from feeds and ordering, write an audit entry. Existing orders stay readable for history.

## UI (handoff required screens)

**Mobile (`features/business/application`):** Apply (form), Draft (save and continue), Upload Documents, Track Status (timeline from `statusHistory`), Respond to Request (shows the reviewer note, allows edits, then resubmit). Business entry points (storefront, campaigns, dashboard) appear only when the `businessId` claim is present.

**Web (`features/applications`):** Reviewer Login, Applications Queue (filter by status, paginated, oldest submitted first), Application Detail (fields, document preview, history), Decision & Notes (start review, request info, approve, reject, with confirmation and a required note where specified), Status Summary (counts per status). Each decision screen shows the prototype disclaimer.

## Workflow

1. Contract first: the `businessApplications` and `businesses` entries in `docs/data-dictionary.md`; `submitBusinessApplication`, `reviewBusinessApplication` and `setBusinessStatus` in `docs/api-contracts.md`.
2. Domain: transition table + `assertTransition` + `allowedReviewActions`, with table-driven tests.
3. Rules: Firestore and Storage rules for applicant and reviewer, with deny tests for everyone else.
4. Callables: submit/resubmit, review actions, approval effects, suspension, with emulator tests.
5. Mobile screens, then web screens (reusing the domain table, not re-deriving it).
6. Run the Phase 3 pass condition below on the emulators with the scenario fixture.

## Phase 3 pass condition (must be automated)

Submit → reviewer requests info → applicant edits and resubmits → reviewer approves. Then assert: the `businesses` doc exists, the claim is set, every step is in `statusHistory` and `auditLogs`, and business-only callables (e.g. create campaign) fail with `FORBIDDEN` **before** approval and succeed after.

## Verification checklist

- [ ] The transition table is the only place that defines allowed moves; every pair is covered by a table-driven test.
- [ ] Applicants can't change status, history or reviewer fields (rules deny tests).
- [ ] Reviewers can't read drafts; students can't read others' applications or documents.
- [ ] Approval creates the business and sets the claim; suspension reverses access; all of it is audited.
- [ ] Reject and request-info require a note; history is append-only.
- [ ] Disclaimer shown on decision and status screens.
