import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class Household {
  const Household({
    required this.id,
    required this.name,
    required this.inviteCode,
    required this.ownerUid,
  });

  final String id;
  final String name;
  final String inviteCode;
  final String ownerUid;

  factory Household.fromMap(String id, Map<String, Object?> map) => Household(
    id: id,
    name: (map['name'] as String?) ?? 'Our books',
    inviteCode: (map['inviteCode'] as String?) ?? '',
    ownerUid: (map['ownerUid'] as String?) ?? '',
  );
}

class Member {
  const Member({
    required this.uid,
    required this.displayName,
    required this.role,
    this.email,
  });

  final String uid;
  final String displayName;
  final String? email;
  final String role;

  bool get isOwner => role == 'owner';

  factory Member.fromMap(String uid, Map<String, Object?> map) => Member(
    uid: uid,
    displayName: (map['displayName'] as String?) ?? 'Member',
    email: map['email'] as String?,
    role: (map['role'] as String?) ?? 'member',
  );
}

class HouseholdException implements Exception {
  const HouseholdException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Prefix for QR codes that carry an invite code.
const inviteQrPrefix = 'bookcatalog:join:';

/// Sign-in and household membership, backed by Firebase Auth + Firestore.
///
/// Data layout (see firestore.rules):
///   users/{uid}                       { householdId }
///   invites/{code}                    { householdId }
///   households/{id}                   { name, inviteCode, ownerUid, createdAt }
///   households/{id}/members/{uid}     { displayName, email, role, inviteCode }
class HouseholdService {
  HouseholdService(this._auth, this._db);

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signInWithGoogle() async {
    final provider = GoogleAuthProvider()..addScope('email');
    await _auth.signInWithProvider(provider);
  }

  Future<void> signOut() => _auth.signOut();

  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);
  DocumentReference<Map<String, dynamic>> _household(String id) =>
      _db.collection('households').doc(id);
  DocumentReference<Map<String, dynamic>> _invite(String code) =>
      _db.collection('invites').doc(code);

  /// The user's household, or null if none (or they were removed from it).
  Stream<String?> watchHouseholdId(String uid) async* {
    await for (final s in _user(uid).snapshots()) {
      final householdId = s.data()?['householdId'] as String?;
      if (householdId == null) {
        yield null;
        continue;
      }
      try {
        final member = await _household(householdId)
            .collection('members')
            .doc(uid)
            .get();
        yield member.exists ? householdId : null;
      } on FirebaseException {
        // Permission denied after being removed from the household.
        yield null;
      }
    }
  }

  Stream<Household?> watchHousehold(String id) =>
      _household(id)
          .snapshots()
          .map((s) => s.exists ? Household.fromMap(s.id, s.data()!) : null);

  Stream<List<Member>> watchMembers(String householdId) =>
      _household(householdId)
          .collection('members')
          .snapshots()
          .map((s) => [for (final d in s.docs) Member.fromMap(d.id, d.data())]);

  Map<String, Object?> _memberData(User user, String role, String code) => {
    'displayName': user.displayName ?? user.email ?? 'Member',
    'email': user.email,
    'role': role,
    'inviteCode': code,
    'joinedAt': FieldValue.serverTimestamp(),
  };

  /// Creates a household owned by [user] and makes it their current one.
  Future<String> createHousehold(User user, String name) async {
    final household = _db.collection('households').doc();
    final code = generateInviteCode();
    final batch = _db.batch()
      ..set(household, {
        'name': name,
        'inviteCode': code,
        'ownerUid': user.uid,
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(
        household.collection('members').doc(user.uid),
        _memberData(user, 'owner', code),
      )
      ..set(_invite(code), {'householdId': household.id})
      ..set(_user(user.uid), {'householdId': household.id});
    await batch.commit().timeout(const Duration(seconds: 20));
    return household.id;
  }

  /// Joins the household with invite [code] (typed or scanned from a QR).
  Future<void> joinHousehold(User user, String code) async {
    code = normalizeInviteCode(code);
    final invite = await _invite(code).get();
    final householdId = invite.data()?['householdId'] as String?;
    if (householdId == null) {
      throw const HouseholdException('That invite code was not found.');
    }
    final batch = _db.batch()
      ..set(
        _household(householdId).collection('members').doc(user.uid),
        _memberData(user, 'member', code),
      )
      ..set(_user(user.uid), {'householdId': householdId});
    await batch.commit().timeout(const Duration(seconds: 20));
  }

  /// Replaces the invite code (owner only), invalidating the old one.
  Future<void> regenerateInviteCode(Household household) async {
    final code = generateInviteCode();
    final batch = _db.batch()
      ..update(_household(household.id), {'inviteCode': code})
      ..delete(_invite(household.inviteCode))
      ..set(_invite(code), {'householdId': household.id});
    await batch.commit().timeout(const Duration(seconds: 20));
  }

  Future<void> renameHousehold(String householdId, String name) =>
      _household(householdId).update({'name': name});

  /// Removes another member (owner only).
  Future<void> removeMember(String householdId, String uid) =>
      _household(householdId).collection('members').doc(uid).delete();

  /// Leaves the household; the catalog stays with the other members.
  Future<void> leaveHousehold(String householdId, String uid) async {
    final batch = _db.batch()
      ..delete(_household(householdId).collection('members').doc(uid))
      ..set(_user(uid), {'householdId': null});
    await batch.commit().timeout(const Duration(seconds: 20));
  }
}

const _codeAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Six characters with no look-alikes (no 0/O, 1/I).
String generateInviteCode() {
  final r = Random.secure();
  return List.generate(
    6,
    (_) => _codeAlphabet[r.nextInt(_codeAlphabet.length)],
  ).join();
}

/// Accepts "abc-123", " ABC123 " or a scanned QR payload.
String normalizeInviteCode(String input) {
  var s = input.trim();
  if (s.startsWith(inviteQrPrefix)) s = s.substring(inviteQrPrefix.length);
  return s.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}
