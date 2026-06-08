import 'package:app_links/app_links.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'shared/services/auth_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: AiTagebuchApp()));
}

class AiTagebuchApp extends ConsumerStatefulWidget {
  const AiTagebuchApp({super.key});

  @override
  ConsumerState<AiTagebuchApp> createState() => _AiTagebuchAppState();
}

class _AiTagebuchAppState extends ConsumerState<AiTagebuchApp> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      ref.read(authServiceProvider); // warm up anonymous auth on startup
      _initDeepLinks();
    }
  }

  Future<void> _initDeepLinks() async {
    final appLinks = AppLinks();

    // Cold start: link that launched the app
    final initialUri = await appLinks.getInitialLink();
    if (initialUri != null) _handleLink(initialUri);

    // Foreground / background: links received while app is running
    appLinks.uriLinkStream.listen(_handleLink);
  }

  void _handleLink(Uri uri) {
    final link = uri.toString();
    if (FirebaseAuth.instance.isSignInWithEmailLink(link)) {
      ref
          .read(authServiceProvider.notifier)
          .completeEmailLinkSignIn(link)
          .catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'AI Tagebuch',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
      debugShowCheckedModeBanner: true,
    );
  }
}
