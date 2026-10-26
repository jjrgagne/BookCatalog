# Build & Deploy Plan

How BookCatalog gets from source code onto the household's Android phones.

## Overview

```
 developer PC                    GitHub                         phones
 ────────────                    ──────                         ──────
 flutter run  ──► USB/emulator
 git push ─────────────────────► CI (every push / PR)
                                   analyze · test · debug APK · rules tests
 git tag v1.2.0 ───────────────► Release workflow
                                   signed release APK
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

## 2. Firebase project

**Status: done.** Project `bookcatalog-101fd` (owner jjrgagne@gmail.com):
Firestore `(default)` in `nam5`, Android app
`1:718401821265:android:0ab4c3ad77cfa99e783670` with the test-key fingerprints,
Google sign-in enabled, rules deployed, `android/app/google-services.json`
committed. The steps below are kept for reference (e.g. a new project).

1. <https://console.firebase.google.com> → **Add project** → name `BookCatalog`
   (Google Analytics not needed).
2. **Build → Firestore Database → Create database** → production mode → pick a
   region near you (cannot be changed later).
3. **Build → Authentication → Get started → Sign-in method → Google → Enable.**
4. **Project settings → General → Your apps → Add app → Android.**
   - Package name: `io.github.jjrgagne.bookcatalog`
   - Add these fingerprints of the shared test signing key
     (`android/app/debug.keystore`, used by every build until a release key is
     set up). Google sign-in will not work without them:

     ```
     SHA-1:   23:26:B4:40:AE:9F:4C:85:BB:86:5B:95:81:DA:0C:05:C0:21:C3:11
     SHA-256: 58:23:22:86:7D:99:E5:AD:8D:F2:41:94:6E:23:52:87:95:1E:68:80:2D:D6:41:6F:59:E0:B5:58:93:E4:96:04
     ```

5. Download **`google-services.json`**, put it in `android/app/`, commit and push.
   That's the only file needed: the app initialises Firebase from it, and the
   Gradle build applies the Google Services plugin only when it exists. Builds
   without it run in **this-phone-only mode** (everything works except sharing).
6. Deploy the security rules (section below) **before** anyone signs in. A new
   database in production mode denies everything until they are deployed.

After the next release build, open the app → **More → Household & sharing →
Sign in with Google → Create household**. Others install the same build and
**Join** with the invite code or QR. Books saved before signing in can be copied
into the household from the same screen.

**Is `google-services.json` secret?** No. It identifies the project but does not
grant access; the Firestore security rules do. It is committed so CI can build.
To harden, restrict the API key to the Android app (package name + SHA-1) in
Google Cloud Console → APIs & Services → Credentials.

### Security rules & indexes

`firestore.rules` and `firestore.indexes.json` live in the repo. Deploy them with
the Firebase CLI (needs Node.js):

```bash
npm install -g firebase-tools
```

```bash
firebase login
```

```bash
firebase deploy --only firestore --project <your-firebase-project-id>
```

Or paste the contents of `firestore.rules` into Firebase console → Firestore →
Rules → Publish.

The rules are tested on every push against the Firestore emulator
(`firestore-tests/`, CI job "Firestore security rules"): only household members
can read or write a catalog, joining needs the current invite code, members
can't promote themselves, and removed members lose access.

## Building on a PC with Norton (or other HTTPS-scanning antivirus)

Norton's Web Shield re-signs HTTPS traffic with its own certificate. Windows
trusts it, but Gradle's Java does not, so local Android builds fail with
`PKIX path building failed`. Either exclude Java/Gradle from Norton's SSL
scanning, or tell Gradle to use the Windows certificate store by adding this
line to `%USERPROFILE%\.gradle\gradle.properties`:

```properties
systemProp.javax.net.ssl.trustStoreType=Windows-ROOT
```

CI builds on GitHub are not affected.

## 3. Continuous integration — `.github/workflows/ci.yml`

Runs on every push to `main` and every pull request:

1. Set up Java 17 and Flutter (pinned in `pubspec.yaml`, cached).
2. `flutter pub get`
3. `dart format --set-exit-if-changed .`
4. `flutter analyze`
5. `flutter test`
6. `flutter build apk --debug` → uploaded as a workflow artifact.
7. In a separate job: Firestore security rules tests against the emulator.

## 4. Versioning

- `pubspec.yaml` `version: MAJOR.MINOR.PATCH+BUILD`.
- Releases are cut by pushing a git tag `vMAJOR.MINOR.PATCH`.
- The release workflow uses the tag for the version name and 1000 + the GitHub
  run number for the build number (Android `versionCode`), so every release can
  be installed over the previous one.

## 5. Signing

**Right now every build is signed with a shared test key** committed at
`android/app/debug.keystore` (standard public password `android`). Builds from
any PC or CI have the same signature, so test APKs update over each other and
one SHA-1 goes into Firebase. The catch: anyone with the repo could sign an APK
that installs as an update. That's fine for household testing; switch to a
private release key before giving the app to anyone outside the house.

Android only installs updates signed with the **same key**. Switching from the
test key to a release key means uninstalling once (export a CSV first if you
haven't set up sharing — shared catalogs live in Firebase and are not lost).
The release key must then be kept safe forever.

To switch:

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

5. Add the release key's SHA-1/SHA-256 to Firebase (section 2, step 4) or Google
   sign-in will fail in release builds.

## 6. Release workflow — `.github/workflows/release.yml`

Triggered by pushing a `v*` tag, e.g.:

```bash
git tag v0.2.0
```

```bash
git push origin v0.2.0
```

1. Analyze and test.
2. Sign with the release key if its secrets exist, otherwise the shared test key.
3. `flutter build apk --release` → `bookcatalog-<version>.apk`.
4. Publish a GitHub **pre-release** with the APK attached.
5. If `FIREBASE_SERVICE_ACCOUNT_JSON` and `FIREBASE_ANDROID_APP_ID` secrets
   exist, also upload to Firebase App Distribution (group `household`).

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

- [ ] Android Studio: SDK Manager → install *Android SDK Command-line Tools*;
      then `flutter doctor --android-licenses` (only needed for local builds)
- [ ] Create Firebase project, Firestore database, enable Google sign-in
- [ ] Add the Android app with the test key fingerprints; commit
      `android/app/google-services.json`
- [ ] Deploy `firestore.rules`
- [ ] Tag a new release so the APK includes Firebase
- [ ] (Later) Create a release keystore, back it up, add the signing secrets
- [ ] (Optional) App Distribution service account + secrets; add testers
