---
name: flutter-development
description: Implement or modify the CampusNiaga Flutter student app under mobile/. Use when creating screens, widgets, Riverpod controllers, repositories, domain models, go_router routes, theming, or Firebase client calls in Dart, or when fixing flutter analyze issues. Covers the feature-first layered structure and Dart standards. Auth guards and claims are covered by authentication-authorization; test-writing technique by unit-testing.
---

# Flutter development: `mobile/`

The app is used by verified USM students for M1-M5. Read `CLAUDE.md` for shared conventions. The Dart package name is `mobile`, so imports are `package:mobile/...`.

## Folder structure (feature-first, layered)

```
mobile/lib/
├─ main.dart                      bootstrap only: Firebase init, emulator wiring, ProviderScope, runApp
├─ app.dart                       MaterialApp.router, theme, router provider
├─ core/
│  ├─ config/env.dart             USE_EMULATORS and other --dart-define values
│  ├─ firebase/                   firebase_providers.dart (Auth/Firestore/Storage/Functions instances),
│  │                              callable_client.dart (wraps httpsCallable, maps errors)
│  ├─ domain/                     shared enums mirroring docs/data-dictionary.md, app_failure.dart (sealed)
│  ├─ router/                     app_router.dart, route names, redirect guard (logic from auth feature)
│  ├─ theme/                      color scheme, text theme, spacing constants
│  ├─ utils/                      money.dart (sen <-> RM display), dates.dart, text_normalize.dart
│  └─ widgets/                    widgets shared by 2+ features (empty states, error views, price text)
└─ features/
   ├─ auth/                       login, register, verify email, profile
   ├─ marketplace/                explore/search, listing detail, listing form, my listings, reservations, report
   ├─ business/
   │  ├─ application/             apply, draft, upload docs, track status, respond to request (M2)
   │  └─ store/                   storefront, products, campaigns, orders (M3)
   ├─ discovery/                  product requests, interest, opportunity feed (M4)
   └─ dashboard/                  business performance (M5)
```

Each feature (or sub-feature) has the same three layers:

```
<feature>/
├─ domain/        immutable models, enums, pure rules (no Flutter or Firebase imports)
├─ data/          <aggregate>_repository.dart: Firestore/Storage reads, direct writes, callable invocations
└─ presentation/
   ├─ <name>_screen.dart
   ├─ widgets/
   └─ <name>_controller.dart     Riverpod Notifier/AsyncNotifier + its provider
```

## Implementation standards

**Models (domain)**
- Immutable classes with `final` fields and `const` constructors, plus `factory X.fromFirestore(DocumentSnapshot<Map<String, Object?>>)` and `Map<String, Object?> toMap()` placed in the data layer as extension or mapper functions, so domain stays Firebase-free.
- Statuses are enhanced enums with a `wireName` matching the snake_case value (`ReservationStatus.requested('requested')`), plus a `fromWire` that throws `FormatException` on unknown values.
- Money is `int priceSen`. Format only through `core/utils/money.dart` (`formatRm(int sen)`). Never use `double` for money.
- No code generation (freezed or json_serializable). Write `copyWith` only where it's used.

**State management (Riverpod, no codegen)**
- One controller per screen use case. Expose `AsyncValue<T>`, and render with `.when(data:, loading:, error:)`.
- Repositories are exposed as plain `Provider`s, so tests override them with `ProviderScope(overrides: [...])`.
- Controllers call repositories and apply domain rules. Widgets call controller methods and never call `FirebaseFirestore.instance` or `FirebaseFunctions.instance` directly.
- Use `ref.watch` in build and `ref.read` in callbacks. Cancel subscriptions via `ref.onDispose`.

**Data access**
- All privileged operations (reserve, resolve reservation, submit/resubmit application, place order, transition order, toggle interest) go through `core/firebase/callable_client.dart`. It converts `FirebaseFunctionsException.details['reason']` into an `AppFailure` subtype.
- Queries are paginated (`limit` + `startAfterDocument`, page size 20) and use only indexed field combinations declared in `firebase/firestore.indexes.json`.
- Use streams (`snapshots()`) only for things the user watches change: own reservations, orders, application status. Use one-shot `get()` for feeds.
- Upload photos through the repository, with size and type checked before upload (rules enforce it again).

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
3. Data layer: repository methods, matching `docs/api-contracts.md` for callables.
4. Controller with unit tests (use repository fakes via provider overrides).
5. Screen and widgets; add a widget test for the key states.
6. Run: `cd mobile && dart format lib test && flutter analyze && flutter test`.
7. Manual check with `flutter run --dart-define=USE_EMULATORS=true` against seeded emulators.

## Verification checklist

- [ ] No widget imports `cloud_firestore`, `firebase_auth` or `cloud_functions` directly.
- [ ] Domain folder has no `package:flutter` or `package:cloud_firestore` imports.
- [ ] Money is `int` sen end to end; RM appears only in formatted strings.
- [ ] Status strings match the data dictionary exactly.
- [ ] Loading, empty and error states are handled; errors are shown via `AppFailure` messages.
- [ ] `flutter analyze` is clean and `flutter test` passes.
- [ ] Nothing out of scope (payments, chat, delivery) was added.
