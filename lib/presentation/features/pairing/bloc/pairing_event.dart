part of 'pairing_bloc.dart';

sealed class PairingEvent { const PairingEvent(); }
final class GenerateCodeRequested  extends PairingEvent { GenerateCodeRequested(this.userId); final String userId; }
final class JoinWithCodeRequested  extends PairingEvent { JoinWithCodeRequested({required this.code, required this.userId}); final String code, userId; }
final class PairingReset           extends PairingEvent {}
