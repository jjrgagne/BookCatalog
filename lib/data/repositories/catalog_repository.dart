import '../models/book.dart';
import '../models/location.dart';
import '../models/tag.dart';

/// Storage for one catalog: either this phone only, or a shared household.
///
/// Saves are upserts keyed by the model's id. Writes return once applied
/// locally; shared catalogs sync in the background (including offline).
abstract class CatalogRepository {
  /// Whether this catalog is shared via Firebase (vs. this phone only).
  bool get isShared;

  Stream<List<Book>> watchBooks();
  Stream<List<Location>> watchLocations();
  Stream<List<Tag>> watchTags();

  Future<void> saveBook(Book book);
  Future<void> saveBooks(List<Book> books);
  Future<void> deleteBook(String id);

  Future<void> saveLocation(Location location);
  Future<void> saveLocations(List<Location> locations);
  Future<void> deleteLocation(String id);

  Future<void> saveTag(Tag tag);
  Future<void> deleteTag(String id);

  void dispose() {}
}
