import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_names.dart';
import '../../../../core/constants/app_constants.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_gradients.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/gradient_text.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/auth_bloc.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});
  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _usernameCtrl = TextEditingController();
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();
  String _selectedAvatar = '🦋';

  static const _avatars = AppConstants.avatarEmojis;

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is Authenticated) context.go(RouteNames.pairInvite);
        if (state is AuthError) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(state.message)));
      },
      child: Scaffold(
        backgroundColor: AppColors.bg1,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 24),
                Row(
                  children: [
                    NeonBackButton(onTap: () => context.go(RouteNames.login)),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GradientText('USYNC', gradient: AppGradients.gradientText2,
                            style: AppTextStyles.logoSmall.copyWith(fontSize: 20, letterSpacing: 3)),
                        Text('Create your space', style: AppTextStyles.h3.copyWith(fontSize: 22)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Center(
                  child: Text('Choose your avatar', style: AppTextStyles.labelCaps),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Wrap(
                    spacing: 10, runSpacing: 10,
                    alignment: WrapAlignment.center,
                    children: _avatars.map((av) {
                      final selected = av == _selectedAvatar;
                      return GestureDetector(
                        onTap: () => setState(() => _selectedAvatar = av),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 54, height: 54,
                          decoration: BoxDecoration(
                            shape:     BoxShape.circle,
                            color:     AppColors.glass,
                            border:    Border.all(
                              color: selected ? AppColors.pink : AppColors.glassBorder,
                              width: 2,
                            ),
                            boxShadow: selected
                                ? [BoxShadow(color: AppColors.pink.withValues(alpha: 0.5), blurRadius: 16)]
                                : null,
                          ),
                          child: Center(child: Text(av, style: const TextStyle(fontSize: 26))),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                GlassInput(label: 'Username', hint: 'your name', prefixIcon: '👤', controller: _usernameCtrl),
                const SizedBox(height: 14),
                GlassInput(label: 'Email', hint: 'your@email.com', prefixIcon: '✉️', controller: _emailCtrl, keyboardType: TextInputType.emailAddress),
                const SizedBox(height: 14),
                GlassInput(label: 'Password', hint: '••••••••', prefixIcon: '🔒', obscure: true, controller: _passwordCtrl),
                const SizedBox(height: 28),
                BlocBuilder<AuthBloc, AuthState>(
                  builder: (context, state) => GlowButton(
                    label: 'Create Account',
                    isLoading: state is AuthLoading,
                    onTap: () => context.read<AuthBloc>().add(SignUpRequested(
                      email:       _emailCtrl.text.trim(),
                      password:    _passwordCtrl.text,
                      username:    _usernameCtrl.text.trim(),
                      avatarEmoji: _selectedAvatar,
                    )),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Already paired? ', style: AppTextStyles.bodyMuted.copyWith(fontSize: 14)),
                    TextButton(
                      onPressed: () => context.go(RouteNames.login),
                      child: const Text('Sign in', style: AppTextStyles.link),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
