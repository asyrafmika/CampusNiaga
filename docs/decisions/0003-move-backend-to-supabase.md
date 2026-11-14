# 0003: Move the backend from Firebase to Supabase

- **Status:** Accepted
- **Date:** 15 Nov 2026
- **Supersedes:** the backend parts of [0001](0001-technology-stack.md) and [0002](0002-server-mediated-writes-and-query-strategy.md)

## Context

The original design ([ADR 0001](0001-technology-stack.md)) used Firebase. CampusNiaga's trusted server logic (the student check, role changes, approvals, stock and capacity handling) ran in Cloud Functions, and product photos and application documents were to live in Cloud Storage. Both services require Firebase's pay-as-you-go Blaze plan, which needs a payment card on file. That plan isn't available for this project, and without it the core of the system couldn't run outside the developer's laptop.

Supabase offers the same capabilities on its free plan, with no payment card: authentication with email confirmation, a PostgreSQL database with Row Level Security, server-side database functions, Edge Functions (500,000 calls a month), and 1 GB of file storage.

The switch was made at the end of Phase 1's backend work, before any user interface or business module existed, so the cost was limited to the Phase 1 backend and its tests.

## Decision

| Concern | Choice |
|---|---|
| Backend | One Supabase project, region Singapore (`ap-southeast-1`), nearest to USM |
| Data | PostgreSQL tables, `snake_case` names, defined in versioned migrations under `supabase/migrations/` |
| Authorization | Row Level Security on every table; no policy means no access |
| Trusted logic | PostgreSQL functions (`SECURITY DEFINER`, called by the apps over RPC). They check the caller, validate input, change data in one transaction and write the audit log. Edge Functions only for logic that can't run in SQL |
| Roles | Read live from tables on every request: `staff_roles` for reviewers and admins, the confirmed email plus `app_config` for students, `businesses` for approved sellers. No roles in login tokens |
| Clients | Flutter with `supabase_flutter`; the React dashboard with `supabase-js` |
| Tests | pgTAP database tests, run in CI against a local Supabase database |

The five architectural rules of ADR 0001 still hold, translated:

1. **The server is the authority.** Privileged changes happen only in database functions; clients may write only what Row Level Security and column privileges allow.
2. **Privileges come from server-controlled data**, never from a field the client can write. They come from tables, not token claims.
3. **One shared `listings` table** serves personal sellers and approved businesses.
4. **Operations that can conflict run in a transaction** inside a database function, with row locks (`select … for update`).
5. **Opportunity ranking (M4) is deterministic** and versioned.

ADR 0002's decisions, after the move:

| ADR 0002 | Now |
|---|---|
| Listings written only through server functions | Kept: `upsert_listing` and `set_listing_status` database functions |
| Search through a `searchTokens` keyword array | **Replaced** by PostgreSQL full-text search |
| Lazy reservation expiry | Kept |
| M5 figures from Firestore aggregation queries plus a `soldQty` counter | **Replaced** by plain SQL `sum`/`count`/`group by`; no counter needed |
| Admin dashboard imports the Functions' TypeScript types | **Replaced** by types generated from the database schema (`supabase gen types typescript`) |
| Seller-name snapshots on listings; photos resized on the device | Snapshots **dropped** (a join is cheap in SQL); photo resizing kept |

## Consequences

- **Role changes take effect immediately.** Roles are read from tables on every request. This removes the Firebase limitation where a removed role stayed valid in the user's token for up to an hour.
- **Transactions, totals and search are simpler** in SQL than in Firestore, which suits the relational data (orders, campaigns, listings, businesses).
- **Free-plan limits to manage:**
  - The project pauses after one week of inactivity; open it before a demo.
  - The built-in email sender allows about 2 emails an hour, and only to the project team. A custom SMTP sender is needed before students can receive confirmation emails.
  - There are no automatic backups.
- **Local development needs Docker** for a full local Supabase stack. The developer instead tests against the hosted project, and CI runs the database tests in a local stack on GitHub.
- The Firebase project `campusniaga-usm` is no longer used and can be deleted from the Firebase console.
