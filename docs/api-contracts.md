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
| `upsert_listing` | 2 | Student (business mode: approved business owner) | Create or edit a listing; validates, rate-limits, sets derived fields |
| `set_listing_status` | 2 | Listing owner | Publish a draft, close a listing, or return it to available |
| `request_reservation` | 2 | Student | Reserve a personal listing |
| `resolve_reservation` | 2 | Seller / buyer | Accept, decline, cancel or mark collected |
| `moderate_listing` | 2 | Admin | Hide or restore a reported listing |
| `set_account_status` | 2 | Admin | Suspend or reactivate an account |
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
