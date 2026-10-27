import 'package:flutter_test/flutter_test.dart';
import 'package:usync/core/constants/app_constants.dart';
import 'package:usync/core/utils/invite_message.dart';

void main() {
  test('contains the code and the download link', () {
    final text = inviteMessage('AB12', downloadUrl: 'https://example.com/usync.apk');
    expect(text, contains('AB12'));
    expect(text, contains('https://example.com/usync.apk'));
  });

  test('without a link it still tells the partner to download the app', () {
    for (final none in [null, '']) {
      final text = inviteMessage('AB12', downloadUrl: none);
      expect(text, contains('AB12'));
      expect(text, contains('Download the app'));
      expect(text, isNot(contains('http')));
    }
  });

  test('by default the shared message carries the temporary download link', () {
    expect(AppConstants.appDownloadUrl, startsWith('https://drive.google.com/'));
    expect(inviteMessage('AB12'), contains(AppConstants.appDownloadUrl));
  });
}
