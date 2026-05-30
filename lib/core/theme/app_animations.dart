import 'package:flutter/material.dart';

abstract final class AppAnimations {
  // ── Durations ─────────────────────────────────────────────────
  static const Duration instant    = Duration(milliseconds: 100);
  static const Duration fast       = Duration(milliseconds: 200);
  static const Duration normal     = Duration(milliseconds: 350);
  static const Duration slow       = Duration(milliseconds: 550);
  static const Duration xslow      = Duration(milliseconds: 800);

  static const Duration logoIn     = Duration(milliseconds: 1300);
  static const Duration splashHold = Duration(seconds: 3);
  static const Duration pulseRing  = Duration(milliseconds: 2800);
  static const Duration orbSpin    = Duration(seconds: 8);
  static const Duration orbSpinSlow= Duration(seconds: 14);
  static const Duration breathe    = Duration(milliseconds: 3500);
  static const Duration floatUp    = Duration(seconds: 6);
  static const Duration bubble     = Duration(milliseconds: 3800);
  static const Duration heartbeat  = Duration(milliseconds: 900);
  static const Duration successPop = Duration(milliseconds: 600);

  // ── Curves ────────────────────────────────────────────────────
  static const Curve elastic    = Cubic(0.34, 1.56, 0.64, 1);
  static const Curve pageSlide  = Cubic(0.4, 0.0, 0.2, 1);
  static const Curve breatheCurve = Curves.easeInOut;
  static const Curve standard   = Curves.easeInOut;
}
