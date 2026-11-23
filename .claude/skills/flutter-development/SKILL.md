---
name: flutter-development
description: Implement or modify the CampusNiaga Flutter student app under mobile/. Use when creating screens, widgets, Riverpod controllers, repositories, domain models, go_router routes, theming, or Supabase client calls in Dart, or when fixing flutter analyze issues. Covers the feature-first layered structure and Dart standards. Auth guards and roles are covered by authentication-authorization; test-writing technique by unit-testing.
---

# Flutter development: `mobile/`

The app is used by verified USM students for M1-M5. Read `CLAUDE.md` for shared conventions. The Dart package name is `mobile`, so imports are `package:mobile/...`.

## Folder structure (feature-first, layered)

```
mobile/lib/
├─ main.dart                      bootstrap only: Supabase init, ProviderScope, runApp (startup errors shown on screen)
├─ app.dart                       MaterialApp.router, theme, router provider
├─ core/
│  ├─ config/supabase_config.dart project URL and publishable key (public by design)
│  ├─ supabase/                   supabase_bootstrap.dart (Supabase.initialize),
│  │                              supabase_providers.dart (client provider),
│  │                              rpc_client.dart (wraps client.rpc, maps error details to AppFailure)
│  ├─ domain/                     shared enums mirroring docs/data-dictionary.md, app_failure.dart (sealed)
│  ├─ router/                     app_router.dart, route names, redirect guard (logic from auth feature)
│  ├─ theme/                      color scheme, text theme, spacing constants
│  ├─ utils/                      money.dart (sen <-> RM display), dates.dart, text_normalize.dart
│  └─ widgets/                    widgets shared by 2+ features (empty states, error views, price text)
└─ features/
   ├─ auth/                       login, register, verify email, profile
   ├─ marketplace/                explore/search, listing detail, listing form, my listings, purchases, report
   ├─ business/
   │  ├─ application/             apply, draft, upload docs, track status, respond to request (M2)
   │  └─ store/                   storefront, products, campaigns, orders (M3)
   ├─ discovery/                  product requests, interest, opportunity feed (M4)
   └─ dashboard/                  business performance (M5)
```

Each feature (or sub-feature) has the same three layers:

```
<feature>/
├─ domain/        immutable models, enums, pure rules (no Flutter or Supabase imports)
├─ data/          <aggregate>_repository.dart: table reads, permitted direct writes, Storage, RPC calls
└─ presentation/
   ├─ <name>_screen.dart
   ├─ widgets/
   └─ <name>_controller.dart     Riverpod Notifier/AsyncNotifier + its provider
```

## Implementation standards

**Models (domain)**
- Immutable classes with `final` fields and `const` constructors, plus `fromRow(Map<String, Object?>)` / `toRow()` mappers for the `snake_case` columns, placed in the data layer so domain stays Supabase-free.
- Statuses are enhanced enums with a `wireName` matching the snake_case value (`PurchaseStatus.completed('completed')`), plus a `fromWire` that throws `FormatException` on unknown values.
- Money is `int priceSen`. Format only through `core/utils/money.dart` (`formatRm(int sen)`). Never use `double` for money.
- No code generation (freezed or json_serializable). Write `copyWith` only where it's used.

**State management (Riverpod, no codegen)**
- One controller per screen use case. Expose `AsyncValue<T>`, and render with `.when(data:, loading:, error:)`.
- Repositories are exposed as plain `Provider`s, so tests override them with `ProviderScope(overrides: [...])`.
- Controllers call repositories and apply domain rules. Widgets call controller methods and never call `Supabase.instance.client` directly.
- Use `ref.watch` in build and `ref.read` in callbacks. Cancel subscriptions via `ref.onDispose`.

**Data access**
- All privileged operations (buy, change a purchase, submit/resubmit application, place order, transition order, toggle interest) go through `core/supabase/rpc_client.dart`. It converts a `PostgrestException` whose `details` holds a reason (e.g. `ITEM_UNAVAILABLE`) into an `AppFailure` subtype.
- Queries are paginated (`range` or keyset on `created_at`, page size 20), select only needed columns, and match indexes declared in the migrations.
- Use streams (`snapshots()`) only for things the user watches change: own purchases, orders, application status. Use one-shot `get()` for feeds.
- Upload photos through the repository: resize on the device first (about 1280 px longest side, 80% JPEG quality), then check size and type (rules enforce it again).
- Listing create/edit calls `upsertListing`; the app never writes `listings` documents directly (ADR 0002).

**UI**
- Material 3, a theme from `core/theme`, and no hard-coded colors or text styles in feature widgets.
- Screens are thin: layout + `ref.watch(controller)`. Extract a widget once a build method is more than about 80 lines or a subtree repeats.
- Every async screen has loading, empty, error (with retry) and data states.
- Business-only entry points are hidden for non-business users, but the server still enforces access. Revenue and profit always carry the label "Estimated (self-reported)". Opportunity results say "Possible opportunity".
- Display only the contact details the handoff allows (no full profiles of other students).

**Routing (go_router)**
- Route paths and names are constants in `core/router`. Feature screens are registered in one router file.
- The redirect guard reads a single `authStateProvider` (see `authentication-authorization` for the gating rules).

**Dart style**
- `flutter_lints` plus strict analyzer modes. Fix all analyzer warnings and infos in touched files.
- Prefer `final`, `const` constructors and trailing commas; use `switch` expressions over sealed types and enums.
- Don't use `print`; use `debugPrint` only in development code paths.

## Workflow

1. Identify the module and screen in the handoff's required-UI list.
2. Create or extend domain models and enums, mirroring `docs/data-dictionary.md`.
3. Data layer: repository methods, matching `docs/api-contracts.md` for database functions.
4. Controller with unit tests (use repository fakes via provider overrides).
5. Screen and widgets; add a widget test for the key states.
6. Run: `cd mobile && dart format lib test && flutter analyze && flutter test`.
7. Manual check with `flutter run` on an Android emulator against the hosted project.

## Verification checklist

- [ ] No widget imports `supabase_flutter` directly.
- [ ] Domain folder has no `package:flutter` or `package:supabase_flutter` imports.
- [ ] Money is `int` sen end to end; RM appears only in formatted strings.
- [ ] Status strings match the data dictionary exactly.
- [ ] Loading, empty and error states are handled; errors are shown via `AppFailure` messages.
- [ ] `flutter analyze` is clean and `flutter test` passes.
- [ ] Nothing out of scope (payments, chat, delivery) was added.
