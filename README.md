# CampusNiaga

An integrated student marketplace and digital entrepreneurship platform for Universiti Sains Malaysia (USM) students. Final Year Project prototype (CAT404).

Today, students sell in WhatsApp and Telegram groups, where older listings are hard to find. CampusNiaga brings together one-off personal-item sales and approved student microbusinesses in one place. It also includes an explainable **Smart Business Opportunity Discovery** feature, which compares what students ask for against what is already on sale.

> The business approval workflow is a **simulated** university reviewer process for this prototype. It is not an official USM or HDC approval and is not integrated with any university system.

## Modules

| # | Module | Client |
|---|---|---|
| M1 | Student Marketplace Management | Mobile |
| M2 | Digital Business Registration & Approval | Mobile + Web |
| M3 | Digital Storefront & Business Order Management | Mobile |
| M4 | Smart Business Opportunity Discovery | Mobile + database |
| M5 | Business Dashboard & Performance Monitoring | Mobile |

Payments, delivery, chat and machine-learning recommendations are intentionally out of scope. Buyers and sellers arrange payment and campus pickup themselves.

## Architecture

| Part | Technology | Users |
|---|---|---|
| `mobile/` | Flutter (Dart) | USM students and approved student businesses |
| `admin/` | React + TypeScript (Vite, MUI) | University reviewers and system administrators |
| `supabase/` | Supabase: PostgreSQL, Row Level Security, database functions, Auth, Storage | Trusted backend |

Both apps use one Supabase project. Permissions are enforced in the database by Row Level Security and database functions, never only by hiding buttons in the UI. Roles are checked live on every request. See [ADR 0003](docs/decisions/0003-move-backend-to-supabase.md) for why the backend is Supabase.

## Repository layout

```
CampusNiaga/
├─ mobile/      Flutter student app
├─ admin/       React reviewer/admin dashboard
├─ supabase/    migrations, database tests, CLI config
└─ docs/        data dictionary, API contracts, architecture decisions
```

## Documentation

- [Data dictionary](docs/data-dictionary.md): tables, columns, status values and storage buckets
- [API contracts](docs/api-contracts.md): the database functions the apps call
- [Architecture decisions](docs/decisions/): why the main technical choices were made

## Development status

| Phase | Scope | Status |
|---|---|---|
| 1 Foundation | Project setup, sign-in, USM student check, staff-only web access | Done |
| 2 Marketplace | Listings, search, reservations, reports | Done |
| 3 Approval | Business application and reviewer workflow (simulated) | Done |
| 4 Business | Storefront, stock, pre-orders, orders | Done |
| 5 Discovery | Product requests, interest, opportunity ranking | Planned |
| 6 Dashboard + QA | Seller analytics, final testing | Planned |

### Phase 1 check

The handoff's Phase 1 pass condition is that a USM student gets in, a non-USM email is refused, and a student can't open staff features. These automated tests prove it, and CI runs them on every pull request:

| Part | Test | What it proves |
|---|---|---|
| Database | `supabase/tests/database/04_phase1_pass_condition.test.sql` | The whole journey: sign up, held until the email is confirmed, then let in; a confirmed gmail account refused; the student can't grant itself a role or read staff data; a role given by an admin works on the next request and its removal does too, both audited |
| Mobile | `mobile/test/app_navigation_test.dart` | A verified student reaches home; a non-USM account stops at "CampusNiaga is for USM students"; a suspended account stops at "Account suspended" |
| Admin | `admin/src/features/auth/components/RequireStaff.test.tsx` | A student who signs in to the dashboard is signed out with a "staff only" message; a reviewer can't open admin pages |

The rules are enforced by the database, so the database test is the one that matters most; the app tests check that each app shows the right screen for the answer it gets.

### Phase 2 check

The handoff's Phase 2 pass condition is that a student publishes an item, a second student finds and reserves it, a simultaneous reservation cannot double-book it, and the seller marks it sold.

| Part | Test | What it proves |
|---|---|---|
| Database | `supabase/tests/database/08_phase2_pass_condition.test.sql` | The journey: Ali publishes a calculator with a photo; Siti finds it by searching and reserves it; Amin's request for the same item is refused (`ITEM_UNAVAILABLE`); Ali accepts, Siti then sees Ali's email, and Ali marks it collected, which sells it |
| Database, two connections | `supabase/tests/concurrency/reservation_race.sh` | Two buyers reserve the last unit at the same moment on separate connections. The second waits for the first's row lock, then is refused; exactly one reservation exists |
| Database | `05_listings`, `06_reservations`, `07_moderation` | Every rule on its own: who may list, reserve, resolve, report and moderate; stock never goes below zero; expiry returns units; contact details stay hidden until acceptance |
| Mobile | `mobile/test/features/marketplace/` | The screens: browse, search and filter, reserve (with quantity), refused reservations show the reason, publish, the listing form, accept a request, report, profile |
| Admin | `admin/src/features/moderation/pages/ModerationPage.test.tsx` | Hide a listing, suspend a seller, dismiss a report |

### Phase 3 check

The handoff's Phase 3 pass condition is: submit → reviewer requests edits → applicant edits and resubmits → approve; business features are unavailable before approval; every change is audited. The approval is a **simulated** reviewer workflow for the FYP, not an official USM/HDC decision, and both apps say so.

| Part | Test | What it proves |
|---|---|---|
| Database | `supabase/tests/database/11_phase3_pass_condition.test.sql` | The journey: Ali drafts an application with a document and submits it; the reviewer starts the review and asks for a price list; Ali reads the note, edits and resubmits with a reply; the reviewer approves. `get_my_business()` refuses Ali (`FORBIDDEN`) until approval and works straight after; the business row exists; the status history and the audit log both hold all six steps in order, with who did each |
| Database | `09_business_applications`, `10_businesses` | Every (status, action) pair: allowed moves succeed, every other one fails with `INVALID_TRANSITION`. Applicants can't change status, reviewer or dates; drafts stay private from staff; other students see nothing; documents follow the same rules; reject and request-info need a note; no second business; suspension removes business access at once and reinstating restores it; the status summary counts by status |
| Mobile | `mobile/test/features/business/application/` | Apply, save a draft, upload a document, submit; respond to a request for changes and resubmit with a reply; the timeline; approved and rejected states; refused submissions show the reason |
| Admin | `admin/src/features/applications/` | The queue and status summary; only the decisions the state machine allows; a note is required to request changes or reject; approval is confirmed with the disclaimer; reviewers can't decide their own application; admins suspend a business |

### Phase 4 check

The handoff's Phase 4 pass condition is: an approved seller creates a storefront, a product and a campaign; two buyers cannot exceed the remaining stock or capacity; cancellations free the quantity.

| Part | Test | What it proves |
|---|---|---|
| Database | `supabase/tests/database/14_phase4_pass_condition.test.sql` | The journey: before approval Ali can't list business products or set up a storefront; the reviewer approves; Ali sets up the storefront, lists a 2-unit brownie box and opens a capacity-3 pre-order. Siti takes both boxes and Amin is refused (`ITEM_UNAVAILABLE`); Siti pre-orders 2, Amin can't take 2 (`CAPACITY_FULL`) but takes the last place, and a fourth is refused. Siti cancels both: the boxes are back on sale and 2 places free up, and Amin gets them. Units ordered plus stock left always equal 2, and pre-ordered units always equal the allocation |
| Database, two connections | `supabase/tests/concurrency/order_race.sh` | Two buyers order the last unit, then the last pre-order place, at the same moment on separate connections. Each time the second waits for the first's row lock and is refused; exactly one order each |
| Database | `12_business_listings`, `13_campaigns_orders` | Every rule on its own: only approved businesses list business products, suspension removes them from the feed and the storefront at once, business products can't be reserved, every campaign and order limit (stock, capacity, per-order limit, dates), every (status, action) pair for orders, who may read campaigns and orders, contact emails only after confirmation |
| Mobile | `mobile/test/features/business/store/` | Order from stock or a pre-order (capped by what is left and the per-order limit), the storefront, a sold-out product, refused orders, cancel from My orders; the business confirms orders, opens and creates pre-orders, edits its storefront and adds business products |

## Getting started

Prerequisites: Flutter (stable) with an Android emulator, and Node.js 22+ (only for running the Supabase CLI with `npx`).

### 1. Create the Supabase project (once)

1. Sign in at [supabase.com](https://supabase.com) and create a project named **CampusNiaga**, region **Southeast Asia (Singapore)**. Save the database password in a password manager; it is never stored in this repository.
2. **Authentication → Sign In / Providers → Email:** keep it enabled, with **Confirm email** on. CampusNiaga only treats confirmed `@student.usm.my` addresses as students.
3. **Authentication → URL Configuration → Redirect URLs:** add `campusniaga://auth-callback`. Links in confirmation and password-reset emails then open the app.
4. **Authentication → Emails → SMTP Settings:** turn on custom SMTP. Supabase's built-in sender allows about 2 emails an hour and only to your project team, so students can't receive confirmation emails without it. A Gmail account with an app password works for a prototype (host `smtp.gmail.com`, port `465`).

### 2. Apply the database migrations

From the repository root:

```bash
npx supabase@2.122.0 login
npx supabase@2.122.0 link --project-ref <your-project-ref>
npx supabase@2.122.0 db push
```

The project ref is the part of the project URL before `.supabase.co`. `db push` applies every migration in `supabase/migrations/` that the project doesn't have yet.

### 3. Make yourself an admin

Sign up in the app first (step 4), then in the dashboard's **SQL Editor** run:

```sql
insert into public.staff_roles (user_id, role)
select id, 'admin' from auth.users where email = 'your.email@student.usm.my';
```

After that, grant reviewer and admin roles from the admin dashboard's **Users & Roles** page (step 5). Each change is written to the audit log.

### 4. Run the mobile app

1. In the dashboard, open **Project Settings → API** (Project URL) and **API Keys** (the **publishable** key). Paste both into `mobile/lib/core/config/supabase_config.dart`. The publishable key is designed to be public. Never paste the secret / `service_role` key.
2. Start an Android emulator and run the app:

```bash
flutter emulators --launch Pixel_9
cd mobile
flutter pub get    # first time only
flutter run
```

The first launch shows the onboarding slides, then **Sign in**. Use **Create an account** with your USM email and confirm it from your inbox. If you open the link on the phone, it signs you in straight away; otherwise, sign in after confirming.

Once signed in, the bottom bar has **Home** (newest listings and categories), **Search** (words, filters, sorting), **Sell** (the listing form: up to 5 photos from the camera or gallery, resized on the phone), **Reservations** (buying and selling) and **Profile** (My Listings, sign out). Payment and pickup are arranged between the students; the app never takes payments.

**Images:** put these in `mobile/assets/images/`; until then the app shows placeholders.

| File | Where | Format |
|---|---|---|
| `onboarding_1.jpg`, `onboarding_2.jpg`, `onboarding_3.jpg` | The three onboarding slides | Portrait photos, about 1080 px wide |

Checks:

```bash
cd mobile
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
```

### 5. Run the admin dashboard

The web dashboard is for reviewers and admins. It uses the same Supabase project; its URL and publishable key are in `admin/src/shared/supabase/client.ts`.

```bash
cd admin
npm install        # first time only
npm run dev        # open http://localhost:5173
```

Sign in with a staff account (step 3). A student account is signed out with a "staff only" message. Checks: `npm run typecheck`, `npm run lint`, `npm test`. See [admin/README.md](admin/README.md) for its pages and structure.

You don't need to run the dashboard to use the mobile app, or the other way round: both talk to the hosted Supabase project directly.

### Database tests

The pgTAP tests in `supabase/tests/database/` run in GitHub Actions on every pull request, against a throwaway local Supabase database. Running them locally needs Docker (`npx supabase@2.122.0 start`, then `npx supabase@2.122.0 test db`).

### Free-plan notes

- A free project **pauses after a week without activity**. Open the dashboard and restore it before a demo.
- The free plan has no automatic backups.
