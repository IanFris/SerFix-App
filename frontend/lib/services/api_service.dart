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
      final body = response.body.trim();
      if (body.isEmpty) {
        throw const ApiException(
            'Server tidak mengirimkan data respons.');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const ApiException('Format respon dari server tidak valid.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['status'] != 'success') {
        final message = decoded['message'];
        throw ApiException(
          message is String && message.isNotEmpty
              ? message
              : 'Gagal menghubungi server (HTTP ${response.statusCode}).',
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

  static Future<List<SerfixRequest>> getServiceRequests({
    String? status,
    int? categoryId,
    String? area,
    String? search,
  }) async {
    final uri = Uri.parse(ApiConstants.serviceRequests).replace(queryParameters: {
      if (status != null && status.isNotEmpty) 'status': status,
      if (categoryId != null) 'category_id': '$categoryId',
      if (area != null && area.isNotEmpty) 'area': area,
      if (search != null && search.isNotEmpty) 'search': search,
    });
    return _mapList(await _getData(uri.toString()))
          .map(SerfixRequest.fromJson)
          .toList();
  }

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
    int minimumStock = 3,
  }) async {
    await _postData(ApiConstants.parts, {
      if (id != null) 'id': id,
      'sku': sku,
      'name': name,
      'stock_quantity': stock,
      'minimum_stock': minimumStock,
      'unit_price': unitPrice,
      'description': description,
    });
  }

  static Future<List<Map<String, dynamic>>> getNotifications() async =>
      _mapList(await _getData(
          '${ApiConstants.enhancements}?action=notifications'));

  static Future<void> readNotifications() async =>
      await _postData(ApiConstants.enhancements,
          {'action': 'read_notifications'});

  static Future<List<Map<String, dynamic>>> getMessages(int requestId) async =>
      _mapList(await _getData(
          '${ApiConstants.enhancements}?action=messages&request_id=$requestId'));

  static Future<void> sendMessage(int requestId, String message) async =>
      await _postData(ApiConstants.enhancements,
          {'action': 'message', 'request_id': requestId, 'message': message});

  static Future<Map<String, dynamic>?> getTracking(int requestId) async {
    final data = await _getData(
        '${ApiConstants.enhancements}?action=tracking&request_id=$requestId');
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Future<void> updateTracking({
    required int requestId,
    required String status,
    double? latitude,
    double? longitude,
    int? etaMinutes,
    String note = '',
  }) async =>
      await _postData(ApiConstants.enhancements, {
        'action': 'tracking',
        'request_id': requestId,
        'status': status,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (etaMinutes != null) 'eta_minutes': etaMinutes,
        'note': note,
      });

  static Future<List<Map<String, dynamic>>> getAttachments(
          int requestId) async =>
      _mapList(await _getData(
          '${ApiConstants.enhancements}?action=attachments&request_id=$requestId'));

  static Future<void> uploadAttachment({
    required int requestId,
    required String kind,
    required String fileName,
    required String base64,
  }) async =>
      await _postData(ApiConstants.enhancements, {
        'action': 'attachment',
        'request_id': requestId,
        'kind': kind,
        'file_name': fileName,
        'base64': base64,
      });

  static Future<void> rescheduleRequest(
          int requestId, DateTime scheduledAt) async =>
      await _postData(ApiConstants.enhancements, {
        'action': 'reschedule',
        'request_id': requestId,
        'scheduled_at': scheduledAt.toIso8601String(),
      });

  static Future<Map<String, dynamic>?> getReview(int requestId) async {
    final data = await _getData(
        '${ApiConstants.enhancements}?action=review&request_id=$requestId');
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Future<void> saveReview(
          int requestId, int rating, String review) async =>
      await _postData(ApiConstants.enhancements, {
        'action': 'review',
        'request_id': requestId,
        'rating': rating,
        'review': review,
      });

  static Future<Map<String, dynamic>> createGatewayPayment(
    int requestId,
    String provider,
  ) async {
    final data = await _postData(ApiConstants.payments, {
      'action': 'gateway_create',
      'request_id': requestId,
      'provider': provider,
    });
    return data is Map ? Map<String, dynamic>.from(data) : {};
  }

  static Future<void> registerPushDevice(String token, String platform) =>
      _postData(ApiConstants.enhancements, {
        'action': 'register_push',
        'token': token,
        'platform': platform,
      });

  static Future<List<Map<String, dynamic>>> getAssets() async =>
      _mapList(await _getData('${ApiConstants.enhancements}?action=assets'));

  static Future<void> saveAsset({
    required String name,
    int? categoryId,
    String brand = '',
    String model = '',
    String serialNumber = '',
    String nextServiceAt = '',
    String notes = '',
  }) =>
      _postData(ApiConstants.enhancements, {
        'action': 'asset',
        'name': name,
        if (categoryId != null) 'category_id': categoryId,
        'brand': brand,
        'model': model,
        'serial_number': serialNumber,
        'next_service_at': nextServiceAt,
        'notes': notes,
      });

  static Future<Map<String, dynamic>?> getInvoice(int requestId) async {
    final data = await _getData(
        '${ApiConstants.enhancements}?action=invoice&request_id=$requestId');
    return data is Map ? Map<String, dynamic>.from(data) : null;
  }

  static Future<List<Map<String, dynamic>>> getReschedules(
          int requestId) async =>
      _mapList(await _getData(
          '${ApiConstants.enhancements}?action=reschedules&request_id=$requestId'));

  static Future<void> proposeReschedule({
    required int requestId,
    required DateTime scheduledAt,
    String reason = '',
  }) =>
      _postData(ApiConstants.enhancements, {
        'action': 'propose_reschedule',
        'request_id': requestId,
        'scheduled_at': scheduledAt.toIso8601String(),
        'reason': reason,
      });

  static Future<void> respondReschedule({
    required int requestId,
    required int proposalId,
    required String decision,
  }) =>
      _postData(ApiConstants.enhancements, {
        'action': 'respond_reschedule',
        'request_id': requestId,
        'proposal_id': proposalId,
        'decision': decision,
      });

  static Future<List<Map<String, dynamic>>> getTechnicianReport() async =>
      _mapList(await _getData(
          '${ApiConstants.enhancements}?action=technician_report'));

  static Future<Map<String, dynamic>> syncOfflineMutations(
          List<Map<String, dynamic>> mutations) async =>
      Map<String, dynamic>.from(await _postData(
          ApiConstants.enhancements,
          {'action': 'offline_sync', 'mutations': mutations}));

  static Future<void> requestPasswordOtp(String email) =>
      _postData(ApiConstants.password,
          {'action': 'request', 'email': email});

  static Future<void> resetPassword({
    required String email,
    required String otp,
    required String password,
  }) =>
      _postData(ApiConstants.password,
          {'action': 'reset', 'email': email, 'otp': otp, 'password': password});

  static Future<List<Map<String, dynamic>>> getServiceAreas() async =>
      _mapList(await _getData(ApiConstants.areas));

  static Future<void> saveServiceArea({
    int? id,
    required String name,
    required int radiusKm,
    required double travelFee,
    required String openingTime,
    required String closingTime,
    required String operatingDays,
  }) =>
      _postData(ApiConstants.areas, {
        if (id != null) 'id': id,
        'name': name,
        'radius_km': radiusKm,
        'travel_fee': travelFee,
        'opening_time': openingTime,
        'closing_time': closingTime,
        'operating_days': operatingDays,
      });

  static Future<List<Map<String, dynamic>>> getStockTransactions() async =>
      _mapList(await _getData('${ApiConstants.parts}?action=transactions'));

  static Future<void> adjustStock({
    required int partId,
    required String type,
    required int quantity,
    required double unitCost,
    String reference = '',
    String notes = '',
  }) =>
      _postData(ApiConstants.parts, {
        'action': 'stock_adjust',
        'part_id': partId,
        'type': type,
        'quantity': quantity,
        'unit_cost': unitCost,
        'reference': reference,
        'notes': notes,
      });
}
