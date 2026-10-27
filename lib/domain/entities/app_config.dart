import 'package:equatable/equatable.dart';

/// Switches the server sets for every installed copy of the app (read before sign-in).
class AppConfig extends Equatable {
  const AppConfig({
    this.minSupportedBuild = 0,
    this.latestBuild       = 0,
    this.updateUrl,
    this.paywallEnabled    = false,
    this.trialDays         = 30,
  });

  /// Nothing required, no paywall: what the app assumes when it cannot reach the server.
  const AppConfig.open() : this();

  /// Builds below this must update before they can be used.
  final int     minSupportedBuild;
  final int     latestBuild;
  /// Where to get the newest version (a Play link, or a download page for an APK).
  final String? updateUrl;
  final bool    paywallEnabled;
  final int     trialDays;

  /// [updateUrl] as a link we are willing to open: https only, never anything else.
  Uri? get safeUpdateUri {
    final raw = updateUrl;
    if (raw == null) return null;
    final uri = Uri.tryParse(raw);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty ? uri : null;
  }

  /// [build] is the installed build number (the number after `+` in pubspec's version).
  bool isUpdateRequired(int build) => build < minSupportedBuild;

  @override
  List<Object?> get props => [minSupportedBuild, latestBuild, updateUrl, paywallEnabled, trialDays];
}
