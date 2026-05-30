import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'core/constants/route_names.dart';
import 'core/router/app_router.dart';
import 'presentation/features/auth/bloc/auth_bloc.dart';
import 'presentation/features/settings/bloc/settings_bloc.dart';
import 'presentation/features/settings/bloc/theme_bloc.dart';

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
            routerConfig: AppRouter.router,
            builder: (context, child) {
              return BlocListener<AuthBloc, AuthState>(
                listener: (context, state) {
                  if (state is Unauthenticated) {
                    AppRouter.router.go(RouteNames.login);
                  }
                },
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}
