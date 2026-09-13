import 'package:flutter/widgets.dart';

import '../extensions/localization_extensions.dart';

/// Emoji for a mood value — universal, not localized.
String moodEmoji(String mood) => switch (mood) {
      'happy' => '😊',
      'calm' => '😌',
      'tense' => '😰',
      'sad' => '😔',
      'mixed' => '🤔',
      _ => '😐', // neutral
    };

/// Localized display label for a mood value.
String moodLabel(BuildContext context, String mood) {
  final l10n = context.l10n;
  return switch (mood) {
    'happy' => l10n.moodHappy,
    'calm' => l10n.moodCalm,
    'tense' => l10n.moodTense,
    'sad' => l10n.moodSad,
    'mixed' => l10n.moodMixed,
    _ => l10n.moodNeutral,
  };
}
