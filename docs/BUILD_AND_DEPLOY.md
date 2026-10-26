# Build & Deploy Plan

How BookCatalog gets from source code onto the household's Android phones.

## Overview

```
 developer PC                    GitHub                         phones
 ────────────                    ──────                         ──────
 flutter run  ──► USB/emulator
 git push ─────────────────────► CI (every push / PR)
                                   analyze · test · debug APK
 git tag v1.2.0 ───────────────► Release workflow
                                   signed APK + AAB
                                   ├─► GitHub Release (APK download)
                                   └─► Firebase App Distribution ──► testers' phones
```

## 1. Local development environment (Windows)

| Tool | Status / how |
|---|---|
| Git, GitHub CLI | Installed via winget |
| Flutter SDK (stable) | `C:\src\flutter`, on the user PATH |
| Android Studio | Installs Android SDK, platform-tools (adb), emulator, and a bundled JDK |
| Flutter + Dart plugins | Android Studio → Settings → Plugins (or use VS Code with the Flutter extension) |

After Android Studio is installed:

1. Open Android Studio → **More Actions → SDK Manager**:
   - SDK Platforms: latest stable Android API.
   - SDK Tools: *Android SDK Command-line Tools (latest)*, *Android SDK
     Platform-Tools*, *Android Emulator*.
2. Accept the Android SDK licenses (you must review and accept these yourself):

   ```bash
   flutter doctor --android-licenses
   ```

3. Check everything is green for Android (Windows/web/Chrome items can be ignored):

   ```bash
   flutter doctor -v
   ```

4. Testing on a real phone (recommended — the camera is the whole point):
   Settings → About phone → tap *Build number* 7 times → Developer options →
   enable **USB debugging**, plug in, accept the prompt, then `flutter devices`.

Day-to-day: `flutter run` (hot reload with `r`), `flutter test`, `flutter analyze`.

## 2. Firebase project (one-time, done in the browser by the owner)

1. <https://console.firebase.google.com> → **Add project** → name `BookCatalog`
   (Google Analytics not needed).
2. **Build → Firestore Database → Create database** → production mode → pick a
   region near you (cannot be changed later).
3. **Build → Authentication → Get started → Sign-in method → Google → Enable.**
4. Connect the Flutter app with the FlutterFire CLI (needs Node.js for the
   Firebase CLI):

   ```bash
   npm install -g firebase-tools
   ```

   ```bash
   firebase login
   ```

   ```bash
   dart pub global activate flutterfire_cli
   ```

   ```bash
   flutterfire configure --project=<your-firebase-project-id> --platforms=android --android-package-name=io.github.jjrgagne.bookcatalog
   ```

   This generates `lib/firebase_options.dart` and
   `android/app/google-services.json`.
5. **Google sign-in needs the signing certificate fingerprints.** Add the SHA-1 and
   SHA-256 of the debug key (and later the release key) under Project settings →
   Your apps → Android app → *Add fingerprint*:

   ```bash
   keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android
   ```

**Are the Firebase config files secret?** No. `google-services.json` and
`firebase_options.dart` identify the project but do not grant access; the
Firestore security rules do. They are committed so CI can build. To harden, restrict
the API key to the Android app (package name + SHA-1) in Google Cloud Console →
APIs & Services → Credentials.

### Security rules & indexes

`firestore.rules` and `firestore.indexes.json` live in the repo and are deployed
with:

```bash
firebase deploy --only firestore
```

Rules are tested locally against the Firestore emulator before deploying (M3).

## 3. Continuous integration — `.github/workflows/ci.yml`

Runs on every push to `main` and every pull request:

1. Set up Java 17 and Flutter (pinned version, cached).
2. `flutter pub get`
3. `dart format --set-exit-if-changed .`
4. `flutter analyze`
5. `flutter test`
6. `flutter build apk --debug` → uploaded as a workflow artifact (handy for
   installing a test build without a PC: download the artifact, unzip, open the APK).

Until the Flutter project is created in M0, the workflow skips the Flutter steps.

## 4. Versioning

- `pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD`.
- Releases are cut by pushing a git tag `vMAJOR.MINOR.PATCH`.
- The release workflow uses the tag for the version name and the GitHub run
  number for the build number (Android `versionCode`), so every release can be
  installed over the previous one.

## 5. Release signing

Android only installs updates signed with the **same key**, so the release key
must be created once and kept safe forever.

1. The owner creates the upload keystore (choose your own passwords; never commit
   them):

   ```bash
   keytool -genkey -v -keystore "$env:USERPROFILE\bookcatalog-upload.jks" -keyalg RSA -keysize 2048 -validity 10000 -alias upload
   ```

2. Back it up somewhere safe (password manager / encrypted backup).
3. Local release builds read `android/key.properties` (git-ignored):

   ```properties
   storeFile=C:\\Users\\<you>\\bookcatalog-upload.jks
   storePassword=...
   keyAlias=upload
   keyPassword=...
   ```

4. For CI, add these **GitHub repository secrets** (Settings → Secrets and
   variables → Actions) — entered by the owner, not by automation:

   | Secret | Value |
   |---|---|
   | `ANDROID_KEYSTORE_BASE64` | `[Convert]::ToBase64String([IO.File]::ReadAllBytes("<path>.jks"))` |
   | `ANDROID_KEYSTORE_PASSWORD` | keystore password |
   | `ANDROID_KEY_ALIAS` | `upload` |
   | `ANDROID_KEY_PASSWORD` | key password |

5. Add the release key's SHA-1/SHA-256 to Firebase (step 2.5) or Google sign-in
   will fail in release builds.

## 6. Release workflow — `.github/workflows/release.yml` (M6)

Triggered by pushing a `v*` tag:

1. Same checks as CI.
2. Decode the keystore from secrets, build `flutter build apk --release` and
   `flutter build appbundle --release`.
3. Create a GitHub Release with the APK attached.
4. Upload the APK to Firebase App Distribution for the `household` tester group.

## 7. Getting the app onto phones

| Option | Cost | Updates | Recommendation |
|---|---|---|---|
| **Firebase App Distribution** | Free | Testers get an email / App Tester app notification for each release | **Recommended** — already on Firebase, easy updates |
| GitHub Release APK (sideload) | Free | Manual download each time; needs "install unknown apps" | Fallback / quick tests |
| Google Play internal testing | $25 one-time developer account | Automatic via Play Store | Later, if wanted |

For App Distribution, CI needs a Firebase service account:
Google Cloud Console → IAM → Service accounts → create one with the
*Firebase App Distribution Admin* role → JSON key → GitHub secret
`FIREBASE_SERVICE_ACCOUNT_JSON`, plus `FIREBASE_ANDROID_APP_ID` (from Project
settings). Testers are added by email in the Firebase console.

## Checklist of owner-only steps

These require your accounts or secrets and are not automated:

- [ ] Finish Android Studio install, SDK components, accept Android licenses
- [ ] Create Firebase project, Firestore database, enable Google sign-in
- [ ] Run `flutterfire configure`; add debug SHA fingerprints
- [ ] Create the release keystore and back it up
- [ ] Add GitHub Actions secrets for signing and App Distribution
- [ ] Add household members as App Distribution testers
