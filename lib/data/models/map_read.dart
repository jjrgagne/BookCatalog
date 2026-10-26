/// Type-tolerant readers for stored documents (Firestore or the local JSON
/// file). A field with an unexpected type reads as missing instead of
/// throwing, so one bad record can't stop the whole catalog from loading.
library;

String? readString(Map<String, Object?> map, String key) {
  final v = map[key];
  return v is String ? v : null;
}

int? readInt(Map<String, Object?> map, String key) {
  final v = map[key];
  return v is num ? v.toInt() : null;
}

List<String> readStrings(Map<String, Object?> map, String key) {
  final v = map[key];
  return v is List ? v.whereType<String>().toList() : const [];
}

/// Times are stored as milliseconds since the epoch.
DateTime readTime(Map<String, Object?> map, String key) =>
    DateTime.fromMillisecondsSinceEpoch(readInt(map, key) ?? 0);
