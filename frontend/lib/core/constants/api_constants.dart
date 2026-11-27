import 'package:flutter/foundation.dart';

class ApiConstants {
  // Base URL default otomatis sesuai platform:
  // - Web / Windows Desktop: http://localhost/serfix/api
  // - Android Emulator: http://10.0.2.2/serfix/api
  // - HP Fisik Android: ganti ke IP Wi-Fi lokal server
  static String _customBaseUrl = '';

  static String get baseUrl {
    if (_customBaseUrl.isNotEmpty) return _customBaseUrl;

    if (kIsWeb || defaultTargetPlatform == TargetPlatform.windows) {
      return 'http://localhost/serfix/api';
    } else {
      // Android Emulator loopback
      return 'http://10.0.2.2/serfix/api';
    }
  }

  static void setCustomBaseUrl(String url) {
    _customBaseUrl = url.trim().replaceAll(RegExp(r'/$'), '');
  }

  static String get login => '$baseUrl/auth/login.php';
  static String get register => '$baseUrl/auth/register.php';
  static String get logout => '$baseUrl/auth/logout.php';
  static String get serviceCatalog => '$baseUrl/catalog/index.php';
  static String get serviceRequests => '$baseUrl/service_requests/index.php';
  static String get technicians => '$baseUrl/technicians/index.php';
  static String get staff => '$baseUrl/staff/index.php';
  static String get parts => '$baseUrl/parts/index.php';
  static String get areas => '$baseUrl/areas/index.php';
  static String get password => '$baseUrl/auth/password.php';
  static String get workOrders => '$baseUrl/work_orders/index.php';
  static String get payments => '$baseUrl/payments/index.php';
  static String get warranties => '$baseUrl/warranties/index.php';
  static String get summary => '$baseUrl/dashboard/index.php';
  static String get enhancements => '$baseUrl/enhancements/index.php';
}
