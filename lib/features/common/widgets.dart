import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../data/models/book.dart';
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

/// Location shown for a book, e.g. "Living Room" or "On loan to Sam".
String locationLabel(Location? location) {
  if (location == null) return 'No location';
  return location.isPerson ? 'On loan to ${location.name}' : location.name;
}

/// A row showing a location; tapping it opens the location picker.
class LocationTile extends ConsumerWidget {
  const LocationTile({
    super.key,
    required this.locationId,
    required this.onChanged,
    this.label,
    this.pickerTitle = 'Choose location',
    this.dense = false,
  });

  final String? locationId;
  final ValueChanged<Location?> onChanged;

  /// Overrides the text, e.g. "Filing to: Office".
  final String Function(Location?)? label;
  final String pickerTitle;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationMapProvider)[locationId];
    return ListTile(
      dense: dense,
      contentPadding: dense ? null : EdgeInsets.zero,
      leading: Icon(locationIcon(location)),
      title: Text((label ?? locationLabel)(location)),
      trailing: const Icon(Icons.edit_outlined, size: 20),
      onTap: () async {
        final picked = await pickLocation(
          context,
          ref,
          selectedId: locationId,
          title: pickerTitle,
        );
        if (picked != null) onChanged(picked.value);
      },
    );
  }
}

/// A row showing tags; tapping it opens the tag picker.
class TagsTile extends ConsumerWidget {
  const TagsTile({
    super.key,
    required this.tagIds,
    required this.onChanged,
    this.emptyText = 'No tags',
    this.pickerTitle = 'Tags',
    this.dense = false,
  });

  final List<String> tagIds;
  final ValueChanged<List<String>> onChanged;
  final String emptyText;
  final String pickerTitle;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    dense: dense,
    contentPadding: dense ? null : EdgeInsets.zero,
    leading: const Icon(Icons.label_outline),
    title: tagIds.isEmpty ? Text(emptyText) : TagChips(tagIds: tagIds),
    trailing: const Icon(Icons.edit_outlined, size: 20),
    onTap: () async {
      final chosen = await pickTags(
        context,
        ref,
        selected: tagIds,
        title: pickerTitle,
      );
      if (chosen != null) onChanged(chosen.toList());
    },
  );
}

/// "3 copies  [-] [+]".
class CopiesTile extends StatelessWidget {
  const CopiesTile({super.key, required this.copies, required this.onChanged});

  final int copies;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: const Icon(Icons.layers_outlined),
    title: Text(copies == 1 ? '1 copy' : '$copies copies'),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'One fewer',
          icon: const Icon(Icons.remove),
          onPressed: copies <= 1 ? null : () => onChanged(copies - 1),
        ),
        IconButton(
          tooltip: 'One more',
          icon: const Icon(Icons.add),
          onPressed: () => onChanged(copies + 1),
        ),
      ],
    ),
  );
}

/// Asks where to move [books], then moves them (remembering the room when
/// lending to a person). Returns the picked result, or null if cancelled.
Future<Picked<Location?>?> pickAndMoveBooks(
  BuildContext context,
  WidgetRef ref,
  List<Book> books, {
  String title = 'Move to',
  bool allowNone = true,
}) async {
  final picked = await pickLocation(
    context,
    ref,
    selectedId: books.length == 1 ? books.single.locationId : null,
    title: title,
    allowNone: allowNone,
  );
  if (picked == null) return null;
  await ref
      .read(catalogActionsProvider)
      .moveBooks(books, picked.value, ref.read(locationMapProvider));
  return picked;
}

/// Result of a picker, so "chose nothing" differs from "cancelled" (null).
class Picked<T> {
  const Picked(this.value);
  final T value;
}

/// Asks for text: one line (names, codes) or, with [multiline], free text
/// such as notes. Returns the trimmed text, or null if cancelled.
Future<String?> showTextDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  String? hint,
  String action = 'Save',
  bool multiline = false,
}) {
  // Not disposed: the dialog's closing animation still uses it after pop.
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: multiline
            ? TextCapitalization.sentences
            : TextCapitalization.words,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        decoration: InputDecoration(
          hintText: hint,
          border: multiline ? const OutlineInputBorder() : null,
        ),
        onSubmitted: multiline ? null : (v) => Navigator.pop(context, v.trim()),
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
