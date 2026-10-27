import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../domain/entities/access.dart';
import '../../domain/entities/app_config.dart';
import '../../domain/repositories/i_access_repository.dart';
import '../datasources/local/prefs_source.dart';
import '../models/access_model.dart';
import '../models/app_config_model.dart';

class AccessRepository implements IAccessRepository {
  AccessRepository({required this.client, required this.prefs, this.timeout = const Duration(seconds: 4)});

  final SupabaseClient client;
  final PrefsSource    prefs;
  /// How long to wait for the server before falling back to the saved copy.
  final Duration       timeout;

  @override
  Future<AppConfig> getConfig() async {
    try {
      final json = await client.rpc('get_app_config').timeout(timeout) as Map<String, dynamic>;
      await prefs.setAppConfigCache(jsonEncode(json));
      return AppConfigModel.fromJson(json);
    } catch (e) {
      debugPrint('Could not load app config: $e');
      return _cachedConfig();
    }
  }

  AppConfig _cachedConfig() {
    final raw = prefs.appConfigCache;
    if (raw == null) return const AppConfig.open();
    try {
      return AppConfigModel.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return const AppConfig.open();
    }
  }

  @override
  Future<Access> getAccess(String coupleId) async {
    try {
      final json = await client.rpc('get_access', params: {'p_couple': coupleId}).timeout(timeout)
          as Map<String, dynamic>;
      return AccessModel.fromJson(json);
    } catch (e) {
      debugPrint('Could not load access: $e');
      return const Access.open();
    }
  }
}
