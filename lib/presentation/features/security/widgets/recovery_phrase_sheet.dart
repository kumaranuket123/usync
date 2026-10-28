import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../shared/widgets/glow_button.dart';

/// Shows a new recovery phrase, then asks which word sits at three positions (tap the right one of four),
/// so we know the phrase was read and kept. No typing. Pops `true` once all three are right.
///
/// Besides writing it on paper, the person can copy it or send it to another app (a password manager, a
/// private note) as a second backup. [copy] and [share] are replaceable for tests.
class RecoveryPhraseSheet extends StatefulWidget {
  const RecoveryPhraseSheet({super.key, required this.phrase, Random? random, this.copy, this.share}) : _random = random;

  final String  phrase;
  final Random? _random;
  final Future<void> Function(String text)? copy;
  final Future<void> Function(String text)? share;

  /// How long a copied phrase may stay on the clipboard.
  static const clipboardLifetime = Duration(minutes: 1);

  /// What gets copied or shared: the words, labelled so a note or password entry is recognisable later.
  static String exportText(String phrase) => 'Usync recovery phrase: $phrase';

  static Future<void> _defaultCopy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    // A phrase left on the clipboard can be read by other apps: remove it again after a minute, but only if
    // it is still what we put there.
    Timer(clipboardLifetime, () async {
      try {
        final now = await Clipboard.getData(Clipboard.kTextPlain);
        if (now?.text == text) await Clipboard.setData(const ClipboardData(text: ''));
      } catch (_) {}
    });
  }

  static Future<void> _defaultShare(String text) => Share.share(text, subject: 'Usync recovery phrase');

  @override
  State<RecoveryPhraseSheet> createState() => _RecoveryPhraseSheetState();
}

class _RecoveryPhraseSheetState extends State<RecoveryPhraseSheet> {
  late final List<String> _words = widget.phrase.split(' ');
  late final Random _random = widget._random ?? Random.secure();
  late final List<int> _asked = _pick();
  /// The four words offered for each asked position (the right one and three others from the phrase).
  late final List<List<String>> _options = [for (final i in _asked) _optionsFor(i)];
  final List<String?> _chosen = [null, null, null];
  bool _quiz = false;
  String? _error;
  bool _copied = false;
  Timer? _copiedTimer;

  List<int> _pick() {
    final all = List<int>.generate(_words.length, (i) => i)..shuffle(_random);
    return (all.take(3).toList()..sort());
  }

  List<String> _optionsFor(int position) {
    final right = _words[position];
    final others = _words.toSet().difference({right}).toList()..shuffle(_random);
    return ([right, ...others.take(3)]..shuffle(_random));
  }

  void _choose(int question, String word) {
    setState(() {
      _chosen[question] = word;
      _error = null;
    });
    if (_chosen.any((c) => c == null)) return;
    final ok = [for (var i = 0; i < 3; i++) _chosen[i] == _words[_asked[i]]].every((v) => v);
    if (ok) {
      Navigator.pop(context, true);
    } else {
      setState(() {
        _error = 'Not quite. Look at the words again and try once more.';
        for (var i = 0; i < 3; i++) {
          _chosen[i] = null;
        }
      });
    }
  }

  Future<void> _copy() async {
    await (widget.copy ?? RecoveryPhraseSheet._defaultCopy)(RecoveryPhraseSheet.exportText(widget.phrase));
    if (!mounted) return;
    setState(() => _copied = true);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  Future<void> _share() async {
    try {
      await (widget.share ?? RecoveryPhraseSheet._defaultShare)(RecoveryPhraseSheet.exportText(widget.phrase));
    } catch (_) {
      // The share sheet could not open; the words are still on screen to write down.
    }
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
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
        const SizedBox(height: 14),
        Text('Want a second copy? Keep it only where you alone can open it, such as a password manager. '
            'Do not send it to your partner, or keep it in a shared note or an email others can read.', style: AppTextStyles.labelSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _copy,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 18),
                label: Text(_copied ? 'Copied' : 'Copy'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _share,
                icon: const Icon(Icons.ios_share, size: 18),
                label: const Text('Save to…'),
              ),
            ),
          ],
        ),
        if (_copied)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Copied. It is removed from the clipboard in a minute.', style: AppTextStyles.labelSmall),
          ),
        const SizedBox(height: 18),
        GlowButton(label: 'I have written it down', onTap: () => setState(() => _quiz = true)),
      ];

  List<Widget> _quizChildren() => [
        Text('Check your phrase', style: AppTextStyles.h3.copyWith(color: Colors.white)),
        const SizedBox(height: 8),
        Text('Tap the right word for each position.', style: AppTextStyles.bodyMuted),
        const SizedBox(height: 14),
        for (var q = 0; q < 3; q++) ...[
          Text('WORD ${_asked[q] + 1}', style: AppTextStyles.labelCaps),
          const SizedBox(height: 8),
          Wrap(
            key: ValueKey('quiz-q$q'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final word in _options[q])
                GestureDetector(
                  onTap: () => _choose(q, word),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _chosen[q] == word ? AppColors.pink.withValues(alpha: 0.25) : AppColors.glass,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: _chosen[q] == word ? AppColors.pink : AppColors.glassBorder),
                    ),
                    child: Text(word, style: AppTextStyles.body.copyWith(fontSize: 15)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: AppTextStyles.labelSmall.copyWith(color: AppColors.error))),
        Center(child: TextButton(onPressed: () => setState(() => _quiz = false), child: Text('Show the words again', style: AppTextStyles.link))),
      ];
}
