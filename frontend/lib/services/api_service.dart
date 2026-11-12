import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../models/serfix_models.dart';
import '../models/user.dart';
import 'session_service.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ApiService {
  static Future<Map<String, String>> _headers({
    bool jsonContentType = false,
    String? tokenOverride,
  }) async {
    final token = tokenOverride ?? (await SessionService.getUser())?.token;
    if (token == null || token.isEmpty) {
      throw const ApiException(
          'Sesi login tidak valid. Silakan login kembali.', 401);
    }
    return {
      if (jsonContentType) 'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  static Map<String, dynamic> _response(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException('Format respon dari server tidak valid.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['status'] != 'success') {
        throw ApiException(
          decoded['message'] as String? ??
              'Gagal menghubungi server (HTTP ${response.statusCode}).',
          response.statusCode,
        );
      }
      return decoded;
    } on FormatException {
      throw const ApiException('Format respon dari server tidak valid.');
    }
  }

  static Future<dynamic> _getData(String url) async {
    final response = await http.get(
      Uri.parse(url),
      headers: await _headers(),
    );
    return _response(response)['data'];
  }

  static Future<dynamic> _postData(
      String url, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse(url),
      headers: await _headers(jsonContentType: true),
      body: jsonEncode(body),
    );
    return _response(response)['data'];
  }

  static List<Map<String, dynamic>> _mapList(dynamic value) {
    if (value is! List) {
      throw const ApiException('Format daftar dari server tidak valid.');
    }
    return value.whereType<Map>().map(Map<String, dynamic>.from).toList();
  }

  static Future<User> login(String email, String password) async {
    final response = await http.post(
      Uri.parse(ApiConstants.login),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email, 'password': password}),
    );
    final data = _response(response)['data'] as Map<String, dynamic>;
    final userData = Map<String, dynamic>.from(
      data['user'] as Map<String, dynamic>,
    )..['token'] = data['token'];
    return User.fromJson(userData);
  }

  static Future<User> register(
    String name,
    String email,
    String password,
  ) async {
    final response = await http.post(
      Uri.parse(ApiConstants.register),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'name': name, 'email': email, 'password': password}),
    );
    final data = _response(response)['data'] as Map<String, dynamic>;
    final userData = Map<String, dynamic>.from(
      data['user'] as Map<String, dynamic>,
    )..['token'] = data['token'];
    return User.fromJson(userData);
  }

  static Future<void> logout(String token) async {
    final response = await http
        .post(
          Uri.parse(ApiConstants.logout),
          headers: await _headers(tokenOverride: token),
        )
        .timeout(const Duration(seconds: 5));
    _response(response);
  }

  static Future<List<ServiceCategory>> getServiceCatalog() async =>
      _mapList(await _getData(ApiConstants.serviceCatalog))
          .map(ServiceCategory.fromJson)
          .toList();

  static Future<List<SerfixRequest>> getServiceRequests() async =>
      _mapList(await _getData(ApiConstants.serviceRequests))
          .map(SerfixRequest.fromJson)
          .toList();

  static Future<Map<String, dynamic>> getDashboardSummary() async {
    final data = await _getData(ApiConstants.summary);
    if (data is! Map) {
      throw const ApiException('Format ringkasan SerFix tidak valid.');
    }
    return Map<String, dynamic>.from(data);
  }

  static Future<List<SerfixTechnician>> getTechnicians({
    String? area,
    int? categoryId,
    DateTime? requestedAt,
    int? durationMinutes,
  }) async {
    final uri = Uri.parse(ApiConstants.technicians).replace(queryParameters: {
      if (area != null) 'area': area,
      if (categoryId != null) 'category_id': '$categoryId',
      if (requestedAt != null) 'requested_at': requestedAt.toIso8601String(),
      if (durationMinutes != null) 'duration_minutes': '$durationMinutes',
    });
    return _mapList(await _getData(uri.toString()))
        .map(SerfixTechnician.fromJson)
        .toList();
  }

  static Future<List<Map<String, dynamic>>> getStaff() async =>
      _mapList(await _getData(ApiConstants.staff));

  static Future<List<SerfixPart>> getParts() async =>
      _mapList(await _getData(ApiConstants.parts))
          .map(SerfixPart.fromJson)
          .toList();

  static Future<List<Map<String, dynamic>>> getWarranties() async =>
      _mapList(await _getData(ApiConstants.warranties));

  static Future<List<Map<String, dynamic>>> getPayments() async =>
      _mapList(await _getData(ApiConstants.payments));

  static Future<void> createServiceRequest({
    required int categoryId,
    required String deviceName,
    required String issue,
    required String address,
    required String area,
    required DateTime scheduledAt,
  }) async {
    await _postData(ApiConstants.serviceRequests, {
      'action': 'create',
      'category_id': categoryId,
      'device_name': deviceName,
      'issue_description': issue,
      'service_address': address,
      'service_area': area,
      'requested_at': scheduledAt.toIso8601String(),
    });
  }

  static Future<void> assignServiceRequest({
    required int requestId,
    required int technicianId,
    required DateTime scheduledAt,
  }) async {
    await _postData(ApiConstants.serviceRequests, {
      'action': 'assign',
      'request_id': requestId,
      'technician_id': technicianId,
      'scheduled_at': scheduledAt.toIso8601String(),
    });
  }

  static Future<void> updateServiceRequest(int requestId, String action) async {
    await _postData(ApiConstants.serviceRequests, {
      'action': action,
      'request_id': requestId,
    });
  }

  static Future<void> updateWorkOrder(
    int requestId,
    String action, {
    String diagnosis = '',
    String description = '',
    String notes = '',
    List<Map<String, int>> parts = const [],
  }) async {
    await _postData(ApiConstants.workOrders, {
      'request_id': requestId,
      'action': action,
      'diagnosis': diagnosis,
      'work_description': description,
      'technician_notes': notes,
      'parts': parts,
    });
  }

  static Future<void> createPayment(
    int requestId,
    String method,
    String reference,
  ) async {
    await _postData(ApiConstants.payments, {
      'action': 'create',
      'request_id': requestId,
      'method': method,
      'reference': reference,
    });
  }

  static Future<void> verifyPayment(int paymentId, String decision) async {
    await _postData(ApiConstants.payments, {
      'action': 'verify',
      'payment_id': paymentId,
      'decision': decision,
    });
  }

  static Future<void> claimWarranty(int warrantyId, String description) async {
    await _postData(ApiConstants.warranties, {
      'action': 'claim',
      'warranty_id': warrantyId,
      'description': description,
    });
  }

  static Future<void> decideWarrantyClaim(
    int claimId,
    String decision,
    String notes,
  ) async {
    await _postData(ApiConstants.warranties, {
      'action': 'decide',
      'claim_id': claimId,
      'decision': decision,
      'decision_notes': notes,
    });
  }

  static Future<void> createStaff({
    required String name,
    required String email,
    required String password,
    required String role,
    String area = '',
    String phone = '',
    List<int> skills = const [],
  }) async {
    await _postData(ApiConstants.staff, {
      'name': name,
      'email': email,
      'password': password,
      'role': role,
      'service_area': area,
      'phone': phone,
      'skill_ids': skills,
    });
  }

  static Future<void> savePart({
    int? id,
    required String sku,
    required String name,
    required int stock,
    required double unitPrice,
    String description = '',
  }) async {
    await _postData(ApiConstants.parts, {
      if (id != null) 'id': id,
      'sku': sku,
      'name': name,
      'stock_quantity': stock,
      'unit_price': unitPrice,
      'description': description,
    });
  }
}
