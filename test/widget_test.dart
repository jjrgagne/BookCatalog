import 'dart:io';

import 'package:bookcatalog/app/app.dart';
import 'package:bookcatalog/app/providers.dart';
import 'package:bookcatalog/data/repositories/local_catalog_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('app starts in this-phone-only mode with an empty library', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dir = Directory.systemTemp.createTempSync('bookcatalog_widget');
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          localRepositoryProvider.overrideWithValue(
            LocalCatalogRepository(File('${dir.path}/catalog.json')),
          ),
        ],
        child: const BookCatalogApp(),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.text('Library'), findsWidgets);
    expect(find.text('No books yet'), findsOneWidget);

    await tester.tap(find.text('Places'));
    await tester.pump();
    expect(find.text('Rooms'), findsOneWidget);
    expect(find.text('On loan to'), findsOneWidget);
  });
}
