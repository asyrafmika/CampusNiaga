---
name: enterprise-architecture
description: Decide where new CampusNiaga code belongs and how the mobile app, admin dashboard and Supabase database divide a feature. Use when starting a new module or feature that spans more than one tier, creating new top-level folders or packages, defining contracts between clients and the backend, choosing between a direct table write and a database function, resolving a module-boundary question, or recording an architectural decision (ADR). Not for single-tier implementation details; use flutter-development, react-dashboard or supabase-backend for those.
---

# Enterprise architecture: CampusNiaga

This skill is the map. It decides *where* code goes and *which tier owns which responsibility*. The tier skills decide *how* to write it.

Read `CLAUDE.md` first. Its non-negotiables and data conventions apply here and aren't repeated.

## Tier responsibilities

| Tier | Owns | Never does |
|---|---|---|
| `mobile/` (Flutter) | Student UX for M1–M5, validation for UX, reading permitted rows, calling database functions | Privileged writes, role/status/owner changes, stock or capacity arithmetic, ranking |
| `admin/` (React) | Reviewer and admin UX for M2, moderation, user access, audit viewing | Writing approvals or roles to tables; it calls database functions |
| `supabase/` functions | Every state change with authority: approvals, reservations, orders, allocation, roles, audit, M4 | UI concerns; trusting any client-supplied role, status, owner or price |
| `supabase/` policies | Default deny; owner-scoped reads and non-privileged writes; role-scoped reads | Workflows (keep policies simple; put workflows in functions) |

**Direct write vs database function:** a client may write a row directly only if all of these hold:
- (a) the caller owns it;
- (b) the change can't affect another user, stock, money, roles, or any status other than its own draft/edit state;
- (c) a policy plus column grants fully express the rule.

Everything else is a database function.

Examples:
- **Direct write:** editing your own profile name, saving a business-application draft, marking your own notification read.
- **Database function:** creating or editing listings (validation, rate limits, derived search fields), reserving, ordering, approving, toggling interest, hiding listings.

## Module-to-code map

| Module | Mobile feature folder | Admin feature folder | Database |
|---|---|---|---|
| Auth / gate | `features/auth` | `features/auth` | `profiles`, `staff_roles`, `is_student()`, `get_my_access()` |
| M1 | `features/marketplace` | `features/moderation` | `listings`, `reservations`, `reports` + functions |
| M2 | `features/business/application` | `features/applications` | `business_applications`, history, `businesses` + functions |
| M3 | `features/business/store` | (none) | `campaigns`, `orders` + functions |
| M4 | `features/discovery` | (none) | `product_requests`, `request_interests`, `opportunities` + ranking functions |
| M5 | `features/dashboard` | (none) | Aggregate functions over the seller's orders |
| Admin | (none) | `features/users`, `features/audit` | `set_staff_role()`, `audit_logs` |

Don't create a module, table, screen or function that isn't traceable to the handoff. If a feature seems to need one, stop and ask the user.

## Contracts between tiers

Contracts are the stable surface, and changing them is a breaking change:

1. **Tables, columns and status values:** `docs/data-dictionary.md` plus the migrations. The admin dashboard uses generated types; Flutter keeps its mirror in `mobile/lib/core/domain/`.
2. **Database functions:** `docs/api-contracts.md`. Each entry lists caller requirements, inputs, output, the reasons it can raise, and side effects (rows written, audit action).
3. **Storage buckets and paths:** in the data dictionary with their access rules.

When adding or changing a contract, update the doc, the migration and the client call sites **in the same change**.

## Layering (applies inside every client)

```
presentation (UI)  ->  application/controller  ->  domain (pure rules)
                              |
                              v
                        data (Supabase I/O)
```

- **Domain** has no Supabase, Flutter or React imports.
- **Data** is the only layer that knows table names, bucket paths and function names.
- **Presentation** reads controller state and forwards intents. It doesn't branch on business rules beyond show/hide, and hiding something is never the security control.
- Dependencies point inward only. A feature may import another feature's `domain` models or its public data provider, but never another feature's widgets or components. Move UI shared by two or more features into `core/` or `shared/`.

## Pragmatic SOLID checklist

- **Single responsibility:** one database function per use case; one repository/service per aggregate (listing, application, order).
- **Open/closed:** state machines are explicit transition lists, so adding a state is a small change.
- **Liskov / interface segregation:** only when two implementations exist; no speculative interfaces.
- **Dependency inversion:** clients inject repositories so tests can replace them with fakes.
- Reject: generic base repositories, service locators, a "utils" dumping ground, inheritance trees for widgets.

## Workflow for a new cross-tier feature

1. Locate it in the handoff (module, state names, roles). Note anything ambiguous, and ask the user if it blocks the work.
2. Write or extend the contract first: data dictionary and API contracts.
3. Backend: migration with policies and functions, plus pgTAP tests (`supabase-backend`, `authentication-authorization`, `unit-testing`).
4. Clients: data layer, controller, then UI (`flutter-development` / `react-dashboard`).
5. Verify the phase pass condition. When the user asks, push the migration and try it on the hosted project.
6. If a decision was made that future work must respect, add `docs/decisions/NNNN-title.md` (context, decision, consequences, about one page).

## Verification checklist

- [ ] Every new artifact maps to a handoff module, and nothing out of scope was added.
- [ ] No client path writes a privileged column; each such change goes through a database function.
- [ ] The contract docs, the migration and the client mirrors are consistent.
- [ ] Domain code imports nothing from Supabase or UI frameworks.
- [ ] No cross-feature UI imports; shared UI lives in `core/` or `shared/`.
- [ ] An ADR exists for any decision that changes a CLAUDE.md non-negotiable (which also needs user approval).
