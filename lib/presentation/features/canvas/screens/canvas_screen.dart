import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
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

  @override
  void initState() {
    super.initState();
    _mount();
  }

  Future<void> _mount() async {
    final uid  = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final user = await GetIt.I<IAuthRepository>().getCurrentUser();
    if (user?.coupleId == null || !mounted) return;
    final couple    = await GetIt.I<ICoupleRepository>().getCouple(user!.coupleId!);
    final partnerId = couple.partnerIdFor(uid);
    final partner   = await GetIt.I<IAuthRepository>().getUserById(partnerId);
    if (!mounted) return;
    setState(() => _partnerName = partner?.username ?? 'Partner');
    context.read<CanvasBloc>().add(CanvasMounted(
      coupleId: couple.id,
      userId:   uid,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: BlocBuilder<CanvasBloc, CanvasState>(
        builder: (context, state) {
          return Stack(
            children: [
              // Drawing area
              Positioned.fill(
                child: GestureDetector(
                  onPanStart: (d) => context.read<CanvasBloc>().add(StrokeStarted(d.localPosition)),
                  onPanUpdate:(d) => context.read<CanvasBloc>().add(StrokeUpdated(d.localPosition)),
                  onPanEnd:   (_) => context.read<CanvasBloc>().add(StrokeEnded()),
                  child: CustomPaint(
                    painter: CanvasStrokePainter(
                      strokes:      state.strokes + state.remoteStrokes,
                      activeStroke: state.activeStroke,
                    ),
                    child: Container(color: Colors.transparent),
                  ),
                ),
              ),

              // Header
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
                          LiveIndicator(label: '$_partnerName is here', color: AppColors.cyan),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Toolbar
              Positioned(
                bottom: 100,
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
                        _ToolBtn(state.isSaving ? '⏳' : '💾', onTap: () {}),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
