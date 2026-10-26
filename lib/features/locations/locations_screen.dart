import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/book.dart';
import '../../data/models/location.dart';
import '../catalog/library_screen.dart';
import '../common/widgets.dart';

/// Rooms and the people books are lent to, with book counts.
class LocationsScreen extends ConsumerWidget {
  const LocationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locations = ref.watch(locationsProvider).value ?? const <Location>[];
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final counts = <String?, int>{};
    for (final b in books) {
      counts[b.locationId] = (counts[b.locationId] ?? 0) + 1;
    }
    final rooms = locations.where((l) => !l.isPerson).toList();
    final people = locations.where((l) => l.isPerson).toList();
    final known = {for (final l in locations) l.id};
    // Includes books whose place was deleted on another phone.
    final unplaced = books.where((b) => !known.contains(b.locationId)).length;

    return Scaffold(
      appBar: AppBar(title: const Text('Places')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 88),
        children: [
          _Section(
            title: 'Rooms',
            kind: LocationKind.room,
            locations: rooms,
            counts: counts,
            emptyText: 'Add the rooms where you keep books.',
          ),
          _Section(
            title: 'On loan to',
            kind: LocationKind.person,
            locations: people,
            counts: counts,
            emptyText:
                'Lend a book by moving it to a person. '
                'Return puts it back in its room.',
          ),
          if (unplaced > 0)
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('No location'),
              trailing: Text('$unplaced'),
              onTap: () => _openLibrary(context, noLocationFilter),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add room'),
        onPressed: () => createLocation(context, ref, kind: LocationKind.room),
      ),
    );
  }
}

/// Opens the library filtered to a location id (or [noLocationFilter]).
void _openLibrary(BuildContext context, String locationId) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => LibraryScreen(initialLocationId: locationId),
    ),
  );
}

class _Section extends ConsumerWidget {
  const _Section({
    required this.title,
    required this.kind,
    required this.locations,
    required this.counts,
    required this.emptyText,
  });

  final String title;
  final LocationKind kind;
  final List<Location> locations;
  final Map<String?, int> counts;
  final String emptyText;

  Future<void> _reorder(WidgetRef ref, int oldIndex, int newIndex) async {
    final list = [...locations];
    list.insert(newIndex, list.removeAt(oldIndex));
    await ref.read(catalogRepositoryProvider).saveLocations([
      for (var i = 0; i < list.length; i++) list[i].copyWith(sortOrder: i),
    ]);
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Location l) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(context, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    final repo = ref.read(catalogRepositoryProvider);
    if (action == 'rename') {
      final name = await showTextDialog(
        context,
        title: 'Rename',
        initial: l.name,
      );
      if (name != null && name.isNotEmpty) {
        await repo.saveLocation(l.copyWith(name: name));
      }
    } else if (action == 'delete') {
      final books = ref.read(booksProvider).value ?? const <Book>[];
      final count = counts[l.id] ?? 0;
      Location? moveTo;
      if (count > 0) {
        final picked = await pickLocation(
          context,
          ref,
          title: 'Move its $count books to',
        );
        if (picked == null || picked.value?.id == l.id) return;
        moveTo = picked.value;
      } else {
        final ok = await confirm(
          context,
          title: 'Delete ${l.name}?',
          action: 'Delete',
          destructive: true,
        );
        if (!ok) return;
      }
      await ref
          .read(catalogActionsProvider)
          .deleteLocation(
            l,
            books,
            moveTo: moveTo,
            locations: ref.read(locationMapProvider),
          );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
              TextButton.icon(
                icon: Icon(
                  kind == LocationKind.room ? Icons.add : Icons.person_add_alt,
                ),
                label: Text(kind == LocationKind.room ? 'Room' : 'Person'),
                onPressed: () => createLocation(context, ref, kind: kind),
              ),
            ],
          ),
        ),
        if (locations.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Text(emptyText, style: theme.textTheme.bodySmall),
          )
        else
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            onReorderItem: (a, b) => _reorder(ref, a, b),
            children: [
              for (var i = 0; i < locations.length; i++)
                ListTile(
                  key: ValueKey(locations[i].id),
                  leading: Icon(locationIcon(locations[i])),
                  title: Text(locations[i].name),
                  subtitle: Text('${counts[locations[i].id] ?? 0} books'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.more_vert),
                        onPressed: () => _menu(context, ref, locations[i]),
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: const Icon(Icons.drag_handle),
                      ),
                    ],
                  ),
                  onTap: () => _openLibrary(context, locations[i].id),
                ),
            ],
          ),
      ],
    );
  }
}
