---
name: authentication-authorization
description: Own CampusNiaga's identity and permission model, including Firebase Auth sign-in, email verification, the USM student-domain gate and test allowlist, custom claims (student, reviewer, admin, businessId), staff role assignment, account suspension, Security Rules helper functions, callable auth guards, and client route guards in Flutter and React. Use whenever code decides who may read or do something, or when a feature is gated by role or approval status.
---

# Authentication & authorization

This skill is the **single definition** of who may do what. Other skills reuse the helpers defined here and don't redefine them. Read `CLAUDE.md` first.

## Identity model

| Concept | Source of truth | Set by |
|---|---|---|
| Signed in | Firebase Auth | Client sign-in (email/password; email link optional) |
| Email verified | `token.email_verified` | Firebase Auth verification email |
| Verified USM student | claim `student: true` | `syncStudentStatus` callable |
| Reviewer / Admin | claims `reviewer: true` / `admin: true` | `setStaffRole` callable (admin only) or the emulator seed script |
| Approved business | claim `businessId: "<id>"` | `reviewBusinessApplication` on approval; removed on suspension |
| Suspended account | Auth `disabled: true` + `users/{uid}.accountStatus: 'suspended'` + refresh tokens revoked | `setAccountStatus` callable (admin only) |

`users/{uid}.roleFlags` mirrors the claims **for display only**. Rules and functions never read it to grant access, and clients can't write it.

## Student gate

- `config/app` (admin-readable only): `studentEmailDomains: ['student.usm.my']`, `testAllowlist: [emails]`.
- `syncStudentStatus` (callable, any signed-in user): requires `email_verified`. Grants `student: true` if the lowercased email's domain exactly matches a configured domain (no suffix matching such as `evilstudent.usm.my`) or the email is in the allowlist. Creates or updates `users/{uid}` with server-controlled fields. Idempotent.
- After any callable that changes claims, the client must refresh the token (`getIdToken(true)` / `user.getIdToken(true)`) before routing.
- Unverified or non-student users can sign in but **cannot trade**. Rules and guards require `student`.

## Security Rules helpers (define once at the top of `firebase/firestore.rules`)

```
// Add each helper to the rules file when a rule first uses it, so every helper is covered by tests.
function isSignedIn()      { return request.auth != null; }
function isStudent()       { return isSignedIn() && request.auth.token.email_verified == true
                                    && request.auth.token.student == true; }
function isReviewer()      { return isSignedIn() && request.auth.token.reviewer == true; }
function isAdmin()         { return isSignedIn() && request.auth.token.admin == true; }
function isStaff()         { return isReviewer() || isAdmin(); }
function isOwner(uid)      { return isSignedIn() && request.auth.uid == uid; }
function ownsBusiness(id)  { return isStudent() && request.auth.token.businessId == id; }
function isActiveAccount() { return get(/databases/$(database)/documents/users/$(request.auth.uid))
                                    .data.accountStatus == 'active'; }
```

- Use `isActiveAccount()` only on direct client **creates and updates** (it costs a read). Reads rely on claims.
- `storage.rules` defines matching helpers (`isStudent`, `isReviewer`, `isAdmin`); use `firestore.get()` there only when ownership lives in Firestore.

### Permission matrix (keep it consistent with the rules)

| Resource | Student | Business owner | Reviewer | Admin |
|---|---|---|---|---|
| `listings` (visible) | read; create/edit own personal via `upsertListing` | + own `mode:'business'` (callable checks `businessId` claim) | (none) | read all; hide via callable |
| `reservations` | read where buyer/seller; changes via callable | same | (none) | read |
| `businessApplications` | read own; edit own while `draft`/`info_requested` (content fields only) | same | read non-draft; decide via callable | read |
| `businesses`, `campaigns`, `orders` | read public storefront; read own orders | read/manage own via callables | (none) | read |
| `productRequests` | read; create own | same | (none) | read |
| `opportunities` | read | read | (none) | read |
| `users/{uid}` | read/update own profile fields only | same | read applicants of non-draft applications | read all; role changes via callable |
| `auditLogs` | (none) | (none) | read entries for applications | read |
| `config/app` | (none) | (none) | (none) | read |

## Callable guards (`functions/src/shared/guards.ts`)

- `requireAuth(req)` → `{ uid, token }` or throws `FORBIDDEN`.
- `requireStudent(req)` → also checks `email_verified`, `student`, and `users/{uid}.accountStatus === 'active'`. Throws `NOT_VERIFIED_STUDENT` or `FORBIDDEN`.
- `requireBusinessOwner(req, businessId)` → `requireStudent` + claim match + `businesses/{id}.status === 'approved'`.
- `requireReviewer(req)` / `requireAdmin(req)` are async and check the caller's **current** claims with `adminAuth.getUser`, because an ID token stays valid for up to an hour after a role is removed. Security Rules can only see the token, so keep privileged writes in callables; rule-based staff reads have that window.
- Guards return a typed `Actor` that services receive. Services never read `req` directly.

## Staff and role management

- Admin assigns or removes `reviewer`/`admin` via `setStaffRole({ uid, role, enabled })`. An admin cannot remove their own admin claim (prevents lockout). Each change is written to `auditLogs`.
- The first admin and reviewer are created by the emulator seed script using the Admin SDK. Never use a client-side flag, a hard-coded UID list in client code, or a Firestore field the client can write.
- `setCustomUserClaims` **replaces** all claims, so always merge with the existing claims.

## Client guards

**Flutter (`go_router` redirect):** unauthenticated → `/login`; not verified → `/verify-email`; verified but no `student` claim → "not eligible" screen; otherwise allow. Business routes also require `businessId`. Derive the state from `idTokenChanges()` claims in one `authStateProvider`.

**React (`RequireStaff`):** wraps every route except `/login`; reads claims from `getIdTokenResult()`; `role="reviewer"` allows reviewers and admins, `role="admin"` allows admins only; a non-staff user is signed out with a "Staff access only" message.

Client guards are for UX only. Every protected action must also fail on the server for the wrong actor.

## Workflow

1. Name the actor and resource, and find the matrix row. If none exists, ask the user before inventing a permission.
2. Add or adjust rules using the helpers, and the guard in the callable.
3. Write deny tests first (wrong role, other owner, unverified, suspended), then the allow test.
4. Update the client guard and the matrix above if anything changed.

## Verification checklist

- [ ] No privilege is derived from client-writable data; claims are set only via the Admin SDK.
- [ ] Domain matching is exact on the lowercased domain; the allowlist is not client-readable.
- [ ] Every rule or guard has allow and deny tests, including a suspended or unverified user.
- [ ] Claims are merged, not replaced; the token is refreshed after a claim change.
- [ ] The matrix in this skill matches `firestore.rules`.
