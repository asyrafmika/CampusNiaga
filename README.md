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
| M4 | Smart Business Opportunity Discovery | Mobile + Cloud Functions |
| M5 | Business Dashboard & Performance Monitoring | Mobile |

Payments, delivery, chat and machine-learning recommendations are intentionally out of scope. Buyers and sellers arrange payment and campus pickup themselves.

## Architecture

| Part | Technology | Users |
|---|---|---|
| `mobile/` | Flutter (Dart) | USM students and approved student businesses |
| `admin/` | React + TypeScript (Vite, MUI) | University reviewers and system administrators |
| `functions/` | Firebase Cloud Functions (TypeScript) | Trusted backend logic |
| `firebase/` | Firestore and Storage security rules, indexes | Shared backend configuration |

All clients share one Firebase project (Authentication, Cloud Firestore, Cloud Storage, Cloud Functions). Permissions are enforced on the server, by Security Rules and Cloud Functions, never only by hiding buttons in the UI.

## Repository layout

```
CampusNiaga/
├─ mobile/      Flutter student app
├─ admin/       React reviewer/admin dashboard        (Phase 1)
├─ functions/   Cloud Functions                       (Phase 1)
├─ firebase/    security rules and indexes            (Phase 1)
├─ seed/        emulator test data                    (Phase 1)
└─ docs/        data dictionary, API contracts, architecture decisions
```

## Documentation

- [Data dictionary](docs/data-dictionary.md): collections, fields and status values
- [API contracts](docs/api-contracts.md): Cloud Functions callable by the apps
- [Architecture decisions](docs/decisions/): why the main technical choices were made

## Development status

| Phase | Scope | Status |
|---|---|---|
| 1 Foundation | Project setup, sign-in, USM student check, staff-only web access | In progress |
| 2 Marketplace | Listings, search, reservations, reports | Planned |
| 3 Approval | Business application and reviewer workflow | Planned |
| 4 Business | Storefront, stock, pre-orders, orders | Planned |
| 5 Discovery | Product requests, interest, opportunity ranking | Planned |
| 6 Dashboard + QA | Seller analytics, final testing | Planned |

## Getting started

Prerequisites: Flutter (stable), Node.js 22+, Java 21+ (for the Firebase emulators) and the Firebase CLI.

### Cloud Functions

```bash
cd functions
npm install        # first time only
npm run build      # compile TypeScript to lib/ (the emulator runs lib/)
npm run lint
npm test           # unit tests
npm run test:emulator   # integration tests on the Auth + Firestore emulators
```

Emulator tests always use the project ID `demo-campusniaga`, and refuse to run without the emulators, so they can never touch the real Firebase project.

On Windows, if an emulator run fails with "port taken", a previous Firestore emulator is still running. Free the port in PowerShell:

```powershell
Get-CimInstance Win32_Process -Filter "Name='java.exe'" | Where-Object { $_.CommandLine -like '*cloud-firestore-emulator*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
```

### Firebase emulators

Build the functions first, then from the repository root:

```bash
firebase emulators:start --project demo-campusniaga
```

Open the Emulator UI at http://127.0.0.1:4000. Stop with Ctrl+C. Always pass `--project demo-campusniaga`: a `demo-` project can't reach any real Firebase service, and the Emulator UI shows only the project it was started with.

### Test accounts

The emulators start empty. With them running, open a second terminal and fill them with test data:

```bash
cd seed
npm install        # first time only
npm run seed       # safe to repeat
```

Every account uses the password `CampusNiaga#2026`. These accounts exist only in the emulators.

| Email | Role | Use it to test |
|---|---|---|
| `ali.test@student.usm.my` | Student | Student features |
| `siti.test@student.usm.my` | Student | A second student, e.g. a buyer |
| `reviewer@campusniaga.test` | Reviewer | Web dashboard: reviewing |
| `admin@campusniaga.test` | Admin | Web dashboard: administration |
| `outsider@example.com` | None | Being refused as a non-USM user |

Running the seed again restores these accounts and `config/app`, and leaves everything else alone. It refuses to run against anything but local emulators and a `demo-` project.

More setup steps are added as Phase 1 continues.
