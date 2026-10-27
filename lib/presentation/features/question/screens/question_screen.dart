import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../domain/repositories/i_auth_repository.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../bloc/question_bloc.dart';
import '../../../../core/utils/app_snack_bar.dart';

class QuestionScreen extends StatelessWidget {
  const QuestionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GetIt.I<QuestionBloc>(),
      child: BlocListener<QuestionBloc, QuestionBlocState>(
        listener: (context, state) {
          if (state is QuestionReady && state.error != null) {
            ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.error!)));
          }
        },
        child: const _QuestionBody(),
      ),
    );
  }
}

class _QuestionBody extends StatefulWidget {
  const _QuestionBody();
  @override
  State<_QuestionBody> createState() => _QuestionBodyState();
}

class _QuestionBodyState extends State<_QuestionBody> {
  final _controller = TextEditingController();
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _init();
    // While waiting for the partner, look for their answer every so often.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) context.read<QuestionBloc>().add(QuestionRefreshed());
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    final user = await GetIt.I<IAuthRepository>().getCurrentUser();
    if (user?.coupleId == null || !mounted) return;
    context.read<QuestionBloc>().add(QuestionOpened(coupleId: user!.coupleId!, userId: uid));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 16, 28, 0),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Question of the day', style: AppTextStyles.h2.copyWith(fontSize: 22)),
                      Text('Answers are shown once you both reply', style: AppTextStyles.label),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<QuestionBloc, QuestionBlocState>(
                builder: (context, state) => switch (state) {
                  QuestionLoading()      => const Center(child: CircularProgressIndicator()),
                  QuestionLoadFailed(:final message) => Center(child: Text(message, style: AppTextStyles.bodyMuted)),
                  QuestionReady()        => _content(context, state),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context, QuestionReady s) {
    final a = s.answers;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(s.question.text, style: AppTextStyles.h2),
          const SizedBox(height: 24),
          if (!a.iAnswered) ...[
            GlassInput(hint: 'Your answer…', controller: _controller, maxLength: 500),
            const SizedBox(height: 8),
            Text(
              a.partnerAnswered ? 'Your partner has answered. Reply to see theirs.' : 'Your partner has not answered yet.',
              style: AppTextStyles.bodyMuted,
            ),
            const SizedBox(height: 20),
            GlowButton(
              label: s.isSending ? 'Sending…' : 'Send answer',
              onTap: s.isSending ? null : () => context.read<QuestionBloc>().add(QuestionAnswered(_controller.text)),
            ),
          ] else ...[
            _AnswerCard(title: 'You', text: a.myAnswer!),
            const SizedBox(height: 14),
            if (a.revealed)
              _AnswerCard(title: 'Your partner', text: a.partnerAnswer!)
            else
              Text('Waiting for your partner to answer…', style: AppTextStyles.bodyMuted),
          ],
        ],
      ),
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({required this.title, required this.text});
  final String title, text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.bg2,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.label),
          const SizedBox(height: 6),
          Text(text, style: AppTextStyles.body),
        ],
      ),
    );
  }
}
