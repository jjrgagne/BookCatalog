import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/book.dart';
import '../models/location.dart';
import '../models/tag.dart';
import 'catalog_repository.dart';

/// A catalog stored as a JSON file on this phone.
///
/// Used before the household is set up (or when Firebase isn't configured).
/// A household catalog of a few thousand books is well under a megabyte.
class LocalCatalogRepository implements CatalogRepository {
  LocalCatalogRepository(this._file);

  final File _file;
  final _books = <String, Book>{};
  final _locations = <String, Location>{};
  final _tags = <String, Tag>{};
  final _changes = StreamController<void>.broadcast();
  Future<void>? _loading;
  Future<void> _writing = Future.value();

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    if (!await _file.exists()) return;
    try {
      final json = jsonDecode(await _file.readAsString()) as Map;
      Map<String, Object?> m(Object? e) => (e as Map).cast<String, Object?>();
      for (final e in (json['books'] as List? ?? const [])) {
        final b = Book.fromMap(m(e)['id'] as String, m(e));
        _books[b.id] = b;
      }
      for (final e in (json['locations'] as List? ?? const [])) {
        final l = Location.fromMap(m(e)['id'] as String, m(e));
        _locations[l.id] = l;
      }
      for (final e in (json['tags'] as List? ?? const [])) {
        final t = Tag.fromMap(m(e)['id'] as String, m(e));
        _tags[t.id] = t;
      }
    } on FormatException {
      // Corrupt file: keep a copy for recovery and start empty.
      await _file.copy('${_file.path}.corrupt');
    }
  }

  Future<void> _changed() async {
    _changes.add(null);
    final json = jsonEncode({
      'version': 1,
      'books': [
        for (final b in _books.values) {'id': b.id, ...b.toMap()},
      ],
      'locations': [
        for (final l in _locations.values) {'id': l.id, ...l.toMap()},
      ],
      'tags': [
        for (final t in _tags.values) {'id': t.id, ...t.toMap()},
      ],
    });
    // Serialise writes; write to a temp file then rename for atomicity.
    _writing = _writing.then((_) async {
      await _file.parent.create(recursive: true);
      final tmp = File('${_file.path}.tmp');
      await tmp.writeAsString(json, flush: true);
      await tmp.rename(_file.path);
    });
    await _writing;
  }

  Stream<List<T>> _watch<T>(Iterable<T> Function() snapshot) async* {
    await _ensureLoaded();
    yield snapshot().toList();
    await for (final _ in _changes.stream) {
      yield snapshot().toList();
    }
  }

  @override
  bool get isShared => false;

  @override
  Stream<List<Book>> watchBooks() => _watch(() => _books.values);

  @override
  Stream<List<Location>> watchLocations() => _watch(() => _locations.values);

  @override
  Stream<List<Tag>> watchTags() => _watch(() => _tags.values);

  /// All books currently stored (used when copying into a household).
  Future<List<Book>> allBooks() async {
    await _ensureLoaded();
    return _books.values.toList();
  }

  Future<List<Location>> allLocations() async {
    await _ensureLoaded();
    return _locations.values.toList();
  }

  Future<List<Tag>> allTags() async {
    await _ensureLoaded();
    return _tags.values.toList();
  }

  /// Removes everything (after it has been copied into a household).
  Future<void> clear() async {
    await _ensureLoaded();
    _books.clear();
    _locations.clear();
    _tags.clear();
    await _changed();
  }

  @override
  Future<void> saveBook(Book book) => saveBooks([book]);

  @override
  Future<void> saveBooks(List<Book> books) async {
    await _ensureLoaded();
    for (final b in books) {
      _books[b.id] = b;
    }
    await _changed();
  }

  @override
  Future<void> deleteBook(String id) async {
    await _ensureLoaded();
    _books.remove(id);
    await _changed();
  }

  @override
  Future<void> saveLocation(Location location) => saveLocations([location]);

  @override
  Future<void> saveLocations(List<Location> locations) async {
    await _ensureLoaded();
    for (final l in locations) {
      _locations[l.id] = l;
    }
    await _changed();
  }

  @override
  Future<void> deleteLocation(String id) async {
    await _ensureLoaded();
    _locations.remove(id);
    await _changed();
  }

  @override
  Future<void> saveTag(Tag tag) async {
    await _ensureLoaded();
    _tags[tag.id] = tag;
    await _changed();
  }

  @override
  Future<void> deleteTag(String id) async {
    await _ensureLoaded();
    _tags.remove(id);
    await _changed();
  }

  @override
  void dispose() {
    unawaited(_changes.close());
  }
}
