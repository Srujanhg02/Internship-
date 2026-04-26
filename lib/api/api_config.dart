import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String _keyBaseUrl = 'api_base_url';
  static const String _keyApiToken = 'api_token';

  // Default dashboard API URL
  static const String defaultBaseUrl = 'http://192.168.1.55:3000';
  static const String scanEndpoint = '/api/dock/scan';

  // Default API token for mobile app authentication
  static const String defaultApiToken = 'SMARTDOCK_MOBILE_SECURE_TOKEN_2026';

  /// Get the configured dashboard base URL
  static Future<String> getBaseUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyBaseUrl) ?? defaultBaseUrl;
  }

  /// Set the dashboard base URL
  static Future<void> setBaseUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyBaseUrl, url);
  }

  /// Get the API authorization token
  static Future<String?> getApiToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyApiToken) ?? defaultApiToken;
  }

  /// Set the API authorization token
  static Future<void> setApiToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyApiToken, token);
  }

  /// Get the full scan endpoint URL
  static Future<String> getScanUrl() async {
    final baseUrl = await getBaseUrl();
    return '$baseUrl$scanEndpoint';
  }

  /// Check if API is configured
  static Future<bool> isConfigured() async {
    final baseUrl = await getBaseUrl();
    return baseUrl.isNotEmpty && baseUrl != defaultBaseUrl;
  }
}
