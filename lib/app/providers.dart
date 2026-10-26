import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog_actions.dart';
import '../data/household/household_service.dart';
import '../data/models/book.dart';
import '../data/models/location.dart';
import '../data/models/tag.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/firestore_catalog_repository.dart';
import '../data/repositories/local_catalog_repository.dart';
import '../data/services/metadata_service.dart';

// ---- Overridden in main() ----

/// Whether Firebase initialised (false when the build has no
/// google-services.json; the app then runs in this-phone-only mode).
final firebaseReadyProvider = Provider<bool>((ref) => false);

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('overridden in main'),
);

final localRepositoryProvider = Provider<LocalCatalogRepository>(
  (ref) => throw UnimplementedError('overridden in main'),
);

// ---- Account & household ----

final householdServiceProvider = Provider<HouseholdService?>((ref) {
  if (!ref.watch(firebaseReadyProvider)) return null;
  return HouseholdService(FirebaseAuth.instance, FirebaseFirestore.instance);
});

final authStateProvider = StreamProvider<User?>((ref) {
  final service = ref.watch(householdServiceProvider);
  return service?.authStateChanges() ?? Stream.value(null);
});

final householdIdProvider = StreamProvider<String?>((ref) {
  final service = ref.watch(householdServiceProvider);
  final user = ref.watch(authStateProvider).value;
  if (service == null || user == null) return Stream.value(null);
  return service.watchHouseholdId(user.uid);
});

final householdProvider = StreamProvider<Household?>((ref) {
  final service = ref.watch(householdServiceProvider);
  final id = ref.watch(householdIdProvider).value;
  if (service == null || id == null) return Stream.value(null);
  return service.watchHousehold(id);
});

final membersProvider = StreamProvider<List<Member>>((ref) {
  final service = ref.watch(householdServiceProvider);
  final id = ref.watch(householdIdProvider).value;
  if (service == null || id == null) return Stream.value(const []);
  return service.watchMembers(id);
});

// ---- Catalog ----

/// The active catalog: the shared household when signed in to one,
/// otherwise this phone's local catalog.
final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  final householdId = ref.watch(householdIdProvider).value;
  if (householdId != null) {
    return FirestoreCatalogRepository(FirebaseFirestore.instance, householdId);
  }
  return ref.watch(localRepositoryProvider);
});

final metadataServiceProvider = Provider<MetadataService>(
  (ref) => MetadataService(),
);

final catalogActionsProvider = Provider<CatalogActions>(
  (ref) => CatalogActions(
    ref.watch(catalogRepositoryProvider),
    ref.watch(metadataServiceProvider),
    userId: ref.watch(authStateProvider).value?.uid,
  ),
);

final booksProvider = StreamProvider<List<Book>>(
  (ref) => ref.watch(catalogRepositoryProvider).watchBooks(),
);

int _compareLocations(Location a, Location b) {
  final kind = a.kind.index.compareTo(b.kind.index);
  if (kind != 0) return kind;
  final order = a.sortOrder.compareTo(b.sortOrder);
  if (order != 0) return order;
  return a.name.toLowerCase().compareTo(b.name.toLowerCase());
}

/// Rooms first, then people; each in the user's chosen order.
final locationsProvider = StreamProvider<List<Location>>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .watchLocations()
      .map((l) => [...l]..sort(_compareLocations)),
);

final tagsProvider = StreamProvider<List<Tag>>(
  (ref) => ref
      .watch(catalogRepositoryProvider)
      .watchTags()
      .map(
        (t) => [
          ...t,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      ),
);

final locationMapProvider = Provider<Map<String, Location>>(
  (ref) => {for (final l in ref.watch(locationsProvider).value ?? []) l.id: l},
);

final tagMapProvider = Provider<Map<String, Tag>>(
  (ref) => {for (final t in ref.watch(tagsProvider).value ?? []) t.id: t},
);

// ---- Scan settings (remembered on this phone) ----

class ScanSettings {
  const ScanSettings({
    this.locationId,
    this.tagIds = const [],
    this.batchMode = false,
  });

  /// Where new scans are filed.
  final String? locationId;

  /// Tags applied to new scans.
  final List<String> tagIds;

  /// Save every scan immediately instead of reviewing each one.
  final bool batchMode;
}

class ScanSettingsNotifier extends Notifier<ScanSettings> {
  static const _location = 'scan.locationId';
  static const _tags = 'scan.tagIds';
  static const _batch = 'scan.batchMode';

  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  ScanSettings build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return ScanSettings(
      locationId: prefs.getString(_location),
      tagIds: prefs.getStringList(_tags) ?? const [],
      batchMode: prefs.getBool(_batch) ?? false,
    );
  }

  void setLocation(String? id) {
    if (id == null) {
      _prefs.remove(_location);
    } else {
      _prefs.setString(_location, id);
    }
    state = ScanSettings(
      locationId: id,
      tagIds: state.tagIds,
      batchMode: state.batchMode,
    );
  }

  void setTags(List<String> ids) {
    _prefs.setStringList(_tags, ids);
    state = ScanSettings(
      locationId: state.locationId,
      tagIds: ids,
      batchMode: state.batchMode,
    );
  }

  void setBatchMode(bool on) {
    _prefs.setBool(_batch, on);
    state = ScanSettings(
      locationId: state.locationId,
      tagIds: state.tagIds,
      batchMode: on,
    );
  }
}

final scanSettingsProvider =
    NotifierProvider<ScanSettingsNotifier, ScanSettings>(
      ScanSettingsNotifier.new,
    );
