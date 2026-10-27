import 'package:flutter_test/flutter_test.dart';
import 'package:usync/data/models/access_model.dart';
import 'package:usync/data/models/app_config_model.dart';
import 'package:usync/domain/entities/access.dart';
import 'package:usync/domain/entities/app_config.dart';

void main() {
  group('AppConfig.isUpdateRequired', () {
    test('only builds below the minimum must update', () {
      const config = AppConfig(minSupportedBuild: 6);
      expect(config.isUpdateRequired(5), isTrue);
      expect(config.isUpdateRequired(6), isFalse);
      expect(config.isUpdateRequired(7), isFalse);
    });

    test('the open config never blocks anyone', () {
      expect(const AppConfig.open().isUpdateRequired(1), isFalse);
      expect(const AppConfig.open().paywallEnabled, isFalse);
    });

    test('is read from the server JSON, with safe defaults for anything missing', () {
      final full = AppConfigModel.fromJson({
        'min_supported_build': 7, 'latest_build': 9, 'update_url': 'https://x.test/app.apk',
        'paywall_enabled': true, 'trial_days': 14,
      });
      expect(full.minSupportedBuild, 7);
      expect(full.updateUrl, 'https://x.test/app.apk');
      expect(full.paywallEnabled, isTrue);
      expect(full.trialDays, 14);

      final empty = AppConfigModel.fromJson({});
      expect(empty.minSupportedBuild, 0);
      expect(empty.paywallEnabled, isFalse);
      expect(empty.trialDays, 30);
    });
  });

  group('AppConfig.safeUpdateUri', () {
    test('only https links are opened', () {
      expect(const AppConfig(updateUrl: 'https://x.test/app.apk').safeUpdateUri, Uri.parse('https://x.test/app.apk'));
      expect(const AppConfig(updateUrl: 'http://x.test/app.apk').safeUpdateUri, isNull);
      expect(const AppConfig(updateUrl: 'intent://x').safeUpdateUri, isNull);
      expect(const AppConfig(updateUrl: 'not a url').safeUpdateUri, isNull);
      expect(const AppConfig().safeUpdateUri, isNull);
    });
  });

  group('AccessModel', () {
    test('reads every state', () {
      for (final s in AccessStatus.values) {
        expect(AccessModel.fromJson({'state': s.name, 'paywall_enabled': true}).status, s);
      }
    });

    test('an unknown or missing state means full access', () {
      expect(AccessModel.fromJson({'state': 'something-new'}).status, AccessStatus.free);
      expect(AccessModel.fromJson({}).status, AccessStatus.free);
    });

    test('reads the end date and the paywall switch', () {
      final a = AccessModel.fromJson({'state': 'trial', 'until': '2026-12-12T10:00:00Z', 'paywall_enabled': true});
      expect(a.paywallEnabled, isTrue);
      expect(a.until!.toUtc(), DateTime.utc(2026, 12, 12, 10));
    });
  });

  group('Access.daysLeft', () {
    final until = DateTime(2026, 6, 20, 15);

    test('counts whole calendar days', () {
      expect(Access(until: until).daysLeft(DateTime(2026, 6, 10, 23)), 10);
      expect(Access(until: until).daysLeft(DateTime(2026, 6, 20, 1)), 0);
    });

    test('is zero once it has passed, or when there is no end date', () {
      expect(Access(until: until).daysLeft(DateTime(2026, 7, 1)), 0);
      expect(const Access().daysLeft(DateTime(2026, 7, 1)), 0);
    });
  });
}
