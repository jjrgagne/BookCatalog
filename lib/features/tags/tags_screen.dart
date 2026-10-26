import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/models/book.dart';
import '../../data/models/tag.dart';
import '../catalog/library_screen.dart';
import '../common/widgets.dart';

class TagsScreen extends ConsumerWidget {
  const TagsScreen({super.key});

  Future<void> _edit(BuildContext context, WidgetRef ref, Tag tag) async {
    final repo = ref.read(catalogRepositoryProvider);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tag.name, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final c in tagPalette)
                    InkWell(
                      onTap: () => Navigator.pop(context, 'color:$c'),
                      child: CircleAvatar(
                        backgroundColor: Color(c),
                        radius: 16,
                        child: c == tag.color
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Rename'),
                onTap: () => Navigator.pop(context, 'rename'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ],
          ),
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    if (action.startsWith('color:')) {
      await repo.saveTag(tag.copyWith(color: int.parse(action.substring(6))));
    } else if (action == 'rename') {
      final name = await showTextDialog(
        context,
        title: 'Rename tag',
        initial: tag.name,
      );
      if (name != null && name.isNotEmpty) {
        await repo.saveTag(tag.copyWith(name: name));
      }
    } else if (action == 'delete') {
      final ok = await confirm(
        context,
        title: 'Delete "${tag.name}"?',
        message: 'It will be removed from all books.',
        action: 'Delete',
        destructive: true,
      );
      if (ok) {
        await ref
            .read(catalogActionsProvider)
            .deleteTag(tag, ref.read(booksProvider).value ?? const <Book>[]);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(tagsProvider).value ?? const <Tag>[];
    final books = ref.watch(booksProvider).value ?? const <Book>[];
    final counts = <String, int>{};
    for (final b in books) {
      for (final t in b.tagIds) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Tags')),
      body: tags.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Tags are labels like Fiction, Signed or Kids. '
                  'A book can have several.',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(
              children: [
                for (final t in tags)
                  ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Color(t.color),
                      radius: 10,
                    ),
                    title: Text(t.name),
                    subtitle: Text('${counts[t.id] ?? 0} books'),
                    trailing: IconButton(
                      icon: const Icon(Icons.more_vert),
                      onPressed: () => _edit(context, ref, t),
                    ),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => LibraryScreen(initialTagId: t.id),
                      ),
                    ),
                  ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('New tag'),
        onPressed: () => createTag(context, ref),
      ),
    );
  }
}
