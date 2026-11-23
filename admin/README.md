# CampusNiaga admin dashboard

The web dashboard for CampusNiaga **HDC administrators**, the one staff role ([ADR 0009](../docs/decisions/0009-single-admin-role.md)) (React, TypeScript, Vite, MUI, React Router, TanStack Query, supabase-js). Students use the mobile app; anyone without the administrator role is signed out with a "staff only" message.

Design reference: the "Dabang" dashboard (purple `#5D5FEF`, Poppins, pastel summary tiles).

## Run it

```bash
cd admin
npm install        # first time only
npm run dev        # http://localhost:5173
```

Sign in with an account that has the administrator role (see "Make yourself an admin" in the root README).

## Pages

| Page | Who | What |
|---|---|---|
| Overview | Admin | Business applications per status (`application_status_summary`) with a link to the queue; account and administrator counts, audit events this week and recent activity |
| Users & Roles | Admin | Search accounts; grant or remove the HDC administrator role (`set_staff_role`); suspend or reactivate accounts (`set_account_status`). All audited. An admin can't remove their own admin role or suspend themselves |
| Audit Log | Admin | Every privileged change, newest first |
| Applications | Admin | The simulated reviewer workflow (M2). Status summary tiles and a paginated queue, oldest submission first, by status. Application detail: the business details, documents opened through 60-second signed links, and the status history. Decision & Notes: start review, request changes (note required), approve or reject (note required), each confirmed; approving and rejecting are final and show the prototype disclaimer. Suspend or reinstate the approved business (`set_business_status`). An administrator can't decide their own application. All through `review_business_application`, all audited |
| Business Performance | Admin | Student entrepreneurship performance ([ADR 0007](../docs/decisions/0007-admin-business-performance.md)): totals and every business for a period, and one business's orders by status, estimated revenue, best sellers, stock and pre-orders. Never cost or profit. Every view is audited, so these queries don't refetch on focus |
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
│  ├─ performance/ business performance
│  ├─ users/     users & roles
│  └─ audit/     audit log
├─ shared/       Supabase client, generated types, errors, formatting, UI pieces
└─ test/         test setup and render helper
```

Only `services/` files talk to Supabase; pages use hooks, and hooks use services.
