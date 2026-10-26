# Creates the BookCatalog milestones, labels and issues on GitHub.
# Safe to re-run: existing milestones/issues (matched by title) are skipped and
# labels are updated in place. Requires the GitHub CLI, signed in (gh auth login).

param([string]$Repo = 'jjrgagne/BookCatalog')

$ErrorActionPreference = 'Stop'

$labels = @(
    @{ name = 'infra';            color = '5319e7'; description = 'Project setup, CI/CD, tooling' }
    @{ name = 'scan';             color = '1d76db'; description = 'Barcode scanning and metadata lookup' }
    @{ name = 'ocr';              color = '0e8a16'; description = 'OCR and manual entry' }
    @{ name = 'catalog';          color = 'fbca04'; description = 'Book storage, list, search, edit' }
    @{ name = 'sharing';          color = 'd93f0b'; description = 'Auth, households, security rules, sync' }
    @{ name = 'locations-tags';   color = 'c5def5'; description = 'Locations (rooms/people) and tags' }
    @{ name = 'release';          color = 'b60205'; description = 'Signing, release builds, distribution' }
    @{ name = 'needs-owner';      color = 'e99695'; description = 'Needs a manual step by the repo owner (accounts, secrets, consoles)' }
)

$milestones = @(
    @{ title = 'M0 - Project setup';      description = 'Flutter project, Firebase project, CI, ISBN utilities with tests, app skeleton.' }
    @{ title = 'M1 - Scan & lookup';      description = 'Scan a barcode and see the book''s details.' }
    @{ title = 'M2 - Catalog';            description = 'Save, list, search and edit books (incl. notes), working offline.' }
    @{ title = 'M3 - Sharing';            description = 'Google sign-in, households, invites, security rules, multi-phone sync.' }
    @{ title = 'M4 - Locations & tags';   description = 'Room/person locations, tags, batch scanning, filters, duplicate detection.' }
    @{ title = 'M5 - OCR & manual entry'; description = 'Fallbacks for books without a scannable barcode.' }
    @{ title = 'M6 - Release';            description = 'App icon, CSV export, signed release builds, distribution to household phones.' }
)

$issues = @(
    # ---------------- M0 ----------------
    @{ m = 0; labels = 'infra'; title = 'Create Flutter project (Android only)'; body = @'
Create the Flutter app in the repo root.

- [ ] `flutter create --org io.github.jjrgagne --project-name bookcatalog --platforms android .`
- [ ] Application ID `io.github.jjrgagne.bookcatalog`, minSdk 24
- [ ] Pin the Flutter version in `pubspec.yaml` (`environment: flutter: <version>`) - CI reads it via `flutter-version-file`
- [ ] Add `flutter_lints` / `analysis_options.yaml`
- [ ] `flutter analyze` and `flutter test` pass; CI green
'@ }
    @{ m = 0; labels = 'infra,needs-owner'; title = 'Create Firebase project and connect the app'; body = @'
See docs/BUILD_AND_DEPLOY.md section 2.

- [ ] Create Firebase project `BookCatalog` (no Analytics)
- [ ] Create Firestore database (production mode, choose region)
- [ ] Enable Authentication > Google
- [ ] Install Firebase CLI + FlutterFire CLI
- [ ] `flutterfire configure --platforms=android` -> commit `lib/firebase_options.dart` and `android/app/google-services.json`
- [ ] Add debug keystore SHA-1/SHA-256 fingerprints
- [ ] Add `firebase.json`, `firestore.rules` (deny-all placeholder), `firestore.indexes.json`
'@ }
    @{ m = 0; labels = 'infra'; title = 'CI: analyze, test and build debug APK'; body = @'
`.github/workflows/ci.yml` already exists and skips Flutter steps until `pubspec.yaml` exists.

- [ ] Confirm it runs green once the Flutter project lands
- [ ] Debug APK artifact downloadable from the workflow run
- [ ] (Optional) branch protection on `main` requiring CI
'@ }
    @{ m = 0; labels = 'scan'; title = 'ISBN utilities with unit tests'; body = @'
`lib/core/isbn.dart`:

- [ ] Normalise input (strip hyphens/spaces, uppercase X)
- [ ] Validate ISBN-10 (mod 11, `X` = 10) and ISBN-13 (mod 10, 978/979 prefix)
- [ ] Convert ISBN-10 -> ISBN-13 and ISBN-13 (978 only) -> ISBN-10
- [ ] Extract ISBN candidates from free OCR text (e.g. `ISBN 0-306-40615-2`, `ISBN-13: 978-...`), returning only checksum-valid ones
- [ ] Format for display with hyphens (optional)
- [ ] Thorough unit tests incl. invalid checksums, 979 prefixes, OCR noise (O/0, I/1, S/5)
'@ }
    @{ m = 0; labels = 'infra'; title = 'App skeleton: routing, state, theme, empty screens'; body = @'
- [ ] Add riverpod, go_router, freezed/json_serializable (+ build_runner)
- [ ] Material 3 theme (light/dark)
- [ ] Bottom navigation: Library, Scan, Locations, Household
- [ ] Placeholder screens
- [ ] Firebase initialised in `main.dart`
'@ }

    # ---------------- M1 ----------------
    @{ m = 1; labels = 'scan'; title = 'Barcode scanner screen'; body = @'
- [ ] `mobile_scanner` with camera permission handling (rationale + settings link if denied)
- [ ] Restrict to EAN-13; accept only 978/979 prefixes; ignore EAN-5 add-ons
- [ ] Debounce repeated reads of the same code
- [ ] Torch toggle; haptic/beep on successful scan
- [ ] Test on real shelves (glossy covers, low light, curved spines)
'@ }
    @{ m = 1; labels = 'scan'; title = 'Metadata lookup: Open Library client'; body = @'
- [ ] `GET https://openlibrary.org/api/books?bibkeys=ISBN:<isbn>&format=json&jscmd=data`
- [ ] Map to a `BookMetadata` model (title, subtitle, authors, publisher, year, cover URL)
- [ ] Set a descriptive User-Agent per Open Library guidelines
- [ ] Timeouts and error handling; unit tests with recorded JSON fixtures
'@ }
    @{ m = 1; labels = 'scan'; title = 'Metadata lookup: Google Books fallback'; body = @'
- [ ] `GET https://www.googleapis.com/books/v1/volumes?q=isbn:<isbn>`
- [ ] Used when Open Library has no result or is missing key fields (merge results)
- [ ] Optional API key via `--dart-define` (works without one at low volume)
- [ ] Unit tests with fixtures
'@ }
    @{ m = 1; labels = 'scan'; title = 'Scan result confirmation card'; body = @'
- [ ] Show cover, title, authors, year after a scan
- [ ] Loading and "not found -> enter manually" states
- [ ] Actions: Save (wired up in M2), Scan next, Discard
'@ }

    # ---------------- M2 ----------------
    @{ m = 2; labels = 'catalog'; title = 'Book model and Firestore repository'; body = @'
- [ ] `Book` model per PLAN.md data model (incl. `notes`, `copies`, `metadataSource`)
- [ ] `BookRepository` (watch all, get, add, update, delete) on `households/{id}/books`
- [ ] Firestore offline persistence enabled; verify writes while in airplane mode sync later
- [ ] Until M3, use a single fixed development household
'@ }
    @{ m = 2; labels = 'catalog'; title = 'Save scanned books and library list'; body = @'
- [ ] Save from the confirmation card
- [ ] Library screen: list and grid views with cover thumbnails (cached images)
- [ ] Sort by title / author / date added
- [ ] Empty state that points to Scan
'@ }
    @{ m = 2; labels = 'catalog'; title = 'Search by title, author or ISBN'; body = @'
Client-side search over the cached catalog (Firestore has no full-text search).

- [ ] Case/diacritic-insensitive matching on title, subtitle, authors
- [ ] ISBN search accepts ISBN-10 or -13, with or without hyphens
- [ ] Stays responsive with ~5,000 books
'@ }
    @{ m = 2; labels = 'catalog'; title = 'Book detail and edit screen (incl. notes)'; body = @'
- [ ] View all fields; edit title/authors/etc. to correct bad metadata
- [ ] Free-text `notes` field (multi-line)
- [ ] Copies count
- [ ] Delete with confirmation
'@ }

    # ---------------- M3 ----------------
    @{ m = 3; labels = 'sharing'; title = 'Google sign-in with Firebase Auth'; body = @'
- [ ] Sign-in screen; stay signed in across launches
- [ ] Sign out from Household screen
- [ ] Works on debug builds (SHA fingerprints registered in Firebase)
'@ }
    @{ m = 3; labels = 'sharing'; title = 'Households: create, join by invite code / QR'; body = @'
- [ ] First sign-in: "Create household" or "Join household"
- [ ] Invite code (short, human-typeable) + QR code to scan from another phone
- [ ] Owner can regenerate the code and remove members
- [ ] Members list on Household screen
'@ }
    @{ m = 3; labels = 'sharing'; title = 'Firestore security rules + emulator tests'; body = @'
- [ ] Only members of a household can read/write its subcollections
- [ ] Joining requires a valid invite code; members cannot change their own role
- [ ] Field validation on books (types, required fields, size limits)
- [ ] Rules unit tests against the Firestore emulator; run in CI
- [ ] Deploy with `firebase deploy --only firestore`
'@ }
    @{ m = 3; labels = 'sharing'; title = 'Verify multi-phone sync'; body = @'
- [ ] Two phones, two Google accounts, one household
- [ ] Scan on one, appears on the other within seconds
- [ ] Offline edits on both, reconnect, check results are sensible
'@ }

    # ---------------- M4 ----------------
    @{ m = 4; labels = 'locations-tags'; title = 'Locations: rooms and people'; body = @'
- [ ] Location model with `kind`: `room` | `person`
- [ ] Locations screen with two sections (Rooms, On loan to); add/rename/reorder/delete (delete only when empty or after moving books)
- [ ] "Move to..." on book detail, and bulk move from a multi-select in the library
- [ ] Decide: store `previousLocationId` for a one-tap "Return" from a person to their room?
'@ }
    @{ m = 4; labels = 'locations-tags'; title = 'Tags: manage and assign'; body = @'
- [ ] Tags screen: add/rename/recolor/delete
- [ ] Assign multiple tags on the scan card and on book detail
- [ ] Bulk tag from multi-select
'@ }
    @{ m = 4; labels = 'locations-tags,scan'; title = 'Current-location batch scanning'; body = @'
- [ ] Location (and optional default tags) picker on the scan screen; remembered between sessions
- [ ] Continuous scanning: each scan auto-saves to the current location
- [ ] Running list of this session's scans with undo
- [ ] Offline queue: ISBNs saved immediately, metadata fetched when back online
'@ }
    @{ m = 4; labels = 'locations-tags,catalog'; title = 'Library filters by location and tag'; body = @'
- [ ] Filter chips for location (rooms and people) and tags; combine with search
- [ ] Per-location counts on the Locations screen
'@ }
    @{ m = 4; labels = 'catalog,scan'; title = 'Duplicate detection on scan'; body = @'
- [ ] Match on normalised ISBN-13
- [ ] Prompt: "Already in <location>" -> Add another copy / Move here / Cancel
'@ }

    # ---------------- M5 ----------------
    @{ m = 5; labels = 'ocr'; title = 'OCR mode for printed ISBNs'; body = @'
- [ ] Toggle on scan screen between Barcode and Text (OCR)
- [ ] `google_mlkit_text_recognition` on camera frames, with a framing guide
- [ ] Use ISBN extraction from `isbn.dart`; accept only checksum-valid results
- [ ] Ask the user to confirm the detected ISBN before lookup
'@ }
    @{ m = 5; labels = 'ocr,catalog'; title = 'Manual entry for books without an ISBN'; body = @'
- [ ] Form: title, authors, publisher, year, location, tags, notes (ISBN optional)
- [ ] Also reachable from "not found" after a scan, pre-filled with the ISBN
'@ }

    # ---------------- M6 ----------------
    @{ m = 6; labels = 'release'; title = 'App icon, name and splash'; body = @'
- [ ] Adaptive launcher icon (`flutter_launcher_icons`)
- [ ] App label "BookCatalog"
- [ ] Native splash (`flutter_native_splash`)
'@ }
    @{ m = 6; labels = 'catalog'; title = 'CSV export of the catalog'; body = @'
- [ ] Export all books with location and tag names resolved
- [ ] Share via Android share sheet (Drive, email, etc.)
'@ }
    @{ m = 6; labels = 'release,needs-owner'; title = 'Release signing and release workflow'; body = @'
See docs/BUILD_AND_DEPLOY.md sections 4-6.

- [ ] Owner creates upload keystore and backs it up
- [ ] `android/key.properties` support in Gradle; release SHA fingerprints added to Firebase
- [ ] Owner adds GitHub secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
- [ ] `.github/workflows/release.yml` on `v*` tags: signed APK + AAB, GitHub Release with APK attached
- [ ] Version name from tag, versionCode from run number
'@ }
    @{ m = 6; labels = 'release,needs-owner'; title = 'Distribute to household phones (Firebase App Distribution)'; body = @'
- [ ] Owner creates service account with Firebase App Distribution Admin role; adds `FIREBASE_SERVICE_ACCOUNT_JSON` and `FIREBASE_ANDROID_APP_ID` secrets
- [ ] Release workflow uploads APK to the `household` tester group
- [ ] Household members accept invites and install
- [ ] Document the "install update" flow in README
'@ }
)

# ---- Labels ----
foreach ($l in $labels) {
    gh label create $l.name --repo $Repo --color $l.color --description $l.description --force | Out-Null
    Write-Host "label: $($l.name)"
}

# ---- Milestones ----
$existing = gh api "repos/$Repo/milestones?state=all&per_page=100" | ConvertFrom-Json
foreach ($ms in $milestones) {
    if ($existing | Where-Object { $_.title -eq $ms.title }) {
        Write-Host "milestone exists: $($ms.title)"
    } else {
        gh api "repos/$Repo/milestones" -f title="$($ms.title)" -f description="$($ms.description)" | Out-Null
        Write-Host "milestone created: $($ms.title)"
    }
}

# ---- Issues ----
$existingIssues = gh issue list --repo $Repo --state all --limit 500 --json title | ConvertFrom-Json
$bodyFile = New-TemporaryFile
try {
    foreach ($i in $issues) {
        if ($existingIssues | Where-Object { $_.title -eq $i.title }) {
            Write-Host "issue exists: $($i.title)"
            continue
        }
        Set-Content -Path $bodyFile -Value $i.body -Encoding utf8
        $url = gh issue create --repo $Repo --title $i.title --body-file $bodyFile --label $i.labels --milestone $milestones[$i.m].title
        Write-Host "issue created: $url"
    }
} finally {
    Remove-Item $bodyFile -ErrorAction SilentlyContinue
}
