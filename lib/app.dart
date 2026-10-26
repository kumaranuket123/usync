import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'core/constants/route_names.dart';
import 'core/theme/app_colors.dart';
import 'core/router/app_router.dart';
import 'core/services/push_notification_service.dart';
import 'presentation/features/auth/bloc/auth_bloc.dart';
import 'presentation/features/settings/bloc/settings_bloc.dart';
import 'presentation/features/settings/bloc/theme_bloc.dart';
import 'presentation/shared/widgets/app_lock_gate.dart';
import 'presentation/shared/widgets/offline_banner.dart';

class UsyncApp extends StatelessWidget {
  const UsyncApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => GetIt.I<AuthBloc>()..add(const AuthStateChecked()),
        ),
        BlocProvider(
          create: (_) => GetIt.I<SettingsBloc>()..add(const SettingsLoaded()),
        ),
        BlocProvider(
          create: (_) => GetIt.I<ThemeBloc>()..add(const ThemeLoaded()),
        ),
      ],
      child: BlocBuilder<ThemeBloc, ThemeState>(
        builder: (context, themeState) {
          return MaterialApp.router(
            title: 'Usync',
            debugShowCheckedModeBanner: false,
            theme: themeState.themeData,
            scaffoldMessengerKey: rootMessengerKey,
            routerConfig: AppRouter.router,
            builder: (context, child) {
              return AppLockGate(child: Stack(fit: StackFit.expand, children: [BlocListener<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is Unauthenticated) {
                    // Settings held the previous account's choices (alert sounds,
                    // the push switch): start over for whoever signs in next.
                    context.read<SettingsBloc>().add(const SettingsLoaded());
                    AppRouter.router.go(RouteNames.login);
                  }
                },
                child: child!,
              ), const OfflineBanner(), const _SigningOutOverlay()]));
            },
          );
        },
      ),
    );
  }
}

/// Covers the app with a spinner while signing out, so the wait is not mistaken for a freeze.
class _SigningOutOverlay extends StatelessWidget {
  const _SigningOutOverlay();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthBloc, AuthState>(
      buildWhen: (a, b) => a is SigningOut || b is SigningOut,
      builder: (context, state) {
        if (state is! SigningOut) return const SizedBox.shrink();
        return Material(
          color: AppColors.bg1.withValues(alpha: 0.85),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: AppColors.pink),
                const SizedBox(height: 18),
                Text(state.deletingAccount ? 'Deleting your account…' : 'Signing out…',
                    style: const TextStyle(color: AppColors.textPrimary, fontSize: 15)),
              ],
            ),
          ),
        );
      },
    );
  }
}
