import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/datasources/local/flutter_secure_key_store.dart';
import '../../data/models/canvas_stroke_codec.dart';
import '../../domain/entities/canvas_stroke.dart';
import '../../presentation/shared/painters/canvas_stroke_painter.dart';
import '../constants/supabase_config.dart';
import '../crypto/content_cipher.dart';
import '../crypto/key_service.dart';

/// Keeps the Android home-screen "Live Doodle" widget in step with the shared
/// canvas: the drawing is rendered to a PNG that the native widget displays.
class HomeWidgetService with WidgetsBindingObserver {
  HomeWidgetService._();

  static const androidProvider = 'com.crn.usync.DoodleWidgetProvider';
  static const _size   = 600.0;
  static const _margin = 36.0;
  static const _minGap = Duration(seconds: 30);

  DateTime? _lastSync;

  /// Refreshes on launch and whenever the app returns to the foreground.
  static void init() {
    final service = HomeWidgetService._();
    WidgetsBinding.instance.addObserver(service);
    service._sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _sync();
  }

  Future<void> _sync() async {
    final last = _lastSync;
    if (last != null && DateTime.now().difference(last) < _minGap) return;
    _lastSync = DateTime.now();
    await syncFromServer();
  }

  /// Loads the saved canvas and redraws the widget. Also runs in the push
  /// background isolate, where GetIt is not set up, so it builds what it needs.
  static Future<void> syncFromServer() async {
    try {
      try {
        Supabase.instance;
      } catch (_) {
        await Supabase.initialize(url: SupabaseConfig.url, publishableKey: SupabaseConfig.publishableKey);
      }
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;

      final profile = await client.from('profiles').select('couple_id').eq('id', uid).maybeSingle();
      final coupleId = profile?['couple_id'] as String?;
      if (coupleId == null) return await refresh(const []);

      final rows = await client.from('canvas_strokes').select().eq('couple_id', coupleId).order('created_at');
      // In this background task there is no service registry: read the keys straight from secure storage.
      final codec = CanvasStrokeCodec(ContentCipher(
        keysFor: (userId) => KeyService(store: const FlutterSecureKeyStore(), namespace: userId),
        currentUserId: () => client.auth.currentUser?.id,
      ));
      final strokes = <CanvasStroke>[
        for (final r in rows) ...[if (await codec.openRow(r) case final stroke?) stroke],
      ];
      // Strokes this phone cannot read yet (no key): keep the last picture instead of blanking the widget.
      if (rows.isNotEmpty && strokes.isEmpty) return;
      await refresh(strokes);
    } catch (_) {
      // Best effort: the widget keeps showing the last picture.
    }
  }

  /// Draws [strokes] (everyone's, in drawing order) and updates the widget.
  static Future<void> refresh(List<CanvasStroke> strokes) async {
    try {
      final file = File('${(await getApplicationSupportDirectory()).path}/doodle_widget.png');
      final png = strokes.isEmpty ? null : await _render(strokes);
      if (png == null) {
        if (file.existsSync()) file.deleteSync();
        await HomeWidget.saveWidgetData<String>('doodle_path', null);
        await HomeWidget.saveWidgetData<String>('doodle_updated', null);
      } else {
        await file.writeAsBytes(png, flush: true);
        final newest = strokes.map((s) => s.timestamp).reduce((a, b) => a.isAfter(b) ? a : b);
        await HomeWidget.saveWidgetData<String>('doodle_path', file.path);
        await HomeWidget.saveWidgetData<String>(
            'doodle_updated', 'Updated ${DateFormat('d MMM, h:mm a').format(newest)}');
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: androidProvider);
    } catch (_) {}
  }

  /// Strokes are in the drawer's screen pixels, which differ per phone, so the
  /// drawing is framed by its own bounds rather than by a canvas size.
  static Future<Uint8List?> _render(List<CanvasStroke> strokes) async {
    Rect? bounds;
    for (final s in strokes) {
      if (s.points.isEmpty) continue;
      final r = Rect.fromPoints(
        s.points.reduce((a, b) => Offset(a.dx < b.dx ? a.dx : b.dx, a.dy < b.dy ? a.dy : b.dy)),
        s.points.reduce((a, b) => Offset(a.dx > b.dx ? a.dx : b.dx, a.dy > b.dy ? a.dy : b.dy)),
      ).inflate(s.width);
      bounds = bounds == null ? r : bounds.expandToInclude(r);
    }
    if (bounds == null || bounds.isEmpty) return null;

    final scale = (_size - 2 * _margin) / (bounds.width > bounds.height ? bounds.width : bounds.height);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, const Rect.fromLTWH(0, 0, _size, _size))
      ..translate(
        (_size - bounds.width * scale) / 2 - bounds.left * scale,
        (_size - bounds.height * scale) / 2 - bounds.top * scale,
      )
      ..scale(scale);
    CanvasStrokePainter(strokes: strokes).paint(canvas, Size(bounds.right, bounds.bottom));

    final image = await recorder.endRecording().toImage(_size.toInt(), _size.toInt());
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data?.buffer.asUint8List();
  }
}
