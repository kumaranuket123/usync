import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'core/constants/route_names.dart';
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
                    AppRouter.router.go(RouteNames.login);
                  }
                },
                child: child!,
              ), const OfflineBanner()]));
            },
          );
        },
      ),
    );
  }
}
