import 'package:flutter/material.dart';
import '../screens/scan_screen.dart';
import '../screens/details_screen.dart';
import '../screens/history_screen.dart';
import '../screens/record_detail_screen.dart';
import '../screens/settings_screen.dart';

class AppRoutes {
  static const String scan = '/scan';
  static const String details = '/details';
  static const String history = '/history';
  static const String recordDetail = '/record-detail';
  static const String settings = '/settings';

  static Map<String, WidgetBuilder> get routes => {
    scan: (context) => const ScanScreen(),
    history: (context) => const HistoryScreen(),
    settings: (context) => const SettingsScreen(),
  };

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case details:
        final args = settings.arguments as Map<String, dynamic>?;
        return MaterialPageRoute(
          builder: (context) =>
              DetailsScreen(vehicleNo: args?['vehicleNo'] as String?),
        );
      case recordDetail:
        final scanId = settings.arguments as String;
        return MaterialPageRoute(
          builder: (context) => RecordDetailScreen(scanId: scanId),
        );
      default:
        return MaterialPageRoute(builder: (context) => const ScanScreen());
    }
  }
}
