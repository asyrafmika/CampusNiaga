# CampusNiaga

Integrated marketplace and digital-entrepreneurship platform for Universiti Sains Malaysia (USM) students. Final Year Project (CAT404) prototype.

The engineering source of truth is the **CampusNiaga Implementation Handoff v1.0 (24 Oct 2026)**. Build only what it lists. If this file and the handoff disagree, the handoff wins; update this file to match. One deliberate exception: the backend is **Supabase instead of Firebase** ([ADR 0003](docs/decisions/0003-move-backend-to-supabase.md)); read the handoff's Firebase terms through that ADR.

## Product boundaries

Five modules:

| # | Module | Client |
|---|---|---|
| M1 | Student Marketplace Management (listings, search, chat and Buy now, reports) | Mobile |
| M2 | Digital Business Registration & Approval (simulated reviewer workflow) | Mobile + Web |
| M3 | Digital Storefront & Business Order Management (stock, pre-orders, orders) | Mobile |
| M4 | Smart Business Opportunity Discovery (deterministic ranking, no ML) | Mobile + database |
| M5 | Business Dashboard & Performance Monitoring (estimated, self-reported) | Mobile + Web (admins, ADR 0007) |

**Never build:** in-app payments, wallets, payment gateways or verification (the one exception is [ADR 0005](docs/decisions/0005-transfer-payments.md): a buyer pays the seller's own bank account or QR outside the app and uploads a receipt that the seller accepts or rejects; CampusNiaga never holds or moves money); delivery or courier integration; general chat or messaging (the one exception is text chat about a personal item with its seller ([ADR 0006](docs/decisions/0006-buy-now.md)) or between the two sides of a confirmed order ([ADR 0004](docs/decisions/0004-deal-chat.md))); ML/LLM recommendations; IoT; USM SSO or official HDC APIs. Approval is a *simulated* reviewer workflow, not an official university decision. Label it that way in the UI.

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
├─ admin/                    React + TypeScript HDC administrator dashboard (Vite)
└─ docs/                     data-dictionary.md, api-contracts.md, decisions/ (ADRs)
```

Current state (23 Nov 2026): read the history below with these later changes, which override it. **Buy now** ([ADR 0006](docs/decisions/0006-buy-now.md), `20261123000000_buy_now`) replaced reservations: `purchases` through `buy_item`, `complete_purchase`, `cancel_purchase`, `relist_purchase` and `my_purchases`; units leave stock at Confirm purchase and the listing is `sold` at 0 (no `reserved` status, no seller accept, no email shared); cash is never released automatically, a transfer only while it has no receipt; `open_conversation(listing_id | order_id | purchase_id)` gives one item chat per listing and student, before buying, while order chats are unchanged; `deal_payments.purchase_id` replaced `reservation_id`; pgTAP 06 and 08, `purchase_race.sh`; in the app `PurchaseRules`, `PurchaseRepository` and the Purchases tab. **Admin business performance** ([ADR 0007](docs/decisions/0007-admin-business-performance.md), `20261123000100_admin_business_performance`): `admin_business_performance_list` and `admin_business_performance` (admins only, audited, never cost or profit) share `business_figures` with `business_dashboard`; `orders.cost_sen` is not selectable (grant any new `orders` column explicitly); `admin/src/features/performance`; pgTAP 25. **Listing payment step and delete** ([ADR 0008](docs/decisions/0008-listing-payment-and-delete.md), `20261123000200_delete_listings`): a personal listing's form goes on to "How buyers pay you" (`ListingPaymentScreen`, the shared `PaymentDetailsForm`), which publishes; Profile has no payment details (a business's are in My store); listings are deleted (status `deleted`, soft and final, shown only to the owner, admins and buyers) instead of closed; pgTAP 26. **One staff role** ([ADR 0009](docs/decisions/0009-single-admin-role.md), `20261123000300_single_admin_role`): only `staff_roles.role = 'admin'` (the HDC administrator), who also reviews applications; `is_reviewer()` and `get_my_access().is_reviewer` are gone; existing reviewers became administrators (audited); old history keeps `actor_role` `reviewer`; `business_applications.reviewer_id` is now `admin_id` (`20261123000400_rename_reviewer_id`); the dashboard has one guard and one role switch. History: Phases 1-6 complete (usability sessions with students still to be run by the user, using `docs/qa/usability-test-kit.md`). The backend moved to Supabase (ADR 0003). `supabase/` holds the Phase 1 migration (profiles, student check, staff roles, app settings, audit log) and its tests; `04_phase1_pass_condition.test.sql` is the Phase 1 pass condition as one journey (README "Phase 1 check"). Phase 2 added three migrations (listings with full-text search and the private `listing-photos` bucket; reservations that hold units from the request, under a row lock, with lazy expiry and in-app notifications; reports and admin moderation), pgTAP files 05-08, and a two-connection race test (`supabase/tests/concurrency/reservation_race.sh`, run by CI). Personal listings have a quantity (`stock` = units still for sale). Phase 3 added `20261116000300_business_approval` (business applications with a draft → submitted → under_review → info_requested / approved / rejected state machine, append-only status history, `businesses` created only on approval, the private `application-documents` bucket, `owns_business(business_id)` for Phase 4 to call first, `get_my_business()`, `application_status_summary()`, `set_business_status()`; `get_my_access()` now also returns `is_business_owner` and `business_status`) and pgTAP 09-11 (11 is the pass condition). A student has at most one unfinished application and one business; staff can't review their own application. Phase 4 added `20261116000400_business_storefront_orders`: business-mode listings (`upsert_listing(..., mode)`, approved businesses only), business attribution in `listing_card` (`business_id`, `business_name`) and suspended businesses dropped from the feed, a trigger that keeps reservations for personal items, `get_storefront` / `update_storefront` with the private `business-logos` bucket, pre-order `campaigns` (`upsert_campaign`, `set_campaign_status`) and `orders` (`place_order`, `transition_order`, `my_orders`). Quantity is held at ordering under a row lock on the listing (ready stock) or the campaign (pre-order) and returned on cancellation; pgTAP 12-14 (14 is the pass condition) and `supabase/tests/concurrency/order_race.sh` (CI). Phase 5 added `20261116000500_opportunity_discovery`: `product_requests` and `request_interests` (written through `create_product_request`, `close_product_request`, `toggle_request_interest`; read through `list_product_requests`, which never names anyone), and the derived `opportunities` table, recomputed by triggers through `recompute_opportunities()`. Text rules: `discovery_terms()` (stop words, curated `discovery_synonyms`, simple singulars); a request's cluster is `{category}|{head term}`; the score is the handoff heuristic with `algo_version` `m4-v1` and stored `params`. pgTAP 15-17 (17 is the pass condition). Phase 6 added `20261116000600_business_dashboard`: `set_order_cost` (the seller's own cost per order, never shown to buyers) and `business_dashboard(from_at, to_at)` (SQL aggregates over the caller's own business; it takes no business id), with `my_orders` returning `cost_sen` on the selling side; pgTAP 18-20 (19 is the pass condition, 20 the end-to-end scenario with the handoff fixture). QA records live in `docs/qa/`. After the handoff, the deal chat ([ADR 0004](docs/decisions/0004-deal-chat.md)) added `20261117000000_deal_chat`: `conversations` (one per reservation or order) and `messages`, written only through `open_conversation`, `send_message`, `mark_conversation_read`, `close_conversation`, `report_conversation`, read by the two participants (RLS, Supabase Realtime on `messages`), with chat reports in `reports.conversation_id` and `get_reported_conversation` for admins (audited); pgTAP 21-22. `20261119000000_transfer_payments` (ADR 0005) added `payment_details` (a student's, and optionally their business's, bank account and/or QR in the private `payment-qr` bucket; only the owner reads them) and `deal_payments` (one per transfer order or reservation: `awaiting_proof` with a 30-minute `due_at`, `submitted` with a screenshot in the private `payment-proofs` bucket, then `accepted` / `rejected` by the seller, or `expired` / `cancelled`). `request_reservation` and `place_order` take `payment_method` (`cash` | `transfer`); `set_payment_details`, `seller_accepts_transfer`, `get_payment`, `submit_payment_proof` and `review_payment` drive it; accepting confirms the order or accepts the reservation, rejecting or missing the deadline releases the units (`orders.cancelled_by` gains `system`); search, listing, storefront, My Orders, Bookings and the payment page sweep overdue payments first (`expire_overdue_payments`, skip-locked); pgTAP 24. In the app, `features/payments` holds Payment details (Profile, and My store for the business), the cash/transfer choice in the order screen and reserve sheet, and the payment page for both sides, with writes through `PaymentActions`. `20261118000000_pickup_pins` added optional map pins (`pickup_lat`, `pickup_lng`, both or neither, inside Malaysia) to `listings` (through `upsert_listing`, returned in `listing_card`) and `businesses` (through `update_storefront`, returned by `get_my_business` and `get_storefront`); pgTAP 23. `admin/` is the staff dashboard (Dabang purple, Poppins): staff login that signs out non-staff, Overview, Applications (queue, detail, decisions, status summary), Reports & Moderation, Users & Roles (`set_staff_role`, `set_account_status`), Audit Log; see `admin/README.md`. `mobile/` uses `supabase_flutter`, Riverpod and go_router, with the USM brand from the CampusNiaga logo (`docs/brand/`: USM purple primary `#5B2A86`, gold accent `#F5B301`, deep purple `#1E0F2E` for the splash and launch screens; logo mark `assets/images/logo_mark.png` via `core/widgets/app_logo.dart`; adaptive Android launcher icon; bundled Montserrat; layouts from the Nestora and Pixel Market references). Navigation is driven by `get_my_access()` and the onboarding flag through `features/auth` (`redirectFor`): splash, first-launch onboarding, sign in and create account (separate pages: deep purple gradient with blurred aurora glows, gold-accented headline, frosted-glass form card, white button; `features/auth/presentation/widgets/auth_layout.dart` and `auth_style.dart`), forgot/reset password, verify email, not eligible, suspended, then the signed-in app: a bottom bar (Home, Search, Sell, Reservations, Profile) over `features/marketplace` (Nestora-style home feed, search with filters, listing detail with reserve and report, listing form with `image_picker` photos, My Listings, My Reservations). `features/business/application` holds the M2 screens (Track Status, Apply, Upload Documents via `file_picker`, Respond to Request), reached from Profile, with writes through `ApplicationActions`. `features/business/store` holds M3: the Storefront, the Order screen (ready stock or a pre-order; the listing detail links to it, business products aren't reserved), My Orders (buying, and the business's orders), and the owner's My store (storefront editing, business products through the shared listing form in business mode, pre-orders), with writes through `StoreActions`. `features/discovery` holds M4 (Discover from Home and Profile: ranked possible opportunities with their reasons, the opportunity page, requests with Interested, My requests, the request form), with writes through `DiscoveryActions`. `features/chat` holds the deal chat (Messages from Profile, the chat screen opened from Bookings and My orders; live messages through `ChatController`, closing and reporting through `ChatActions`). The bottom bar's reservations tab is called Bookings. Pickup pins use `core/domain/geo_point.dart` (`GeoPoint`, `PickupPinRules`, `UsmCampus`) and `core/widgets/pickup_map.dart` (OpenStreetMap through `flutter_map`, no API key: preview, full-screen view with Directions via `url_launcher`, the pin picker and `PickupPinField`); tests turn tiles off with `mapTilesEnabledProvider`. `features/dashboard` holds M5 (from My store: period filter, estimated figures labelled self-reported, orders by status, top products, stock, pre-order capacity); costs are recorded from My Orders through `StoreActions.setOrderCost`. Marketplace writes go through `MarketplaceActions`; repositories map database errors to `AppFailure` in `core/supabase/supabase_guard.dart`. Email links use the deep link `campusniaga://auth-callback`. The Android app ID is `com.asyrafmika.campusniaga`. Do not rename the Dart package `mobile` or change the app ID without asking.

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
2. **Privileges come from server-controlled tables, read live on every request:** `staff_roles` (admin: the HDC administrator, the one staff role, ADR 0009), the confirmed email plus `app_config` (student), `businesses` (approved seller). Never from a client-writable column, and never from login-token claims.
3. **One shared `listings` table** for personal and business products (`mode` `personal` | `business`). There is no separate business product-upload module.
4. **Every operation that can conflict runs in one transaction inside a database function**, locking the rows it checks (`select … for update`): purchases, stock, campaign allocation.
5. **M4 is deterministic.** Pure, versioned rules; each result stores `algo_version` and its parameters.

## Shared data conventions

- Tables are plural, columns `snake_case`. Status values are `snake_case` text exactly as in the handoff (`pending_confirmation`, `info_requested`), enforced with `check` constraints.
- Money is an **integer in sen** (`price_sen`, `total_sen`). Never use floating-point RM in storage or arithmetic. Convert to RM only for display.
- Times are `timestamptz`. Every table has `created_at`; changeable tables have `updated_at`, kept by the `set_updated_at` trigger.
- Owner columns (`owner_id`, `applicant_id`, `buyer_id`, `creator_id`) can't change after creation.
- Every table, column and status value is defined in `docs/data-dictionary.md`. A schema change adds a migration and updates the dictionary in the same commit, and updates the Dart mirror in `mobile/lib/core/domain/` when the app uses it.
- Listings are written only through `upsert_listing` / `set_listing_status`. Search uses PostgreSQL full-text search, unpaid transfers expire lazily, and M5 uses SQL aggregates.
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

- Every migration ships with pgTAP tests. Each Row Level Security policy and each privilege needs a test that the intended user is allowed **and** a test that at least one other user (another student, a role-less staff account, signed out) is refused.
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
