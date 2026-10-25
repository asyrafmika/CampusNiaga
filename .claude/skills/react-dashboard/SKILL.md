---
name: react-dashboard
description: Implement or modify the CampusNiaga reviewer/admin web dashboard under admin/ (React, TypeScript, Vite, MUI, React Router, TanStack Query). Use when building pages, components, hooks, services, routing, tables, filters or forms for the application queue, application detail and decisions, status summary, moderation, user access, or audit log. Staff-only route protection is in authentication-authorization; the M2 workflow rules are in business-registration-workflow.
---

# React dashboard: `admin/`

The dashboard is web only and used by **reviewers** (M2 application review) and **admins** (role assignment, moderation, audit). Students never use it. Read `CLAUDE.md` for shared conventions.

## Folder structure (modular, feature-based)

```
admin/src/
├─ main.tsx                      createRoot, providers
├─ app/
│  ├─ App.tsx
│  ├─ router.tsx                 all routes; staff routes wrapped in <RequireStaff role=...>
│  ├─ providers.tsx              ThemeProvider, QueryClientProvider, AuthProvider
│  └─ layout/                    AppShell, nav (items filtered by role)
├─ features/
│  ├─ auth/                      LoginPage, AuthProvider, useAuth, RequireStaff
│  ├─ applications/              queue, detail, decision dialog, status summary (M2)
│  ├─ moderation/                reports list, hide listing, suspend account
│  ├─ users/                     reviewer/admin role assignment
│  └─ audit/                     audit log viewer
└─ shared/
   ├─ firebase/                  client.ts (app/auth/db/storage/functions; emulator wiring), callable.ts
   ├─ types/domain.ts            mirrors docs/data-dictionary.md
   ├─ lib/                       money.ts, dates.ts, errors.ts (reason -> message)
   └─ ui/                        components used by 2+ features (DataTable, StatusChip, ConfirmDialog)
```

Each feature folder:

```
features/<feature>/
├─ pages/          route-level components (<Name>Page.tsx)
├─ components/     feature-private components
├─ hooks/          useXxx: TanStack Query queries and mutations
├─ services/       xxxService.ts: the only files that touch Firestore/Storage/callables
├─ types.ts        feature view types (derived from shared/types/domain.ts)
└─ index.ts        public surface: pages and hooks other code may import
```

Import another feature only through its `index.ts`. Never import from `shared/` back into `app/`.

## Implementation standards

**TypeScript**
- `strict`, `noUncheckedIndexedAccess`, `exactOptionalPropertyTypes`. No `any`; parse Firestore data at the service boundary into typed objects (a small zod schema or a hand-written guard), and reject unknown status values.
- Props are typed with `type XProps = {...}`. Use function components only, with named exports.

**Data flow**
- Services are plain async functions: `listApplications({ status, cursor })`, `reviewApplication(input)`. They know collection names and callable names. Nothing else does.
- Hooks wrap services in TanStack Query: `useApplications(filter)` → `useQuery`; `useReviewApplication()` → `useMutation` that invalidates the affected query keys on success.
- Query keys are defined in one `queryKeys.ts` per feature (`['applications', 'list', filter]`).
- Lists are cursor-paginated (`limit` 20 + `startAfter`). Never fetch a whole collection.
- Status counts use Firestore aggregation (`getCountFromServer`) per status, not by downloading documents.
- Every privileged action (approve, reject, request info, start review, assign role, hide listing, suspend account) calls a **callable**. The dashboard never writes those fields directly; rules would reject it anyway.

**UI**
- MUI components and theme tokens; no inline hex colors. Use `DataTable` from `shared/ui` for queues and logs.
- Each page handles loading (skeleton), empty, error (message from `shared/lib/errors.ts` + retry) and data states.
- Destructive or final actions (approve, reject, suspend) use `ConfirmDialog`. Rejecting or requesting info requires a non-empty remark.
- Show the "Prototype reviewer workflow — not an official USM/HDC decision" notice on application decision screens.
- Open private documents via short-lived download URLs fetched on demand, never stored or logged.
- Render user-supplied text as text (no `dangerouslySetInnerHTML`).

**Components**
- Pages compose hooks and components; they contain no Firestore code and no business rules.
- Business rules a reviewer sees (which actions are valid in which status) come from one function `allowedReviewActions(status)` in the applications feature, matching the server's transition table.

## Workflow

1. Confirm the screen is in the handoff (Web: Reviewer Login / Applications Queue / Application Detail / Decision & Notes / Status Summary; admin: moderation, user access, audit).
2. Add or extend types in `shared/types/domain.ts` if the data dictionary changed.
3. Service function, then a hook, then components, then the page and route.
4. Tests: hooks/services with mocked Firebase modules; components with React Testing Library (see `unit-testing`).
5. Run `npm --prefix admin run typecheck && npm --prefix admin run lint && npm --prefix admin run test`.
6. Manual check with `npm --prefix admin run dev` against seeded emulators, logged in as the seeded reviewer and admin, plus a student account to confirm it's refused.

## Verification checklist

- [ ] No Firestore, Storage or Functions imports outside `services/` and `shared/firebase/`.
- [ ] No privileged field is written directly; each action maps to a documented callable.
- [ ] Every route except `/login` is wrapped in `RequireStaff` with the correct role.
- [ ] Lists are paginated; counts use aggregation queries.
- [ ] `typecheck`, `lint` and `test` all pass; no `any` and no unchecked `!`.
- [ ] Prototype-workflow disclaimer is visible on decision screens.
