import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:home_widget/home_widget.dart';

import '../../../../core/services/home_widget_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../features/auth/bloc/auth_bloc.dart';
import '../../../shared/animations/breathe_animation.dart';
import '../../../shared/widgets/glass_card.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/heartbeat_visualizer.dart';
import '../../../shared/widgets/live_indicator.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/widgets_bloc.dart';
import '../../../../core/utils/app_snack_bar.dart';

class WidgetsScreen extends StatelessWidget {
  const WidgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final coupleId = auth is Authenticated ? (auth.user.coupleId ?? '') : '';
    return BlocProvider(
      create: (_) => GetIt.I<WidgetsBloc>()..add(WidgetsLoaded(coupleId)),
      child: const _WidgetsBody(),
    );
  }
}

class _WidgetsBody extends StatelessWidget {
  const _WidgetsBody();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 14),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Widgets', style: AppTextStyles.h2),
                        Text('Add to your home screen', style: AppTextStyles.label),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                children: [
                  const _DoodleWidgetCard(),
                  const SizedBox(height: 13),
                  GridView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 13,
                      crossAxisSpacing: 13,
                      // Grows with the text size so a larger font cannot overflow the cards.
                      mainAxisExtent:
                          240 * MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 2.0),
                    ),
                    children: [
                      // Heartbeat
                      _WidgetCard(
                        icon: '💓',
                        name: 'Heartbeat',
                        desc: 'Coming soon',
                        glowColor: AppColors.pink,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: HeartbeatVisualizer(width: 120, height: 30),
                        ),
                      ),

                      // Mood
                      _WidgetCard(
                        icon: '💭',
                        name: 'Mood',
                        desc: 'Coming soon',
                        glowColor: AppColors.purple,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: GlassCard(
                            borderRadius: 12,
                            padding: const EdgeInsets.symmetric(
                                vertical: 8, horizontal: 16),
                            child: Column(
                              children: [
                                const Text('😊',
                                    style: TextStyle(fontSize: 22)),
                                Text('Happy', style: AppTextStyles.labelSmall),
                              ],
                            ),
                          ),
                        ),
                      ),

                      // Presence
                      _WidgetCard(
                        icon: '🌐',
                        name: 'Presence',
                        desc: 'Coming soon',
                        glowColor: AppColors.pinkLight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: LiveIndicator(
                              label: 'Active 2m ago', color: AppColors.cyan),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  // Streak (full width)
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.glass,
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: AppColors.glassBorder),
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('🔥',
                                  style: TextStyle(fontSize: 32)),
                              const SizedBox(height: 6),
                              Text('Connection Streak',
                                  style: AppTextStyles.label.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14)),
                              Text("You've been in sync every day",
                                  style: AppTextStyles.labelSmall),
                            ],
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            BlocBuilder<WidgetsBloc, WidgetsBlocState>(
                              builder: (context, state) {
                                final streak = state is WidgetsReady
                                    ? state.couple.streakDays.toString()
                                    : '—';
                                return GradientText(streak,
                                    gradient: AppGradients.gradientText2,
                                    style: const TextStyle(
                                        fontSize: 40,
                                        fontWeight: FontWeight.w800));
                              },
                            ),
                            Text('days', style: AppTextStyles.label),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard(
      {required this.icon,
      required this.name,
      required this.desc,
      required this.glowColor,
      this.child});
  final String icon;
  final String name, desc;
  final Color glowColor;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return BreatheAnimation(
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Glow blob — positioned relative to the card, clipped by Stack
          Positioned(
            top: -20,
            right: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    glowColor.withValues(alpha: 0.4),
                    Colors.transparent
                  ],
                ),
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.glassBorder),
            ),
            padding: const EdgeInsets.all(14),
            child: ClipRect(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(icon, style: const TextStyle(fontSize: 26)),
                  const SizedBox(height: 6),
                  Text(name,
                      style: AppTextStyles.label.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 12)),
                  const SizedBox(height: 3),
                  Text(desc,
                      style: AppTextStyles.labelSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (child != null) child!,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The one widget that is live: shows the shared canvas as it is on the home screen.
class _DoodleWidgetCard extends StatefulWidget {
  const _DoodleWidgetCard();
  @override
  State<_DoodleWidgetCard> createState() => _DoodleWidgetCardState();
}

class _DoodleWidgetCardState extends State<_DoodleWidgetCard>
    with WidgetsBindingObserver {
  File? _image;
  String? _caption;
  bool _loading = true;
  bool _onHomeScreen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from the launcher after pinning (or removing) the widget.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkInstalled();
  }

  Future<void> _checkInstalled() async {
    if (!Platform.isAndroid) return;
    var installed = false;
    try {
      final widgets = await HomeWidget.getInstalledWidgets();
      installed = widgets.any((w) =>
          (w.androidClassName ?? '').endsWith('DoodleWidgetProvider'));
    } catch (_) {
      // Not available here: keep offering the button.
    }
    if (mounted) setState(() => _onHomeScreen = installed);
  }

  Future<void> _load() async {
    String? path, caption;
    try {
      await HomeWidgetService.syncFromServer();
      path = await HomeWidget.getWidgetData<String>('doodle_path');
      caption = await HomeWidget.getWidgetData<String>('doodle_updated');
    } catch (_) {
      // Widget storage unavailable (e.g. unsupported platform): show the empty state.
    }
    if (!mounted) return;
    // A new file object every time, so Image.file does not reuse its cached picture.
    imageCache.clear();
    _checkInstalled();
    setState(() {
      _image = path == null ? null : File(path);
      _caption = caption;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final messenger = ScaffoldMessenger.of(context);
    String? hint;
    if (!Platform.isAndroid) {
      hint = 'Home-screen widgets are available on Android for now.';
    } else if (await HomeWidget.isRequestPinWidgetSupported() != true) {
      hint = 'Long-press your home screen, tap Widgets, and pick Usync.';
    } else {
      await HomeWidget.requestPinWidget(
          qualifiedAndroidName: HomeWidgetService.androidProvider);
    }
    if (hint != null) messenger.showSnackBar(appSnackBar(content: Text(hint)));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.cyan.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('✏️', style: TextStyle(fontSize: 26)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Live Doodle',
                        style: AppTextStyles.label.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    Text('What you two draw shows on your home screen',
                        style: AppTextStyles.labelSmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          AspectRatio(
            aspectRatio: 1.6,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.bg1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.glassBorder),
              ),
              clipBehavior: Clip.antiAlias,
              alignment: Alignment.center,
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : _image == null
                      ? Text('No doodle yet — draw on the canvas',
                          style: AppTextStyles.labelSmall)
                      : Image.file(_image!, fit: BoxFit.contain),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 8,
            children: [
              Text(_onHomeScreen ? 'On your home screen ✓' : (_caption ?? ''),
                  style: AppTextStyles.labelSmall),
              FilledButton.icon(
                onPressed: _add,
                icon: Icon(_onHomeScreen ? Icons.add : Icons.add_to_home_screen, size: 18),
                label: Text(_onHomeScreen ? 'Add another' : 'Add to home screen'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
