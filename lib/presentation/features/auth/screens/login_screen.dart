import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/particle_field.dart';
import '../bloc/auth_bloc.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) {
          final route = state.user.coupleId != null ? RouteNames.home : RouteNames.pairInvite;
          context.go(route);
        } else if (state is AuthError) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: Stack(
          children: [
            const ParticleField(count: 20),
            SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 80),
                    GradientText('USYNC', gradient: AppGradients.gradientText2, style: AppTextStyles.logoSmall),
                    const SizedBox(height: 14),
                    Text('Welcome back', style: AppTextStyles.h2),
                    const SizedBox(height: 8),
                    Text('Your partner is waiting for you', style: AppTextStyles.bodyMuted),
                    const SizedBox(height: 48),
                    GlassInput(label: 'Email', hint: 'your@email.com', prefixIcon: '✉️', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
                    const SizedBox(height: 14),
                    GlassInput(label: 'Password', hint: '••••••••', prefixIcon: '🔒', obscure: true, controller: _passwordCtrl),
                    const SizedBox(height: 28),
                    BlocBuilder<AuthBloc, AuthState>(
                      builder: (context, state) => GlowButton(
                        label: 'Continue',
                        isLoading: state is AuthLoading,
                        onTap: () => context.read<AuthBloc>().add(SignInRequested(
                          email:    _emailCtrl.text.trim(),
                          password: _passwordCtrl.text,
                        )),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {},
                        child: const Text('Forgot password?', style: AppTextStyles.link),
                      ),
                    ),
                    Divider(color: AppColors.glassBorder, height: 40),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('New here? ', style: AppTextStyles.bodyMuted.copyWith(fontSize: 14)),
                        TextButton(
                          onPressed: () => context.go(RouteNames.register),
                          child: const Text('Create account', style: AppTextStyles.link),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
