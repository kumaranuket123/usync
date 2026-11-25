import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

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
  final _scroll = ScrollController();
  /// A key per message, so a reply can scroll to the message it quotes once that bubble is built.
  final _keys = <String, GlobalKey>{};
  /// Ids of what the list shows, newest first (what the last build used).
  var _order = const <String>[];
  String? _highlight;
  Timer? _highlightTimer;

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

  /// Scrolls to the message [id] (a reply's original) and flashes it. Older pages are loaded when it is
  /// further back; if it is gone (deleted, vanished) the user is told.
  Future<void> goToMessage(String id) async {
    for (var attempt = 0; attempt < 40 && mounted; attempt++) {
      final index = _order.indexOf(id);
      if (index < 0) {
        if (!_bloc.state.hasOlder) {
          // ignore: use_build_context_synchronously (the loop only runs while mounted)
          ScaffoldMessenger.of(context).showSnackBar(appSnackBar(content: const Text('The original message is no longer available')));
          return;
        }
        _bloc.add(ChatOlderRequested());
        await Future<void>.delayed(const Duration(milliseconds: 150));
        continue;
      }
      final bubble = _keys[id]?.currentContext;
      if (bubble != null) {
        // ignore: use_build_context_synchronously (the loop only runs while mounted)
        await Scrollable.ensureVisible(bubble, duration: const Duration(milliseconds: 300), curve: Curves.easeOut, alignment: 0.5);
        if (!mounted) return;
        _highlightTimer?.cancel();
        setState(() => _highlight = id);
        _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
          if (mounted) setState(() => _highlight = null);
        });
        return;
      }
      // Not built yet (far from the screen): move towards where it should be, then look again.
      if (!_scroll.hasClients) return;
      final position = _scroll.position;
      final average = (position.maxScrollExtent + position.viewportDimension) / _order.length;
      _scroll.jumpTo((index * average).clamp(0.0, position.maxScrollExtent));
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    _scroll.dispose();
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
                        Text('🔒 Encrypted', style: AppTextStyles.label),
                      ],
                    ),
                  ),
                  const _TimerButton(),
                  const SizedBox(width: 8),
                  const _MoreButton(),
                ],
              ),
            ),
            Expanded(
              child: BlocBuilder<ChatBloc, ChatState>(
                builder: (context, state) {
                  if (state.loading) return const Center(child: LoadingDots());
                  if (state.messages.isEmpty && state.notices.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Say something sweet.\nMessages, photos and voice notes only you two can read. They stay on your phones until you delete them; tap the timer if you want them to vanish after being read.',
                          style: AppTextStyles.bodyMuted,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  // Messages and "timer changed" lines in the order they happened; the newest is at the bottom.
                  final items = <({DateTime at, Object item})>[
                    for (final m in state.messages) (at: m.createdAt, item: m),
                    for (final n in state.notices) (at: n.at, item: n),
                  ]..sort((a, b) => b.at.compareTo(a.at));
                  _order = [for (final i in items) i.item is ChatMessage ? (i.item as ChatMessage).id : ''];
                  return NotificationListener<ScrollNotification>(
                    // Near the top (the end of a reversed list): bring in an older page.
                    onNotification: (n) {
                      if (state.hasOlder && n.metrics.extentAfter < 400) context.read<ChatBloc>().add(ChatOlderRequested());
                      return false;
                    },
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true, // newest at the bottom, and the list stays there
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i].item;
                        final Widget row;
                        if (item is ChatTimerNotice) {
                          row = _TimerNoticeLine(key: ValueKey(item), notice: item);
                        } else {
                          final m = item as ChatMessage;
                          row = KeyedSubtree(
                            key: _keys.putIfAbsent(m.id, GlobalKey.new),
                            child: _Bubble(key: ValueKey(m.id), message: m, state: state, highlighted: _highlight == m.id),
                          );
                        }
                        // The list is newest first, so the next item is the older one: a new day starts here
                        // when that one is from another day (or there is none).
                        final startsDay = i == items.length - 1 || !_sameDay(items[i + 1].at, items[i].at);
                        if (!startsDay) return row;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [_DayLabel(day: items[i].at), row],
                        );
                      },
                    ),
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

bool _sameDay(DateTime a, DateTime b) {
  final x = a.toLocal(), y = b.toLocal();
  return x.year == y.year && x.month == y.month && x.day == y.day;
}

/// "Today", "Yesterday", or the date ("12 Nov", with the year when it is not this year).
String dayLabel(DateTime day, {DateTime? now}) {
  final d = day.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final dayOnly = DateTime(d.year, d.month, d.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  final days = todayOnly.difference(dayOnly).inDays;
  if (days == 0) return 'Today';
  if (days == 1) return 'Yesterday';
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final text = '${d.day} ${months[d.month - 1]}';
  return d.year == today.year ? text : '$text ${d.year}';
}

/// The small centred pill above the first message of each day.
class _DayLabel extends StatelessWidget {
  const _DayLabel({required this.day});
  final DateTime day;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(dayLabel(day), style: AppTextStyles.label),
          ),
        ),
      );
}

String _clock(Duration d) {
  final s = d.inSeconds.clamp(0, 359999);
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

/// "You set messages to vanish 1 minute after seen": a quiet centred line where the timer was changed.
class _TimerNoticeLine extends StatelessWidget {
  const _TimerNoticeLine({super.key, required this.notice});
  final ChatTimerNotice notice;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.glass,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.glassBorder),
            ),
            child: Text(
              notice.timer.isOff
                  ? '⏱ ${notice.byMe ? 'You turned' : 'Your partner turned'} vanishing messages off'
                  : '⏱ ${notice.byMe ? 'You set' : 'Your partner set'} messages to vanish ${notice.timer.label} after read',
              style: AppTextStyles.label,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
}

class _Bubble extends StatelessWidget {
  const _Bubble({super.key, required this.message, required this.state, this.highlighted = false});
  final ChatMessage message;
  final ChatState   state;
  /// Flashes briefly after a reply jumped here.
  final bool        highlighted;

  @override
  Widget build(BuildContext context) {
    final mine  = message.isMine(state.userId);
    final color = mine ? AppColors.pink : AppColors.cyan;
    return _SwipeToReply(
      enabled: !message.locked,
      onReply: () => context.read<ChatBloc>().add(ChatReplyStarted(message)),
      child: Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        // Hold a message to delete it.
        onLongPress: () => _askDelete(context),
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: highlighted ? 0.4 : 0.14),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Column(
          // The bubble is only as wide as its widest child; the tick sits under the content, on the right.
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.reply != null)
              _QuotedReply(
                reply: message.reply!,
                userId: state.userId,
                inBubble: true,
                // Tap the quote: go to the message it answers.
                onTap: () => context.findAncestorStateOfType<_BodyState>()?.goToMessage(message.reply!.messageId),
              ),
            // No Align around the content: it would take all the width and every bubble would be full width.
            _content(context),
            const SizedBox(height: 2),
            // When it was sent, and for your own messages a quiet tick: one when sent, two (in colour) once
            // your partner has seen it.
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(message.createdAt.toLocal())),
                  style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                ),
                if (mine) ...[
                  const SizedBox(width: 4),
                  // Clock while it waits for a connection, one tick sent, two grey delivered, two blue read.
                  Icon(
                    message.pending ? Icons.schedule : (message.isSeen || message.isDelivered) ? Icons.done_all : Icons.done,
                    size: 14,
                    color: message.isSeen ? AppColors.cyan : AppColors.textDim,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
      ),
      ),
    );
  }

  Future<void> _askDelete(BuildContext context) async {
    HapticUtil.medium();
    final bloc = context.read<ChatBloc>();
    final mine = message.isMine(state.userId);
    final choice = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.bg2,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (sheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                leading: const Icon(Icons.delete_outline, color: AppColors.textPrimary),
                title: Text('Delete for me', style: AppTextStyles.body),
                subtitle: Text('Only removed from this phone', style: AppTextStyles.bodyMuted),
                onTap: () => Navigator.of(sheet).pop(false),
              ),
              // Only what you wrote yourself can be taken back from your partner's phone.
              if (mine)
                ListTile(
                  leading: const Icon(Icons.delete_forever_outlined, color: AppColors.error),
                  title: const Text('Delete for everyone', style: TextStyle(color: AppColors.error)),
                  subtitle: Text('Removed from both phones', style: AppTextStyles.bodyMuted),
                  onTap: () => Navigator.of(sheet).pop(true),
                ),
              ListTile(
                leading: const Icon(Icons.close, color: AppColors.textMuted),
                title: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
                onTap: () => Navigator.of(sheet).pop(),
              ),
            ],
          ),
        ),
      ),
    );
    if (choice != null) bloc.add(ChatMessageDeleted(message.id, forEveryone: choice));
  }

  Widget _content(BuildContext context) {
    if (message.locked) {
      return Text('🔒 Locked until your key arrives', style: AppTextStyles.bodyMuted);
    }
    return switch (message.kind) {
      ChatKind.text  => Text(message.text ?? '', style: AppTextStyles.body),
      ChatKind.image => _ImageContent(message: message, mine: message.isMine(state.userId)),
      ChatKind.voice => _VoiceContent(message: message, mine: message.isMine(state.userId)),
    };
  }
}

/// Drag a message to the right to reply to it: it follows the finger a little, and springs back.
class _SwipeToReply extends StatefulWidget {
  const _SwipeToReply({required this.child, required this.onReply, required this.enabled});
  final Widget child;
  final VoidCallback onReply;
  final bool enabled;

  @override
  State<_SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<_SwipeToReply> with SingleTickerProviderStateMixin {
  static const _trigger = 56.0;
  static const _max     = 72.0;
  double _dx = 0;
  double _from = 0;
  bool _armed = false;
  late final AnimationController _back = AnimationController(vsync: this, duration: const Duration(milliseconds: 180))
    ..addListener(() => setState(() => _dx = _from * (1 - Curves.easeOut.transform(_back.value))));

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _update(DragUpdateDetails d) {
    if (_back.isAnimating) _back.stop();
    final next = (_dx + d.delta.dx).clamp(0.0, _max);
    // Past the line the phone ticks once, so the reply is felt before the finger lets go.
    if (!_armed && next >= _trigger) {
      _armed = true;
      HapticUtil.light();
    } else if (_armed && next < _trigger) {
      _armed = false;
    }
    setState(() => _dx = next);
  }

  void _end([DragEndDetails? _]) {
    if (_armed) widget.onReply();
    _armed = false;
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    final progress = (_dx / _trigger).clamp(0.0, 1.0);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: _end,
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          Opacity(
            opacity: progress,
            child: Transform.scale(
              scale: 0.6 + 0.4 * progress,
              child: const CircleAvatar(radius: 14, backgroundColor: AppColors.glassMid, child: Icon(Icons.reply, size: 16, color: AppColors.textPrimary)),
            ),
          ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}

/// What a reply answers: who wrote it, and a line of the original (or "Photo" / "Voice note").
class _QuotedReply extends StatelessWidget {
  const _QuotedReply({required this.reply, required this.userId, this.inBubble = false, this.onClose, this.onTap});
  final ChatReply reply;
  final String userId;
  /// Inside a message bubble rather than in the bar above the input.
  final bool inBubble;
  final VoidCallback? onClose;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final mine  = reply.senderId == userId;
    final color = mine ? AppColors.pink : AppColors.cyan;
    final line  = switch (reply.kind) {
      ChatKind.text  => reply.text ?? '',
      ChatKind.image => '📷 Photo',
      ChatKind.voice => '🎤 Voice note',
    };
    final body = Container(
      margin: EdgeInsets.only(bottom: inBubble ? 6 : 0),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: color, width: 3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(mine ? 'You' : 'Your partner', style: AppTextStyles.label.copyWith(color: color, fontWeight: FontWeight.w600)),
                Text(line, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMuted.copyWith(fontSize: 13)),
              ],
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(width: 8),
            GestureDetector(onTap: onClose, child: const Icon(Icons.close, size: 18, color: AppColors.textMuted)),
          ],
        ],
      ),
    );
    // In the bar it spans the width; in a bubble it is only as wide as its text.
    final shown = inBubble ? body : SizedBox(width: double.infinity, child: body);
    return onTap == null ? shown : GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: shown);
  }
}

class _ImageContent extends StatefulWidget {
  const _ImageContent({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

  @override
  State<_ImageContent> createState() => _ImageContentState();
}

class _ImageContentState extends State<_ImageContent> {
  late final Future<Uint8List?> _bytes = context.read<ChatBloc>().loadMedia(widget.message);

  /// Every photo takes the same fixed box in the chat (cropped to fit), so a big picture does not fill the screen;
  /// the whole picture is shown when it is tapped.
  static const _size = 200.0;

  /// The user tapped it: it is shown clearly from now on (the server's answer may take a moment).
  bool _revealed = false;

  void _reveal() {
    _revealed = true;
    // The timer of a photo starts now, not when it first appeared in the chat.
    if (!widget.mine && !widget.message.isSeen) context.read<ChatBloc>().add(ChatMediaRevealed(widget.message.id));
  }

  /// Opens every photo of the chat you can see, oldest first, starting at this one: swipe sideways to move
  /// between them. A partner's photo you have not revealed yet is left out (it stays hidden until tapped).
  void _openGallery(BuildContext context) {
    final bloc = context.read<ChatBloc>();
    final photos = [
      for (final m in bloc.state.messages)
        if (m.kind == ChatKind.image && !m.locked && (m.id == widget.message.id || m.isMine(bloc.state.userId) || m.isSeen)) m,
    ];
    final start = photos.indexWhere((m) => m.id == widget.message.id);
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (_) => _PhotoGallery(bloc: bloc, photos: photos, initial: start < 0 ? 0 : start),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Your partner's photo stays hidden (and its timer waits) until you tap it; your own is always clear.
    // With no vanish timer (Off) there is nothing to hold back: it is shown clearly and counts as read.
    final blurred = !widget.mine && !widget.message.isSeen && !_revealed && widget.message.ttlSeconds > 0;
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        if (snap.connectionState != ConnectionState.done) {
          return const SizedBox(width: _size, height: _size, child: Center(child: LoadingDots()));
        }
        if (bytes == null) {
          return SizedBox(width: _size, child: Text('Photo could not be loaded', style: AppTextStyles.bodyMuted));
        }
        Widget picture = Image.memory(bytes, width: _size, height: _size, fit: BoxFit.cover, gaplessPlayback: true, cacheWidth: 400);
        if (blurred) {
          picture = Stack(
            alignment: Alignment.center,
            children: [
              ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14, tileMode: TileMode.clamp), child: picture),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.visibility_outlined, size: 16, color: Colors.white),
                  SizedBox(width: 6),
                  Text('Tap to reveal', style: TextStyle(color: Colors.white, fontSize: 12)),
                ]),
              ),
            ],
          );
        }
        return GestureDetector(
          onTap: () {
            setState(_reveal);
            _openGallery(context);
          },
          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: _size, height: _size, child: picture)),
        );
      },
    );
  }
}

/// Full-screen photos of the chat, like a gallery: swipe sideways for the next or previous one, pinch to zoom.
class _PhotoGallery extends StatefulWidget {
  const _PhotoGallery({required this.bloc, required this.photos, required this.initial});
  final ChatBloc bloc;
  final List<ChatMessage> photos;
  final int initial;

  @override
  State<_PhotoGallery> createState() => _PhotoGalleryState();
}

class _PhotoGalleryState extends State<_PhotoGallery> {
  late final PageController _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;
  /// Zoomed in: the picture takes the finger, so paging is paused until it is zoomed out again.
  bool _zoomed = false;
  final _loads = <String, Future<Uint8List?>>{};

  Future<Uint8List?> _bytes(ChatMessage m) => _loads.putIfAbsent(m.id, () => widget.bloc.loadMedia(m));

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.photos.length;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pages,
            itemCount: total,
            physics: _zoomed ? const NeverScrollableScrollPhysics() : const PageScrollPhysics(),
            onPageChanged: (i) => setState(() {
              _index = i;
              _zoomed = false;
            }),
            itemBuilder: (_, i) => FutureBuilder<Uint8List?>(
              future: _bytes(widget.photos[i]),
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) return const Center(child: LoadingDots());
                final bytes = snap.data;
                if (bytes == null) {
                  return Center(child: Text('Photo could not be loaded', style: AppTextStyles.bodyMuted));
                }
                return _ZoomablePhoto(bytes: bytes, onZoomChanged: (z) {
                  if (i == _index && z != _zoomed) setState(() => _zoomed = z);
                });
              },
            ),
          ),
          Positioned(top: 16, left: 16, child: SafeArea(child: NeonBackButton(onTap: () => Navigator.of(context).pop()))),
          if (total > 1)
            Positioned(
              top: 24,
              right: 20,
              child: SafeArea(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(12)),
                  child: Text('${_index + 1} / $total', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ZoomablePhoto extends StatefulWidget {
  const _ZoomablePhoto({required this.bytes, required this.onZoomChanged});
  final Uint8List bytes;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomablePhoto> createState() => _ZoomablePhotoState();
}

class _ZoomablePhotoState extends State<_ZoomablePhoto> {
  final _controller = TransformationController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => InteractiveViewer(
        transformationController: _controller,
        onInteractionEnd: (_) => widget.onZoomChanged(_controller.value.getMaxScaleOnAxis() > 1.02),
        child: Center(child: Image.memory(widget.bytes, gaplessPlayback: true)),
      );
}

class _VoiceContent extends StatefulWidget {
  const _VoiceContent({required this.message, required this.mine});
  final ChatMessage message;
  final bool mine;

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
    // Playing it is revealing it: the timer of a partner's voice note starts now.
    if (!widget.mine && !widget.message.isSeen) context.read<ChatBloc>().add(ChatMediaRevealed(widget.message.id));
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
  final _focus    = FocusNode();
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
    _focus.dispose();
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
    return BlocListener<ChatBloc, ChatState>(
      // Starting a reply puts the cursor in the field.
      listenWhen: (a, b) => a.replyingTo?.id != b.replyingTo?.id && b.replyingTo != null,
      listener: (_, __) => _focus.requestFocus(),
      child: Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.glassBorder))),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          BlocBuilder<ChatBloc, ChatState>(
            buildWhen: (a, b) => a.replyingTo != b.replyingTo,
            builder: (context, state) {
              final m = state.replyingTo;
              if (m == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _QuotedReply(
                  reply: ChatReply.of(m),
                  userId: state.userId,
                  onClose: () => context.read<ChatBloc>().add(ChatReplyCancelled()),
                ),
              );
            },
          ),
          Row(
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
                    focusNode: _focus,
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
        ],
      ),
      ),
    );
  }
}

/// Header menu: clear the whole chat.
class _MoreButton extends StatelessWidget {
  const _MoreButton();

  Future<void> _clear(BuildContext context) async {
    final bloc = context.read<ChatBloc>();
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text('Clear chat?', style: AppTextStyles.h4),
        content: Text(
          'Every message, photo and voice note is deleted. This cannot be undone. Clear it only on this phone, or on your partner\'s phone too.',
          style: AppTextStyles.bodyMuted,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted))),
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('This phone', style: TextStyle(color: AppColors.error))),
          TextButton(onPressed: () => Navigator.pop(dialog, true), child: const Text('Both phones', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (choice != null) bloc.add(ChatCleared(forEveryone: choice));
  }

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'More',
        color: AppColors.bg2,
        icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
        onSelected: (_) => _clear(context),
        itemBuilder: (_) => const [
          PopupMenuItem(
            value: 'clear',
            child: Row(children: [
              Icon(Icons.delete_sweep_outlined, color: AppColors.error, size: 20),
              SizedBox(width: 10),
              Text('Clear chat', style: TextStyle(color: AppColors.error)),
            ]),
          ),
        ],
      );
}

/// Header button: chooses how long the messages you send live after your partner has seen them.
class _TimerButton extends StatelessWidget {
  const _TimerButton();

  Future<void> _choose(BuildContext context) async {
    final bloc = context.read<ChatBloc>();
    final picked = await showModalBottomSheet<ChatTimer>(
      context: context,
      backgroundColor: AppColors.bg2,
      // Six choices and an explanation can be taller than the default sheet: let it grow, and scroll on small screens.
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Text('Messages vanish…', style: AppTextStyles.h4),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'The same for both of you: it applies to every new message, from either of you, and starts when the message has been read. With Off, messages stay on your phones until you delete them.',
                style: AppTextStyles.bodyMuted,
              ),
            ),
            for (final t in ChatTimer.values)
              ListTile(
                title: Text(t.isOff ? 'Never (off)' : 'After ${t.label}', style: AppTextStyles.body),
                trailing: bloc.state.timer == t ? const Icon(Icons.check, color: AppColors.cyan) : null,
                onTap: () => Navigator.pop(context, t),
              ),
          ],
        ),
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
