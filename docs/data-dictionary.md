# Data dictionary

This is the single definition of CampusNiaga's database (Supabase PostgreSQL) and file storage. It follows the Implementation Handoff v1.0, section 6, adapted to SQL by [ADR 0003](decisions/0003-move-backend-to-supabase.md).

The tables themselves are defined in `supabase/migrations/`. A table marked **(Phase 1)** exists; the others are planned and are created by their phase's migration. Any change to a table updates this document and adds a migration in the same commit. The Flutter app mirrors status values in `mobile/lib/core/domain/`; the admin dashboard uses types generated from the database.

## Conventions

| Rule | Detail |
|---|---|
| Names | Tables plural, columns `snake_case` |
| Keys | `id uuid` (or `bigint` identity for logs); foreign keys reference the parent's `id` |
| Status values | `snake_case` text with a `check` constraint, exactly as listed here |
| Money | Integer **sen** (`price_sen`, `total_sen`): RM 12.50 is stored as `1250`. Never floating-point RM |
| Time | `timestamptz`. Every table has `created_at`, and changeable tables have `updated_at`, kept by a trigger |
| Owner columns | `owner_id`, `applicant_id`, `buyer_id`, `creator_id`, `reporter_id` can't change after creation |
| Written by | **Client**: the app may write it directly, as Row Level Security and column privileges allow. **Server**: only database functions write it. **Input**: supplied by the user, validated and written by a database function |
| Access | Row Level Security is on for every table. Without a matching policy, access is denied |

## Who is what

Roles are read from tables on every request, never from login tokens:

| Role | Rule (database function) |
|---|---|
| Verified student | `is_student()`: email confirmed, address matches `app_config.student_email_domains` exactly or is in `app_config.test_allowlist`, and the profile is `active` |
| Reviewer | `is_reviewer()`: a `staff_roles` row with `role = 'reviewer'` |
| Admin | `is_admin()`: a `staff_roles` row with `role = 'admin'` |
| Approved business owner | Owns a `businesses` row with `status = 'approved'` (Phase 3) |

## Tables

### `auth.users` (managed by Supabase Auth)

Accounts, passwords, emails and email confirmation (`email_confirmed_at`). The apps never write it directly; Supabase Auth does.

### `profiles` (Phase 1)

One per account, created by a trigger when someone signs up.

| Column | Type | Written by | Notes |
|---|---|---|---|
| `id` | uuid | Server | Same as `auth.users.id` |
| `name` | text | Client | 1–60 characters, not only spaces. The only column a user may change, and only while `active`. Defaults to the sign-up name, else the part of the email before the @ |
| `email` | text | Server | Copied from Auth, and kept in sync when it changes |
| `account_status` | `active` \| `suspended` | Server | Suspended accounts lose student access |

Read: the owner, and admins.

### `staff_roles` (Phase 1)

| Column | Type | Notes |
|---|---|---|
| `user_id` | uuid | Primary key together with `role` |
| `role` | `reviewer` \| `admin` | |
| `granted_by` | uuid? | The admin who granted it |
| `created_at` | timestamptz | |

Written only by `set_staff_role()`. Read: the user's own rows, and admins. The first admin is added in the Supabase SQL editor (see the README).

### `app_config` (Phase 1)

A single row of settings. Read by admins only, because it holds the test allowlist. Changed in the Supabase dashboard, never from the apps.

| Column | Type | Default |
|---|---|---|
| `student_email_domains` | text[] | `{student.usm.my}`, at least one |
| `test_allowlist` | text[] | empty. Emails allowed for FYP evaluation |
| `categories` | text[] | Books, Electronics, Fashion, Food & Beverage, Hostel Essentials, Stationery, Others |
| `max_application_documents` | integer | 5 |
| `max_upload_bytes` | integer | 5,242,880 (5 MB) |

### `audit_logs` (Phase 1)

Append-only record of important actions, written only by database functions. Read: admins (reviewers get application history in Phase 3).

| Column | Type | Notes |
|---|---|---|
| `id` | bigint | Identity |
| `actor_id` | uuid? | Who did it |
| `action` | text | e.g. `role.granted`, `application.approved`, `listing.hidden` |
| `target_type`, `target_id` | text | e.g. `user` / the user's id |
| `metadata` | jsonb | Minimal context only; no sensitive data |
| `created_at` | timestamptz | |

### `listings` (Phase 2)

A product, shared by personal sellers and approved businesses. Written only through `upsert_listing()` and `set_listing_status()`.

| Column | Type | Source | Notes |
|---|---|---|---|
| `id` | uuid | Server | |
| `owner_id` | uuid | Server | The caller; can't change |
| `mode` | `personal` \| `business` | Input (create only) | `business` requires an approved business owned by the caller |
| `business_id` | uuid? | Server | Set for `business` mode |
| `title` | text | Input | 3–80 characters |
| `normalized_title` | text | Server | Lowercased, punctuation removed; used by M4 matching |
| `search_vector` | tsvector | Server | Generated from title, description and category; PostgreSQL full-text search |
| `description` | text | Input | Up to 1,000 characters |
| `category` | text | Input | One of `app_config.categories` |
| `price_sen` | integer | Input | 0–10,000,000 |
| `condition` | `new` \| `like_new` \| `good` \| `fair` | Input | |
| `photo_paths` | text[] | Input | 1–5 paths in the `listing-photos` bucket (resized on the device before upload) |
| `stock` | integer | Input (personal) / Server (orders) | 0 or more |
| `pickup_area` | text | Input | Campus pickup location |
| `status` | `draft` \| `available` \| `reserved` \| `sold` \| `closed` | Server | `draft` → `available` → `reserved` → `sold`; `closed` when withdrawn. A cancelled or expired reservation returns it to `available` |
| `hidden` | boolean | Server | Admin moderation; hidden listings are left out of feeds and M4 supply |

### `reservations` (Phase 2)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `listing_id`, `buyer_id`, `seller_id` | uuid | The buyer can't be the seller |
| `pickup_note` | text? | Buyer's preferred time or place |
| `status` | `requested` \| `accepted` \| `declined` \| `cancelled` \| `collected` \| `expired` | |
| `expires_at` | timestamptz? | Expiry is evaluated when the reservation is read or acted on; no scheduled job |

At most one accepted active reservation per personal listing, enforced with a row lock in `request_reservation()` / `resolve_reservation()`.

### `business_applications` (Phase 3)

| Column | Type | Written by | Notes |
|---|---|---|---|
| `id` | uuid | Server | |
| `applicant_id` | uuid | Client (create) | Can't change |
| `business_name`, `category`, `description`, `contact_details`, `collection_details` | text | Client | Editable only while `draft` or `info_requested` |
| `document_paths` | text[] | Client | Private paths in `application-documents`; same rule |
| `status` | `draft` \| `submitted` \| `under_review` \| `info_requested` \| `approved` \| `rejected` | Client (`draft` only) / Server | |
| `reviewer_id` | uuid? | Server | |
| `remarks` | text? | Server | Latest reviewer note |
| `submitted_at`, `decided_at` | timestamptz? | Server | |

### `application_status_history` (Phase 3)

Append-only, one row per status change: `application_id`, `from_status`, `to_status`, `actor_id`, `actor_role`, `note`, `created_at`.

### `businesses` (Phase 3)

Created only when a reviewer approves an application: `id`, `owner_id`, `application_id`, `name`, `description`, `logo_path?`, `pickup_details`, `status` (`approved` \| `suspended`).

### `campaigns` (Phase 4)

A pre-order campaign: `id`, `business_id`, `listing_id`, `title`, `price_sen`, `start_at`, `close_at` (after `start_at`), `capacity`, `per_order_limit?`, `allocated_qty` (never above `capacity`; changed only inside transactions), `pickup_details`, `status` (`draft` \| `open` \| `closed`).

### `orders` (Phase 4)

| Column | Type | Notes |
|---|---|---|
| `id` | uuid | |
| `buyer_id`, `business_id`, `listing_id` | uuid | |
| `campaign_id` | uuid? | Present for pre-orders |
| `qty` | integer | 1 or more |
| `unit_price_sen` | integer | Price snapshot at order time |
| `total_sen` | integer | `unit_price_sen × qty` |
| `status` | `pending_confirmation` \| `confirmed` \| `preparing` \| `ready_for_pickup` \| `completed` \| `cancelled` | Cancellation is allowed before `completed`; pending and confirmed orders hold campaign capacity |
| `collection_details` | text | |
| `cost_sen` | integer? | Seller-entered cost, for estimated profit |
| `completed_at` | timestamptz? | M5 date filters and totals |

### `product_requests` (Phase 5)

`id`, `creator_id`, `name`, `normalized_name`, `category`, `preferred_price_sen?`, `campus_area`, `notes?`, `cluster_key?` (server), `status` (`active` \| `closed`).

### `request_interests` (Phase 5)

`request_id`, `user_id`, `created_at`. The primary key `(request_id, user_id)` allows one interest per student per request.

### `opportunities` (Phase 5)

Derived M4 result per cluster, written only by the server: `cluster_key` (primary key), `category`, `keywords[]`, `request_ids[]`, `unique_interest_count`, `active_supply_count`, `distinct_seller_count`, `median_listed_price_sen?`, `median_preferred_price_sen?`, `price_gap`, `score`, `reasons[]`, `insufficient_data` (fewer than 2 students), `algo_version`, `calculated_at`.

### `reports` (Phase 2)

`id`, `reporter_id`, `listing_id?`, `reported_user_id?`, `reason`, `status` (`open` \| `reviewed` \| `actioned`, server), `action?` (server).

### `notifications` (Phase 2)

In-app notices written by the server: `id`, `recipient_id`, `type`, `title`, `body`, `target?`, `read` (the recipient may set it), `created_at`.

## File storage (Supabase Storage buckets)

| Bucket | Contents | Access |
|---|---|---|
| `listing-photos` | Product photos: JPEG, PNG or WebP, up to 5 MB, under `{owner_id}/{listing_id}/` | Owner writes; signed-in users read |
| `application-documents` | Business application documents: PDF, JPEG or PNG, up to 5 MB, under `{applicant_id}/{application_id}/` | Private. The applicant writes while the application is editable; the applicant and reviewers read through short-lived signed URLs |
| `business-logos` | Business logos, under `{business_id}/` | Business owner writes; signed-in users read |
