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
    Object? json;
    try {
      json = jsonDecode(await _file.readAsString());
    } on FormatException {
      // Corrupt file: keep a copy for recovery and start empty.
      await _file.copy('${_file.path}.corrupt');
      return;
    }
    if (json is! Map) return;
    _readInto(json['books'], _books, Book.fromMap);
    _readInto(json['locations'], _locations, Location.fromMap);
    _readInto(json['tags'], _tags, Tag.fromMap);
  }

  /// Loads records with a string `id`, skipping any malformed entries.
  static void _readInto<T>(
    Object? list,
    Map<String, T> into,
    T Function(String id, Map<String, Object?> map) fromMap,
  ) {
    if (list is! List) return;
    for (final e in list) {
      if (e is! Map) continue;
      final map = e.cast<String, Object?>();
      final id = map['id'];
      if (id is String) into[id] = fromMap(id, map);
    }
  }

  static List<Map<String, Object?>> _writeAll<T>(
    Iterable<T> items,
    String Function(T) id,
    Map<String, Object?> Function(T) toMap,
  ) => [
    for (final item in items) {'id': id(item), ...toMap(item)},
  ];

  Future<void> _changed() async {
    _changes.add(null);
    final json = jsonEncode({
      'version': 1,
      'books': _writeAll(_books.values, (b) => b.id, (b) => b.toMap()),
      'locations': _writeAll(_locations.values, (l) => l.id, (l) => l.toMap()),
      'tags': _writeAll(_tags.values, (t) => t.id, (t) => t.toMap()),
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

  /// Emits the current list, then again after every change. Subscribes to
  /// changes before loading so nothing between load and listen is missed.
  Stream<List<T>> _watch<T>(Iterable<T> Function() snapshot) {
    late final StreamController<List<T>> controller;
    StreamSubscription<void>? sub;
    controller = StreamController<List<T>>(
      onListen: () {
        sub = _changes.stream.listen(
          (_) => controller.add(snapshot().toList()),
        );
        _ensureLoaded().then(
          (_) => controller.add(snapshot().toList()),
          onError: controller.addError,
        );
      },
      onCancel: () => sub?.cancel(),
    );
    return controller.stream;
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
