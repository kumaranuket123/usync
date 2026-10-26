/// OAuth client IDs from Google Cloud Console (APIs & Services > Credentials).
/// The web client ID has a default (client IDs are not secrets); either can be
/// overridden at build time, e.g.
/// `flutter run --dart-define=GOOGLE_WEB_CLIENT_ID=... --dart-define=GOOGLE_IOS_CLIENT_ID=...`
/// The web client ID is the one also set in Supabase (Auth > Providers > Google).
abstract final class GoogleConfig {
  static const String webClientId = String.fromEnvironment(
    'GOOGLE_WEB_CLIENT_ID',
    defaultValue: '230005891640-7krghpcpqab6ck06bqc1euljhv1md67s.apps.googleusercontent.com',
  );
  static const String iosClientId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
}
