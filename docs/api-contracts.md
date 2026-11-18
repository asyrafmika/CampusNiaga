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
| `upsert_listing` | 2 ✅, 4 ✅, pins | Student (business mode: approved business owner) | Create or edit a listing, with an optional map pin; validates, rate-limits, sets derived fields |
| `set_listing_status` | 2 ✅ | Listing owner | Publish a draft, close or re-open a listing, or mark it sold |
| `search_listings` | 2 ✅ | Student | The marketplace feed: search, filters, sort, pages (expires overdue transfer holds first) |
| `get_listing` | 2 ✅ | Student, owner, admin | One listing for the detail page |
| `request_reservation` | 2 ✅, ADR 0005 | Student | Reserve units of a listing, paying cash or by transfer; holds them at once |
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
| `get_storefront` | 4 ✅ | Student | A business's storefront: details, products, open pre-orders |
| `update_storefront` | 4 ✅, pins | Business owner | Edit the storefront's description, pickup details, map pin and logo |
| `upsert_campaign` | 4 ✅ | Business owner | Create or edit a pre-order campaign |
| `set_campaign_status` | 4 ✅ | Business owner | Open or close a campaign |
| `place_order` | 4 ✅, ADR 0005 | Student | Order ready stock or join a pre-order campaign, paying cash or by transfer |
| `transition_order` | 4 ✅ | Business owner / buyer | Move an order through its statuses, or cancel it |
| `my_orders` | 4 ✅ | Student | My Orders, buying side or the business's selling side |
| `set_order_cost` | 6 ✅ | Business owner | Record the business's cost for an order (for estimated profit) |
| `business_dashboard` | 6 ✅ | Business owner | The business's own performance figures for a date range |
| `create_product_request` | 5 ✅ | Student | Ask for a product nobody sells yet |
| `close_product_request` | 5 ✅ | Request creator | Close a request that is no longer needed |
| `list_product_requests` | 5 ✅ | Student | Active requests (or my own) with interest counts |
| `toggle_request_interest` | 5 ✅ | Student | Add or remove interest in a product request |
| `recompute_opportunities` | 5 ✅ | Server (triggers) | Recalculate the M4 opportunity ranking |
| `set_payment_details` | ADR 0005 | Student (business: approved owner) | Save or remove where buyers pay by transfer |
| `seller_accepts_transfer` | ADR 0005 | Student | Whether a listing's seller takes transfers |
| `get_payment` | ADR 0005 | Buyer / seller | The payment page: amount, deadline, where to pay (buyer), proof (seller) |
| `submit_payment_proof` | ADR 0005 | Buyer | Send the uploaded screenshot before the deadline |
| `review_payment` | ADR 0005 | Seller | Accept (confirm the deal) or reject (with a reason) a payment |

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

## `upsert_listing(listing_id, title, description, category, price_sen, condition, quantity, photo_paths, pickup_area, mode default 'personal', pickup_lat default null, pickup_lng default null)`

| | |
|---|---|
| **Caller** | Verified student. Editing: the listing's owner. Business listings (creating or editing): the owner of an approved business (`owns_business`) |
| **Input** | `listing_id`: `null` to create, or the listing to edit · `title`: 3–80 characters after trimming · `description`: up to 1,000 characters · `category`: one of `listing_categories()` · `price_sen`: 0–10,000,000 · `condition`: `new`, `like_new`, `good` or `fair` · `quantity`: units for sale, 1–999 (stored as `stock`) · `photo_paths`: up to 5 paths `{owner_id}/{listing_id}/{file}` ending in `.jpg`, `.jpeg`, `.png` or `.webp` · `pickup_area`: 2–80 characters · `mode` (Phase 4): `personal` or `business`, used only when creating; an edit keeps the listing's mode · `pickup_lat`, `pickup_lng` (pickup pins): both or neither, inside Malaysia (latitude 0.8–7.5, longitude 99.5–119.5); a call without them saves the listing with no pin |
| **Output** | `{ listing_id, status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` · `FORBIDDEN` (not the owner; or business mode without an approved business) · `INVALID_TRANSITION` (reserved or sold personal listings can't be edited) · `RATE_LIMITED` (more than 20 new listings in an hour) · `42501` (signed out) |
| **Derived on the server** | `owner_id` (the caller), `business_id` (the caller's business, for business mode), `status` (`draft` on create, unchanged on edit, except that restocking a sold-out business listing makes it `available`), `normalized_title`, `search_vector` |
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
| **Output** | Rows of `listing_card`: `id, owner_id, seller_name, mode, title, description, category, price_sen, condition, photo_paths, stock, pickup_area, status, created_at, business_id, business_name, pickup_lat, pickup_lng` (`business_id` and `business_name` set for business products, Phase 4; the pin when the seller set one) |
| **Shows** | `available` listings that aren't hidden, from sellers whose account is active and, for business products, whose business is approved. Ties sort newest first |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (sort or page) · `42501` |
| **Why a function** | Profiles are private, so a plain table read can't show the seller's name. The function returns only the name, nothing else about the seller |
| **Side effects** | Sweeps overdue transfer payments first (ADR 0005), so held units come back on sale; it never waits for rows another transaction holds |

## `get_listing(listing_id uuid)`

| | |
|---|---|
| **Caller** | Verified student or admin |
| **Output** | One `listing_card` row |
| **Shows** | Students: any listing that isn't a draft, isn't hidden, whose seller is active and, for business products, whose business is approved. The owner: their own listings in any status. Admins: everything |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` (missing or not visible to the caller) · `42501` |
| **Side effects** | Sweeps overdue transfer payments first, like `search_listings` |

## `request_reservation(listing_id uuid, qty integer default 1, pickup_note text default null, payment_method text default 'cash')`

| | |
|---|---|
| **Caller** | Verified student who doesn't own the listing. Personal listings only: business products are ordered (`place_order`) |
| **Input** | `qty`: 1–999 · `pickup_note`: up to 200 characters, optional · `payment_method`: `cash` or `transfer` (the seller must have payment details) |
| **Output** | `{ reservation_id, status: 'requested', expires_at, payment_id }` (`payment_id` for a transfer; its `expires_at` is the 30-minute proof deadline) |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (including transfer to a cash-only seller) · `NOT_FOUND` (missing or draft) · `FORBIDDEN` (own listing) · `ITEM_UNAVAILABLE` (not available, hidden, seller suspended, or fewer units left than asked; the message says how many are left) · `ALREADY_EXISTS` (an active reservation on this listing already) · `RATE_LIMITED` (more than 10 in an hour) · `42501` |
| **Side effects** | Locks the listing, expires its overdue reservations, takes `qty` out of `stock` (the listing becomes `reserved` at 0), creates the `deal_payments` row for a transfer, and notifies the seller |
| **Concurrency** | Requests for the same listing run one at a time behind the row lock, so they can never hold more units than exist. CI proves this with two real connections (`supabase/tests/concurrency/reservation_race.sh`) |

## `resolve_reservation(reservation_id uuid, action text)`

| | |
|---|---|
| **Caller** | The seller (`accept`, `decline`, `collect`) or either side (`cancel`) |
| **Allowed** | `accept`, `decline`: from `requested` · `cancel`: from `requested` or `accepted` · `collect`: from `accepted` |
| **Output** | `{ reservation_id, status, listing_status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (unknown action) · `NOT_FOUND` · `FORBIDDEN` (not a party, or the buyer trying a seller action) · `INVALID_TRANSITION` (wrong status, expired, `accept` on a transfer reservation (use `review_payment`), or the buyer cancelling after sending proof) · `42501` |
| **Side effects** | `accept` gives 7 days to collect. Declining or cancelling closes an open payment (`cancelled`). `decline` and `cancel` return the units. `collect` sells the listing when no stock and no other active reservation remain. Notifies the other party |

## `my_reservations(side text default 'buying')`

| | |
|---|---|
| **Caller** | Verified student |
| **Input** | `side`: `buying` or `selling` |
| **Output** | Rows of `reservation_card`: `id, listing_id, listing_title, listing_photo, pickup_area, price_sen, qty, pickup_note, status, expires_at, created_at, updated_at, i_am_buyer, other_party_name, other_party_email, payment_id, payment_status, payment_due_at, payment_reject_reason` (the payment columns are null for cash). Active ones first, then newest |
| **Privacy** | `other_party_email` is filled only once the reservation is `accepted` or `collected`; until then each side sees only the other's name |
| **Side effects** | Sweeps overdue transfer payments, then expires the caller's overdue reservations (skipping listings another transaction holds) |

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
| **Output** | `{ business_id, application_id, name, description, pickup_details, pickup_lat, pickup_lng, logo_path, status, created_at }` (`logo_path` from Phase 4; the pin is `null` when not set). A suspended business is returned too, so the app can explain it |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` (no business: not applied, or not approved yet) · `42501` |

## Helpers

`owns_business(business_id uuid) → boolean`: the caller is a verified student, owns that business, and it is `approved`. Phase 4 functions call it first. `is_staff() → boolean`: the caller has any `staff_roles` row (reviewer or admin); used by the review-queue policies. Storage policies use `can_upload_application_document(name)` and `can_read_application_document(name)`.

## Storefront, pre-orders and orders (M3)

Approved businesses sell from a storefront. Their products are ordinary `listings` with `mode = 'business'` (there is no separate product module). A buyer orders ready stock, or pre-orders through an open campaign. No money moves through the app: buyers pay cash on pickup, or by transfer with proof the seller accepts (ADR 0005); the seller records progress. Every business-only function calls `owns_business()` first, so it refuses a student without an approved business, and a suspended one, with `FORBIDDEN`.

## `get_storefront(business_id uuid)`

| | |
|---|---|
| **Caller** | Verified student (the owner and admins too) |
| **Output** | `{ business: { business_id, name, description, logo_path, pickup_details, pickup_lat, pickup_lng, status, owner_name }, is_owner, categories, listings, campaigns }`. `categories`: the distinct categories of its listed products. `listings`: its `available`, visible products as `listing_card`s, newest first (up to 50). `campaigns`: `open` campaigns that haven't closed, with `{ campaign_id, listing_id, listing_title, listing_photo, title, price_sen, start_at, close_at, capacity, allocated_qty, remaining, per_order_limit, pickup_details, status }`, closing soonest first |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` (missing, or suspended for anyone but its owner and admins) · `42501` |
| **Side effects** | Sweeps overdue transfer payments first, like `search_listings` |

## `update_storefront(description text, pickup_details text, logo_path text default null, pickup_lat double precision default null, pickup_lng double precision default null)`

| | |
|---|---|
| **Caller** | Owner of an approved business |
| **Input** | `description`: up to 1,000 characters · `pickup_details`: 5–200 · `logo_path`: `null` (no logo) or an uploaded `{business_id}/{file}.jpg\|jpeg\|png\|webp` in `business-logos` · `pickup_lat`, `pickup_lng`: the pickup pin, both or neither, inside Malaysia; a call without them removes the pin |
| **Output** | `{ business_id }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` (no approved business) · `INVALID_INPUT` · `42501` |
| **Notes** | The name stays the approved one |

## `upsert_campaign(campaign_id, listing_id, title, price_sen, start_at, close_at, capacity, per_order_limit, pickup_details)`

| | |
|---|---|
| **Caller** | Owner of the approved business the listing belongs to |
| **Input** | `campaign_id`: `null` to create, or the campaign to edit · `listing_id`: a published (not draft, not hidden) business listing of the caller's business; can't change on edit · `title`: 3–80 characters · `price_sen`: 0–10,000,000 · `start_at`, `close_at`: `close_at` after `start_at` and in the future · `capacity`: 1–10,000, and not below the units already ordered · `per_order_limit`: `null` or 1 to `capacity` · `pickup_details`: 5–200 characters |
| **Output** | `{ campaign_id, status }` (new campaigns are `draft`) |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` · `INVALID_INPUT` · `NOT_FOUND` · `INVALID_TRANSITION` (a closed campaign can't be edited) · `RATE_LIMITED` (more than 20 new campaigns in an hour) · `42501` |
| **Notes** | Editing an open campaign changes it for new orders only; placed orders keep their price and collection details |

## `set_campaign_status(campaign_id uuid, new_status text)`

| | |
|---|---|
| **Caller** | Owner of the campaign's approved business |
| **Allowed** | `draft` → `open` (its `close_at` must be in the future) · `open` → `closed` · `draft` → `closed` |
| **Output** | `{ campaign_id, status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` · `INVALID_INPUT` · `NOT_FOUND` · `INVALID_TRANSITION` · `42501` |
| **Notes** | Closing stops new orders; existing orders carry on |

## `place_order(listing_id uuid, qty integer default 1, campaign_id uuid default null, buyer_note text default null, payment_method text default 'cash')`

| | |
|---|---|
| **Caller** | Verified student who doesn't own the business |
| **Input** | `listing_id`: a business product · `qty`: 1–999 · `campaign_id`: `null` for ready stock, or an open campaign for this listing · `buyer_note`: up to 200 characters · `payment_method`: `cash` or `transfer` (the business, or its owner, must have payment details) |
| **Ready stock** | Locks the listing; it must be `available`, visible, from an approved business with an active owner, with `stock >= qty`. Takes `qty` out of `stock` (the listing becomes `sold` at 0). Price and the business's pickup details are copied into the order |
| **Pre-order** | Locks the campaign; it must be `open`, started and not closed, with `qty` within `per_order_limit` and `allocated_qty + qty <= capacity`. Adds `qty` to `allocated_qty`. The campaign's price and pickup details are copied into the order |
| **Output** | `{ order_id, status: 'pending_confirmation', total_sen, payment_id, payment_due_at }` (the payment fields for a transfer: 30 minutes to send proof) |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (quantity, note, per-order limit, or a campaign for another listing) · `NOT_FOUND` · `FORBIDDEN` (own business) · `ITEM_UNAVAILABLE` (personal listing, not available, hidden, suspended, or not enough stock; the message says how many are left) · `INVALID_TRANSITION` (the pre-order isn't open: draft, closed, not started or past its close date) · `CAPACITY_FULL` (the message says how many places are left) · `RATE_LIMITED` (more than 20 orders in an hour) · `42501` |
| **Side effects** | Expires overdue unpaid orders on the same listing or campaign first, so their units are free. Creates the `deal_payments` row for a transfer. Notifies the business owner (`order_placed`) |
| **Concurrency** | Orders for the same listing or campaign run one at a time behind its row lock, so they can never take more than exists. CI proves it with two real connections (`supabase/tests/concurrency/order_race.sh`) |

## `transition_order(order_id uuid, action text)`

| | |
|---|---|
| **Caller** | The business owner (`confirm`, `prepare`, `ready`, `complete`: needs `owns_business`); the buyer or the business owner (`cancel`) |
| **Allowed** | `confirm`: `pending_confirmation` → `confirmed` · `prepare`: `confirmed` → `preparing` · `ready`: `preparing` → `ready_for_pickup` · `complete`: `ready_for_pickup` → `completed` (sets `completed_at`) · `cancel`: any status before `completed` → `cancelled` (sets `cancelled_by`) |
| **Output** | `{ order_id, status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (unknown action) · `NOT_FOUND` · `FORBIDDEN` (not a party, the buyer trying a seller action, or a suspended business progressing an order) · `INVALID_TRANSITION` (including `confirm` on a transfer order (use `review_payment`) and the buyer cancelling after sending proof) · `42501` |
| **Side effects** | Cancelling locks the campaign or listing first, then returns the quantity: `allocated_qty` goes down, or `stock` goes up (a sold-out listing becomes `available` again), and an open payment is closed. Notifies the other party (`order_<status>`) |

## `my_orders(side text default 'buying', page_size integer default 50, page_offset integer default 0)`

| | |
|---|---|
| **Caller** | Verified student. `selling`: the orders of the business they own (also while it is suspended) |
| **Input** | `side`: `buying` or `selling` · `page_size`: 1–100 · `page_offset`: 0 or more |
| **Output** | Rows of `order_card`: `id, listing_id, listing_title, listing_photo, business_id, business_name, campaign_id, campaign_title, qty, unit_price_sen, total_sen, status, buyer_note, collection_details, cancelled_by, created_at, updated_at, completed_at, i_am_buyer, other_party_name, other_party_email, cost_sen, payment_id, payment_status, payment_due_at, payment_reject_reason`. `cost_sen` (Phase 6) is shown only on the selling side; the payment columns (ADR 0005) are null for cash; buyers never see a seller's cost. Orders in progress first, then newest |
| **Privacy** | `other_party_email` (the buyer's, or the business owner's) is filled only from `confirmed` to `completed`; a pending or cancelled order shows only the name |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `42501` |
| **Side effects** | Sweeps overdue transfer payments first |

`can_upload_business_logo(name)` is the Storage helper for `business-logos`.

## Smart Business Opportunity Discovery (M4)

Deterministic and explainable: no machine learning. Students ask for products and show interest; the database groups similar requests into clusters, compares the demand with matching listings and ranks the clusters as "possible opportunities". The rules and the score formula are in the data dictionary (`opportunities`, "Discovery terms"). Results are visible to every verified student, not only businesses.

## `create_product_request(name text, category text, campus_area text, preferred_price_sen integer default null, notes text default null)`

| | |
|---|---|
| **Caller** | Verified student |
| **Input** | `name`: 3–80 characters with at least one meaningful word · `category`: one of `listing_categories()` · `campus_area`: 2–80 characters · `preferred_price_sen`: 0–10,000,000, optional · `notes`: up to 300 characters, optional |
| **Output** | `{ request_id, cluster_key }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `ALREADY_EXISTS` (the caller already has an active request in this cluster) · `RATE_LIMITED` (more than 10 in a day) · `42501` |
| **Side effects** | Recomputes the cluster's opportunity |

## `close_product_request(request_id uuid)`

| | |
|---|---|
| **Caller** | The request's creator |
| **Allowed** | `active` → `closed` |
| **Output** | `{ request_id, status: 'closed' }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` · `FORBIDDEN` · `INVALID_TRANSITION` · `42501` |
| **Side effects** | The request and its interests leave the cluster, which is recomputed (and removed if it has no active request left) |

## `toggle_request_interest(request_id uuid)`

| | |
|---|---|
| **Caller** | Verified student who didn't make the request |
| **Output** | `{ request_id, interested, interest_count }`: whether the caller is now interested, and the request's number of interested students |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` · `FORBIDDEN` (own request) · `INVALID_TRANSITION` (closed) · `RATE_LIMITED` (more than 30 new interests in an hour) · `42501` |
| **Side effects** | Recomputes the request's cluster. Repeated taps never add up: one row per student per request, and the cluster counts distinct students |

## `list_product_requests(category text default null, cluster_key text default null, mine boolean default false, page_size integer default 20, page_offset integer default 0)`

| | |
|---|---|
| **Caller** | Verified student |
| **Shows** | Active requests, newest first, optionally of one category or one cluster; with `mine`, the caller's own requests in any status |
| **Output** | Rows of `request_card`: `id, name, category, preferred_price_sen, campus_area, notes, status, cluster_key, created_at, interest_count, i_am_interested, is_mine`. Nobody's identity is shown |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (page) · `42501` |

## Reading opportunities

The apps read `opportunities` directly (Row Level Security: verified students and staff), ordered by `score` desc, `last_interest_at` desc, `cluster_key`, 20 per page. Each row carries its own explanation (`reasons`) and `insufficient_data` flag.

## `recompute_opportunities(target_cluster text default null)`

Internal (no client may call it). Recomputes one cluster, or every cluster when `null`, and returns how many it refreshed. Triggers call it when a request is created or closed, an interest is added or removed, a listing's status, visibility, title, category or price changes, a listing is added or deleted, a seller's account status changes, or a business is suspended or reinstated. Each row stores `algo_version` (`m4-v1`) and `params`.

## Business Dashboard & Performance Monitoring (M5)

For approved businesses only, and only their own data: the functions take no business id, they use the caller's business. Revenue and profit are **estimated / self-reported**: CampusNiaga doesn't take or verify payments, so revenue is the sum of the totals of orders the seller marked completed, and costs are what the seller typed in. Application counts are M2 (`application_status_summary`), not M5.

## `set_order_cost(order_id uuid, cost_sen integer)`

| | |
|---|---|
| **Caller** | Owner of the order's approved business (`owns_business`) |
| **Input** | `cost_sen`: 0–100,000,000, or `null` to clear |
| **Allowed** | Any order of the business that isn't cancelled |
| **Output** | `{ order_id, cost_sen }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` · `FORBIDDEN` (not the seller, or the business isn't approved) · `INVALID_INPUT` · `INVALID_TRANSITION` (cancelled) · `42501` |

## `business_dashboard(from_at timestamptz default null, to_at timestamptz default null)`

| | |
|---|---|
| **Caller** | Owner of an approved business |
| **Input** | An optional range: `from_at` inclusive, `to_at` exclusive; `null` means unbounded. `from_at` must be before `to_at` |
| **Output** | `{ business_id, business_name, from_at, to_at, orders_by_status, total_orders, completed_count, estimated_revenue_sen, recorded_cost_sen, costed_completed_count, estimated_profit_sen, top_products, stock, campaigns }` |
| **Counting** | `orders_by_status` (every status, zeros included) and `total_orders`: orders *placed* in the range. Completed figures: orders *completed* in the range (`completed_at`). `estimated_revenue_sen` = sum of their `total_sen`; `recorded_cost_sen` = sum of their entered `cost_sen` (`costed_completed_count` says how many have one); `estimated_profit_sen` = revenue − recorded costs. `top_products`: up to 5 products by revenue from those completed orders, then units, with `{ listing_id, title, units, revenue_sen }`. `stock`: every published business product with `{ listing_id, title, status, stock, hidden }`, lowest stock first. `campaigns`: draft and open pre-orders with `{ campaign_id, title, status, capacity, allocated_qty, remaining, close_at }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` (no approved business) · `INVALID_INPUT` (range) · `42501` |

## Deal chat ([ADR 0004](decisions/0004-deal-chat.md))

Text between the buyer and seller of an accepted reservation or a confirmed business order. All callers must be verified students; anyone else who isn't a participant gets `NOT_FOUND`, so they can't tell whether a chat exists. A chat **can send** while its deal is active and it isn't closed (see `conversations` in the data dictionary). New messages arrive live through Supabase Realtime: subscribe to `INSERT` on `public.messages` filtered by `conversation_id`.

`conversation_card`: `{ conversation_id, kind ('reservation' | 'order'), reservation_id, order_id, listing_id, listing_title, listing_photo, other_party_name, i_am_buyer, last_message, last_message_at, last_message_mine, unread_count, can_send, closed, created_at }`.

## `open_conversation(reservation_id uuid default null, order_id uuid default null)`

| | |
|---|---|
| **Caller** | The buyer or seller of the reservation or order |
| **Input** | Exactly one of the two ids |
| **Allowed** | Creates the chat while the deal is active; an existing chat is returned whatever the deal's state |
| **Output** | `{ conversation_id, created }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` · `INVALID_TRANSITION` (reservation not accepted or overdue; order not confirmed) · `42501` |

## `send_message(conversation_id uuid, body text)`

| | |
|---|---|
| **Caller** | A participant |
| **Input** | `body`: 1–1,000 characters after trimming |
| **Allowed** | While the chat can send. 20 messages a minute per student |
| **Output** | `{ message_id, created_at }`; the sender's read marker moves to it |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` · `INVALID_TRANSITION` ("This chat was closed." or read-only because the deal ended) · `RATE_LIMITED` · `42501` |

## `my_conversations(page_size integer default 30, page_offset integer default 0)` · `get_conversation(conversation_id uuid)`

| | |
|---|---|
| **Caller** | Any verified student; only their own chats |
| **Output** | `conversation_card` rows, newest activity first; `get_conversation` returns one card or `NOT_FOUND` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` (page) · `NOT_FOUND` · `42501` |

## `mark_conversation_read(conversation_id uuid)`

| | |
|---|---|
| **Caller** | A participant |
| **Output** | `{ conversation_id, last_read_id }`: everything up to the newest message is read |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` · `42501` |

## `close_conversation(conversation_id uuid)`

| | |
|---|---|
| **Caller** | A participant |
| **Effect** | Ends the chat for both (the block); it can't be reopened. Audit action `chat.closed` |
| **Output** | `{ conversation_id, closed: true }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` · `INVALID_TRANSITION` (already closed) · `42501` |

## `report_conversation(conversation_id uuid, reason text, details text default '')`

| | |
|---|---|
| **Caller** | A participant, about the other one (works on closed and read-only chats too) |
| **Input** | `reason`: `scam`, `offensive` or `other` (`other` needs details); `details` up to 500 characters |
| **Output** | `{ report_id, status: 'open' }`. Admins handle it with `dismiss_report` or `set_account_status`, as for listing reports |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` · `ALREADY_EXISTS` (an open report on this chat) · `RATE_LIMITED` (10 reports a day) · `42501` |

## `get_reported_conversation(report_id uuid)`

| | |
|---|---|
| **Caller** | Admin |
| **Output** | `{ conversation_id, listing_title, buyer: { id, name, email }, seller: { … }, closed_at, messages: [{ id, from ('buyer' \| 'seller'), body, created_at }] }`, oldest first, the latest 500 |
| **Effect** | Admins can't browse chats; they see one only through a report about it. Each view is audited (`chat.viewed`) |
| **Errors** | `FORBIDDEN` · `NOT_FOUND` (no chat on that report) · `42501` |

## Transfer payments ([ADR 0005](decisions/0005-transfer-payments.md))

A buyer may pay a seller's own bank account or QR code outside the app and upload a screenshot; the seller checks their bank and accepts or rejects it. CampusNiaga never holds or moves money, and records what the seller decided. The units stay held while a payment is open; a payment without proof 30 minutes after ordering or reserving expires and releases them.

## `set_payment_details(for_business boolean, bank_name text default null, account_name text default null, account_number text default null, qr_path text default null)`

| | |
|---|---|
| **Caller** | Verified student. `for_business`: the owner of an approved business |
| **Input** | `bank_name` (2–60), `account_name` (2–80) and `account_number` (6–20 digits; spaces and dashes removed) together or not at all · `qr_path`: the caller's own upload `{uid}/{file}` in `payment-qr`. Neither an account number nor a QR code removes the details |
| **Output** | `{ saved: true }`, or `{ saved: false }` when removed |
| **Errors** | `NOT_VERIFIED_STUDENT` · `FORBIDDEN` (business details without an approved business) · `INVALID_INPUT` · `42501` |

## `seller_accepts_transfer(listing_id uuid)`

| | |
|---|---|
| **Caller** | Verified student |
| **Output** | `true` when the listing's business (for a business product) or seller has payment details. The details themselves aren't returned |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` (draft, hidden or missing) · `42501` |

## `get_payment(payment_id uuid)`

| | |
|---|---|
| **Caller** | The payment's buyer or seller |
| **Output** | `{ payment_id, order_id, reservation_id, i_am_buyer, item_title, qty, deal_status, seller_name, amount_sen, status, due_at, proof_path, submitted_at, decided_at, reject_reason, pay_to }`. `pay_to` = `{ bank_name, account_name, account_number, qr_path }` for the buyer while the payment is `awaiting_proof` or `submitted`; otherwise `null` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` (missing, or not a party) · `42501` |
| **Side effects** | Sweeps overdue transfer payments first |

## `submit_payment_proof(payment_id uuid, proof_path text)`

| | |
|---|---|
| **Caller** | The payment's buyer |
| **Input** | `proof_path`: the buyer's upload `{buyer_id}/{payment_id}/{file}` in `payment-proofs` |
| **Allowed** | `awaiting_proof` → `submitted`, before `due_at` |
| **Output** | `{ payment_id, status: 'submitted' }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `NOT_FOUND` · `FORBIDDEN` (the seller) · `INVALID_INPUT` (no such upload) · `INVALID_TRANSITION` (already sent, or the time has run out) · `42501` |
| **Side effects** | Locks the deal's listing or campaign first. A reservation's hold becomes 7 days, for the seller to check. Notifies the seller (`payment_submitted`) |

## `review_payment(payment_id uuid, accept boolean, reason text default null)`

| | |
|---|---|
| **Caller** | The payment's seller (for an order, the owner of the approved business) |
| **Input** | `accept` · `reason`: required to reject, 1–200 characters |
| **Allowed** | `submitted` → `accepted` / `rejected` |
| **Output** | `{ payment_id, status, deal_status }` |
| **Errors** | `NOT_VERIFIED_STUDENT` · `INVALID_INPUT` · `NOT_FOUND` · `FORBIDDEN` (the buyer, or a suspended business) · `INVALID_TRANSITION` (no proof yet, or already decided) · `42501` |
| **Side effects** | Accept: the order becomes `confirmed`, or the reservation `accepted` (7 days to collect). Reject: the order is cancelled (`cancelled_by = 'seller'`) or the reservation declined, and the units go back on sale. Audited (`payment.accepted` / `payment.rejected`); notifies the buyer |

`can_read_payment_qr`, `can_upload_payment_proof`, `can_read_payment_proof` and `can_delete_payment_proof` are the Storage helpers for `payment-qr` and `payment-proofs`. `payment_details_for`, `cancel_order_hold`, `expire_unpaid_orders`, `expire_overdue_payments` and `lock_payment` are internal.
