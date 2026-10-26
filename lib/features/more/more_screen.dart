import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../core/csv.dart';
import '../../data/models/book.dart';
import '../common/widgets.dart';
import '../household/household_screen.dart';
import '../tags/tags_screen.dart';

final _packageInfoProvider = FutureProvider<PackageInfo>(
  (ref) => PackageInfo.fromPlatform(),
);

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  Future<void> _exportCsv(BuildContext context, WidgetRef ref) async {
    final books = ref.read(booksProvider).value ?? const <Book>[];
    if (books.isEmpty) {
      showSnack(context, 'There are no books to export yet.');
      return;
    }
    final csv = booksToCsv(
      books,
      ref.read(locationMapProvider),
      ref.read(tagMapProvider),
    );
    final dir = await getTemporaryDirectory();
    final date = DateTime.now().toIso8601String().substring(0, 10);
    final file = File('${dir.path}/bookcatalog-$date.csv');
    // BOM so spreadsheet apps detect UTF-8 (accents, etc.).
    await file.writeAsString('﻿$csv');
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: 'text/csv')],
        subject: 'BookCatalog export ($date)',
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shared = ref.watch(catalogRepositoryProvider).isShared;
    final household = ref.watch(householdProvider).value;
    final info = ref.watch(_packageInfoProvider).value;
    final count = ref.watch(booksProvider).value?.length ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        children: [
          ListTile(
            leading: Icon(
              shared ? Icons.cloud_done_outlined : Icons.phone_android,
            ),
            title: Text(
              shared
                  ? household?.name ?? 'Shared household'
                  : 'This phone only',
            ),
            subtitle: Text(
              shared
                  ? '$count books, shared with your household'
                  : '$count books. Set up a household to share.',
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.groups_outlined),
            title: const Text('Household & sharing'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HouseholdScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('Tags'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const TagsScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.file_download_outlined),
            title: const Text('Export catalog (CSV)'),
            subtitle: const Text('Opens in Sheets, Excel, etc.'),
            onTap: () async {
              try {
                await _exportCsv(context, ref);
              } catch (e) {
                if (context.mounted) showSnack(context, 'Export failed: $e');
              }
            },
          ),
          const Divider(),
          AboutListTile(
            icon: const Icon(Icons.info_outline),
            applicationName: 'BookCatalog',
            applicationVersion: info == null
                ? null
                : '${info.version} (${info.buildNumber})',
            aboutBoxChildren: const [
              Text(
                'Book details from Open Library and Google Books. '
                'Source: github.com/jjrgagne/BookCatalog',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
