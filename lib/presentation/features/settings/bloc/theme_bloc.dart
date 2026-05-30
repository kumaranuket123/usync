import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/theme/themes/midnight_purple.dart';
import '../../../../data/datasources/local/prefs_source.dart';

part 'theme_event.dart';
part 'theme_state.dart';

class ThemeBloc extends Bloc<ThemeEvent, ThemeState> {
  ThemeBloc({required this.prefsSource})
      : super(ThemeState(
          activeThemeId: MidnightPurpleTheme.id,
          themeData: AppTheme.build(MidnightPurpleTheme.tokens),
        )) {
    on<ThemeLoaded>(_onLoaded);
    on<ThemeChanged>(_onChanged);
  }

  final PrefsSource prefsSource;

  void _onLoaded(ThemeLoaded _, Emitter<ThemeState> emit) {
    final id     = prefsSource.themeId;
    final tokens = AppTheme.tokensFor(id);
    emit(ThemeState(activeThemeId: id, themeData: AppTheme.build(tokens)));
  }

  Future<void> _onChanged(ThemeChanged e, Emitter<ThemeState> emit) async {
    final tokens = AppTheme.tokensFor(e.id);
    await prefsSource.setThemeId(e.id);
    emit(ThemeState(activeThemeId: e.id, themeData: AppTheme.build(tokens)));
  }
}
