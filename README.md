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
| 2 Marketplace | Listings, search, reservations, reports | Planned |
| 3 Approval | Business application and reviewer workflow | Planned |
| 4 Business | Storefront, stock, pre-orders, orders | Planned |
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
