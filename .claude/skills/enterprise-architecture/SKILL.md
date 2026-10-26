---
name: enterprise-architecture
description: Decide where new CampusNiaga code belongs and how the mobile app, admin dashboard and Cloud Functions divide a feature. Use when starting a new module or feature that spans more than one tier, creating new top-level folders or packages, defining contracts between clients and the backend, resolving a module-boundary question, or recording an architectural decision (ADR). Not for single-tier implementation details; use flutter-development, react-dashboard or firebase-backend for those.
---

# Enterprise architecture: CampusNiaga

This skill is the map. It decides *where* code goes and *which tier owns which responsibility*. The tier skills decide *how* to write it.

Read `CLAUDE.md` first. Its non-negotiables and data conventions apply here and aren't repeated.

## Tier responsibilities

| Tier | Owns | Never does |
|---|---|---|
| `mobile/` (Flutter) | Student UX for M1-M5, local validation for UX, reading permitted data, calling callables | Privileged writes, role/status/owner changes, stock or capacity arithmetic, ranking |
| `admin/` (React) | Reviewer and admin UX for M2, moderation, user access, audit viewing | Writing approvals or roles directly to Firestore; it calls callables |
| `functions/` | Every state transition with authority: approvals, reservations, orders, allocations, claims, audit logs, M4 recompute | UI concerns; trusting any client-supplied role, status, owner or price |
| `firebase/` rules | Default-deny; owner-scoped direct writes for non-privileged fields; role-scoped reads | Business workflows (keep rules small and use functions for workflows) |

**Rule for choosing direct write vs callable:** a client may write a document directly only if (a) the caller owns it, (b) the change can't affect another user, stock, money, roles or any status other than its own draft/edit state, and (c) rules can fully validate it. Everything else is a callable.

Examples: editing own profile name, saving a business-application draft, marking own notification read → direct write. Creating or editing listings (rate limits and derived search fields, ADR 0002), reserving, ordering, approving, toggling interest, hiding listings → callable.

## Module-to-code map

| Module | Mobile feature folder | Admin feature folder | Functions area |
|---|---|---|---|
| Auth / gate | `features/auth` | `features/auth` | `callable/auth/*` |
| M1 | `features/marketplace` | `features/moderation` | `callable/marketplace/*` |
| M2 | `features/business/application` | `features/applications` | `callable/business/*` |
| M3 | `features/business/store` | (none) | `callable/orders/*`, `callable/campaigns/*` |
| M4 | `features/discovery` | (none) | `callable/discovery/*`, `triggers/opportunities/*`, `domain/opportunity/*` |
| M5 | `features/dashboard` | (none) | (reads only; aggregation in client or a callable if rules can't scope it) |
| Admin | (none) | `features/users`, `features/audit` | `callable/admin/*` |

Don't create a module, collection, screen or callable that isn't traceable to the handoff. If a feature seems to need one, stop and ask the user.

## Contracts between tiers

Contracts are the stable surface, and changing them is a breaking change:

1. **Firestore document shapes and status values**: `docs/data-dictionary.md`, mirrored in one domain-types file per codebase (see CLAUDE.md).
2. **Callable APIs**: `docs/api-contracts.md`. Each entry lists name, caller requirements (claims), input schema, output shape, the `details.reason` values it can raise, and side effects (documents written, audit action).
3. **Storage paths**: listed in the data dictionary with their access rules.

When adding or changing a contract, update the doc, the functions zod schema and the client call sites **in the same change**.

## Layering (applies inside every tier)

```
presentation (UI)  ->  application/controller  ->  domain (pure rules)
                              |
                              v
                        data (Firebase I/O)
```

- **Domain** has no Firebase, Flutter or React imports. State machines, money arithmetic and M4 scoring live here and are unit-tested.
- **Data** is the only layer that knows Firestore paths, Storage paths and callable names.
- **Presentation** reads controller state and forwards intents. It doesn't branch on business rules beyond show/hide, and hiding something is never the security control.
- Dependencies point inward only. A feature may import another feature's `domain` models or its public data provider, but never another feature's widgets or components. Move UI shared by two or more features into `core/` or `shared/`.

## Pragmatic SOLID checklist

- **Single responsibility:** one callable per use case; one repository/service per aggregate (listing, application, order).
- **Open/closed:** state machines are transition tables (data), so adding a state doesn't mean rewriting branching logic.
- **Liskov / interface segregation:** only when two implementations exist; don't create speculative interfaces.
- **Dependency inversion:** inject Firebase clients and the clock (`now()`) into services so they can be tested with emulators or fakes.
- Reject: generic base repositories, service locators, an "utils" dumping ground, inheritance trees for widgets.

## Workflow for a new cross-tier feature

1. Locate it in the handoff (module, state names, roles). Note anything ambiguous, and ask the user if it blocks the work.
2. Write or extend the contract first: data dictionary entries, callable spec in `docs/api-contracts.md`.
3. Backend: domain logic with tests, then rules with tests, then the callable with emulator tests (`firebase-backend`, `authentication-authorization`, `unit-testing`).
4. Clients: data layer, controller, then UI (`flutter-development` / `react-dashboard`).
5. Verify the phase pass condition end-to-end on the emulators.
6. If a decision was made that future work must respect, add `docs/decisions/NNNN-title.md` (context, decision, consequences, max ~1 page).

## Verification checklist

- [ ] Every new artifact maps to a handoff module, and nothing out of scope was added.
- [ ] No client path writes a privileged field; each such write goes through a callable.
- [ ] The contract docs and the three domain-type mirrors are consistent.
- [ ] Domain code imports nothing from Firebase or UI frameworks.
- [ ] No cross-feature UI imports; shared UI lives in `core/` or `shared/`.
- [ ] An ADR exists for any decision that changes a CLAUDE.md non-negotiable (which also needs user approval).
