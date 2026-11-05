import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-level preferences: theme, display name, onboarding and push reminders.
class SettingsProvider with ChangeNotifier {
  static const _kThemeMode = 'theme_mode';
  static const _kUserName = 'user_name';
  static const _kOnboarded = 'onboarded';
  static const _kPush = 'push_reminders';

  ThemeMode _themeMode = ThemeMode.system;
  String? _userName;
  bool _loaded = false;
  bool _onboarded = false;
  bool _pushReminders = true;

  ThemeMode get themeMode => _themeMode;
  String? get userName => _userName;
  bool get loaded => _loaded;
  bool get onboarded => _onboarded;
  bool get pushReminders => _pushReminders;

  SettingsProvider({bool autoLoad = true}) {
    if (autoLoad) _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _themeMode = switch (prefs.getString(_kThemeMode)) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    _userName = prefs.getString(_kUserName);
    // Users upgrading from <= 2.2 already went through the old first-run
    // name prompt; don't send them through onboarding again.
    _onboarded = prefs.getBool(_kOnboarded) ??
        (prefs.containsKey(_kUserName) || prefs.containsKey('auto_sync'));
    _pushReminders = prefs.getBool(_kPush) ?? true;
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

  Future<void> completeOnboarding() async {
    _onboarded = true;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kOnboarded, true);
  }

  Future<void> setPushReminders(bool on) async {
    _pushReminders = on;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kPush, on);
  }

  /// Time-of-day greeting, personalized if a name is set.
  String greeting([DateTime? at]) {
    final h = (at ?? DateTime.now()).hour;
    final part = h < 12
        ? 'Good morning'
        : h < 17
            ? 'Good afternoon'
            : 'Good evening';
    return (_userName != null && _userName!.isNotEmpty) ? '$part, $_userName' : part;
  }
}
