import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Screen 2: Home / Heute
/// Großer Record-Button + Verlauf-Teaser (MVP-Konzept §6)
class RecordingScreen extends ConsumerStatefulWidget {
  const RecordingScreen({super.key});

  @override
  ConsumerState<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends ConsumerState<RecordingScreen> {
  bool _isRecording = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _formattedDate(),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 48),
            GestureDetector(
              onTap: _toggleRecording,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _isRecording ? 140 : 120,
                height: _isRecording ? 140 : 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _isRecording
                      ? colorScheme.error
                      : colorScheme.primary,
                ),
                child: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  color: colorScheme.onPrimary,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _isRecording
                  ? 'Aufnahme läuft…'
                  : 'Tagebucheintrag erstellen',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }

  void _toggleRecording() {
    setState(() => _isRecording = !_isRecording);
    // TODO: RecordingNotifier aufrufen
  }

  String _formattedDate() {
    final now = DateTime.now();
    return '${now.day}. ${_monthName(now.month)} ${now.year}';
  }

  String _monthName(int month) => const [
        '', 'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
        'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
      ][month];
}
