---
name: authentication-authorization
description: Own CampusNiaga's identity and permission model on Supabase, including sign-up and sign-in with email and password, email confirmation, the USM student check and test allowlist, the one staff role (the HDC administrator, role admin) in the staff_roles table, approved-business ownership, account suspension, the access helper functions (is_student, is_admin, is_staff, get_my_access), the permission matrix behind Row Level Security, and route guards in Flutter and React. Use whenever code decides who may read or do something, or when a feature is gated by role or approval status.
---

# Authentication & authorization

This skill is the **single definition** of who may do what. Other skills reuse the helpers defined here and don't redefine them. Read `CLAUDE.md` first.

## Identity model

| Concept | Source of truth | Changed by |
|---|---|---|
| Signed in | Supabase Auth session | The app (`signInWithPassword`, `signUp`) |
| Email confirmed | `auth.users.email_confirmed_at` | The user clicking the confirmation email |
| Verified USM student | `public.is_student()`, computed on every request | Nobody stores it. It follows from the confirmed email, `app_config`, and the account being active |
| HDC administrator | A `public.staff_roles` row with `role = 'admin'`, the only staff role ([ADR 0009](../../../docs/decisions/0009-single-admin-role.md)) | `set_staff_role()` (admins only). The first admin is added in the Supabase SQL editor |
| Approved business owner | `public.businesses` row owned by the user with `status = 'approved'` | `review_business_application()` on approval; `set_business_status()` (Phase 3) |
| Suspended | `profiles.account_status = 'suspended'` | `set_account_status()` (admins, Phase 2) |

**Roles are read live from tables, never from the login token**, so a granted or removed role applies on the very next request. Don't add roles to JWT claims or the access token hook. They would go stale, which is the problem ADR 0003 removed.

## Student check

- `app_config.student_email_domains` (default `student.usm.my`) and `app_config.test_allowlist` are readable by admins only.
- `public.is_eligible_student_email(email, domains, allowlist)` is pure: exact, case-insensitive domain match, so sub-domains and look-alikes fail; or an exact allowlisted email.
- `public.is_student()` requires a confirmed email, an eligible address and an `active` profile. Signed-in but unconfirmed or ineligible users can browse nothing student-only and can't trade.
- Email confirmation needs real email delivery: the hosted project must use custom SMTP before students other than the project team can sign up.

## Helper functions (defined in `supabase/migrations/…_foundation.sql`)

| Function | Returns |
|---|---|
| `public.is_student()` | Verified USM student, as above |
| `public.is_admin()` (and `public.is_staff()`, the same since ADR 0009) | Has the administrator `staff_roles` row |
| `public.get_my_access()` | `{ user_id, email, email_confirmed, account_status, is_student, is_admin, is_business_owner, business_status }` for the apps' navigation |

All are `security definer`, `stable` and `set search_path = ''`, and can't be executed by `anon`. In policies, call them as `(select public.is_admin())` so they run once per query. Add `public.owns_business(business_id)` in Phase 3 in the same style.

## Permission matrix (keep it consistent with the policies)

| Resource | Student | Business owner | Admin |
|---|---|---|---|
| `profiles` | read own; rename self while active | same | read all; status via function |
| `staff_roles` | read own | same | read all; change via `set_staff_role` |
| `app_config` | (none) | (none) | read |
| `audit_logs` | (none) | (none) | read |
| `listings` (Phase 2) | read visible; write own via `upsert_listing` | + own business listings | read all; hide via function |
| `purchases` (ADR 0006) | read where buyer or seller; changes via functions | same | read |
| Business performance (ADR 0007) | (none) | own, through `business_dashboard` | read through audited functions; never cost or profit |
| `business_applications` (Phase 3) | read own; edit own while `draft`/`info_requested` | same | read non-draft; decide via function |
| `businesses`, `campaigns`, `orders` (Phases 3–4) | read storefronts; read own orders | manage own via functions | read |
| `product_requests`, `opportunities` (Phase 5) | read; create own requests | same | read |

Signed-out visitors (`anon`) get nothing.

## Client guards (UX only; the database enforces everything)

**Flutter (`go_router` redirect, driven by `get_my_access()` on sign-in and on app resume):** signed out → `/login`; email not confirmed → `/verify-email`; confirmed but `is_student` false → "not eligible"; suspended → "account suspended"; otherwise allow. Business routes also require an approved business.

**React (`RequireStaff`):** every route except `/login`; calls `get_my_access()`; only the HDC administrator (`is_admin`) gets in, so there is one guard around the whole shell; anyone else is signed out with "Staff access only".

## Workflow

1. Name the actor and resource, and find the matrix row. If none exists, ask the user before inventing a permission.
2. Write the policy or function check using the helpers.
3. Write refused tests first (other student, role-less staff, signed out, unconfirmed, suspended), then the allowed test.
4. Update the client guard and the matrix if anything changed.

## Verification checklist

- [ ] No privilege comes from a client-writable column or from token claims.
- [ ] Domain matching is exact; the allowlist isn't readable by students.
- [ ] Every policy and function has allowed and refused tests, including unconfirmed and suspended users.
- [ ] Role changes take effect on the next request (a test proves it).
- [ ] The matrix in this skill matches the policies.
