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
| `submit_business_application` | 3 | Applicant | Submit or resubmit an application |
| `review_business_application` | 3 | Reviewer | Start review, request info, approve or reject |
| `set_business_status` | 3 | Admin | Suspend or reinstate a business |
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
| **Output** | `{ user_id, email, email_confirmed, account_status, is_student, is_reviewer, is_admin }` |
| **Errors** | `FORBIDDEN` (no user in the request) · `42501` (signed out) |
| **Notes** | Roles are read live, so the result reflects changes immediately. The apps use it to decide which screens to show; the database still enforces every rule itself |

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
