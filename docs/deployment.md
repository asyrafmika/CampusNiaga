# Deployment

How the two CampusNiaga apps are published from GitHub. Both talk to the hosted Supabase project directly, so deploying them never changes the database. Migrations are applied separately with `supabase db push` (README, "Getting started").

| App | Where it goes | Workflow | How it starts |
|---|---|---|---|
| 📱 Mobile (Android) | An `.apk` attached to a [GitHub Release](https://github.com/asyrafmika/CampusNiaga/releases) | [`release-apk.yml`](../.github/workflows/release-apk.yml) | Pushing a version tag (`v1.0.0`), or by hand |
| 🖥️ Admin dashboard | GitHub Pages, https://asyrafmika.github.io/CampusNiaga/ | [`admin-pages.yml`](../.github/workflows/admin-pages.yml) | Every change to `admin/` on `main`, or by hand |

## 📱 Releasing the Android app

1. Make sure `main` is green in CI.
2. Tag the commit with the version and push the tag:

   ```bash
   git checkout main && git pull
   git tag v1.0.0
   git push origin v1.0.0
   ```

3. The workflow runs the Flutter tests, builds a release APK (version `1.0.0`, build number = the workflow run number) and creates the release **CampusNiaga v1.0.0** with `CampusNiaga-1.0.0.apk` attached.

To build an APK without a release, open **Actions → Release Android app → Run workflow**. The APK is then a downloadable artifact of that run.

**Installing:** on the Android phone, download the APK from the release, open it and allow installs from that source (Android asks once). While the repository is private, only people with access to it can download releases.

### Signing key (do once)

Android only installs an update over an existing app when both are signed with the same key. Until the key below is set up, the workflow signs with a temporary debug key: the APK installs, but each new version has to replace the old one by uninstalling it first (which also signs the user out).

Run in PowerShell from the repository root. `keytool` comes with Android Studio.

```powershell
cd mobile/android
& "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v `
  -keystore app/upload-keystore.jks -storetype PKCS12 -keyalg RSA -keysize 2048 `
  -validity 10000 -alias campusniaga
```

`keytool` asks for a password and your name. Then create `mobile/android/key.properties` (both files are ignored by git and must never be committed):

```properties
storePassword=<the password you chose>
keyPassword=<the same password>
keyAlias=campusniaga
storeFile=upload-keystore.jks
```

Local `flutter build apk --release` builds now use this key. Give the same key to GitHub as secrets:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("app/upload-keystore.jks")) | gh secret set ANDROID_KEYSTORE_BASE64
gh secret set ANDROID_KEYSTORE_PASSWORD   # paste the password when asked
gh secret set ANDROID_KEY_ALIAS --body campusniaga
```

Keep a backup of `upload-keystore.jks` and its password, for example in your password manager. If they are lost, future versions can't update existing installs.

## 🖥️ Publishing the admin dashboard

The dashboard is a static site (Vite build), so GitHub Pages can host it. The workflow builds it with the base path `/CampusNiaga/` and copies `index.html` to `404.html`, so links such as `/CampusNiaga/applications/<id>` open directly.

**Status:** live at https://asyrafmika.github.io/CampusNiaga/ since 17 Nov 2026 (the repository is public; a private one would need GitHub Pro for Pages).

How it was switched on, for reference:

1. **Settings → Pages → Build and deployment → Source:** choose **GitHub Actions**.
2. **Settings → Secrets and variables → Actions → Variables → New repository variable:** name `ADMIN_PAGES_ENABLED`, value `true`.
3. **Actions → Deploy admin dashboard → Run workflow** (or push any change to `admin/`).

Without the variable, the workflow only builds and tests the dashboard and skips the deploy job. Deleting the variable is the way to pause deployments.

**Supabase settings:** none needed. The dashboard signs in with email and password and sends no email links, and the publishable key in `admin/src/shared/supabase/client.ts` is designed to be public: Row Level Security and the staff role checks in the database decide what each person can see. Anyone can open the page, but only accounts with a reviewer or admin role get past the login.

## 📸 Refreshing the README screenshots

- **Mobile:** `cd mobile && flutter test test_screenshots` renders the screens with demo data (no emulator or account needed) into `docs/images/mobile/`. This folder is outside `test/`, so CI never runs it.
- **Admin:** screenshots of the running dashboard (`npm --prefix admin run dev`), signed in as a staff account, saved into `docs/images/admin/` at 1440×900.
