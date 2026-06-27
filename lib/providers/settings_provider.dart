import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level preferences: theme mode and the user's display name.
class SettingsProvider with ChangeNotifier {
  static const _kThemeMode = 'theme_mode';
  static const _kUserName = 'user_name';

  ThemeMode _themeMode = ThemeMode.system;
  String? _userName;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;
  String? get userName => _userName;
  bool get loaded => _loaded;

  /// True once prefs are loaded and the user hasn't been onboarded yet.
  /// (An empty string means "asked but skipped", so we don't prompt again.)
  bool get needsName => _loaded && _userName == null;

  SettingsProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    switch (prefs.getString(_kThemeMode)) {
      case 'light':
        _themeMode = ThemeMode.light;
      case 'dark':
        _themeMode = ThemeMode.dark;
      default:
        _themeMode = ThemeMode.system;
    }
    _userName = prefs.getString(_kUserName);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemeMode, mode.name);
  }

  Future<void> setUserName(String name) async {
    _userName = name.trim();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUserName, _userName!);
  }

  /// Time-of-day greeting, personalized if a name is set.
  String greeting() {
    final h = DateTime.now().hour;
    final part = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    return (_userName != null && _userName!.isNotEmpty) ? '$part, $_userName' : part;
  }
}
