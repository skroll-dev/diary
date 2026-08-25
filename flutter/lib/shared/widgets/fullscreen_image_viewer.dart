import 'package:flutter/material.dart';

import '../models/entry_image.dart';
import 'storage_image.dart';

/// Full-screen swipeable viewer over an entry's full-resolution images.
/// Opened from both the history detail sheet and the topics-review grid.
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
  late final _controller = PageController(initialPage: widget.initialIndex);

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
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.images.length,
        itemBuilder: (context, index) => Center(
          child: InteractiveViewer(
            child: StorageImage(
              objectPath: widget.images[index].fullPath,
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
