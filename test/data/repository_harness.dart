import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:usync/core/services/outbox_service.dart';
import 'package:usync/data/datasources/local/session_cache.dart';
import 'package:usync/domain/entities/notification_item.dart';
import 'package:usync/domain/repositories/i_notification_repository.dart';

/// A request the repository sent, as the fake server saw it.
class Recorded {
  Recorded(this.request, this.body, [this.bodyBytes = const []]);
  final http.BaseRequest request;
  final String body;
  /// The raw request body (an upload is binary, so [body] is not reliable for it).
  final List<int> bodyBytes;

  String get method => request.method;
  String get path => request.url.path;
  Map<String, String> get query => request.url.queryParameters;
  Object? get json => body.isEmpty ? null : jsonDecode(body);
}

/// A real [SupabaseClient] whose HTTP layer is a stub, so repositories run their
/// real query-building and parsing without a network.
class FakeBackend {
  FakeBackend() {
    client = SupabaseClient(
      'http://fake.supabase.test',
      'anon-key',
      httpClient: MockClient((request) async {
        // An upload is binary and not valid text; tests read it from bodyBytes instead.
        String body;
        try {
          body = request.body;
        } on FormatException {
          body = '';
        }
        final recorded = Recorded(request, body, request.bodyBytes);
        requests.add(recorded);
        final reply = _handler(recorded);
        // The Postgrest parser reads the originating request off the response.
        return http.Response.bytes(reply.bodyBytes, reply.statusCode, request: request, headers: reply.headers);
      }),
    );
  }

  late final SupabaseClient client;
  final requests = <Recorded>[];
  http.Response Function(Recorded) _handler = (_) => http.Response('[]', 200);

  void respond(http.Response Function(Recorded) handler) => _handler = handler;

  static http.Response ok(Object? body, {int status = 200}) =>
      http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

  static http.Response error(String code, String message, {int status = 409}) =>
      ok({'code': code, 'message': message, 'details': null, 'hint': null}, status: status);

  Future<void> dispose() => client.dispose();
}

class FakeConnectivity implements Connectivity {
  FakeConnectivity([this.current = const [ConnectivityResult.wifi]]);
  List<ConnectivityResult> current;
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;
}

/// Notification repository that records what would have been sent.
class RecordingNotifications implements INotificationRepository {
  final sent = <({String coupleId, String fromUserId, NotifType type, String body, String? detail})>[];

  @override
  Future<void> notifyPartner({
    required String coupleId,
    required String fromUserId,
    required NotifType type,
    required String Function(String senderName) body,
    String Function(String senderName)? detail,
  }) async =>
      sent.add((coupleId: coupleId, fromUserId: fromUserId, type: type, body: body('Alex'), detail: detail?.call('Alex')));

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

/// Hive-backed pieces the repositories need, created in a throwaway directory.
class LocalStorage {
  late Directory dir;
  late Box<dynamic> cacheBox;
  late Box<dynamic> outboxBox;
  late SessionCache sessionCache;
  late OutboxService outbox;
  final connectivity = FakeConnectivity();

  Future<void> setUp() async {
    dir = await Directory.systemTemp.createTemp('repo_test');
    Hive.init(dir.path);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    cacheBox = await Hive.openBox<dynamic>('cache_$stamp');
    outboxBox = await Hive.openBox<dynamic>('outbox_$stamp');
    sessionCache = SessionCache(box: cacheBox);
    outbox = OutboxService(
      box: outboxBox,
      connectivity: connectivity,
      retryEvery: const Duration(hours: 1),
    );
    await outbox.init();
  }

  Future<void> tearDown() async {
    await outbox.flush();
    outbox.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  }
}
