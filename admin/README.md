# CampusNiaga admin dashboard

The web dashboard for CampusNiaga **reviewers and administrators** (React, TypeScript, Vite, MUI, React Router, TanStack Query, supabase-js). Students use the mobile app; anyone without a staff role is signed out with a "staff only" message.

Design reference: the "Dabang" dashboard (purple `#5D5FEF`, Poppins, pastel summary tiles).

## Run it

```bash
cd admin
npm install        # first time only
npm run dev        # http://localhost:5173
```

Sign in with an account that has a staff role (see "Make yourself an admin" in the root README).

## Pages

| Page | Who | What |
|---|---|---|
| Overview | Reviewer, admin | Admins: account and staff counts, audit events this week, recent activity. Reviewers: the Phase 3 application queue placeholder |
| Users & Roles | Admin | Search accounts; grant or remove reviewer and admin roles (`set_staff_role`); suspend or reactivate accounts (`set_account_status`). All audited. An admin can't remove their own admin role or suspend themselves |
| Audit Log | Admin | Every privileged change, newest first |
| Applications | Reviewer, admin | Phase 3 |
| Reports & Moderation | Admin | Open and closed reports with the listing, reporter and seller. Hide or restore the listing (`moderate_listing`), suspend the seller (`set_account_status`) or dismiss the report (`dismiss_report`), each with an optional note. All audited |

## Checks

```bash
npm run typecheck
npm run lint
npm test           # Vitest + Testing Library (happy-dom)
npm run build
```

## Database types

`src/shared/types/database.ts` is generated from the hosted database, never edited by hand. After a migration is pushed:

```bash
npm run gen:types
```

## Structure

```
src/
├─ app/          App, router, theme, layout (sidebar, top bar, navigation by role)
├─ features/
│  ├─ auth/      staff login, get_my_access, RequireStaff
│  ├─ overview/  summary tiles and recent activity
│  ├─ users/     users & roles
│  └─ audit/     audit log
├─ shared/       Supabase client, generated types, errors, formatting, UI pieces
└─ test/         test setup and render helper
```

Only `services/` files talk to Supabase; pages use hooks, and hooks use services.
