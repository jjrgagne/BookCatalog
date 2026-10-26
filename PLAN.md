# BookCatalog — Project Plan

An Android app (Flutter) for cataloguing every book in the house. Scan a book's
ISBN barcode (or OCR the printed ISBN), look up its details automatically, and
file it under a location and tags. The catalog is shared between everyone in the
household through Firebase.

## Scope

**In scope (v1)**

- Android only (minSdk 24 / Android 7.0+). iOS is not planned.
- Barcode scanning of ISBN EAN-13 codes; OCR fallback for printed ISBN-10/13.
- Automatic metadata lookup (Open Library, then Google Books).
- Shared household catalog in Cloud Firestore, with offline support.
- Locations: either a **room** ("Living Room") or a **person** the book is on
  loan to ("Sam Jones").
- Tags.
- A free-text **notes** field on each book.
- CSV export.

**Out of scope (for now)**

- iOS, web, desktop.
- Reading status, ratings, wishlist, stats, lending history.
- Uploading cover photos (covers are linked from the metadata source).

## Technology

| Area | Choice |
|---|---|
| Framework | Flutter (stable channel), Dart |
| Barcode | `mobile_scanner` (ML Kit on Android) |
| OCR | `google_mlkit_text_recognition` (on-device) |
| Metadata | Open Library API (no key) → Google Books API fallback → manual entry |
| Backend | Firebase: Cloud Firestore + Firebase Auth (Google sign-in) |
| State | Riverpod |
| Navigation | Flutter Navigator + bottom navigation bar |
| Models | Hand-written Dart classes (no code generation) |
| Offline/local storage | Firestore cache when shared; a JSON file in phone-only mode |
| CI/CD | GitHub Actions |
| Distribution | GitHub Releases APK now; Firebase App Distribution optional (see [docs/BUILD_AND_DEPLOY.md](docs/BUILD_AND_DEPLOY.md)) |

**Phone-only mode.** Builds without `google-services.json` (and users who
haven't signed in) keep the catalog in a JSON file on the phone. After joining a
household, those books can be copied into the shared catalog.

Application ID: `io.github.jjrgagne.bookcatalog`

## How the data is stored and shared

The catalog lives in Cloud Firestore inside a Firebase project owned by the
household. Each phone keeps a local cache, so browsing and scanning work offline
and sync when back online. Only signed-in members of a household can read or
write its data (enforced by Firestore security rules); other people who install
the app cannot see it. A household-sized catalog fits comfortably in Firebase's
free (Spark) plan.

### Data model (Firestore)

```
users/{uid}              householdId
invites/{code}           householdId

households/{householdId}
  name, inviteCode, ownerUid, createdAt
  members/{uid}          role: owner | member, displayName, email, inviteCode

  locations/{locationId}
    name                 "Living Room" or "Sam Jones"
    kind                 room | person
    sortOrder

  tags/{tagId}
    name, color

  books/{bookId}
    isbn13, isbn10, title, subtitle, authors[], publisher,
    publishedYear, coverUrl,
    locationId, tagIds[], copies,
    previousLocationId   room it was in before being lent (for one-tap Return)
    notes                free text
    metadataSource       openlibrary | google | manual | pending
    addedBy, addedAt, updatedAt   (times as milliseconds since epoch)
```

Notes:

- ISBNs are normalised to ISBN-13 for storage and duplicate detection; ISBN-10 is
  kept when the book has one.
- Search is done client-side over the cached catalog (Firestore has no full-text
  search, and a household catalog of a few thousand books is small enough).
- Moving a book from a room to a person records the room in
  `previousLocationId`; a **Return** button on books that are on loan moves them
  back to that room in one tap and clears the field.

## Scanning flow

1. Pick a **current location** — every scan is filed there until changed.
2. **Barcode mode** (default): accept EAN-13 starting `978`/`979`; ignore the
   5-digit price add-on.
3. **OCR mode**: find ISBN-10/13 candidates in recognised text (hyphens/spaces
   allowed), keep only those with a valid checksum, convert ISBN-10 → ISBN-13.
4. Look up metadata → confirmation card (cover, title, author) → optionally adjust
   location/tags/notes → save.
5. Duplicate check: "Already in the Office — add another copy or move it?"
6. Manual entry for books with no ISBN.
7. Batch mode: beep/vibrate per scan and a running list to review; scans made
   offline are looked up once back online.

## Screens

- **Library** — grid/list, search (title/author/ISBN), filter by location and tag.
- **Scan** — barcode/OCR toggle, current-location picker.
- **Book detail / edit** — all fields including notes; move to another location;
  **Return** when on loan.
- **Locations** — rooms and people, in two sections.
- **Tags**.
- **Household** — members, invite code / QR, CSV export, sign out.

## Project structure

```
lib/
  main.dart                    Firebase (optional) + local storage start-up
  app/                         app shell, providers
  core/                        isbn.dart, search.dart, csv.dart
  data/
    models/                    book, location, tag, metadata
    repositories/              catalog interface, local JSON, Firestore
    services/                  Open Library, Google Books, merged lookup
    household/                 sign-in, households, invites
    catalog_actions.dart       move/lend/return, deletes, pending lookups
  features/
    scan/                      barcode, review sheet, OCR
    catalog/                   library, detail, edit/manual entry
    locations/  tags/  household/  more/  common/
test/
firestore.rules  firestore-tests/  firebase.json
.github/workflows/             ci.yml, release.yml
```

## Milestones

Each milestone has a GitHub milestone and issues; see the repository's
[Milestones](https://github.com/jjrgagne/BookCatalog/milestones) page.

| # | Milestone | Outcome |
|---|---|---|
| M0 | Project setup | Flutter project, Firebase project, CI, ISBN utilities with tests, app skeleton |
| M1 | Scan & lookup | Scan a barcode and see the book's details |
| M2 | Catalog | Save, list, search and edit books (incl. notes), offline |
| M3 | Sharing | Google sign-in, households, invites, security rules, multi-phone sync |
| M4 | Locations & tags | Room/person locations, tags, batch scanning, filters, duplicates |
| M5 | OCR & manual entry | Fallbacks for books without a scannable barcode |
| M6 | Release | Icon, CSV export, signed release builds, distribution to household phones |

M1 is the key check that the idea works: if scanning feels good on real shelves,
the rest is standard app work.
