import 'dart:convert';

/// A single image attached to a diary entry. [fullPath]/[thumbPath] are
/// Firebase Storage object paths (never signed/download URLs) — resolved to
/// a viewable URL at read time via [FirebaseStorage], see
/// `shared/widgets/storage_image.dart`. Stored and read back verbatim in the
/// `Entries.images` JSON column, never reconstructed from uid/date/ordinal.
class EntryImage {
  const EntryImage({
    required this.fullPath,
    required this.thumbPath,
    required this.order,
    required this.width,
    required this.height,
    required this.thumbWidth,
    required this.thumbHeight,
  });

  final String fullPath;
  final String thumbPath;

  /// Explicit, mutable sort key — the element with `order == 0` is by
  /// construction the entry's card-preview thumbnail.
  final int order;

  final int width;
  final int height;
  final int thumbWidth;
  final int thumbHeight;

  factory EntryImage.fromJson(Map<String, dynamic> j) => EntryImage(
        fullPath: j['fullPath'] as String? ?? '',
        thumbPath: j['thumbPath'] as String? ?? '',
        order: (j['order'] as num?)?.toInt() ?? 0,
        width: (j['width'] as num?)?.toInt() ?? 0,
        height: (j['height'] as num?)?.toInt() ?? 0,
        thumbWidth: (j['thumbWidth'] as num?)?.toInt() ?? 0,
        thumbHeight: (j['thumbHeight'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'fullPath': fullPath,
        'thumbPath': thumbPath,
        'order': order,
        'width': width,
        'height': height,
        'thumbWidth': thumbWidth,
        'thumbHeight': thumbHeight,
      };

  EntryImage copyWith({int? order}) => EntryImage(
        fullPath: fullPath,
        thumbPath: thumbPath,
        order: order ?? this.order,
        width: width,
        height: height,
        thumbWidth: thumbWidth,
        thumbHeight: thumbHeight,
      );
}

/// Decodes the `Entries.images` JSON-TEXT column into a sorted list. Falls
/// back to an empty list on malformed input rather than throwing.
List<EntryImage> parseEntryImages(String json) {
  try {
    return (jsonDecode(json) as List)
        .map((e) => EntryImage.fromJson(e as Map<String, dynamic>))
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  } catch (_) {
    return [];
  }
}

String encodeEntryImages(List<EntryImage> images) =>
    jsonEncode(images.map((i) => i.toJson()).toList());
