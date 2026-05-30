part of 'theme_bloc.dart';
sealed class ThemeEvent { const ThemeEvent(); }
final class ThemeLoaded  extends ThemeEvent { const ThemeLoaded(); }
final class ThemeChanged extends ThemeEvent { ThemeChanged(this.id); final String id; }
