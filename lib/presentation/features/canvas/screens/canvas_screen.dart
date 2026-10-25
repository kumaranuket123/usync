import 'dart:ui' as ui;

import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../../domain/repositories/i_couple_repository.dart';
import '../../../shared/painters/canvas_stroke_painter.dart';
import '../../../shared/widgets/live_indicator.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/canvas_bloc.dart';

class CanvasScreen extends StatelessWidget {
  const CanvasScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<CanvasBloc>(),
      child: const _CanvasBody(),
    );
  }
}

class _CanvasBody extends StatefulWidget {
  const _CanvasBody();
  @override
  State<_CanvasBody> createState() => _CanvasBodyState();
}

class _CanvasBodyState extends State<_CanvasBody> {
  static const _colors = [
    Color(0xFFFF6EC7), Color(0xFFC77DFF),
    Color(0xFF00D4FF), Colors.white, Color(0xFFFFD700),
  ];

  String _partnerName = '…';
  final _canvasKey = GlobalKey();
  /// Hides the header and toolbar so the whole screen is canvas.
  bool _showChrome = true;

  @override
  void initState() {
    super.initState();
    _mount();
  }

  Future<void> _mount() async {
    try {
      final uid  = Supabase.instance.client.auth.currentUser?.id;
      if (uid == null) return;
      final user = await GetIt.I<IAuthRepository>().getCurrentUser();
      if (user?.coupleId == null || !mounted) return;
      final couple  = await GetIt.I<ICoupleRepository>().getCouple(user!.coupleId!);
      final partner = await GetIt.I<IAuthRepository>().getUserById(couple.partnerIdFor(uid));
      if (!mounted) return;
      setState(() => _partnerName = partner?.username ?? 'Partner');
      context.read<CanvasBloc>().add(CanvasMounted(
        coupleId:      couple.id,
        userId:        uid,
        partnerUserId: couple.partnerIdFor(uid),
      ));
    } catch (err) {
      debugPrint('Canvas mount failed: $err');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Could not connect the shared canvas'),
        action: SnackBarAction(label: 'Retry', onPressed: _mount),
      ));
    }
  }

  /// Renders the drawing onto the app background and hands the PNG to the bloc,
  /// which stores it as a memory and notifies the partner.
  Future<void> _save() async {
    final bloc = context.read<CanvasBloc>();
    if (bloc.state.isSaving) return;
    if (bloc.state.committed.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draw something first')),
      );
      return;
    }
    final boundary = _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return;

    final drawing = await boundary.toImage(pixelRatio: 2);
    // The strokes are transparent where nothing is drawn; flatten onto the dark background.
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, drawing.width.toDouble(), drawing.height.toDouble()),
      Paint()..color = AppColors.bg1,
    );
    canvas.drawImage(drawing, Offset.zero, Paint());
    final flat = await recorder.endRecording().toImage(drawing.width, drawing.height);
    final data = await flat.toByteData(format: ui.ImageByteFormat.png);
    if (data == null || !mounted) return;

    bloc.add(MemorySaved(data.buffer.asUint8List()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: BlocListener<CanvasBloc, CanvasState>(
        listenWhen: (a, b) => a.isSaving && !b.isSaving,
        listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(state.saveFailed
              ? 'Could not save the doodle'
              : 'Saved to Memories — $_partnerName was notified ✏️'),
        )),
        child: BlocBuilder<CanvasBloc, CanvasState>(
        // The canvas below has its own builder; this one only drives the toolbar.
        buildWhen: (a, b) =>
            a.activeTool != b.activeTool ||
            a.activeColor != b.activeColor ||
            a.partnerHere != b.partnerHere ||
            a.isSaving != b.isSaving,
        builder: (context, state) {
          return Stack(
            children: [
              // Drawing area — repaints per point without rebuilding the toolbar.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (d) => context.read<CanvasBloc>().add(StrokeStarted(d.localPosition)),
                  onPanUpdate:(d) => context.read<CanvasBloc>().add(StrokeUpdated(d.localPosition)),
                  onPanEnd:   (_) => context.read<CanvasBloc>().add(StrokeEnded()),
                  onPanCancel: () => context.read<CanvasBloc>().add(StrokeEnded()),
                  child: RepaintBoundary(
                    key: _canvasKey,
                    child: BlocBuilder<CanvasBloc, CanvasState>(
                      buildWhen: (a, b) =>
                          !identical(a.committed, b.committed) ||
                          !identical(a.activeStroke, b.activeStroke),
                      builder: (context, drawing) => CustomPaint(
                        size: Size.infinite,
                        painter: CanvasStrokePainter(
                          strokes:      drawing.committed,
                          activeStroke: drawing.activeStroke,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Header
              if (_showChrome)
              Positioned(
                top: 0, left: 0, right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [AppColors.bg1.withValues(alpha: 0.95), Colors.transparent],
                    ),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                      child: Row(
                        children: [
                          NeonBackButton(),
                          const SizedBox(width: 14),
                          Text('Shared Canvas', style: AppTextStyles.h4),
                          const Spacer(),
                          LiveIndicator(
                            label: state.partnerHere ? '$_partnerName is here' : '$_partnerName is away',
                            color: AppColors.cyan,
                            isActive: state.partnerHere,
                          ),
                          const SizedBox(width: 10),
                          _ChromeButton(
                            icon: Icons.fullscreen,
                            tooltip: 'Full screen',
                            onTap: () => setState(() => _showChrome = false),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Brings the header and toolbar back from full screen.
              if (!_showChrome)
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 8,
                  right: 12,
                  child: _ChromeButton(
                    icon: Icons.fullscreen_exit,
                    tooltip: 'Show tools',
                    onTap: () => setState(() => _showChrome = true),
                  ),
                ),

              // Toolbar
              if (_showChrome)
              Positioned(
                bottom: MediaQuery.paddingOf(context).bottom + 16,
                left: 0, right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xE00A0A1F),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppColors.glassBorder),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 32)],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ToolBtn('✏️', active: state.activeTool == CanvasTool.pen,
                            onTap: () => context.read<CanvasBloc>().add(ToolChanged(CanvasTool.pen))),
                        _ToolBtn('🧹', active: state.activeTool == CanvasTool.eraser,
                            onTap: () => context.read<CanvasBloc>().add(ToolChanged(CanvasTool.eraser))),
                        const _Divider(),
                        ..._colors.map((c) => _ColorDot(
                          color: c,
                          selected: state.activeColor == c,
                          onTap: () => context.read<CanvasBloc>().add(ColorChanged(c)),
                        )),
                        const _Divider(),
                        _ToolBtn('🗑️', onTap: () => context.read<CanvasBloc>().add(CanvasCleared())),
                        _ToolBtn(state.isSaving ? '⏳' : '💾', onTap: _save),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
        ),
      ),
    );
  }
}

class _ChromeButton extends StatelessWidget {
  const _ChromeButton({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String   tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: AppColors.glass,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.glassBorder),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn(this.icon, {this.active = false, required this.onTap});
  final String icon;
  final bool   active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: active ? AppColors.pink.withValues(alpha: 0.2) : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: AppColors.glassBorder, margin: const EdgeInsets.symmetric(horizontal: 3));
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({required this.color, required this.selected, required this.onTap});
  final Color color;
  final bool  selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 22, height: 22,
        margin: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          color:  color,
          shape:  BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : Colors.transparent, width: 2),
        ),
        transform: selected ? (Matrix4.identity()..scaleByDouble(1.25, 1.25, 1.25, 1)) : Matrix4.identity(),
        transformAlignment: Alignment.center,
      ),
    );
  }
}
