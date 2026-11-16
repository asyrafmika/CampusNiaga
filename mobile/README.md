# 📱 CampusNiaga student app

The Flutter app for USM students and approved student businesses: the marketplace (M1), business applications (M2), storefronts and orders (M3), opportunity discovery (M4) and the business dashboard (M5). See the [main README](../README.md) for the whole project.

## Run it

```bash
flutter emulators --launch Pixel_9
flutter pub get
flutter run
```

The app connects to the hosted Supabase project set in `lib/core/config/supabase_config.dart`.

## Checks

```bash
flutter analyze
dart format --output=none --set-exit-if-changed lib test
flutter test
```

## Structure

```
lib/
├─ core/       config, Supabase guard and errors, domain enums, router, storage, theme, utils, shared widgets
└─ features/
   ├─ onboarding/    first-launch slides
   ├─ auth/          sign in, sign up, access gate, profile
   ├─ marketplace/   feed, search, listing detail and form, reservations (M1)
   ├─ business/
   │  ├─ application/  apply, documents, track status (M2)
   │  └─ store/        storefront, orders, my store, pre-orders (M3)
   ├─ discovery/     opportunities and product requests (M4)
   └─ dashboard/     business dashboard (M5)
```

Each feature has `data/` (repositories over Supabase), `domain/` (models and rules) and `presentation/` (screens and widgets).

## Release builds and screenshots

- APKs are built and published by GitHub Actions on each version tag; see [docs/deployment.md](../docs/deployment.md), including the signing key.
- `flutter test test_screenshots` re-renders the README screenshots with demo data into `../docs/images/mobile/`.
