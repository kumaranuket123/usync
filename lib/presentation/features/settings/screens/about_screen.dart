import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/privacy_policy.dart';
import '../../../shared/widgets/neon_back_button.dart';

/// What Usync is and everything it can do. When a feature is added or removed,
/// update [_sections] so this page stays true.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  /// Read from the installed app, so it always matches pubspec.yaml.
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'Version ${info.version} (${info.buildNumber})');
    }).catchError((_) {});
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
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text('About Usync', style: AppTextStyles.h2.copyWith(fontSize: 24), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _Hero(version: _version),
                    for (final section in _sections) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(0, 22, 0, 10),
                        child: Text(section.title, style: AppTextStyles.labelCaps),
                      ),
                      for (final f in section.features) _FeatureCard(f),
                    ],
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: () => openPrivacyPolicy(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.glass,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: Row(
                          children: [
                            const Text('🔒', style: TextStyle(fontSize: 18)),
                            const SizedBox(width: 12),
                            Expanded(child: Text('Read our Privacy Policy', style: AppTextStyles.body.copyWith(fontSize: 15))),
                            Text('›', style: TextStyle(color: AppColors.textDim, fontSize: 18)),
                          ],
                        ),
                      ),
                    ),
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

class _Hero extends StatelessWidget {
  const _Hero({required this.version});
  final String version;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.glassBorder),
      ),
      child: Column(
        children: [
          const Text('💞', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('Usync', style: AppTextStyles.h2),
          if (version.isNotEmpty) Text(version, style: AppTextStyles.labelSmall),
          const SizedBox(height: 12),
          Text(
            'A private space for two. Usync keeps you emotionally in sync with your partner, '
            'whether you live together or far apart: draw, touch, share how you feel, answer a '
            'question a day, plan things to do and keep your memories, all in real time.',
            style: AppTextStyles.bodyMuted,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard(this.feature);
  final _Feature feature;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppColors.glass.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.glassBorder.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(color: feature.tint, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(feature.emoji, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(feature.title, style: AppTextStyles.body.copyWith(fontSize: 15)),
                const SizedBox(height: 2),
                Text(feature.text, style: AppTextStyles.labelSmall.copyWith(height: 1.45)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Feature {
  const _Feature(this.emoji, this.tint, this.title, this.text);
  final String emoji, title, text;
  final Color  tint;
}

class _Section {
  const _Section(this.title, this.features);
  final String         title;
  final List<_Feature> features;
}

const _pink   = Color(0x1FFF2D78);
const _cyan   = Color(0x1F00D4FF);
const _purple = Color(0x1F9D4EDD);
const _green  = Color(0x1F00E676);
const _gold   = Color(0x1AFFD700);

const _sections = <_Section>[
  _Section('CONNECT', [
    _Feature('🔗', _purple, 'Pairing',
        'Sign in with Google, then pair with your partner using a 4-character invite code that expires after 24 hours. One couple per account.'),
    _Feature('👆', _pink, 'Touch sync',
        'Press and hold to send your touch: your partner\'s phone vibrates in real time, wherever they are. Hold at the same time and you both see it.'),
    _Feature('💭', _purple, 'Moods',
        'Share how you feel with a preset or your own custom mood. Your partner\'s latest mood shows on their Home screen, with a short history below.'),
    _Feature('💞', _pink, 'Mood insights',
        'See how in sync you have been over the last 7 days: the days you shared a similar mood, and the mood each of you shared most.'),
    _Feature('💬', _cyan, 'Question of the day',
        'One question a day for both of you. Your partner\'s answer stays hidden until you have answered too. The questions suit couples who live together or apart.'),
  ]),
  _Section('CREATE AND REMEMBER', [
    _Feature('✏️', _cyan, 'Shared canvas',
        'Draw together live on the same canvas. Save a doodle and your partner is told.'),
    _Feature('🖼️', _pink, 'Memories',
        'Doodles and pictures you save are kept in a private space. Older pictures can be moved to your phone and copied to a "Usync" gallery album.'),
    _Feature('🕰️', _purple, 'Timeline',
        'Your journey in one place: the day you connected, streak milestones, how many days you have been together, and your own special dates (anniversaries, trips) with a countdown and a reminder on the day, yearly if you like.'),
    _Feature('🎯', _cyan, 'Bucket list',
        'A shared list of things you want to do together. Either of you can add items, tick them off and see the progress. Adding works offline.'),
    _Feature('🔥', _gold, 'Streaks',
        'Every day you both do something in the app (a mood, a doodle, a memory, a question, a bucket-list item) keeps your day streak alive.'),
  ]),
  _Section('NEAR OR FAR', [
    _Feature('🏡', _purple, 'Relationship type',
        'Choose Together or Long-distance in your Profile. It is shared with your partner and tailors the daily questions and what you see on Home.'),
    _Feature('✈️', _cyan, 'Long-distance card',
        'For long-distance couples, Home shows how far apart you are and a shared "next time we meet" countdown that either of you can set.'),
    _Feature('📍', _green, 'Location',
        'Optional. Share your last known location and see your partner on a map, or ask for a fresh one. Your partner is always notified when you are located, and you can switch it off any time.'),
  ]),
  _Section('ALWAYS WITH YOU', [
    _Feature('🔔', _pink, 'Notifications',
        'Get a push when your partner does something. In Alert sounds you choose which alerts stay silent.'),
    _Feature('📱', _cyan, 'Home-screen widget',
        'On Android, put the Live Doodle widget on your home screen to see your shared drawing without opening the app. Tap it to jump in.'),
    _Feature('📶', _green, 'Works offline',
        'Moods, dates, doodles and bucket-list items you add without a connection are saved on your phone and sent when you are back online.'),
    _Feature('🎨', _purple, 'Themes',
        'Pick from five themes: Midnight Purple, Lavender Dream, Sunset Glow, Ocean Blue and Neon Pink.'),
  ]),
  _Section('PRIVATE BY DESIGN', [
    _Feature('🔐', _gold, 'App lock',
        'Protect Usync with your fingerprint, face or screen lock. It is handled by your phone; we never see your biometric data.'),
    _Feature('🛡️', _green, 'Only the two of you',
        'Everything you share is visible only to you and your partner. There are no ads and no third-party analytics.'),
    _Feature('💔', _pink, 'You are in control',
        'Disconnect from your partner or delete your account at any time in Settings. Everything you shared is permanently deleted.'),
  ]),
];
