import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../data/household/household_service.dart';
import '../common/widgets.dart';

/// Sign-in, creating/joining a household, invites and members.
class HouseholdScreen extends ConsumerStatefulWidget {
  const HouseholdScreen({super.key});

  @override
  ConsumerState<HouseholdScreen> createState() => _HouseholdScreenState();
}

class _HouseholdScreenState extends ConsumerState<HouseholdScreen> {
  bool _working = false;

  Future<void> _run(Future<void> Function() task) async {
    setState(() => _working = true);
    try {
      await task();
    } on FirebaseAuthException catch (e) {
      if (mounted) showSnack(context, 'Sign-in failed: ${e.message ?? e.code}');
    } on HouseholdException catch (e) {
      if (mounted) showSnack(context, e.message);
    } catch (e) {
      if (mounted) {
        showSnack(context, 'Something went wrong. Are you online? ($e)');
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(firebaseReadyProvider);
    final service = ref.watch(householdServiceProvider);
    final user = ref.watch(authStateProvider).value;
    final householdId = ref.watch(householdIdProvider).value;

    Widget body;
    if (!ready || service == null) {
      body = const _NotConfigured();
    } else if (user == null) {
      body = _SignIn(
        onSignIn: () => _run(service.signInWithGoogle),
        working: _working,
      );
    } else if (householdId == null) {
      body = _NoHousehold(user: user, service: service, run: _run);
    } else {
      body = _InHousehold(user: user, service: service, run: _run);
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Household & sharing')),
      body: Stack(
        children: [body, if (_working) const LinearProgressIndicator()],
      ),
    );
  }
}

class _NotConfigured extends StatelessWidget {
  const _NotConfigured();

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.cloud_off, size: 56),
      const SizedBox(height: 16),
      Text(
        'Sharing is not switched on in this build',
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      const Text(
        'Your books are saved on this phone. Once the household\'s Firebase '
        'project is connected (see docs/BUILD_AND_DEPLOY.md), install the new '
        'build, sign in, and copy this phone\'s books into the shared '
        'household catalog.',
        textAlign: TextAlign.center,
      ),
    ],
  );
}

class _SignIn extends StatelessWidget {
  const _SignIn({required this.onSignIn, required this.working});

  final VoidCallback onSignIn;
  final bool working;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const Icon(Icons.groups_outlined, size: 56),
      const SizedBox(height: 16),
      Text(
        'Share the catalog with your household',
        style: Theme.of(context).textTheme.titleLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 12),
      const Text(
        'Sign in with Google, then create a household or join one with an '
        'invite code. Everyone in the household sees and edits the same '
        'catalog, even offline.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      FilledButton.icon(
        icon: const Icon(Icons.login),
        label: const Text('Sign in with Google'),
        onPressed: working ? null : onSignIn,
      ),
    ],
  );
}

class _NoHousehold extends ConsumerWidget {
  const _NoHousehold({
    required this.user,
    required this.service,
    required this.run,
  });

  final User user;
  final HouseholdService service;
  final Future<void> Function(Future<void> Function()) run;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> join(String code) => run(() async {
      await service.joinHousehold(user, code);
      if (context.mounted) showSnack(context, 'Joined the household');
    });

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(
          'Signed in as ${user.email ?? user.displayName}',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Start a household',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Creates a shared catalog. You will get an invite code for '
                  'everyone else.',
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () async {
                    final name = await showTextDialog(
                      context,
                      title: 'Household name',
                      initial: 'Our books',
                      action: 'Create',
                    );
                    if (name == null || name.isEmpty) return;
                    await run(() => service.createHousehold(user, name));
                  },
                  child: const Text('Create household'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Join a household',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ask someone in the household for the invite code, or scan '
                  'the QR code on their phone.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.keyboard),
                        label: const Text('Enter code'),
                        onPressed: () async {
                          final code = await showTextDialog(
                            context,
                            title: 'Invite code',
                            hint: 'e.g. K7Q2XM',
                            action: 'Join',
                          );
                          if (code != null && code.isNotEmpty) await join(code);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('Scan QR'),
                        onPressed: () async {
                          final code = await Navigator.push<String>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const _ScanInviteQr(),
                            ),
                          );
                          if (code != null) await join(code);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        TextButton(
          onPressed: () => run(service.signOut),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

class _InHousehold extends ConsumerWidget {
  const _InHousehold({
    required this.user,
    required this.service,
    required this.run,
  });

  final User user;
  final HouseholdService service;
  final Future<void> Function(Future<void> Function()) run;

  Future<void> _copyLocalBooks(BuildContext context, WidgetRef ref) async {
    final local = ref.read(localRepositoryProvider);
    final books = await local.allBooks();
    if (!context.mounted) return;
    final ok = await confirm(
      context,
      title: 'Copy ${books.length} books into the household?',
      message:
          'Books, places and tags saved on this phone before you joined will '
          'be added to the shared catalog, then removed from the phone-only '
          'list.',
      action: 'Copy',
    );
    if (!ok) return;
    await run(() async {
      await ref
          .read(catalogActionsProvider)
          .importAll(
            books: books,
            locations: await local.allLocations(),
            tags: await local.allTags(),
          );
      await local.clear();
      if (context.mounted) showSnack(context, 'Copied ${books.length} books');
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider).value;
    final members = ref.watch(membersProvider).value ?? const <Member>[];
    final localBooks = ref.watch(_localBookCountProvider).value ?? 0;
    if (household == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final isOwner = household.ownerUid == user.uid;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(household.name, style: theme.textTheme.headlineSmall),
          subtitle: Text('Signed in as ${user.email ?? user.displayName}'),
          trailing: isOwner
              ? IconButton(
                  tooltip: 'Rename',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () async {
                    final name = await showTextDialog(
                      context,
                      title: 'Household name',
                      initial: household.name,
                    );
                    if (name != null && name.isNotEmpty) {
                      await run(
                        () => service.renameHousehold(household.id, name),
                      );
                    }
                  },
                )
              : null,
        ),
        if (localBooks > 0)
          Card(
            color: theme.colorScheme.secondaryContainer,
            child: ListTile(
              leading: const Icon(Icons.upload),
              title: Text('$localBooks books are only on this phone'),
              subtitle: const Text('Copy them into the shared catalog'),
              onTap: () => _copyLocalBooks(context, ref),
            ),
          ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text('Invite code', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                SelectableText(
                  household.inviteCode,
                  style: theme.textTheme.displaySmall?.copyWith(
                    letterSpacing: 6,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(8),
                  child: QrImageView(
                    data: '$inviteQrPrefix${household.inviteCode}',
                    size: 180,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'On the other phone: More → Household → sign in → '
                  'Join → enter the code or scan this QR.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Share code'),
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text:
                              'Join our BookCatalog household with invite '
                              'code ${household.inviteCode}',
                        ),
                      ),
                    ),
                    if (isOwner)
                      TextButton(
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            title: 'Make a new invite code?',
                            message:
                                'The old code will stop working. Existing '
                                'members are not affected.',
                            action: 'New code',
                          );
                          if (ok) {
                            await run(
                              () => service.regenerateInviteCode(household),
                            );
                          }
                        },
                        child: const Text('New code'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('Members', style: theme.textTheme.titleMedium),
        for (final m in members)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Text(
                m.displayName.isEmpty ? '?' : m.displayName[0].toUpperCase(),
              ),
            ),
            title: Text(
              m.uid == user.uid ? '${m.displayName} (you)' : m.displayName,
            ),
            subtitle: Text(
              [m.email, if (m.isOwner) 'owner'].whereType<String>().join(' · '),
            ),
            trailing: isOwner && m.uid != user.uid
                ? IconButton(
                    tooltip: 'Remove',
                    icon: const Icon(Icons.person_remove_outlined),
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        title: 'Remove ${m.displayName}?',
                        message: 'They will no longer see the catalog.',
                        action: 'Remove',
                        destructive: true,
                      );
                      if (ok) {
                        await run(
                          () => service.removeMember(household.id, m.uid),
                        );
                      }
                    },
                  )
                : null,
          ),
        const SizedBox(height: 24),
        if (!isOwner)
          OutlinedButton(
            onPressed: () async {
              final ok = await confirm(
                context,
                title: 'Leave ${household.name}?',
                message: 'The catalog stays with the other members.',
                action: 'Leave',
                destructive: true,
              );
              if (ok) {
                await run(() => service.leaveHousehold(household.id, user.uid));
              }
            },
            child: const Text('Leave household'),
          ),
        TextButton(
          onPressed: () => run(service.signOut),
          child: const Text('Sign out'),
        ),
      ],
    );
  }
}

final _localBookCountProvider = StreamProvider<int>(
  (ref) => ref.watch(localRepositoryProvider).watchBooks().map((b) => b.length),
);

class _ScanInviteQr extends StatefulWidget {
  const _ScanInviteQr();

  @override
  State<_ScanInviteQr> createState() => _ScanInviteQrState();
}

class _ScanInviteQrState extends State<_ScanInviteQr> {
  final _controller = MobileScannerController(
    formats: const [BarcodeFormat.qrCode],
  );
  bool _done = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan invite QR')),
    body: MobileScanner(
      controller: _controller,
      onDetect: (capture) {
        if (_done) return;
        for (final b in capture.barcodes) {
          final v = b.rawValue;
          if (v != null && v.startsWith(inviteQrPrefix)) {
            _done = true;
            Navigator.pop(context, v);
            return;
          }
        }
      },
    ),
  );
}
