import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/book.dart';
import '../features/catalog/library_screen.dart';
import '../features/locations/locations_screen.dart';
import '../features/more/more_screen.dart';
import '../features/scan/scan_screen.dart';
import 'providers.dart';

class BookCatalogApp extends StatelessWidget {
  const BookCatalogApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF6D4C41);
    return MaterialApp(
      title: 'BookCatalog',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _lookingUp = false;

  /// Looks up pending books until none are left, including ones scanned
  /// while a round was running. Stops when offline or nothing progresses;
  /// the next catalog change (or a pull-to-refresh) tries again.
  Future<void> _completePending() async {
    if (_lookingUp) return;
    _lookingUp = true;
    // Books already handled this run, in case the catalog stream hasn't
    // caught up with our own saves yet.
    final handled = <String>{};
    try {
      while (mounted) {
        final pending = (ref.read(booksProvider).value ?? const <Book>[])
            .where(
              (b) =>
                  b.metadataSource == MetadataSource.pending &&
                  !handled.contains(b.id),
            )
            .toList();
        if (pending.isEmpty) break;
        handled.addAll(pending.map((b) => b.id));
        final done = await ref
            .read(catalogActionsProvider)
            .completePendingLookups(pending);
        if (done == 0) break;
      }
    } finally {
      _lookingUp = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Fill in details for books scanned while offline whenever the catalog
    // loads or changes.
    ref.listen(booksProvider, (_, next) {
      if (next.value != null) unawaited(_completePending());
    });

    final pages = [
      const LibraryScreen(),
      // The camera only runs while the Scan tab is visible.
      ScanScreen(active: _index == 1),
      const LocationsScreen(),
      const MoreScreen(),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book_outlined),
            selectedIcon: Icon(Icons.menu_book),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Icon(Icons.qr_code_scanner),
            label: 'Scan',
          ),
          NavigationDestination(
            icon: Icon(Icons.place_outlined),
            selectedIcon: Icon(Icons.place),
            label: 'Places',
          ),
          NavigationDestination(icon: Icon(Icons.more_horiz), label: 'More'),
        ],
      ),
    );
  }
}
