import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

/// Module-level, session-lifetime cache of resolved download URLs. Firebase
/// Storage download tokens don't expire the way signed URLs do, so caching
/// for the app session is safe and avoids a redundant network round-trip
/// (`getDownloadURL()`) every time a tile scrolls back into view.
final _downloadUrlCache = <String, Future<String>>{};

/// Displays an image stored at a Firebase Storage object path. Resolves the
/// path to a download URL directly via the Storage SDK (no proxy round-trip
/// for reads) and renders it through [CachedNetworkImage] for on-disk
/// caching across app restarts.
class StorageImage extends StatefulWidget {
  const StorageImage({
    super.key,
    required this.objectPath,
    this.fit = BoxFit.cover,
  });

  final String objectPath;
  final BoxFit fit;

  @override
  State<StorageImage> createState() => _StorageImageState();
}

class _StorageImageState extends State<StorageImage> {
  // Deliberately a StatefulWidget with a memoized Future, not an inline
  // `future:` built in a stateless build() — FutureBuilder compares its
  // `future` by reference, so calling getDownloadURL() inline would recreate
  // the future (and re-trigger a real network call) on every rebuild,
  // causing flicker during scroll.
  late Future<String> _urlFuture;

  @override
  void initState() {
    super.initState();
    _urlFuture = _resolve(widget.objectPath);
  }

  @override
  void didUpdateWidget(covariant StorageImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Widgets in a reordered list/grid without a per-item Key get their
    // Element/State REUSED at the same tree position rather than recreated —
    // without this, objectPath would silently change under an already-
    // resolved _urlFuture and the old image would keep showing at that slot
    // forever (exactly what happened in the un-keyed list-card photo strip
    // after a reorder).
    if (oldWidget.objectPath != widget.objectPath) {
      // Block body, not `=> _urlFuture = _resolve(...)`: an assignment
      // expression evaluates to the assigned value, so an arrow-bodied
      // closure here would "return" the Future itself — setState() asserts
      // against that (it looks like an accidental `async` callback) even
      // though nothing here is actually asynchronous.
      setState(() {
        _urlFuture = _resolve(widget.objectPath);
      });
    }
  }

  Future<String> _resolve(String objectPath) => _downloadUrlCache.putIfAbsent(
        objectPath,
        () => FirebaseStorage.instance.ref(objectPath).getDownloadURL(),
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: _urlFuture,
      builder: (context, snap) {
        if (!snap.hasData) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          );
        }
        return CachedNetworkImage(
          imageUrl: snap.data!,
          fit: widget.fit,
          placeholder: (context, url) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          errorWidget: (context, url, error) => Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Icon(Icons.broken_image_outlined),
          ),
        );
      },
    );
  }
}
