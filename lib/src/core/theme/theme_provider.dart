import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../di/service_locator.dart';

/// SharedPreferences key for persisting the selected theme mode.
const String kThemeModeKey = 'bandana_theme_mode';

/// Global singleton [ChangeNotifier] for app theme mode.
/// Allows direct observation via [ListenableBuilder] without requiring [ProviderScope],
/// ensuring full compatibility with both standalone widget tests and Riverpod.
class ThemeModeManager extends ChangeNotifier {
  static final ThemeModeManager instance = ThemeModeManager._();
  ThemeModeManager._() {
    init();
  }

  ThemeMode _themeMode = ThemeMode.system;
  ThemeMode get themeMode => _themeMode;

  /// Initializes the theme mode from SharedPreferences if available.
  void init([SharedPreferences? prefs]) {
    try {
      final p = prefs ??
          (getIt.isRegistered<SharedPreferences>() ? getIt<SharedPreferences>() : null);
      if (p != null) {
        final saved = p.getString(kThemeModeKey);
        if (saved == 'light') {
          _themeMode = ThemeMode.light;
        } else if (saved == 'dark') {
          _themeMode = ThemeMode.dark;
        } else {
          _themeMode = ThemeMode.system;
        }
        notifyListeners();
      }
    } catch (_) {}
  }

  /// Sets and persists the theme mode.
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    try {
      final p = getIt.isRegistered<SharedPreferences>()
          ? getIt<SharedPreferences>()
          : await SharedPreferences.getInstance();
      if (mode == ThemeMode.light) {
        await p.setString(kThemeModeKey, 'light');
      } else if (mode == ThemeMode.dark) {
        await p.setString(kThemeModeKey, 'dark');
      } else {
        await p.remove(kThemeModeKey);
      }
    } catch (_) {}
  }

  /// Toggles between light and dark mode based on current mode and brightness.
  Future<void> toggle(Brightness currentBrightness) async {
    if (_themeMode == ThemeMode.dark) {
      await setThemeMode(ThemeMode.light);
    } else if (_themeMode == ThemeMode.light) {
      await setThemeMode(ThemeMode.dark);
    } else {
      // System mode: switch to the opposite of current active brightness
      if (currentBrightness == Brightness.dark) {
        await setThemeMode(ThemeMode.light);
      } else {
        await setThemeMode(ThemeMode.dark);
      }
    }
  }
}

/// Global theme manager instance.
final themeModeManager = ThemeModeManager.instance;

/// Riverpod notifier bridging [ThemeModeManager].
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    themeModeManager.addListener(_sync);
    ref.onDispose(() => themeModeManager.removeListener(_sync));
    return themeModeManager.themeMode;
  }

  void _sync() {
    state = themeModeManager.themeMode;
  }

  Future<void> setThemeMode(ThemeMode mode) => themeModeManager.setThemeMode(mode);
  Future<void> toggle(Brightness currentBrightness) => themeModeManager.toggle(currentBrightness);
}

/// Riverpod provider for application [ThemeMode].
final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(
  ThemeModeNotifier.new,
);
