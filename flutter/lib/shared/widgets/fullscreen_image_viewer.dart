import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../models/entry_image.dart';
import 'storage_image.dart';

/// Full-screen swipeable viewer over an entry's full-resolution images, with
/// pinch-to-zoom and double-tap-to-zoom like a regular gallery app.
///
/// Built on PhotoViewGallery rather than a hand-rolled PageView +
/// InteractiveViewer: PhotoView's gesture detector is specifically designed
/// to arbitrate between per-image pinch/pan/double-tap-zoom and the
/// gallery's own swipe-between-photos, which a plain InteractiveViewer
/// nested in a PageView gets wrong (pinch competing with the page-swipe
/// recognizer, and no double-tap-zoom at all — InteractiveViewer doesn't
/// provide that out of the box).
class FullscreenImageViewer extends StatefulWidget {
  const FullscreenImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  final List<EntryImage> images;
  final int initialIndex;

  static void open(
    BuildContext context, {
    required List<EntryImage> images,
    required int initialIndex,
  }) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FullscreenImageViewer(
        images: images,
        initialIndex: initialIndex,
      ),
      fullscreenDialog: true,
    ));
  }

  @override
  State<FullscreenImageViewer> createState() => _FullscreenImageViewerState();
}

class _FullscreenImageViewerState extends State<FullscreenImageViewer> {
  late final _pageController = PageController(initialPage: widget.initialIndex);

  // PhotoViewGalleryPageOptions needs a synchronous ImageProvider, but
  // Storage object paths only resolve to a URL asynchronously — so resolve
  // all of them up front (reusing StorageImage's cache; cheap, capped at
  // kMaxImagesPerEntry) rather than per-page.
  late final Future<List<String>> _urlsFuture = Future.wait(
    widget.images.map((img) => resolveStorageDownloadUrl(img.fullPath)),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      extendBodyBehindAppBar: true,
      body: FutureBuilder<List<String>>(
        future: _urlsFuture,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white),
            );
          }
          final urls = snap.data!;
          return PhotoViewGallery.builder(
            pageController: _pageController,
            itemCount: urls.length,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
            builder: (context, index) => PhotoViewGalleryPageOptions(
              imageProvider: CachedNetworkImageProvider(urls[index]),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              initialScale: PhotoViewComputedScale.contained,
            ),
          );
        },
      ),
    );
  }
}
