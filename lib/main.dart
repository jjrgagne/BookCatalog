import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'data/repositories/local_catalog_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final firebaseReady = await _initFirebase();
  final prefs = await SharedPreferences.getInstance();
  final docs = await getApplicationDocumentsDirectory();
  final local = LocalCatalogRepository(File('${docs.path}/catalog.json'));

  runApp(
    ProviderScope(
      overrides: [
        firebaseReadyProvider.overrideWithValue(firebaseReady),
        sharedPreferencesProvider.overrideWithValue(prefs),
        localRepositoryProvider.overrideWithValue(local),
      ],
      child: const BookCatalogApp(),
    ),
  );
}

/// Initialises Firebase from android/app/google-services.json. Builds made
/// without that file run in this-phone-only mode.
Future<bool> _initFirebase() async {
  try {
    await Firebase.initializeApp();
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    return true;
  } catch (e) {
    debugPrint('Firebase not configured; running in local mode ($e)');
    return false;
  }
}
