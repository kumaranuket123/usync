part of 'pairing_bloc.dart';

sealed class PairingState {}
final class PairingInitial extends PairingState {}
final class PairingLoading extends PairingState {}
final class CodeGenerated  extends PairingState { CodeGenerated(this.code); final String code; }
final class PairingSuccess extends PairingState { PairingSuccess(this.couple); final Couple couple; }
/// Someone entered this user's invite code.
final class PartnerJoined  extends PairingState {}
final class PairingError   extends PairingState { PairingError(this.message); final String message; }
