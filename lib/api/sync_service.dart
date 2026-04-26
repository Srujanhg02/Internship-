import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../db/database_helper.dart';
import 'api_config.dart';

/// Response from a scan API call.
class ScanResponse {
  final bool success;
  final String action; // "ARRIVAL" or "DEPARTURE"
  final String? message;
  final String? error; // Server error message on failure

  ScanResponse({
    required this.success,
    this.action = '',
    this.message,
    this.error,
  });
}

class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      sendTimeout: const Duration(seconds: 30),
    ),
  );

  final DatabaseHelper _db = DatabaseHelper();

  /// Send a vehicle scan to the dashboard.
  /// The server determines whether this is an ARRIVAL or DEPARTURE.
  Future<ScanResponse> scanVehicle(String vehicleNo) async {
    try {
      final url = await ApiConfig.getScanUrl();
      final token = await ApiConfig.getApiToken();

      final response = await _dio.post(
        url,
        data: {'vehicleNo': vehicleNo},
        options: Options(
          headers: {
            'Content-Type': 'application/json',
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
            'bypass-tunnel-reminder': 'true', // for localtunnel
            'ngrok-skip-browser-warning': 'true', // for ngrok
          },
          // Don't throw on non-2xx so we can read the error body
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = response.data;

      if (response.statusCode == 200 || response.statusCode == 201) {
        return ScanResponse(
          success: true,
          action: data?['action'] as String? ?? '',
          message: data?['message'] as String?,
        );
      }

      // Server rejected it (e.g., no pending slots)
      return ScanResponse(
        success: false,
        error: data?['error'] as String? ?? 'Server rejected the scan',
      );
    } on DioException catch (e) {
      _logError('Scan failed for $vehicleNo', e);
      // Try to extract error from server response body
      final errorMsg = e.response?.data?['error'] as String?;
      return ScanResponse(
        success: false,
        error: errorMsg ?? 'Network error: Check Wi-Fi and server connection',
      );
    } catch (e) {
      _logError('Unexpected error scanning $vehicleNo', e);
      return ScanResponse(
        success: false,
        error: 'Network error: Check Wi-Fi and server connection',
      );
    }
  }

  /// Sync all entries with retry logic
  Future<SyncResult> syncAllPending() async {
    final entries = await _db.getAllEntries();

    if (entries.isEmpty) {
      return SyncResult(total: 0, success: 0, failed: 0);
    }

    int successCount = 0;
    int failCount = 0;

    for (final entry in entries) {
      bool synced = false;

      for (int attempt = 1; attempt <= 3; attempt++) {
        final result = await scanVehicle(entry.vehicleNo);
        synced = result.success;
        if (synced) break;

        if (attempt < 3) {
          await Future.delayed(Duration(seconds: 1 << (attempt - 1)));
        }
      }

      if (synced) {
        successCount++;
      } else {
        failCount++;
      }
    }

    return SyncResult(
      total: entries.length,
      success: successCount,
      failed: failCount,
    );
  }

  /// Test the API connection
  Future<bool> testConnection() async {
    try {
      final baseUrl = await ApiConfig.getBaseUrl();
      final token = await ApiConfig.getApiToken();

      // We just hit the base URL to see if the server is alive.
      // Even a 404 means the Next.js server successfully responded!
      await _dio.get(
        baseUrl,
        options: Options(
          headers: {
            if (token != null && token.isNotEmpty)
              'Authorization': 'Bearer $token',
            'bypass-tunnel-reminder': 'true', // for localtunnel
            'ngrok-skip-browser-warning': 'true', // for ngrok
          },
          validateStatus: (status) => true, // Any status means it's connected
        ),
      );

      return true; // Reached the server successfully
    } catch (e) {
      return false; // Network error or timeout
    }
  }

  void _logError(String message, dynamic error) {
    debugPrint('[SyncService] $message: $error');
  }
}

class SyncResult {
  final int total;
  final int success;
  final int failed;

  SyncResult({
    required this.total,
    required this.success,
    required this.failed,
  });

  bool get allSynced => failed == 0 && total > 0;
  bool get hasFailures => failed > 0;
}
