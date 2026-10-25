# 0001: Technology stack and architecture

- **Status:** Accepted
- **Date:** 26 Oct 2026

## Context

CampusNiaga needs a student mobile app, a web dashboard for university reviewers and administrators, and a backend that enforces permissions for a marketplace, a business-approval workflow, order handling and an opportunity-ranking feature. It's a Final Year Project built by one developer, so it needs low operational overhead and strong local testing, while staying secure.

## Decision

| Concern | Choice |
|---|---|
| Student app | Flutter, Dart 3, feature-first layered folders, `flutter_riverpod` without code generation, `go_router` |
| Reviewer/admin dashboard | React + TypeScript (strict) on Vite, React Router, MUI, TanStack Query |
| Backend | One Firebase project, `campusniaga-usm`: Authentication, Cloud Firestore, Cloud Storage, Cloud Functions v2 (TypeScript, Node 22) |
| Region | `asia-southeast1` (Singapore), the nearest region to USM |
| Validation | `zod` schemas in every Cloud Function |
| Testing | Firebase Emulator Suite; Vitest; `@firebase/rules-unit-testing`; `flutter_test` with `mocktail` |

Architectural rules:

1. **The server is the authority.** Roles, approvals, stock, campaign allocation, order transitions, rankings and audit logs are written only by Cloud Functions. Clients write only their own non-privileged data, as Security Rules permit.
2. **Privileges come from custom claims** (`student`, `reviewer`, `admin`, `businessId`) set by trusted code, never from a client-writable field.
3. **One shared `listings` collection** serves personal sellers and approved businesses.
4. **Operations that can conflict run in Firestore transactions** inside Cloud Functions.
5. **Opportunity ranking (M4) is deterministic** and versioned, with no machine learning.

## Consequences

- No servers to manage. The emulators let the whole system run and be tested locally without cost or risk to real data.
- Cloud Functions and Cloud Storage need the Firebase Blaze plan in the real project. The free usage allowance covers prototype use.
- Business logic sits in Cloud Functions rather than in the apps, so it is enforced the same way for both clients and can be tested independently.
- Firestore's query limits shape the data model: counts and rankings are precomputed, and every list is paginated.
