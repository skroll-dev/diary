import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../repositories/entry_repository.dart';

/// Fetches the signed-in user's full entry history from Firestore into Drift,
/// showing a non-dismissible progress dialog with a live count. Call this
/// right after a successful login (anonymous → real account, or sign-in to an
/// existing account) so returning users see their full diary history.
///
/// No-op (and shows nothing) for anonymous users — anonymous accounts are
/// device-local, so there is no cross-device history to backfill.
Future<void> runHistorySyncWithProgress(BuildContext context, WidgetRef ref) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null || user.isAnonymous) return;

  final repo = ref.read(entryRepositoryProvider);
  final progress = ValueNotifier<(int loaded, int total)>((0, 0));
  var dialogShown = false;
  var syncDone = false;

  void showProgressDialog() {
    dialogShown = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Center(
          child: Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
              child: ValueListenableBuilder<(int loaded, int total)>(
                valueListenable: progress,
                builder: (ctx, value, _) {
                  final (loaded, total) = value;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (total == 0)
                        CircularProgressIndicator(color: Theme.of(ctx).colorScheme.primary)
                      else
                        SizedBox(
                          width: 160,
                          child: LinearProgressIndicator(
                            value: loaded / total,
                            color: Theme.of(ctx).colorScheme.primary,
                          ),
                        ),
                      const SizedBox(height: 20),
                      Text(
                        total == 0
                            ? 'Einträge werden gesucht …'
                            : 'Einträge werden geladen … $loaded von $total',
                        style: Theme.of(ctx).textTheme.bodyMedium,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  try {
    // Only pop up the dialog if the fetch takes long enough to matter —
    // skip it entirely if sync already finished within the delay window.
    unawaited(Future.delayed(const Duration(milliseconds: 300), () {
      if (!syncDone && context.mounted) showProgressDialog();
    }));

    final inserted = await repo.syncAllEntriesFromFirestore(
      onProgress: (loaded, total) => progress.value = (loaded, total),
    );
    syncDone = true;

    await repo.markHistorySynced(user.uid);
    debugPrint('[HistorySync] synced $inserted new entries for ${user.uid}');
  } catch (e, st) {
    debugPrint('[HistorySync] failed: $e\n$st');
  } finally {
    if (dialogShown && context.mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }
}
