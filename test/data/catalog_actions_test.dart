import 'dart:io';

import 'package:bookcatalog/core/csv.dart';
import 'package:bookcatalog/data/catalog_actions.dart';
import 'package:bookcatalog/data/models/book.dart';
import 'package:bookcatalog/data/models/location.dart';
import 'package:bookcatalog/data/models/tag.dart';
import 'package:bookcatalog/data/repositories/local_catalog_repository.dart';
import 'package:bookcatalog/data/services/metadata_service.dart';
import 'package:flutter_test/flutter_test.dart';

const office = Location(id: 'office', name: 'Office');
const den = Location(id: 'den', name: 'Den');
const sam = Location(id: 'sam', name: 'Sam', kind: LocationKind.person);
const alex = Location(id: 'alex', name: 'Alex', kind: LocationKind.person);
final locations = {
  for (final l in [office, den, sam, alex]) l.id: l,
};

Book book({String id = 'b1', String? at, String? previous}) => Book(
  id: id,
  title: 'A book',
  isbn13: '9780306406157',
  locationId: at,
  previousLocationId: previous,
  addedAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

void main() {
  group('moving and returning', () {
    test('lending remembers the room', () {
      final lent = CatalogActions.moveBook(book(at: 'office'), sam, locations);
      expect(lent.locationId, 'sam');
      expect(lent.previousLocationId, 'office');
      expect(CatalogActions.returnTarget(lent, locations), office);
    });

    test('passing between people keeps the original room', () {
      final lent = CatalogActions.moveBook(book(at: 'office'), sam, locations);
      final passed = CatalogActions.moveBook(lent, alex, locations);
      expect(passed.locationId, 'alex');
      expect(passed.previousLocationId, 'office');
    });

    test('moving to a room clears the remembered room', () {
      final lent = CatalogActions.moveBook(book(at: 'office'), sam, locations);
      final back = CatalogActions.moveBook(lent, den, locations);
      expect(back.locationId, 'den');
      expect(back.previousLocationId, isNull);
      expect(CatalogActions.returnTarget(back, locations), isNull);
    });

    test('no return target when the room was deleted', () {
      final b = book(at: 'sam', previous: 'gone');
      expect(CatalogActions.returnTarget(b, locations), isNull);
    });
  });

  group('with local repository', () {
    late Directory dir;
    late LocalCatalogRepository repo;
    late CatalogActions actions;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('bookcatalog_test');
      repo = LocalCatalogRepository(File('${dir.path}/catalog.json'));
      actions = CatalogActions(repo, MetadataService());
    });

    tearDown(() async {
      repo.dispose();
      await dir.delete(recursive: true);
    });

    test('persists and reloads', () async {
      await repo.saveLocations([office, sam]);
      await repo.saveBook(book(at: 'office'));
      await repo.saveTag(const Tag(id: 't', name: 'Fiction'));

      final reloaded = LocalCatalogRepository(File('${dir.path}/catalog.json'));
      final books = await reloaded.watchBooks().first;
      expect(books.single.locationId, 'office');
      expect((await reloaded.watchLocations().first).length, 2);
      expect((await reloaded.watchTags().first).single.name, 'Fiction');
    });

    test('deleting a room moves its books and clears return targets', () async {
      await repo.saveBooks([
        book(id: 'here', at: 'office'),
        book(id: 'lent', at: 'sam', previous: 'office'),
      ]);
      final books = await repo.watchBooks().first;
      await actions.deleteLocation(
        office,
        books,
        moveTo: den,
        locations: locations,
      );
      final after = {for (final b in await repo.watchBooks().first) b.id: b};
      expect(after['here']!.locationId, 'den');
      expect(after['lent']!.locationId, 'sam');
      expect(after['lent']!.previousLocationId, isNull);
    });

    test('deleting a tag removes it from books', () async {
      const tag = Tag(id: 't', name: 'Fiction');
      await repo.saveTag(tag);
      await repo.saveBook(book().copyWith(tagIds: ['t', 'u']));
      await actions.deleteTag(tag, await repo.watchBooks().first);
      expect((await repo.watchBooks().first).single.tagIds, ['u']);
    });
  });

  test('findByIsbn', () {
    expect(findByIsbn([book()], '9780306406157')?.id, 'b1');
    expect(findByIsbn([book()], '9780804429573'), isNull);
  });

  test('CSV export escapes and resolves names', () {
    final b = book(at: 'sam', previous: 'office').copyWith(
      title: 'Hello, "World"',
      authors: ['A', 'B'],
      tagIds: ['t'],
      notes: 'line1\nline2',
    );
    final csv = booksToCsv(
      [b],
      locations,
      {'t': const Tag(id: 't', name: 'Fiction')},
    );
    final lines = csv.split('\r\n');
    expect(lines.first, startsWith('ISBN-13,ISBN-10,Title'));
    expect(csv, contains('"Hello, ""World"""'));
    expect(csv, contains('A; B'));
    expect(csv, contains('Sam,person,Office,Fiction,1,"line1\nline2"'));
  });
}
