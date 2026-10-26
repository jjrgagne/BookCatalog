import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/book.dart';
import '../models/location.dart';
import '../models/tag.dart';
import 'catalog_repository.dart';

/// A household catalog shared through Cloud Firestore.
///
/// Firestore caches everything on the phone, so reads work offline and
/// writes are queued until the connection returns. Write futures only
/// complete when the server acknowledges them, so they are not awaited.
class FirestoreCatalogRepository implements CatalogRepository {
  FirestoreCatalogRepository(this._db, this.householdId);

  final FirebaseFirestore _db;
  final String householdId;

  DocumentReference<Map<String, dynamic>> get _household =>
      _db.collection('households').doc(householdId);
  CollectionReference<Map<String, dynamic>> get _books =>
      _household.collection('books');
  CollectionReference<Map<String, dynamic>> get _locations =>
      _household.collection('locations');
  CollectionReference<Map<String, dynamic>> get _tags =>
      _household.collection('tags');

  @override
  bool get isShared => true;

  Stream<List<T>> _watch<T>(
    CollectionReference<Map<String, dynamic>> col,
    T Function(String id, Map<String, Object?> data) fromMap,
  ) => col.snapshots().map(
    (s) => [for (final d in s.docs) fromMap(d.id, d.data())],
  );

  @override
  Stream<List<Book>> watchBooks() => _watch(_books, Book.fromMap);

  @override
  Stream<List<Location>> watchLocations() =>
      _watch(_locations, Location.fromMap);

  @override
  Stream<List<Tag>> watchTags() => _watch(_tags, Tag.fromMap);

  void _fireAndForget(Future<void> write) =>
      unawaited(write.catchError((_) {}));

  /// Commits [items] in batches of 400 (Firestore allows 500 per batch).
  Future<void> _saveAll<T>(
    CollectionReference<Map<String, dynamic>> col,
    List<T> items,
    String Function(T) id,
    Map<String, Object?> Function(T) toMap,
  ) async {
    for (var i = 0; i < items.length; i += 400) {
      final batch = _db.batch();
      for (final item in items.skip(i).take(400)) {
        batch.set(col.doc(id(item)), toMap(item));
      }
      _fireAndForget(batch.commit());
    }
  }

  @override
  Future<void> saveBook(Book book) async =>
      _fireAndForget(_books.doc(book.id).set(book.toMap()));

  @override
  Future<void> saveBooks(List<Book> books) =>
      _saveAll(_books, books, (b) => b.id, (b) => b.toMap());

  @override
  Future<void> deleteBook(String id) async =>
      _fireAndForget(_books.doc(id).delete());

  @override
  Future<void> saveLocation(Location location) async =>
      _fireAndForget(_locations.doc(location.id).set(location.toMap()));

  @override
  Future<void> saveLocations(List<Location> locations) =>
      _saveAll(_locations, locations, (l) => l.id, (l) => l.toMap());

  @override
  Future<void> deleteLocation(String id) async =>
      _fireAndForget(_locations.doc(id).delete());

  @override
  Future<void> saveTag(Tag tag) async =>
      _fireAndForget(_tags.doc(tag.id).set(tag.toMap()));

  @override
  Future<void> deleteTag(String id) async =>
      _fireAndForget(_tags.doc(id).delete());

  @override
  void dispose() {}
}
