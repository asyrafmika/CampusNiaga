# API contracts

The server functions the mobile app and admin dashboard call. They are PostgreSQL functions in Supabase, called over RPC (`supabase.rpc('name', {...})`). Data shapes are in the [data dictionary](data-dictionary.md).

Anything that grants privileges, changes another user's data, or could conflict with another user (stock, capacity, reservations) goes through one of these functions. Each one checks the caller, validates its input and makes its changes, including the audit entry, in a single transaction.

## Errors

A refused call fails with SQL state `P0001`. Its `details` field holds one of the reasons below, and clients map each reason to a user-facing message. Calls the caller isn't allowed to make at all (for example, signed out) fail with SQL state `42501`.

| `details` | Meaning |
|---|---|
| `NOT_VERIFIED_STUDENT` | Signed in, but not a verified USM student |
| `FORBIDDEN` | Not signed in, lacks the required role, or doesn't own the resource |
| `INVALID_INPUT` | Input failed validation |
| `NOT_FOUND` | A referenced record doesn't exist |
| `INVALID_TRANSITION` | The status change isn't allowed from the current status |
| `ITEM_UNAVAILABLE` | Listing no longer available, or stock ran out |
| `CAPACITY_FULL` | Pre-order capacity reached |
| `ALREADY_EXISTS` | Duplicate, e.g. an existing active reservation or open application |
| `RATE_LIMITED` | Too many requests in a short time |

## Functions

| Function | Phase | Caller | Purpose |
|---|---|---|---|
| `get_my_access` | 1 ✅ | Signed-in user | What the user may do: student, reviewer, admin, account status |
| `set_staff_role` | 1 ✅ | Admin | Grant or remove the reviewer / admin role |
| `listing_categories` | 2 ✅ | Signed-in user | The categories a listing may use |
| `upsert_listing` | 2 ✅ | Student (business mode from Phase 4: approved business owner) | Create or edit a listing; validates, rate-limits, sets derived fields |
| `set_listing_status` | 2 ✅ | Listing owner | Publish a draft, close or re-open a listing, or mark it sold |
| `search_listings` | 2 ✅ | Student | The marketplace feed: search, filters, sort, pages |
| `get_listing` | 2 ✅ | Student, owner, admin | One listing for the detail page |
| `request_reservation` | 2 ✅ | Student | Reserve units of a listing; holds them at once |
| `resolve_reservation` | 2 ✅ | Seller / buyer | Accept, decline, cancel or mark collected |
| `my_reservations` | 2 ✅ | Student | My Reservations, buying or selling side |
| `report_listing` | 2 ✅ | Student | Report a listing to the admins |
| `moderate_listing` | 2 ✅ | Admin | Hide or restore a listing |
| `dismiss_report` | 2 ✅ | Admin | Close a report without action |
| `set_account_status` | 2 ✅ | Admin | Suspend or reactivate an account |
| `submit_business_application` | 3 ✅ | Applicant | Submit or resubmit an application |
| `review_business_application` | 3 ✅ | Reviewer, admin | Start review, request info, approve or reject |
| `application_status_summary` | 3 ✅ | Reviewer, admin | Number of applications in each status |
| `set_business_status` | 3 ✅ | Admin | Suspend or reinstate a business |
| `get_my_business` | 3 ✅ | Business owner | The caller's business; refused before approval |
| `place_order` | 4 | Student | Order ready stock or join a pre-order campaign |
| `transition_order` | 4 | Business owner / buyer | Move an order through its statuses, or cancel it |
| `toggle_request_interest` | 5 | Student | Add or remove interest in a product request |
| `recompute_opportunities` | 5 | Server (triggers) | Recalculate the M4 opportunity ranking |

Each function's full contract is added below when it is implemented.

---

## `get_my_access()`

| | |
|---|---|
| **Caller** | Any signed-in user |
| **Input** | None. Everything is read on the server from the caller's account |
| **Output** | `{ user_id, email, email_confirmed, account_status, is_student, is_reviewer, is_admin, is_business_owner, business_status }` |
| **Errors** | `FORBIDDEN` (no user in the request) · `42501` (signed out) |
| **Notes** | Roles are read live, so the result reflects changes immediately. The apps use it to decide which screens to show; the database still enforces every rule itself. `is_business_owner` (Phase 3) is true when the user is a verified student with an `approved` business; `business_status` is that business's status (`approved` or `suspended`), or `null` without one |

`is_student` is true when the email is confirmed, the address's domain exactly matches one of `app_config.student_email_domains` (default `student.usm.my`) or the address is in `app_config.test_allowlist`, and the account is `active`. Matching is case-insensitive; sub-domains and look-alike domains don't match. Unlike the earlier Firebase design, there is no separate "sync" call: student status is worked out on every request.

## `set_staff_role(target_user_id uuid, role text, enabled boolean)`

| | |
|---|---|
| **Caller** | Admin |
| **Input** | `target_user_id`: an existing account · `role`: `reviewer` or `admin` · `enabled`: grant (`true`) or remove (`false`) |
| **Output** | `{ user_id, role, enabled, changed }`. `changed` is `false` when the user already had (or already lacked) the role |
| **Errors** | `FORBIDDEN` (not an admin, or an admin removing their own admin role) · `INVALID_INPUT` · `NOT_FOUND` · `42501` (signed out) |
| **Side effects** | When `changed`: adds or removes the `staff_roles` row and writes audit entry `role.granted` or `role.revoked` with `metadata.role` |
| **Timing** | Takes effect on the user's next request; there is no token to expire |

## `listing_categories()`

| | |
|---|---|
| **Caller** | Any signed-in user |
| **Output** | `text[]`, from `app_config.categories` (which only admins can read directly, because it also holds the test allowlist) |

## `upsert_listing(listing_id, title, description, category, price_sen, condition, quantity, photo_paths, pickup_area)`

| | |
|---|---|
| **Caller** | Verified student. Editing: the listing's owner |
| **Input** | `listing_id`: `null` to create, or the listing to edit · `title`: 3–80 characters after trimming · `description`: up to 1,000 characters · `category`: one of `listing_categories()` · `price_sen`: 0–10,000,000 · `condition`: `new`, `like_new`, `good` or `fair` · `quantity`: units for sale, 1–999 (stored as `stock`) · `photo_paths`: up to 5 paths `{owner_id}/{listing_id}/{file}` ending in `.jpg`, `.jpeg`, `.png` or `.webp` · `pickup_area`: 2–80 characters |
| **Output** | `{ listing_id, status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` · `FORBIDDEN` (not the owner) · `INVALID_TRANSITION` (reserved or sold listings can't be edited) · `RATE_LIMITED` (more than 20 new listings in an hour) · `42501` (signed out) |
| **Derived on the server** | `owner_id` (the caller), `mode` (`personal`), `status` (`draft` on create, unchanged on edit), `normalized_title`, `search_vector` |
| **Notes** | Photos are stored under the listing's id, so the app creates the draft first (no photos), uploads, then calls again with the paths. A published listing must keep at least one photo |

## `set_listing_status(listing_id uuid, new_status text)`

| | |
|---|---|
| **Caller** | Verified student who owns the listing |
| **Allowed changes** | `draft` → `available` (needs a photo) or `closed` · `available` → `closed` or `sold` · `closed` → `available`. `reserved` changes through reservations |
| **Output** | `{ listing_id, status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (unknown status, or publishing without a photo) · `NOT_FOUND` · `FORBIDDEN` · `INVALID_TRANSITION` · `42501` |
| **Side effects** | `sold` sets `stock` to 0 (every remaining unit went, for example sold outside the app) |

## `search_listings(search, category, condition, min_price_sen, max_price_sen, sort, page_size, page_offset)`

| | |
|---|---|
| **Caller** | Verified student |
| **Input** (all optional) | `search`: web-search syntax (`calculator -broken`, `"desk lamp"`), matched with English word forms against title, description and category · `category`, `condition`: exact match · `min_price_sen`, `max_price_sen`: inclusive · `sort`: `newest` (default), `price_asc`, `price_desc` or `relevance` · `page_size`: 1–50 (default 20) · `page_offset`: 0 or more |
| **Output** | Rows of `listing_card`: `id, owner_id, seller_name, mode, title, description, category, price_sen, condition, photo_paths, stock, pickup_area, status, created_at` |
| **Shows** | `available` listings that aren't hidden, from sellers whose account is active. Ties sort newest first |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (sort or page) · `42501` |
| **Why a function** | Profiles are private, so a plain table read can't show the seller's name. The function returns only the name, nothing else about the seller |

## `get_listing(listing_id uuid)`

| | |
|---|---|
| **Caller** | Verified student or admin |
| **Output** | One `listing_card` row |
| **Shows** | Students: any listing that isn't a draft, isn't hidden and whose seller is active. The owner: their own listings in any status. Admins: everything |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` (missing or not visible to the caller) · `42501` |

## `request_reservation(listing_id uuid, qty integer default 1, pickup_note text default null)`

| | |
|---|---|
| **Caller** | Verified student who doesn't own the listing |
| **Input** | `qty`: 1–999 · `pickup_note`: up to 200 characters, optional |
| **Output** | `{ reservation_id, status: 'requested', expires_at }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` (missing or draft) · `FORBIDDEN` (own listing) · `ITEM_UNAVAILABLE` (not available, hidden, seller suspended, or fewer units left than asked; the message says how many are left) · `ALREADY_EXISTS` (an active reservation on this listing already) · `RATE_LIMITED` (more than 10 in an hour) · `42501` |
| **Side effects** | Locks the listing, expires its overdue reservations, takes `qty` out of `stock` (the listing becomes `reserved` at 0) and notifies the seller |
| **Concurrency** | Requests for the same listing run one at a time behind the row lock, so they can never hold more units than exist. CI proves this with two real connections (`supabase/tests/concurrency/reservation_race.sh`) |

## `resolve_reservation(reservation_id uuid, action text)`

| | |
|---|---|
| **Caller** | The seller (`accept`, `decline`, `collect`) or either side (`cancel`) |
| **Allowed** | `accept`, `decline`: from `requested` · `cancel`: from `requested` or `accepted` · `collect`: from `accepted` |
| **Output** | `{ reservation_id, status, listing_status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (unknown action) · `NOT_FOUND` · `FORBIDDEN` (not a party, or the buyer trying a seller action) · `INVALID_TRANSITION` (wrong status, or expired) · `42501` |
| **Side effects** | `accept` gives 7 days to collect. `decline` and `cancel` return the units. `collect` sells the listing when no stock and no other active reservation remain. Notifies the other party |

## `my_reservations(side text default 'buying')`

| | |
|---|---|
| **Caller** | Verified student |
| **Input** | `side`: `buying` or `selling` |
| **Output** | Rows of `reservation_card`: `id, listing_id, listing_title, listing_photo, pickup_area, price_sen, qty, pickup_note, status, expires_at, created_at, updated_at, i_am_buyer, other_party_name, other_party_email`. Active ones first, then newest |
| **Privacy** | `other_party_email` is filled only once the reservation is `accepted` or `collected`; until then each side sees only the other's name |
| **Side effects** | Expires the caller's overdue reservations first |

## `report_listing(listing_id uuid, reason text, details text default '')`

| | |
|---|---|
| **Caller** | Verified student who doesn't own the listing |
| **Input** | `reason`: `prohibited_item`, `scam`, `offensive`, `misleading` or `other` (needs details) · `details`: up to 500 characters |
| **Output** | `{ report_id, status: 'open' }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` (missing or draft) · `FORBIDDEN` (own listing) · `ALREADY_EXISTS` (an open report on it already) · `RATE_LIMITED` (more than 10 a day) · `42501` |

## `moderate_listing(listing_id uuid, hide boolean, note text default null)`

| | |
|---|---|
| **Caller** | Admin |
| **Output** | `{ listing_id, hidden, changed }` |
| **Errors** | `FORBIDDEN` · `INVALID_INPUT` · `NOT_FOUND` · `42501` |
| **Side effects** | When `changed`: sets `listings.hidden`, writes audit `listing.hidden` or `listing.restored` and notifies the owner. Hiding also closes the listing's open reports as `actioned` / `listing_hidden`. A hidden listing leaves the feed and can't be reserved; its owner and admins still see it |

## `dismiss_report(report_id uuid, note text default null)`

| | |
|---|---|
| **Caller** | Admin |
| **Output** | `{ report_id, status: 'reviewed' }` |
| **Errors** | `FORBIDDEN` · `INVALID_INPUT` · `NOT_FOUND` · `INVALID_TRANSITION` (already closed) · `42501` |
| **Side effects** | The report becomes `reviewed` / `dismissed`; audit `report.dismissed` |

## `set_account_status(user_id uuid, account_status text, note text default null)`

| | |
|---|---|
| **Caller** | Admin, for someone else's account |
| **Input** | `account_status`: `active` or `suspended` |
| **Output** | `{ user_id, account_status, changed }` |
| **Errors** | `FORBIDDEN` (not an admin, or their own account) · `INVALID_INPUT` · `NOT_FOUND` · `42501` |
| **Side effects** | When `changed`: updates the profile and writes audit `account.suspended` or `account.reactivated`. Suspending closes open reports about the user as `actioned` / `account_suspended`. Takes effect on the user's next request: a suspended account fails the student check, can't trade, and its listings leave the feed |

## Business applications (M2)

The approval is a **simulated** reviewer workflow for the FYP, not an official USM decision; both apps say so. The applicant creates and edits a draft directly (Row Level Security and column privileges allow only that), uploads documents to `application-documents/{applicant_id}/{application_id}/`, and changes status only through the functions below. Every status change locks the application row, inserts an `application_status_history` row and writes audit entry `application.<new status>`, all in one transaction.

## `submit_business_application(application_id uuid, response_note text default null)`

| | |
|---|---|
| **Caller** | Verified student who owns the application |
| **Allowed** | `draft` → `submitted`, and `info_requested` → `submitted` (a resubmission after edits) |
| **Checks** | Business name 3–80 characters · category one of `listing_categories()` · description 20–1,000 · contact details 5–200 · collection details 5–200 · documents: no more than `app_config.max_application_documents`, no duplicates, each `{caller}/{application_id}/{file}.pdf\|jpg\|jpeg\|png` and already uploaded · `response_note`: up to 500 characters, kept in the history |
| **Output** | `{ application_id, status: 'submitted' }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (the message names the field) · `NOT_FOUND` · `FORBIDDEN` (not the applicant) · `INVALID_TRANSITION` (already submitted, under review or decided) · `ALREADY_EXISTS` (the caller already has a business, or another open application) · `42501` |
| **Side effects** | `submitted_at` = now; history row (`actor_role` `applicant`, note = `response_note`); audit `application.submitted` with `metadata.from` |

## `review_business_application(application_id uuid, action text, note text default null)`

| | |
|---|---|
| **Caller** | Reviewer or admin, not on their own application |
| **Actions** | `start_review`: `submitted` → `under_review` · `request_info`: `under_review` → `info_requested` (note required) · `approve`: `under_review` → `approved` · `reject`: `under_review` → `rejected` (note required) |
| **Input** | `note`: up to 1,000 characters; required (not blank) for `request_info` and `reject`, optional otherwise |
| **Output** | `{ application_id, status, business_id }`. `business_id` is set only by `approve` |
| **Errors** | `FORBIDDEN` (not staff, or own application) · `INVALID_INPUT` (unknown action, missing or long note) · `NOT_FOUND` (missing, or still a draft) · `INVALID_TRANSITION` · `ALREADY_EXISTS` (approve: the applicant already has a business) · `42501` |
| **Side effects** | `reviewer_id` = caller; `remarks` = the note when one is given; `decided_at` on approve and reject. History row (`actor_role` `reviewer` or `admin`); audit `application.<status>`; notification `application_<status>` to the applicant |
| **Approval** | In the same transaction, inserts the `businesses` row (`owner_id` = applicant, name, description, `pickup_details` = collection details, `status` `approved`). Business access follows immediately: `owns_business()` and `get_my_access()` read the table live, so there is no token to refresh |

## `application_status_summary()`

| | |
|---|---|
| **Caller** | Reviewer or admin |
| **Output** | Rows `{ status, total }`, one for each of `submitted`, `under_review`, `info_requested`, `approved`, `rejected`, in that order, including zeros. Drafts are private and not counted |
| **Errors** | `FORBIDDEN` · `42501` |

## `set_business_status(business_id uuid, status text, note text default null)`

| | |
|---|---|
| **Caller** | Admin |
| **Input** | `status`: `approved` (reinstate) or `suspended` · `note`: up to 500 characters |
| **Output** | `{ business_id, status, changed }` |
| **Errors** | `FORBIDDEN` · `INVALID_INPUT` · `NOT_FOUND` · `42501` |
| **Side effects** | When `changed`: updates the business, writes audit `business.suspended` or `business.reinstated` and notifies the owner. A suspended business fails `owns_business()` at once, so every business-only function refuses it. From Phase 4 its listings also leave the feed and can't be ordered; existing orders stay readable |

## `get_my_business()`

| | |
|---|---|
| **Caller** | Verified student with a business |
| **Output** | `{ business_id, application_id, name, description, pickup_details, status, created_at }`. A suspended business is returned too, so the app can explain it |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` (no business: not applied, or not approved yet) · `42501` |

## Helpers

`owns_business(business_id uuid) → boolean`: the caller is a verified student, owns that business, and it is `approved`. Phase 4 functions call it first. `is_staff() → boolean`: the caller has any `staff_roles` row (reviewer or admin); used by the review-queue policies. Storage policies use `can_upload_application_document(name)` and `can_read_application_document(name)`.
