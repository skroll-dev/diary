import 'package:url_launcher/url_launcher.dart';

const kTermsUrl = 'https://silbenquiz.de/diary-web/terms.html';

String privacyPolicyUrl(String languageCode) =>
    'https://silbenquiz.de/diary-web/privacy_${languageCode == 'de' ? 'de' : 'en'}.html';

Future<void> openLegalUrl(String url) =>
    launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
