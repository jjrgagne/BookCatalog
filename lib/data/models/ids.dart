import 'dart:math';

final _random = Random.secure();
const _alphabet =
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';

/// Generates a 20-character random ID in the same style as Firestore's
/// auto-IDs, so documents can be created offline in either backend.
String generateId() => List.generate(
  20,
  (_) => _alphabet[_random.nextInt(_alphabet.length)],
).join();

/// Sentinel used by `copyWith` methods to distinguish "not passed" from null.
const Object unset = Object();
