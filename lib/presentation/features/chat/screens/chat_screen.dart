import 'dart:async';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/services/secure_screen.dart';
import '../../../../core/services/voice_recorder.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/app_snack_bar.dart';
import '../../../../core/utils/haptic_util.dart';
import '../../../../domain/entities/chat_message.dart';
import '../../../shared/widgets/loading_dots.dart';
import '../../../shared/widgets/neon_back_button.dart';
import '../../auth/bloc/auth_bloc.dart';
import '../bloc/chat_bloc.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthBloc>().state;
    final user = auth is Authenticated ? auth.user : null;
    return BlocProvider(
      create: (_) => GetIt.I<ChatBloc>()..add(ChatOpened(coupleId: user?.coupleId ?? '', userId: user?.id ?? '')),
      child: BlocListener<ChatBloc, ChatState>(
        listenWhen: (_, b) => b.notice != null,
        listener: (context, state) => ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: Text(state.notice!))),
        child: const _Body(),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  const _Body();

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> with WidgetsBindingObserver {
  late final ChatBloc _bloc = context.read<ChatBloc>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SecureScreen.set(true); // no screenshots or screen recording while the chat is open
    _bloc.add(ChatVisibilityChanged(visible: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) =>
      _bloc.add(ChatVisibilityChanged(visible: state == AppLifecycleState.resumed));

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SecureScreen.set(false);
    _bloc.add(ChatVisibilityChanged(visible: false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  const NeonBackButton(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Private chat', style: AppTextStyles.h2.copyWith(fontSize: 22)),
                        BlocBuilder<ChatBloc, ChatState>(
                          buildWhen: (a, b) => a.timer != b.timer,
                          builder: (_, state) => Text('🔒 Encrypted · vanishes ${state.timer.label} after seen', style: AppTextStyles.label),
                        ),
                      ],
                    ),
                  ),
                  const _TimerButton(),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state.loading) return const Center(child: LoadingDots());
                  if (state.messages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Say something sweet.\nMessages, photos and voice notes only you two can read. They vanish after your partner has seen them: tap the timer to choose how long.',
                          style: AppTextStyles.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  final list = state.messages.reversed.toList();
                  return ListView.builder(
                    reverse: true, // newest at the bottom, and the list stays there
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _Bubble(key: ValueKey(list[i].id), message: list[i], state: state),
                  );
                },
              ),
            ),
            const _InputBar(),
          ],
        ),
      ),
    );
  }
}

String _clock(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.message, required this.state});
  final ChatMessage message;
  final ChatState   state;

  @override
  Widget build(BuildContext context) {
    final mine  = message.isMine(state.userId);
    final color = mine ? AppColors.pink : AppColors.cyan;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(alignment: Alignment.centerLeft, child: _content(context)),
            // Your own messages show a quiet tick: one when sent, two (in colour) once your partner has seen it.
            if (mine) ...[
              const SizedBox(height: 2),
              Icon(message.isSeen ? Icons.done_all : Icons.done, size: 14, color: message.isSeen ? AppColors.cyan : AppColors.textDim),
            ],
          ],
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    if (message.locked) {
      return Text('🔒 Locked until your key arrives', style: AppTextStyles.bodyMuted);
    }
    return switch (message.kind) {
      ChatKind.text  => Text(message.text ?? '', style: AppTextStyles.body),
      ChatKind.image => _ImageContent(message: message),
      ChatKind.voice => _VoiceContent(message: message),
    };
  }
}

class _ImageContent extends StatefulWidget {
  const _ImageContent({required this.message});
  final ChatMessage message;

  @override
  State<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends State<_ImageContent> {
  late final Future<Uint8List?> _bytes = context.read<ChatBloc>().loadMedia(widget.message);

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
        future: _bytes,
        builder: (context, snap) {
          final bytes = snap.data;
          if (snap.connectionState != ConnectionState.done) {
            return const SizedBox(width: 200, height: 160, child: Center(child: LoadingDots()));
          }
          if (bytes == null) {
            return Text('Photo could not be loaded', style: AppTextStyles.bodyMuted);
          }
          return GestureDetector(
            onTap: () => showDialog<void>(
              context: context,
              barrierColor: Colors.black,
              builder: (_) => Dialog.fullscreen(
                backgroundColor: Colors.black,
                child: Stack(
                  children: [
                    Center(child: InteractiveViewer(child: Image.memory(bytes))),
                    Positioned(top: 16, left: 16, child: SafeArea(child: NeonBackButton(onTap: () => Navigator.of(context).pop()))),
                  ],
                ),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.memory(bytes, width: 220, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          );
        },
      );
}

class _VoiceContent extends StatefulWidget {
  const _VoiceContent({required this.message});
  final ChatMessage message;

  @override
  State<_VoiceContent> createState() => _VoiceContentState();
}

class _VoiceContentState extends State<_VoiceContent> {
  final _player = AudioPlayer();
  PlayerState _state = PlayerState.stopped;
  Duration _pos = Duration.zero;
  bool _loading = false;
  final _subs = <StreamSubscription<dynamic>>[];

  Duration get _total => Duration(milliseconds: widget.message.durationMs ?? 0);

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onPlayerStateChanged.listen((s) { if (mounted) setState(() => _state = s); }));
    _subs.add(_player.onPositionChanged.listen((p) { if (mounted) setState(() => _pos = p); }));
    _subs.add(_player.onPlayerComplete.listen((_) { if (mounted) setState(() => _pos = Duration.zero); }));
  }

  @override
  void dispose() {
    for (final s in _subs) { s.cancel(); }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_loading) return;
    if (_state == PlayerState.playing) {
      await _player.pause();
      return;
    }
    if (_state == PlayerState.paused) {
      await _player.resume();
      return;
    }
    setState(() => _loading = true);
    final bytes = await context.read<ChatBloc>().loadMedia(widget.message);
    if (!mounted) return;
    setState(() => _loading = false);
    if (bytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: const Text('Voice note could not be loaded')));
      return;
    }
    // Played straight from memory: the decrypted audio is never written to a file.
    await _player.play(BytesSource(bytes, mimeType: 'audio/mp4'));
  }

  @override
  Widget build(BuildContext context) {
    final playing = _state == PlayerState.playing;
    final progress = _total.inMilliseconds == 0 ? 0.0 : (_pos.inMilliseconds / _total.inMilliseconds).clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: AppColors.glassMid),
            child: _loading
                ? const Padding(padding: EdgeInsets.all(11), child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(playing ? Icons.pause : Icons.play_arrow, color: AppColors.textPrimary),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 110,
          child: LinearProgressIndicator(value: progress, minHeight: 4, backgroundColor: AppColors.glassMid, color: AppColors.lavender),
        ),
        const SizedBox(width: 10),
        Text(_clock(playing || _pos > Duration.zero ? _pos : _total), style: AppTextStyles.label),
      ],
    );
  }
}

class _InputBar extends StatefulWidget {
  const _InputBar();

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar> {
  static const _maxVoice = Duration(minutes: 2);
  final _text     = TextEditingController();
  final _recorder = VoiceRecorder();
  Timer?   _ticker;
  Duration _elapsed   = Duration.zero;
  bool     _recording = false;
  bool     _cancelling = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _recorder.dispose();
    _text.dispose();
    super.dispose();
  }

  void _sendText() {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    context.read<ChatBloc>().add(ChatTextSent(t));
    _text.clear();
    HapticUtil.light();
  }

  Future<void> _pickImage() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: AppColors.bg2,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined, color: AppColors.textPrimary),
              title: Text('Take a photo', style: AppTextStyles.body),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined, color: AppColors.textPrimary),
              title: Text('Choose from gallery', style: AppTextStyles.body),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      // Shrunk before sending: a phone photo is many megabytes, and this keeps it quick to seal and send.
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 80);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      context.read<ChatBloc>().add(ChatImageSent(bytes));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: const Text('Could not open the photo')));
    }
  }

  Future<void> _startRecording() async {
    try {
      if (!await _recorder.start()) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: const Text('Allow the microphone to send voice notes')));
        return;
      }
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: const Text('Could not start recording')));
      return;
    }
    HapticUtil.medium();
    setState(() { _recording = true; _cancelling = false; _elapsed = Duration.zero; });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted) return;
      setState(() => _elapsed += const Duration(milliseconds: 250));
      if (_elapsed >= _maxVoice) _finishRecording();
    });
  }

  Future<void> _finishRecording() async {
    if (!_recording) return;
    _ticker?.cancel();
    final cancelled = _cancelling;
    setState(() => _recording = false);
    if (cancelled) {
      await _recorder.cancel();
      return;
    }
    final note = await _recorder.stop();
    if (!mounted || note == null) return;
    // A tap that was too short to be a message.
    if (note.durationMs < 800) return;
    context.read<ChatBloc>().add(ChatVoiceSent(bytes: note.bytes, durationMs: note.durationMs));
  }

  @override
  Widget build(BuildContext context) {
    final hasText = _text.text.trim().isNotEmpty;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.glassBorder))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!_recording)
            IconButton(
              onPressed: _pickImage,
              icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.textMuted),
            ),
          Expanded(
            child: _recording
                ? Container(
                    height: 48,
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: AppColors.glass, borderRadius: BorderRadius.circular(24)),
                    child: Text(
                      _cancelling ? '← Release to cancel' : '🔴 ${_clock(_elapsed)}  ← slide left to cancel',
                      style: AppTextStyles.body.copyWith(color: _cancelling ? AppColors.error : null),
                    ),
                  )
                : TextField(
                    controller: _text,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    textCapitalization: TextCapitalization.sentences,
                    style: AppTextStyles.body,
                    decoration: InputDecoration(
                      hintText: 'Message',
                      counterText: '',
                      filled: true,
                      fillColor: AppColors.glass,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                    ),
                  ),
          ),
          const SizedBox(width: 8),
          if (hasText && !_recording)
            GestureDetector(
              onTap: _sendText,
              child: const CircleAvatar(radius: 24, backgroundColor: AppColors.pink, child: Icon(Icons.send, color: Colors.white)),
            )
          else
            GestureDetector(
              onLongPressStart: (_) => _startRecording(),
              onLongPressMoveUpdate: (d) {
                final cancelling = d.offsetFromOrigin.dx < -80;
                if (cancelling != _cancelling && _recording) setState(() => _cancelling = cancelling);
              },
              onLongPressEnd: (_) => _finishRecording(),
              onLongPressCancel: () => _finishRecording(),
              child: CircleAvatar(
                radius: 24,
                backgroundColor: _recording ? AppColors.error : AppColors.glassMid,
                child: const Icon(Icons.mic, color: AppColors.textPrimary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Header button: chooses how long the messages you send live after your partner has seen them.
class _TimerButton extends StatelessWidget {
  const _TimerButton();

  Future<void> _choose(BuildContext context) async {
    final bloc = context.read<ChatBloc>();
    final picked = await showModalBottomSheet<ChatTimer>(
      context: context,
      backgroundColor: AppColors.bg2,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Messages you send vanish after…', style: AppTextStyles.h4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'The time starts when your partner has seen the message. It applies to new messages you send; one nobody opens is deleted after 1 day.',
                style: AppTextStyles.bodyMuted,
              ),
            ),
            for (final t in ChatTimer.values)
              ListTile(
                title: Text(t.label, style: AppTextStyles.body),
                trailing: bloc.state.timer == t ? const Icon(Icons.check, color: AppColors.cyan) : null,
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
      ),
    );
    if (picked != null) bloc.add(ChatTimerChanged(picked));
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<ChatBloc, ChatState>(
        buildWhen: (a, b) => a.timer != b.timer,
        builder: (context, state) => GestureDetector(
          onTap: () => _choose(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.timer_outlined, size: 16, color: AppColors.textPrimary),
                const SizedBox(width: 4),
                Text(state.timer.shortLabel, style: AppTextStyles.label.copyWith(color: AppColors.textPrimary)),
              ],
            ),
          ),
        ),
      );
}
