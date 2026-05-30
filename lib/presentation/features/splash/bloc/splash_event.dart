part of 'splash_bloc.dart';

sealed class SplashEvent { const SplashEvent(); }
final class SplashStarted extends SplashEvent {}
