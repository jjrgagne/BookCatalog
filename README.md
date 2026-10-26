# BookCatalog

An Android app for cataloguing the books in our house. Scan a book's ISBN barcode
(or read the printed ISBN with OCR), fetch its details automatically, and file it
under a room — or under the person it's on loan to — with tags and notes. The
catalog is shared between household members through Firebase.

- **Plan:** [PLAN.md](PLAN.md)
- **Build & deploy:** [docs/BUILD_AND_DEPLOY.md](docs/BUILD_AND_DEPLOY.md)
- **Progress:** [Milestones](https://github.com/jjrgagne/BookCatalog/milestones)

## Status

Planning / project setup (milestone M0).

## Getting started (developers)

Requirements: Flutter (stable), Android Studio with the Android SDK, and an
Android phone with USB debugging or an emulator.

```bash
flutter pub get
flutter run
```

See [docs/BUILD_AND_DEPLOY.md](docs/BUILD_AND_DEPLOY.md) for the full setup,
including Firebase.
