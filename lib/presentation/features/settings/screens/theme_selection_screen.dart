import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/theme/themes/lavender_dream.dart';
import '../../../../core/theme/themes/midnight_purple.dart';
import '../../../../core/theme/themes/neon_pink.dart';
import '../../../../core/theme/themes/ocean_blue.dart';
import '../../../../core/theme/themes/sunset_glow.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/theme_bloc.dart';

class _ThemeEntry {
  const _ThemeEntry(this.id, this.name, this.swatches, this.gradient);
  final String         id;
  final String         name;
  final List<Color>    swatches;
  final LinearGradient gradient;
}

class ThemeSelectionScreen extends StatelessWidget {
  const ThemeSelectionScreen({super.key});

  static final _themes = [
    _ThemeEntry(MidnightPurpleTheme.id, MidnightPurpleTheme.name, MidnightPurpleTheme.swatches, MidnightPurpleTheme.cardGradient),
    _ThemeEntry(NeonPinkTheme.id,       NeonPinkTheme.name,       NeonPinkTheme.swatches,       NeonPinkTheme.cardGradient),
    _ThemeEntry(OceanBlueTheme.id,      OceanBlueTheme.name,      OceanBlueTheme.swatches,      OceanBlueTheme.cardGradient),
    _ThemeEntry(LavenderDreamTheme.id,  LavenderDreamTheme.name,  LavenderDreamTheme.swatches,  LavenderDreamTheme.cardGradient),
    _ThemeEntry(SunsetGlowTheme.id,     SunsetGlowTheme.name,     SunsetGlowTheme.swatches,     SunsetGlowTheme.cardGradient),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Themes', style: AppTextStyles.h2.copyWith(fontSize: 24)),
                      Text('Choose your emotional palette', style: AppTextStyles.label),
                    ],
                  ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ThemeBloc, ThemeState>(
                builder: (context, themeState) {
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 40),
                    children: _themes.map((entry) {
                      final selected = themeState.activeThemeId == entry.id;
                      return GestureDetector(
                        onTap: () => context.read<ThemeBloc>().add(ThemeChanged(entry.id)),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(bottom: 13),
                          height: 110,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(
                              color: selected ? Colors.white.withValues(alpha: 0.6) : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24),
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: Opacity(
                                    opacity: 0.65,
                                    child: Container(decoration: BoxDecoration(gradient: entry.gradient)),
                                  ),
                                ),
                                Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.25))),
                                Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(entry.name, style: AppTextStyles.h4.copyWith(fontSize: 18))),
                                          Container(
                                            width: 28, height: 28,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: selected ? Colors.white : Colors.transparent,
                                              border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                                            ),
                                            child: selected
                                                ? const Center(child: Text('✓', style: TextStyle(color: Color(0xFFFF2D78), fontSize: 14, fontWeight: FontWeight.w700)))
                                                : null,
                                          ),
                                        ],
                                      ),
                                      Row(
                                        children: entry.swatches.map((c) => Container(
                                          width: 24, height: 24,
                                          margin: const EdgeInsets.only(right: 7),
                                          decoration: BoxDecoration(
                                            color: c,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white.withValues(alpha: 0.3), width: 1.5),
                                          ),
                                        )).toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
