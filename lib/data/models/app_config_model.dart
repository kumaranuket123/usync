import '../../domain/entities/app_config.dart';

class AppConfigModel extends AppConfig {
  const AppConfigModel({
    super.minSupportedBuild,
    super.latestBuild,
    super.updateUrl,
    super.paywallEnabled,
    super.trialDays,
  });

  /// The JSON returned by the `get_app_config` RPC.
  factory AppConfigModel.fromJson(Map<String, dynamic> json) => AppConfigModel(
    minSupportedBuild: (json['min_supported_build'] as num?)?.toInt() ?? 0,
    latestBuild:       (json['latest_build'] as num?)?.toInt() ?? 0,
    updateUrl:         json['update_url'] as String?,
    paywallEnabled:    json['paywall_enabled'] as bool? ?? false,
    trialDays:         (json['trial_days'] as num?)?.toInt() ?? 30,
  );
}
