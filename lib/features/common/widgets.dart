import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/models/ids.dart';
import '../../data/models/location.dart';
import '../../data/models/tag.dart';
import '../../data/services/backup_sources.dart';

/// A book cover from its URL, with a placeholder when missing or offline.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.url, this.width = 48});

  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final placeholder = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.menu_book,
        size: width * 0.5,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
    if (url == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: width,
        height: height,
        fit: BoxFit.cover,
        placeholder: (_, _) => placeholder,
        errorWidget: (_, _, _) => placeholder,
      ),
    );
  }
}

/// Small coloured chips for a book's tags.
class TagChips extends ConsumerWidget {
  const TagChips({super.key, required this.tagIds});

  final List<String> tagIds;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagMapProvider);
    final list = tagIds.map((id) => tags[id]).whereType<Tag>().toList();
    if (list.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [for (final t in list) TagLabel(tag: t)],
    );
  }
}

class TagLabel extends StatelessWidget {
  const TagLabel({super.key, required this.tag});

  final Tag tag;

  @override
  Widget build(BuildContext context) {
    final color = Color(tag.color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(tag.name, style: Theme.of(context).textTheme.labelSmall),
    );
  }
}

IconData locationIcon(Location? location) => location == null
    ? Icons.help_outline
    : location.isPerson
    ? Icons.person_outline
    : Icons.meeting_room_outlined;

/// Result of a picker, so "chose nothing" differs from "cancelled" (null).
class Picked<T> {
  const Picked(this.value);
  final T value;
}

/// Asks for a single line of text.
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String action = 'Save',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: Text(action),
        ),
      ],
    ),
  );
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  String? message,
  String action = 'OK',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: message == null ? null : Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Creates a room or person and saves it.
Future<Location?> createLocation(
  BuildContext context,
  WidgetRef ref, {
  required LocationKind kind,
}) async {
  final name = await showTextDialog(
    context,
    title: kind == LocationKind.room ? 'New room' : 'Lend to…',
    hint: kind == LocationKind.room ? 'e.g. Living Room' : "Person's name",
    action: 'Add',
  );
  if (name == null || name.isEmpty) return null;
  final existing = ref.read(locationsProvider).value ?? [];
  final location = Location(
    id: generateId(),
    name: name,
    kind: kind,
    sortOrder: existing.where((l) => l.kind == kind).length,
  );
  await ref.read(catalogRepositoryProvider).saveLocation(location);
  return location;
}

/// Bottom sheet listing rooms and people. Returns null if dismissed.
Future<Picked<Location?>?> pickLocation(
  BuildContext context,
  WidgetRef ref, {
  String? selectedId,
  String title = 'Choose location',
  bool allowNone = true,
}) {
  return showModalBottomSheet<Picked<Location?>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final locations = ref.watch(locationsProvider).value ?? [];
        final rooms = locations.where((l) => !l.isPerson).toList();
        final people = locations.where((l) => l.isPerson).toList();
        Widget tile(Location l) => ListTile(
          leading: Icon(locationIcon(l)),
          title: Text(l.name),
          trailing: l.id == selectedId ? const Icon(Icons.check) : null,
          onTap: () => Navigator.pop(context, Picked<Location?>(l)),
        );
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, controller) => ListView(
            controller: controller,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              if (allowNone)
                ListTile(
                  leading: const Icon(Icons.block),
                  title: const Text('No location'),
                  trailing: selectedId == null ? const Icon(Icons.check) : null,
                  onTap: () =>
                      Navigator.pop(context, const Picked<Location?>(null)),
                ),
              const _SectionHeader('Rooms'),
              ...rooms.map(tile),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('Add room'),
                onTap: () async {
                  final l = await createLocation(
                    context,
                    ref,
                    kind: LocationKind.room,
                  );
                  if (l != null && context.mounted) {
                    Navigator.pop(context, Picked<Location?>(l));
                  }
                },
              ),
              const _SectionHeader('On loan to'),
              ...people.map(tile),
              ListTile(
                leading: const Icon(Icons.person_add_alt),
                title: const Text('Add person'),
                onTap: () async {
                  final l = await createLocation(
                    context,
                    ref,
                    kind: LocationKind.person,
                  );
                  if (l != null && context.mounted) {
                    Navigator.pop(context, Picked<Location?>(l));
                  }
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelLarge
          ?.copyWith(color: Theme.of(context).colorScheme.primary),
    ),
  );
}

/// Creates a tag and saves it.
Future<Tag?> createTag(BuildContext context, WidgetRef ref) async {
  final name = await showTextDialog(
    context,
    title: 'New tag',
    hint: 'e.g. Fiction, Signed, Kids',
    action: 'Add',
  );
  if (name == null || name.isEmpty) return null;
  final count = ref.read(tagsProvider).value?.length ?? 0;
  final tag = Tag(
    id: generateId(),
    name: name,
    color: tagPalette[count % tagPalette.length],
  );
  await ref.read(catalogRepositoryProvider).saveTag(tag);
  return tag;
}

/// Multi-select tag sheet. Returns null if dismissed.
Future<Set<String>?> pickTags(
  BuildContext context,
  WidgetRef ref, {
  required Iterable<String> selected,
  String title = 'Tags',
}) {
  final chosen = {...selected};
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final tags = ref.watch(tagsProvider).value ?? [];
        return StatefulBuilder(
          builder: (context, setState) => SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final t in tags)
                        FilterChip(
                          label: Text(t.name),
                          avatar: CircleAvatar(
                            backgroundColor: Color(t.color),
                            radius: 6,
                          ),
                          selected: chosen.contains(t.id),
                          onSelected: (on) => setState(
                            () => on ? chosen.add(t.id) : chosen.remove(t.id),
                          ),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.add, size: 18),
                        label: const Text('New tag'),
                        onPressed: () async {
                          final t = await createTag(context, ref);
                          if (t != null) setState(() => chosen.add(t.id));
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, chosen),
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}

/// "Search Amazon / AbeBooks / Google" buttons for books no source knows.
/// They open in the phone's browser; details can then be typed in.
class WebSearchButtons extends StatelessWidget {
  const WebSearchButtons({super.key, required this.isbn13});

  final String isbn13;

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      Text('Search:', style: Theme.of(context).textTheme.labelLarge),
      for (final s in webSearchesFor(isbn13))
        ActionChip(
          avatar: const Icon(Icons.open_in_new, size: 16),
          label: Text(s.label),
          onPressed: () =>
              launchUrl(s.url, mode: LaunchMode.externalApplication),
        ),
    ],
  );
}

void showSnack(BuildContext context, String message, {SnackBarAction? action}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message), action: action));
}
