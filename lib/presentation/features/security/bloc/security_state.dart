part of 'security_bloc.dart';

sealed class SecurityState { const SecurityState(); }

final class SecurityLoading extends SecurityState {
  const SecurityLoading();
}

final class SecurityReady extends SecurityState {
  const SecurityReady({
    required this.encryption,
    this.busy = false,
    this.notice,
    this.phraseToShow,
  });

  final EncryptionState encryption;
  /// An action is running.
  final bool            busy;
  /// Shown once by the screen (an error or a confirmation).
  final String?         notice;
  /// A new recovery phrase waiting to be shown and confirmed. Never stored here beyond that.
  final String?         phraseToShow;

  SecurityReady copyWith({EncryptionState? encryption, bool? busy, String? notice, String? phraseToShow, bool clearPhrase = false}) =>
      SecurityReady(
        encryption:   encryption ?? this.encryption,
        busy:         busy ?? this.busy,
        notice:       notice,
        phraseToShow: clearPhrase ? null : (phraseToShow ?? this.phraseToShow),
      );
}
