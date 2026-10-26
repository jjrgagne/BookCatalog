import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bookcatalog/app/providers.dart';
import 'package:bookcatalog/data/catalog_actions.dart';
import 'package:bookcatalog/data/models/book.dart';
import 'package:bookcatalog/data/models/book_metadata.dart';
import 'package:bookcatalog/data/models/location.dart';
import 'package:bookcatalog/data/models/tag.dart';
import 'package:bookcatalog/data/repositories/local_catalog_repository.dart';
import 'package:bookcatalog/data/services/metadata_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const isbn = '9780306406157';

Book pendingBook({String id = 'b1', String? locationId}) => Book(
  id: id,
  title: 'ISBN $isbn',
  isbn13: isbn,
  locationId: locationId,
  metadataSource: MetadataSource.pending,
  addedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

const details = BookMetadata(
  isbn13: isbn,
  title: 'Found Title',
  authors: ['An Author'],
  publishedYear: 2001,
  source: MetadataSource.openlibrary,
);

/// A metadata service whose lookups finish only when [release] completes.
MetadataService slowService(Completer<void> release, {BookMetadata? result}) =>
    MetadataService.withSources([
      (_) async {
        await release.future;
        return result;
      },
    ], coverCheck: (_) async => false);

void main() {
  group('tolerant parsing', () {
    test('wrong field types read as missing instead of throwing', () {
      final book = Book.fromMap('x', {
        'title': 42,
        'authors': 'not a list',
        'copies': '3',
        'tagIds': ['ok', 7],
        'publishedYear': 1999.0,
        'addedAt': 'yesterday',
      });
      expect(book.title, '');
      expect(book.authors, isEmpty);
      expect(book.copies, 1);
      expect(book.tagIds, ['ok']);
      expect(book.publishedYear, 1999);
      expect(book.addedAt, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('copies are kept at least 1', () {
      expect(Book.fromMap('x', {'title': 't', 'copies': 0}).copies, 1);
    });

    test('location and tag tolerate bad types', () {
      expect(
        Location.fromMap('l', {'name': 1, 'kind': 'planet'}).kind,
        LocationKind.room,
      );
      expect(Tag.fromMap('t', {'color': 'red'}).color, 0xFF607D8B);
    });
  });

  group('local repository', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('bc_robust'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('skips malformed entries and keeps the good ones', () async {
      final file = File('${dir.path}/catalog.json')
        ..writeAsStringSync(
          jsonEncode({
            'books': [
              {'id': 'good', 'title': 'Good'},
              {'title': 'no id'},
              'not a map',
              {'id': 5, 'title': 'numeric id'},
            ],
            'locations': 'garbage',
          }),
        );
      final repo = LocalCatalogRepository(file);
      final books = await repo.watchBooks().first;
      expect(books.map((b) => b.id), ['good']);
      expect(await repo.watchLocations().first, isEmpty);
    });

    test('a corrupt file is backed up and the catalog starts empty', () async {
      final file = File('${dir.path}/catalog.json')
        ..writeAsStringSync('{not json');
      final repo = LocalCatalogRepository(file);
      expect(await repo.watchBooks().first, isEmpty);
      expect(File('${file.path}.corrupt').existsSync(), isTrue);
    });

    test('watchers see the initial list and every later change', () async {
      final repo = LocalCatalogRepository(File('${dir.path}/catalog.json'));
      final seen = <int>[];
      final sub = repo.watchBooks().listen((b) => seen.add(b.length));
      await repo.saveBook(pendingBook(id: 'a'));
      await repo.saveBook(pendingBook(id: 'b'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(seen.last, 2);
      expect(seen.first, lessThanOrEqualTo(1));
    });
  });

  group('lookups apply onto the latest version of a book', () {
    late Directory dir;
    late LocalCatalogRepository repo;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('bc_lookup');
      repo = LocalCatalogRepository(File('${dir.path}/catalog.json'));
    });
    tearDown(() => dir.deleteSync(recursive: true));

    Future<Book> stored(String id) async =>
        (await repo.watchBooks().first).singleWhere((b) => b.id == id);

    test('a move made during a slow lookup is kept', () async {
      final release = Completer<void>();
      final original = pendingBook(locationId: 'office');
      await repo.saveBook(original);
      var latest = original;
      final actions = CatalogActions(
        repo,
        slowService(release, result: details),
        currentBook: (_) => latest,
      );

      final lookup = actions.lookUpAndApply(original, onlyIfPending: true);
      // The user moves the book while the lookup is still running.
      latest = original.copyWith(locationId: 'den');
      await repo.saveBook(latest);
      release.complete();

      expect(await lookup, LookupOutcome.updated);
      final result = await stored('b1');
      expect(result.title, 'Found Title');
      expect(result.locationId, 'den');
    });

    test('details typed in during a lookup are not overwritten', () async {
      final release = Completer<void>();
      final original = pendingBook();
      await repo.saveBook(original);
      final typed = original.copyWith(
        title: 'My Title',
        metadataSource: MetadataSource.manual,
      );
      final actions = CatalogActions(
        repo,
        slowService(release, result: details),
        currentBook: (_) => typed,
      );
      final lookup = actions.lookUpAndApply(original, onlyIfPending: true);
      await repo.saveBook(typed);
      release.complete();
      expect(await lookup, LookupOutcome.skipped);
      expect((await stored('b1')).title, 'My Title');
    });

    test('the same book is never looked up twice at once', () async {
      final release = Completer<void>();
      final book = pendingBook(id: 'twice');
      final actions = CatalogActions(
        repo,
        slowService(release, result: details),
      );
      final first = actions.lookUpAndApply(book);
      final second = await actions.lookUpAndApply(book);
      expect(second, LookupOutcome.skipped);
      release.complete();
      expect(await first, LookupOutcome.updated);
    });

    test('unknown books stop being pending', () async {
      final release = Completer<void>()..complete();
      await repo.saveBook(pendingBook(id: 'unknown'));
      final actions = CatalogActions(repo, slowService(release));
      final done = await actions.completePendingLookups(
        await repo.watchBooks().first,
      );
      expect(done, 1);
      expect((await stored('unknown')).metadataSource, MetadataSource.manual);
    });
  });

  test('scan settings drop deleted places and tags', () async {
    SharedPreferences.setMockInitialValues({
      'scan.locationId': 'deleted-room',
      'scan.tagIds': ['kept', 'deleted-tag'],
    });
    final prefs = await SharedPreferences.getInstance();
    final dir = Directory.systemTemp.createTempSync('bc_settings');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = LocalCatalogRepository(File('${dir.path}/catalog.json'));
    await repo.saveTag(const Tag(id: 'kept', name: 'Kept'));

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        localRepositoryProvider.overrideWithValue(repo),
      ],
    );
    addTearDown(container.dispose);
    // Let the location and tag streams load.
    container.listen(locationsProvider, (_, _) {});
    container.listen(tagsProvider, (_, _) {});
    await container.read(tagsProvider.future);
    await container.read(locationsProvider.future);

    final effective = container.read(effectiveScanSettingsProvider);
    expect(effective.locationId, isNull);
    expect(effective.tagIds, ['kept']);
  });
}
