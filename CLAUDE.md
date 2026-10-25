# CampusNiaga

Integrated marketplace and digital-entrepreneurship platform for Universiti Sains Malaysia (USM) students. Final Year Project (CAT404) prototype.

The engineering source of truth is the **CampusNiaga Implementation Handoff v1.0 (24 Oct 2026)**. Build only what it lists. If this file and the handoff disagree, the handoff wins; update this file to match.

## Product boundaries

Five modules:

| # | Module | Client |
|---|---|---|
| M1 | Student Marketplace Management (listings, search, reservations, reports) | Mobile |
| M2 | Digital Business Registration & Approval (simulated reviewer workflow) | Mobile + Web |
| M3 | Digital Storefront & Business Order Management (stock, pre-orders, orders) | Mobile |
| M4 | Smart Business Opportunity Discovery (deterministic ranking, no ML) | Mobile + Functions |
| M5 | Business Dashboard & Performance Monitoring (estimated, self-reported) | Mobile |

**Never build:** in-app payments, wallets, payment gateways or verification; delivery or courier integration; chat or messaging; ML/LLM recommendations; IoT; USM SSO or official HDC APIs. Approval is a *simulated* reviewer workflow, not an official university decision. Label it that way in the UI.

## Repository layout

```
CampusNiaga/
├─ CLAUDE.md                 shared conventions (this file)
├─ .claude/skills/           task-specific Claude Code skills (see "Skills" below)
├─ firebase.json             Firebase + emulator configuration (Phase 1)
├─ .firebaserc               project aliases (Phase 1)
├─ firebase/                 firestore.rules, storage.rules, firestore.indexes.json
├─ functions/                Cloud Functions, TypeScript (Node 22)
├─ mobile/                   Flutter student app (Dart package name: `mobile`)
├─ admin/                    React + TypeScript reviewer/admin dashboard (Vite)
├─ seed/                     emulator seed scripts and the handoff scenario fixture
└─ docs/                     data-dictionary.md, api-contracts.md, decisions/ (ADRs)
```

Current state (25 Oct 2026): only `mobile/` exists, as an unmodified `flutter create` scaffold. Everything else is created in Phase 1. Do not rename the Dart package `mobile` or change the bundle ID without asking.

## Technology stack and architectural decisions

| Concern | Decision |
|---|---|
| Mobile | Flutter (stable), Dart 3, feature-first layered architecture, `flutter_riverpod` (no code generation), `go_router` |
| Web dashboard | React + TypeScript (strict) on Vite, React Router, MUI, TanStack Query for server state |
| Backend | Firebase Auth, Cloud Firestore, Cloud Storage, Cloud Functions v2 (TypeScript, Node 22, region `asia-southeast1`), FCM (best-effort, late) |
| Validation | `zod` schemas in every callable; client validation is for UX only |
| Tests | `flutter_test` + `mocktail`; Vitest for `functions/` and `admin/`; `@firebase/rules-unit-testing` against the Emulator Suite |
| Firebase project | `campusniaga-usm` (Spark plan for now; Firestore in `asia-southeast1`; Storage and Functions need Blaze before deploying). Used only when the user asks to deploy |
| Local development | Firebase Emulator Suite only. No deploy, no production data, until the user explicitly asks |

Things that cannot change without the user's approval (record them as an ADR in `docs/decisions/`):

1. **The server is the authority.** Roles, approvals, stock, campaign allocation, order transitions, opportunity rankings and audit logs are written only by Cloud Functions (Admin SDK). Clients may write only their own non-privileged fields, as permitted by Security Rules.
2. **Privileges come from custom claims**, set only by trusted code: `student`, `reviewer`, `admin` (booleans) and `businessId` (string, present only for an active approved business). Never derive privilege from a client-writable document field.
3. **Use one shared `listings` collection** for personal and business products (`mode: 'personal' | 'business'`). There is no separate business product-upload module.
4. **Every operation that can conflict runs in a Firestore transaction** inside a callable: reservations, stock decrements, campaign allocation.
5. **M4 is deterministic.** It uses pure, versioned functions; the result stores `algoVersion` and the parameters it used.

## Shared data conventions

- Field names are `camelCase`; collection names are `camelCase` plural (`businessApplications`). Status *values* are `snake_case` strings exactly as in the handoff (`pending_confirmation`, `info_requested`).
- Money is an **integer in sen** (`priceSen`, `totalSen`). Never use floating-point RM in storage or arithmetic. Convert to RM only for display.
- Times are Firestore `Timestamp`. Every document has `createdAt` and `updatedAt`, set with server timestamps.
- Owner IDs (`ownerUid`, `applicantUid`, `buyerUid`, `creatorUid`) can't change after creation.
- Canonical collections: `users`, `listings`, `reservations`, `businessApplications`, `businesses`, `campaigns`, `orders`, `productRequests`, `requestInterests` (doc ID `{requestId}_{uid}`), `opportunities` (doc ID `clusterKey`), `reports`, `auditLogs`, plus the supporting `config` (app settings, such as student email domains) and `notifications` (in-app notices).
- Every status value and field name is defined once in `docs/data-dictionary.md` and mirrored in exactly one file per codebase:
  `mobile/lib/core/domain/` enums, `admin/src/shared/types/domain.ts`, `functions/src/domain/types.ts`. A schema change updates the dictionary and all three files in the same change.
- Callable errors use `HttpsError` with `details.reason` set to one of: `NOT_VERIFIED_STUDENT`, `FORBIDDEN`, `INVALID_INPUT`, `NOT_FOUND`, `INVALID_TRANSITION`, `ITEM_UNAVAILABLE`, `CAPACITY_FULL`, `ALREADY_EXISTS`, `RATE_LIMITED`. Clients map `reason` to a user message in one place.

## Engineering principles

- Apply SOLID principles pragmatically. Keep each module to one responsibility and depend on narrow interfaces, but don't add an abstraction (interface, factory, base class) until a second real implementation or a test double needs it. Dart classes are already implicit interfaces.
- Keep business logic out of UI code. Widgets and React components render state and forward user intent. Rules, state transitions and calculations live in domain or service code that can be tested without UI.
- Every code change is small, compiles, passes analysis and tests, and is limited to the task at hand.
- Preserve existing code and user edits. Read before you edit. Don't reformat or restructure unrelated code. Never overwrite a file you haven't inspected.
- Escape or sanitize user-entered display content. Validate everything server-side.

## Language standards

**Dart:** follow `flutter_lints`, plus `strict-casts`, `strict-inference` and `strict-raw-types` (added to `mobile/analysis_options.yaml` in Phase 1). Files `snake_case.dart`; types `PascalCase`; members `lowerCamelCase`; prefer `final` and `const`; no `dynamic` outside JSON-mapping boundaries.

**TypeScript:** `strict: true`, `noUncheckedIndexedAccess: true`, `exactOptionalPropertyTypes: true`. No `any` (use `unknown` and narrow it), no non-null `!` except right after a check. React components go in `PascalCase.tsx`; other modules are `camelCase.ts`. Use named exports; the only exception is a default export where a tool requires one.

## Development commands

Run from the repository root. Commands marked (P1) work after Phase 1 scaffolding.

| Task | Command |
|---|---|
| Start emulators | `firebase emulators:start --import=./emulator-data --export-on-exit` (P1) |
| Seed emulators | `npm --prefix seed run seed` (P1) |
| Mobile: get, analyze, format check, test | `cd mobile && flutter pub get && flutter analyze && dart format --set-exit-if-changed lib test && flutter test` |
| Mobile: run against emulators | `cd mobile && flutter run --dart-define=USE_EMULATORS=true` (P1) |
| Functions: build / lint / unit tests | `npm --prefix functions run build`, `run lint`, `run test` (P1) |
| Rules + integration tests | `firebase emulators:exec --only auth,firestore,storage,functions "npm --prefix functions run test:emulator"` (P1) |
| Admin: dev / typecheck / lint / test | `npm --prefix admin run dev`, `run typecheck`, `run lint`, `run test` (P1) |

Never run `firebase deploy`, connect to a production project, install global tools, or add dependencies unless the user asks for it in the current task.

## Testing requirements

- Domain logic (state machines, M4 scoring, money and stock arithmetic) must have unit tests for every transition and edge case.
- Every Security Rules change needs a test that it allows the intended actor **and** a test that it denies at least one other actor.
- Every callable needs emulator tests for the success path, an unauthorized caller, invalid input and an invalid transition. Callables that change stock or capacity also need a concurrency test.
- Each build phase is complete only when its handoff pass condition is an automated test (or a documented manual step, if UI-only) that passes.
- Definition of done: format check, analyze/lint, typecheck and tests all pass for every touched package; docs and contracts are updated; nothing is out of scope.

## Build phases

1 Foundation → 2 Marketplace → 3 Approval → 4 Business → 5 Discovery → 6 Dashboard + QA. Implement one phase at a time. Report what was created, the setup commands and the verification result, then **wait for the user's instruction before starting the next phase**.

## Skills

Task-specific guidance lives in `.claude/skills/`. Each skill has one area; this file holds the rules they share.

| Skill | Use for |
|---|---|
| `enterprise-architecture` | Placing new code, module boundaries, cross-tier features, ADRs |
| `flutter-development` | Anything under `mobile/` |
| `react-dashboard` | Anything under `admin/` |
| `firebase-backend` | `functions/`, Firestore/Storage rules, indexes, data model, transactions |
| `authentication-authorization` | Sign-in, student gate, custom claims, roles, route guards, permission rules |
| `unit-testing` | Writing or fixing tests, emulator test setup, fixtures |
| `code-refactoring` | Changing structure without changing behavior |
| `business-registration-workflow` | Module M2 end to end |
