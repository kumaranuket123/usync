/// OAuth client IDs from Google Cloud Console (APIs & Services > Credentials).
/// The web client ID has a default (client IDs are not secrets); either can be
/// overridden at build time, e.g.
/// `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...`
/// The web client ID is the one also set in Supabase (Auth > Providers > Google).
abstract final class GoogleConfig {
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '375959701381-uscvicji8tb4soptuq0c44hni511lhep.apps.googleusercontent.com',
  );
  static const String iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
}
