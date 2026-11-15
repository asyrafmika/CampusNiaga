# CampusNiaga

Integrated marketplace and digital-entrepreneurship platform for Universiti Sains Malaysia (USM) students. Final Year Project (CAT404) prototype.

The engineering source of truth is the **CampusNiaga Implementation Handoff v1.0 (24 Oct 2026)**. Build only what it lists. If this file and the handoff disagree, the handoff wins; update this file to match. One deliberate exception: the backend is **Supabase instead of Firebase** ([ADR 0003](docs/decisions/0003-move-backend-to-supabase.md)); read the handoff's Firebase terms through that ADR.

## Product boundaries

Five modules:

| # | Module | Client |
|---|---|---|
| M1 | Student Marketplace Management (listings, search, reservations, reports) | Mobile |
| M2 | Digital Business Registration & Approval (simulated reviewer workflow) | Mobile + Web |
| M3 | Digital Storefront & Business Order Management (stock, pre-orders, orders) | Mobile |
| M4 | Smart Business Opportunity Discovery (deterministic ranking, no ML) | Mobile + database |
| M5 | Business Dashboard & Performance Monitoring (estimated, self-reported) | Mobile |

**Never build:** in-app payments, wallets, payment gateways or verification; delivery or courier integration; chat or messaging; ML/LLM recommendations; IoT; USM SSO or official HDC APIs. Approval is a *simulated* reviewer workflow, not an official university decision. Label it that way in the UI.

## Repository layout

```
CampusNiaga/
├─ CLAUDE.md                 shared conventions (this file)
├─ .claude/skills/           task-specific Claude Code skills (see "Skills" below)
├─ supabase/
│  ├─ config.toml            Supabase CLI configuration (local stack used by CI)
│  ├─ migrations/            versioned SQL: tables, Row Level Security, database functions
│  └─ tests/database/        pgTAP tests (`supabase test db`)
├─ mobile/                   Flutter student app (Dart package name: `mobile`)
├─ admin/                    React + TypeScript reviewer/admin dashboard (Vite)
└─ docs/                     data-dictionary.md, api-contracts.md, decisions/ (ADRs)
```

Current state (15 Nov 2026): Phase 1 complete; Phase 2 (marketplace) is next. The backend moved to Supabase (ADR 0003). `supabase/` holds the Phase 1 migration (profiles, student check, staff roles, app settings, audit log) and its tests; `04_phase1_pass_condition.test.sql` is the Phase 1 pass condition as one journey (README "Phase 1 check"). `admin/` is the staff dashboard (Dabang purple, Poppins): staff login that signs out non-staff, Overview, Users & Roles (`set_staff_role`), Audit Log; see `admin/README.md`. `mobile/` uses `supabase_flutter`, Riverpod and go_router, with a bright navy theme (primary `#3B66C4`, amber accent, bundled Montserrat; layouts from the Nestora and Pixel Market references). Navigation is driven by `get_my_access()` and the onboarding flag through `features/auth` (`redirectFor`): splash, first-launch onboarding, sign in and create account (separate pages: brand navy gradient with blurred aurora glows, amber-accented headline, frosted-glass form card, white button; `features/auth/presentation/widgets/auth_layout.dart` and `auth_style.dart`), forgot/reset password, verify email, not eligible, suspended, then home (a placeholder until the Phase 2 marketplace, which follows the Nestora home layout). Email links use the deep link `campusniaga://auth-callback`. The Android app ID is `com.asyrafmika.campusniaga`. Do not rename the Dart package `mobile` or change the app ID without asking.

## Technology stack and architectural decisions

| Concern | Decision |
|---|---|
| Mobile | Flutter (stable), Dart 3, feature-first layered architecture, `flutter_riverpod` (no code generation), `go_router`, `supabase_flutter` |
| Web dashboard | React + TypeScript (strict) on Vite, React Router, MUI, TanStack Query, `supabase-js` with types generated from the database |
| Backend | Supabase: Auth, PostgreSQL with Row Level Security, database functions called over RPC, Storage; Edge Functions only for logic SQL can't do. Hosted project in Singapore (`ap-southeast-1`) |
| Validation | Inside the database functions and table `check` constraints; client validation is for UX only |
| Tests | pgTAP database tests (`supabase/tests/database/`), run by CI on a local Supabase; `flutter_test` + `mocktail`; Vitest for `admin/` |
| Development | The user develops and tests against the hosted Supabase project (they are its only user). Automated tests never touch it: they run in CI's throwaway local database |

Things that cannot change without the user's approval (record them as an ADR in `docs/decisions/`):

1. **The server is the authority.** Roles, approvals, stock, campaign allocation, order transitions, opportunity rankings and audit logs change only inside database functions. Clients may write only what Row Level Security and column privileges allow, which is their own non-privileged data.
2. **Privileges come from server-controlled tables, read live on every request:** `staff_roles` (reviewer, admin), the confirmed email plus `app_config` (student), `businesses` (approved seller). Never from a client-writable column, and never from login-token claims.
3. **One shared `listings` table** for personal and business products (`mode` `personal` | `business`). There is no separate business product-upload module.
4. **Every operation that can conflict runs in one transaction inside a database function**, locking the rows it checks (`select … for update`): reservations, stock, campaign allocation.
5. **M4 is deterministic.** Pure, versioned rules; each result stores `algo_version` and its parameters.

## Shared data conventions

- Tables are plural, columns `snake_case`. Status values are `snake_case` text exactly as in the handoff (`pending_confirmation`, `info_requested`), enforced with `check` constraints.
- Money is an **integer in sen** (`price_sen`, `total_sen`). Never use floating-point RM in storage or arithmetic. Convert to RM only for display.
- Times are `timestamptz`. Every table has `created_at`; changeable tables have `updated_at`, kept by the `set_updated_at` trigger.
- Owner columns (`owner_id`, `applicant_id`, `buyer_id`, `creator_id`) can't change after creation.
- Every table, column and status value is defined in `docs/data-dictionary.md`. A schema change adds a migration and updates the dictionary in the same commit, and updates the Dart mirror in `mobile/lib/core/domain/` when the app uses it.
- Listings are written only through `upsert_listing` / `set_listing_status`. Search uses PostgreSQL full-text search, reservations expire lazily, and M5 uses SQL aggregates.
- Refused function calls raise SQL state `P0001` with the reason in the error's `details`: `NOT_VERIFIED_STUDENT`, `FORBIDDEN`, `INVALID_INPUT`, `NOT_FOUND`, `INVALID_TRANSITION`, `ITEM_UNAVAILABLE`, `CAPACITY_FULL`, `ALREADY_EXISTS`, `RATE_LIMITED` (via `public.raise_app_error`). Clients map the reason to a user message in one place.

### Database rules for every migration

- Enable Row Level Security on every new table. Revoke what clients mustn't do (`revoke all … from anon, authenticated`), then grant only what a policy covers. Grant column-level `update (…)` when users may change only some columns.
- Write privileged logic as `security definer` functions with `set search_path = ''` and schema-qualified names. Check the caller first, then validate input, then act; write the audit entry in the same function.
- New functions are executable by everyone by default: always `revoke execute … from public, anon`, then grant to `authenticated` only if apps call it. Internal helpers and trigger functions get no grants.
- In policies, call helper functions as `(select public.is_admin())` so they run once per query.
- Never edit a migration that has been applied to the hosted project; add a new one.

## Engineering principles

- Apply SOLID principles pragmatically. Keep each module to one responsibility and depend on narrow interfaces, but don't add an abstraction (interface, factory, base class) until a second real implementation or a test double needs it. Dart classes are already implicit interfaces.
- Keep business logic out of UI code. Widgets and React components render state and forward user intent. Rules, state transitions and calculations live in the database functions or in domain code that can be tested without UI.
- Every code change is small, compiles, passes analysis and tests, and is limited to the task at hand.
- Preserve existing code and user edits. Read before you edit. Don't reformat or restructure unrelated code. Never overwrite a file you haven't inspected.
- Escape or sanitize user-entered display content. Validate everything server-side.

## Language standards

**SQL:** lowercase keywords, `snake_case`, schema-qualified names (`public.profiles`), one migration per change, comments explaining security decisions.

**Dart:** `flutter_lints` plus `strict-casts`, `strict-inference` and `strict-raw-types` (in `mobile/analysis_options.yaml`). Files `snake_case.dart`; types `PascalCase`; members `lowerCamelCase`; prefer `final` and `const`; no `dynamic` outside JSON-mapping boundaries.

**TypeScript:** `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`. No `any` (use `unknown` and narrow it), no non-null `!` except right after a check. React components go in `PascalCase.tsx`; other modules are `camelCase.ts`. Use named exports; the only exception is a default export where a tool requires one.

## Development commands

Run from the repository root.

| Task | Command |
|---|---|
| Mobile: get, analyze, format check, test | `cd mobile && flutter pub get && flutter analyze && dart format --set-exit-if-changed lib test && flutter test` |
| Mobile: run | Start an Android emulator (`flutter emulators --launch Pixel_9`), then `cd mobile && flutter run`. The app connects to the hosted project in `mobile/lib/core/config/supabase_config.dart` |
| Apply migrations to the hosted project | `npx supabase@2.122.0 link --project-ref <ref>` once, then `npx supabase@2.122.0 db push`. **This changes the real database: only when the user asks** |
| Database tests | Run by CI (`supabase db start` then `supabase test db`). Locally they need Docker, which this machine doesn't have |
| Admin: dev / typecheck / lint / test | `npm --prefix admin run dev`, `run typecheck`, `run lint`, `run test` |

Never run `db push`, change hosted-project settings, install global tools, or add dependencies unless the user asks for it in the current task. Never put the `service_role` key or database password in the repository; the publishable key in `supabase_config.dart` is meant to be public.

## Testing requirements

- Every migration ships with pgTAP tests. Each Row Level Security policy and each privilege needs a test that the intended user is allowed **and** a test that at least one other user (another student, a reviewer, signed out) is refused.
- Every database function needs tests for success, an unauthorized caller, invalid input and, for state changes, an invalid transition. Functions that change stock or capacity also need a test proving the limit can't be exceeded.
- Domain logic (state machines, M4 scoring, money and stock arithmetic) must have tests for every transition and edge case.
- Each build phase is complete only when its handoff pass condition is an automated test (or a documented manual step, if UI-only) that passes.
- Definition of done: format check, analyze/lint and tests pass for every touched package; CI's database job passes; docs and contracts are updated; nothing is out of scope.

## Build phases

1 Foundation → 2 Marketplace → 3 Approval → 4 Business → 5 Discovery → 6 Dashboard + QA. Implement one phase at a time. Report what was created, the setup commands and the verification result, then **wait for the user's instruction before starting the next phase**.

## Skills

Task-specific guidance lives in `.claude/skills/`. Each skill has one area; this file holds the rules they share.

| Skill | Use for |
|---|---|
| `enterprise-architecture` | Placing new code, module boundaries, cross-tier features, ADRs |
| `flutter-development` | Anything under `mobile/` |
| `react-dashboard` | Anything under `admin/` |
| `supabase-backend` | `supabase/`: migrations, tables, Row Level Security, database functions, storage, transactions |
| `authentication-authorization` | Sign-up, email confirmation, the student check, staff roles, route guards, permission rules |
| `unit-testing` | Writing or fixing tests: pgTAP, Flutter, React |
| `code-refactoring` | Changing structure without changing behavior |
| `business-registration-workflow` | Module M2 end to end |
