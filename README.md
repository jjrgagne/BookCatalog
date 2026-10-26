# BookCatalog

An Android app for cataloguing the books in our house. Scan a book's ISBN barcode
(or read the printed ISBN with the camera), fetch its details automatically, and
file it under a room — or under the person it's on loan to — with tags and notes.
The catalog is shared between household members through Firebase.

- **Plan:** [PLAN.md](PLAN.md)
- **Build & deploy:** [docs/BUILD_AND_DEPLOY.md](docs/BUILD_AND_DEPLOY.md)
- **Progress:** [Milestones](https://github.com/jjrgagne/BookCatalog/milestones)

## Install on a phone

1. On the Android phone, open the
   [latest release](https://github.com/jjrgagne/BookCatalog/releases).
2. Download `bookcatalog-<version>.apk` and open it. If asked, allow your browser
   to install unknown apps.
3. New versions install over the old one; your books are kept.

Android 7.0 or newer.

## Using it

- **Scan** — pick where books are going ("Filing to: Office") and optional tags,
  then point the camera at barcodes. Turn on **Quick scan** to save every scan
  straight away while working through a shelf; offline scans get their details
  later.
- No barcode? **Read printed ISBN** takes a photo and finds the ISBN in it,
  **Type ISBN** looks one up, and **No ISBN** lets you enter a book by hand.
- **Library** — search by title, author, ISBN or notes; filter by place and tags;
  long-press to select several books to move, tag or delete.
- **Places** — rooms, and people books are lent to. Lending is just moving a book
  to a person; **Return** puts it back in the room it came from.
- **More** — tags, household sharing (invite code / QR), CSV export.

Until Firebase is connected (see the build guide), the app works fully on each
phone on its own; once connected, sign in and copy those books into the shared
household.

## Developers

Requirements: Flutter (version pinned in `pubspec.yaml`), Android Studio with the
Android SDK, and an Android phone with USB debugging or an emulator.

```bash
flutter pub get
```

```bash
flutter test
```

```bash
flutter run
```

Code layout: `lib/core` (ISBN, search, CSV), `lib/data` (models, repositories,
lookup services, household), `lib/features/*` (screens), `firestore.rules` with
tests in `firestore-tests/`.
