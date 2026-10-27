import '../constants/app_constants.dart';

/// The text shared with an invite code. [downloadUrl] is where the partner can get the app;
/// without one the message just tells them to download it.
String inviteMessage(String code, {String? downloadUrl = AppConstants.appDownloadUrl}) {
  final link = downloadUrl == null || downloadUrl.isEmpty
      ? "Download the app and let's connect."
      : "Download the app here:\n$downloadUrl\n\nThen enter the code and let's connect.";
  return 'Join me on Usync! 💖\n\nYour invite code: $code\n\n$link';
}
