import 'dart:math';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glass_input.dart';
import '../../../shared/widgets/glow_button.dart';

/// Shows a new recovery phrase, then asks for three of its words so we know it was written down.
/// Pops `true` once the quiz is passed.
class RecoveryPhraseSheet extends StatefulWidget {
  const RecoveryPhraseSheet({super.key, required this.phrase, Random? random}) : _random = random;

  final String  phrase;
  final Random? _random;

  @override
  State<RecoveryPhraseSheet> createState() => _RecoveryPhraseSheetState();
}

class _RecoveryPhraseSheetState extends State<RecoveryPhraseSheet> {
  late final List<String> _words = widget.phrase.split(' ');
  late final List<int> _asked = _pick();
  final _answers = List.generate(3, (_) => TextEditingController());
  bool _quiz = false;
  String? _error;

  List<int> _pick() {
    final random = widget._random ?? Random.secure();
    final all = List<int>.generate(_words.length, (i) => i)..shuffle(random);
    return (all.take(3).toList()..sort());
  }

  @override
  void dispose() {
    for (final c in _answers) {
      c.dispose();
    }
    super.dispose();
  }

  void _check() {
    final ok = [for (var i = 0; i < 3; i++) _answers[i].text.trim().toLowerCase() == _words[_asked[i]]].every((v) => v);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() => _error = 'Those words do not match. Check what you wrote down.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _quiz ? _quizChildren() : _showChildren(),
        ),
      ),
    );
  }

  List<Widget> _showChildren() => [
        Text('Your recovery phrase', style: AppTextStyles.h3.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text(
          'Write these 12 words down, in order, and keep them somewhere safe. They are the only way to get your keys back on a new phone. '
          'Nobody can recover them for you, not even the developer, and anyone who has them can restore your keys.',
          style: AppTextStyles.bodyMuted,
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < _words.length; i++)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.glass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.glassBorder),
                ),
                child: Text('${i + 1}. ${_words[i]}', style: AppTextStyles.body.copyWith(fontSize: 14)),
              ),
          ],
        ),
        const SizedBox(height: 18),
        GlowButton(label: 'I have written it down', onTap: () => setState(() => _quiz = true)),
      ];

  List<Widget> _quizChildren() => [
        Text('Check your phrase', style: AppTextStyles.h3.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text('Type the words you wrote down at these positions.', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 14),
        for (var i = 0; i < 3; i++) ...[
          GlassInput(label: 'WORD ${_asked[i] + 1}', hint: 'word', controller: _answers[i]),
          const SizedBox(height: 10),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppTextStyles.labelSmall.copyWith(color: AppColors.error))),
        GlowButton(label: 'Confirm', onTap: _check),
        Center(child: TextButton(onPressed: () => setState(() => _quiz = false), child: Text('Show the words again', style: AppTextStyles.link))),
      ];
}
