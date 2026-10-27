import '../../domain/entities/access.dart';

class AccessModel extends Access {
  const AccessModel({super.status, super.until, super.paywallEnabled});

  /// The JSON returned by the `get_access` RPC.
  factory AccessModel.fromJson(Map<String, dynamic> json) => AccessModel(
    status:         AccessStatus.fromString(json['state'] as String?),
    until:          json['until'] == null ? null : DateTime.parse(json['until'] as String).toLocal(),
    paywallEnabled: json['paywall_enabled'] as bool? ?? false,
  );
}
