# Test plan and results

This is the Phase 6 quality-assurance record for CampusNiaga: what was tested, how, and the result. It covers the three kinds of testing the handoff asks for (section 9, Phase 6): **functional**, **scenario** and **usability**. Functional and scenario testing are automated and run on every pull request. Usability testing needs real students; its kit is in [usability-test-kit.md](usability-test-kit.md), and its results are recorded there once the sessions have been run.

Results are as of 16 Nov 2026, branch `phase6/dashboard-qa`, from the CI run on GitHub Actions.

## 1. Summary

| Suite | Where | What it runs on | Result |
|---|---|---|---|
| Database (pgTAP) | `supabase/tests/database/` (20 files) | A fresh local Supabase stack started by CI (Supabase CLI 2.122.0), with every migration applied | **870 / 870 passed** |
| Concurrency | `supabase/tests/concurrency/` (2 scripts) | Two real database connections at the same moment | **2 / 2 passed** |
| Mobile (Flutter) | `mobile/test/` | `flutter test`: unit tests and widget tests through the real router, with in-memory repositories | **194 / 194 passed** |
| Admin dashboard (React) | `admin/src/**/*.test.ts(x)` | Vitest with React Testing Library | **67 / 67 passed** |
| Static checks | CI | `flutter analyze` and `dart format`; TypeScript `tsc --noEmit`, ESLint, production build; `supabase db lint` | **All clean** |

Automated tests never touch the hosted Supabase project; they run in CI's throwaway database.

## 2. How the tests were checked to be meaningful (mutation testing)

A passing test only matters if it would fail when the code is wrong. For each phase from 3 onwards, deliberate bugs were planted in the code one at a time (for example: removing a permission check, counting a student twice, letting stock go negative, dropping the "estimated" label), and the tests were run against each.

| Phase | Bugs planted | Caught | Notes |
|---|---|---|---|
| 3 Approval (database) | 27 | 27 | |
| 4 Business (database) | 37 | 36 | The one miss removes a check that a second check already makes, so behaviour is unchanged |
| 4 Business (mobile) | 4 | 4 | |
| 5 Discovery (database) | 32 | 32 | One test was added during this exercise (the supply cap) when a bug first went unnoticed |
| 5 Discovery (mobile) | 3 | 3 | |
| 6 Dashboard (database) | 15 | 15 | Two tests were strengthened during this exercise (a range boundary, product ordering) |
| 6 Dashboard (mobile) | 3 | 3 | |

Writing the tests also found real defects, fixed before release: number tiles that clipped their text, buttons that stretched across a row, and a cost dialog that released its text field while still closing.

## 3. Functional testing: requirements to tests

Each requirement from the handoff maps to the automated tests that prove it. "DB" files are in `supabase/tests/database/`.

### Access and roles (sections 2 and 7)

| Requirement | Tests |
|---|---|
| Only verified USM students (confirmed email, `student.usm.my` or the test allowlist, active account) can trade | DB `01`, `02`, `04`; mobile `test/app_navigation_test.dart` |
| Reviewer and admin roles come from server tables and take effect at once; students can't grant themselves roles | DB `03`, `04` |
| Staff-only web access: students are signed out of the dashboard; reviewers can't open admin pages | admin `RequireStaff.test.tsx`, `navigation.test.tsx` |
| Hiding buttons is never the security: every rule is enforced by the database | Every DB file tests refused callers (other student, reviewer, signed out, suspended) as well as the allowed one |

### M1 Student Marketplace (section 4)

| Requirement | Tests |
|---|---|
| Shared listing form (title, description, category, photos, RM price, condition, quantity, pickup, mode) with server validation | DB `05`, `12`; mobile `marketplace_screens_test.dart` |
| Searchable feed with category, price and condition filters; detail page with seller or storefront attribution | DB `05`, `12`; mobile `marketplace_screens_test.dart` |
| Lifecycle draft → available → reserved → sold; the seller can edit or close | DB `05`, `06` |
| One active reservation per buyer per item; seller accepts or declines; only needed contact details are shared, after acceptance | DB `06`, `08` |
| A simultaneous reservation can't double-book | DB `08`; `concurrency/reservation_race.sh` |
| Users report listings; admins hide listings or suspend accounts; history is kept | DB `07`; admin `ModerationPage.test.tsx` |

### M2 Business Registration & Approval (section 4)

| Requirement | Tests |
|---|---|
| Application with name, category, description, contact and collection details, optional documents | DB `09`; mobile `application_screens_test.dart` |
| States draft → submitted → under_review → info_requested / approved / rejected; every other move refused | DB `09` (all 24 status-action pairs) |
| Edit and resubmit after a request for changes; history, notes and times kept | DB `09`, `11` |
| Only a reviewer action approves and creates the business; suspension is server-side | DB `10`, `11` |
| Students see only their applications; drafts stay private; documents are private | DB `09` |
| Reviewer queue, detail, decisions and status counts, labelled as a simulated workflow | admin `ApplicationsPage.test.tsx`, `ApplicationDetailPage.test.tsx` |

### M3 Storefront & Orders (section 5)

| Requirement | Tests |
|---|---|
| Storefront with name, logo, description, categories, pickup details | DB `12`; mobile `store_screens_test.dart` |
| Only approved businesses publish business products; personal items are reserved, business products ordered | DB `12`, `13` |
| Ready stock is never oversold | DB `13`, `14`; `concurrency/order_race.sh` |
| Pre-order campaigns: dates, price, per-order limit, capacity, pickup, draft / open / closed | DB `13` |
| Pending and later orders hold capacity; cancellation releases it; capacity is never exceeded | DB `13`, `14`; `concurrency/order_race.sh` |
| Orders move pending_confirmation → confirmed → preparing → ready_for_pickup → completed; cancellation before completion | DB `13` (all 30 status-action pairs) |
| Payment and collection happen outside the app | Mobile screens show the notice; there is no payment code |

### M4 Opportunity Discovery (section 5)

| Requirement | Tests |
|---|---|
| Product requests with name, category, preferred price, campus area, notes; one interest per student per request | DB `15`; mobile `discovery_test.dart` |
| Text normalised; similar requests cluster by category and curated synonyms | DB `15`, `17` |
| Demand counts distinct students; supply counts visible matching listings and sellers; median prices compared | DB `16`, `17` |
| Ranked by the handoff heuristic, explained by counts and prices, "insufficient data" below 2 students, version stored | DB `16`, `17` |
| Labelled "possible opportunity"; visible to all verified students | DB `16`; mobile `discovery_test.dart` |

### M5 Business Dashboard (section 5)

| Requirement | Tests |
|---|---|
| Orders by status, completed sales, estimated revenue, entered costs, estimated profit, top products, stock and campaign overview | DB `18`, `19`; mobile `dashboard_test.dart` |
| Filter by date | DB `18`; mobile `dashboard_test.dart` |
| Never another seller's data | DB `18`, `19` (and the function takes no business id) |
| Labelled estimated / self-reported | mobile `dashboard_test.dart` |

## 4. Phase pass conditions (handoff section 9)

| Phase | Pass condition | Automated proof |
|---|---|---|
| 1 Foundation | Auth + verified-student gate; staff-only web access | DB `04`; mobile `app_navigation_test.dart`; admin `RequireStaff.test.tsx` |
| 2 Marketplace | Publish, find, reserve; no double booking; seller marks sold | DB `08`; `reservation_race.sh` |
| 3 Approval | Submit → request edits → resubmit → approve; no business features before; all audited | DB `11` |
| 4 Business | Storefront, product, campaign; two buyers can't exceed stock or capacity; cancellation frees quantity | DB `14`; `order_race.sh` |
| 5 Discovery | Synonyms cluster, one student once, supply lowers the score, price gap matters, reasons match | DB `17` |
| 6 Dashboard + QA | Completed orders update the analytics; seller A can't read B's data; functional, scenario and usability tests | DB `19`; this document; [usability-test-kit.md](usability-test-kit.md) |

## 5. Scenario testing

`supabase/tests/database/20_end_to_end_scenario.test.sql` runs the handoff's minimal scenario fixture through all five modules in one go: 2 students, 1 applicant, 1 approved business seller, 1 reviewer and 1 admin; 2 personal listings, 2 business products, a capacity-3 pre-order, three similar requests ("brownie", "brownies", "chocolate brownie") and a competing listing. It follows the three cross-module flows of the handoff:

- **Casual:** student → personal listing → reservation (a second buyer is refused) → collection → sold.
- **Business:** apply → reviewer requests edits → resubmit → approve (all audited) → storefront and products → order (no overselling) and pre-order (capacity full at 3) → every order status → dashboard (estimated revenue and profit), with the other business seeing none of it.
- **Discovery:** three requests form one cluster, three distinct students however many taps, the competing listing lowers the score, the price gap adds to it, the reasons say so, and hiding the listing removes it from supply at once.

Result: **33 / 33 passed**.

## 6. What is not automated

| Area | Why | How it is checked |
|---|---|---|
| Running on a real phone against the hosted project | Needs a signed-in human and the emulator | The manual checklist below |
| Email delivery (sign-up confirmation, password reset) | Depends on the email provider | Checked by hand when the accounts were created (Phase 1) |
| Uploads to the hosted Storage buckets | Tests use the local stack; Storage policies are tested through their helper functions | The manual checklist below |
| Usability | Needs real participants | [usability-test-kit.md](usability-test-kit.md) |

### Manual end-to-end checklist (Android emulator, hosted project)

Use three accounts: two students (one becomes the business owner) and one staff account with the reviewer role. Tick each step.

| # | Step | Expected | Done |
|---|---|---|---|
| 1 | Sign up with a USM address; open the confirmation email | The app lets you in after confirming | ☐ |
| 2 | Sign up with a non-USM address | "CampusNiaga is for USM students" | ☐ |
| 3 | Student A lists an item with a photo and publishes it | It appears in student B's feed and search | ☐ |
| 4 | Student B reserves it; A accepts and marks it collected | B sees A's email after acceptance; the item becomes sold | ☐ |
| 5 | B reports another listing; admin hides it in the dashboard | It leaves the feed; the audit log shows it | ☐ |
| 6 | A applies for a business with a document; reviewer requests changes; A resubmits; reviewer approves | The timeline shows every step; A's My business shows the store | ☐ |
| 7 | A edits the storefront (logo), adds a product, opens a pre-order | B sees the storefront, the product and the pre-order | ☐ |
| 8 | B orders and pre-orders; A confirms, prepares, readies and completes the order, and records a cost | B is notified at each step; A's dashboard shows the sale and estimated profit | ☐ |
| 9 | B requests "brownies"; A taps Interested | Discover shows a possible opportunity with 2 students and its reasons | ☐ |
| 10 | Admin suspends A's business | A's products and storefront disappear for B; A sees the suspension | ☐ |
