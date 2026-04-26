import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_config.dart';

class SettingsProvider extends ChangeNotifier {
  bool _isDarkMode = true;
  String _apiBaseUrl = ApiConfig.defaultBaseUrl;
  String _apiToken = '';
  bool _isLoading = false;

  bool get isDarkMode => _isDarkMode;
  String get apiBaseUrl => _apiBaseUrl;
  String get apiToken => _apiToken;
  bool get isLoading => _isLoading;

  /// Load settings from SharedPreferences
  Future<void> loadSettings() async {
    _isLoading = true;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('is_dark_mode') ?? true;
      _apiBaseUrl = await ApiConfig.getBaseUrl();
      _apiToken = (await ApiConfig.getApiToken()) ?? '';
    } catch (e) {
      debugPrint('Error loading settings: $e');
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Toggle dark/light mode
  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_dark_mode', _isDarkMode);
    notifyListeners();
  }

  /// Set the dashboard API base URL
  Future<void> setApiBaseUrl(String url) async {
    _apiBaseUrl = url;
    await ApiConfig.setBaseUrl(url);
    notifyListeners();
  }

  /// Set the API token
  Future<void> setApiToken(String token) async {
    _apiToken = token;
    await ApiConfig.setApiToken(token);
    notifyListeners();
  }
}
