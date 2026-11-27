import 'package:flutter/foundation.dart';

import '../models/serfix_models.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';

export '../models/serfix_models.dart';

class SerfixProvider extends ChangeNotifier {
  User? _user;
  List<ServiceCategory> _categories = [];
  List<SerfixRequest> _requests = [];
  List<SerfixTechnician> _technicians = [];
  List<SerfixPart> _parts = [];
  List<Map<String, dynamic>> _warranties = [];
  List<Map<String, dynamic>> _payments = [];
  List<Map<String, dynamic>> _staff = [];
  List<Map<String, dynamic>> _notifications = [];
  List<Map<String, dynamic>> _assets = [];
  List<Map<String, dynamic>> _technicianReport = [];
  Map<String, dynamic> _summary = {};
  bool _isLoading = false;
  String? _errorMessage;

  SerfixRole get role => switch (_user?.role) {
        'technician' => SerfixRole.technician,
        'admin' => SerfixRole.admin,
        'manager' => SerfixRole.manager,
        _ => SerfixRole.customer,
      };
  List<ServiceCategory> get categories => List.unmodifiable(_categories);
  List<SerfixRequest> get requests => List.unmodifiable(_requests);
  List<SerfixTechnician> get technicians => List.unmodifiable(_technicians);
  List<SerfixPart> get parts => List.unmodifiable(_parts);
  List<Map<String, dynamic>> get warranties => List.unmodifiable(_warranties);
  List<Map<String, dynamic>> get payments => List.unmodifiable(_payments);
  List<Map<String, dynamic>> get staff => List.unmodifiable(_staff);
  List<Map<String, dynamic>> get notifications =>
      List.unmodifiable(_notifications);
  List<Map<String, dynamic>> get assets => List.unmodifiable(_assets);
  List<Map<String, dynamic>> get technicianReport =>
      List.unmodifiable(_technicianReport);
  Map<String, dynamic> get summary => Map.unmodifiable(_summary);
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> load(User user) async {
    _user = user;
    await refresh();
  }

  Future<void> refresh() async {
    if (_user == null || _user!.isGuest) {
      _categories = [];
      _requests = [];
      _technicians = [];
      _parts = [];
      _warranties = [];
      _payments = [];
      _staff = [];
      _notifications = [];
      _assets = [];
      _technicianReport = [];
      _summary = {};
      _errorMessage = null;
      notifyListeners();
      return;
    }
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        ApiService.getServiceCatalog(),
        ApiService.getServiceRequests(),
        ApiService.getDashboardSummary(),
      ]);
      _categories = results[0] as List<ServiceCategory>;
      _requests = results[1] as List<SerfixRequest>;
      _summary = results[2] as Map<String, dynamic>;
      _notifications = await ApiService.getNotifications();
      if (role == SerfixRole.admin || role == SerfixRole.manager) {
        _technicians = await ApiService.getTechnicians();
        _parts = await ApiService.getParts();
        _warranties = await ApiService.getWarranties();
        _payments = await ApiService.getPayments();
        if (role == SerfixRole.admin) {
          _staff = await ApiService.getStaff();
        }
      } else if (role == SerfixRole.technician) {
        _parts = await ApiService.getParts();
      } else {
        _warranties = await ApiService.getWarranties();
        _assets = await ApiService.getAssets();
      }
      if (role == SerfixRole.admin || role == SerfixRole.manager) {
        _technicianReport = await ApiService.getTechnicianReport();
      }
      await SessionService.saveSerfixCache({
        'requests': _requests.map((item) => item.toJson()).toList(),
        'categories': _categories.map((item) => item.toJson()).toList(),
        'summary': _summary,
        'notifications': _notifications,
        'assets': _assets,
        'technicianReport': _technicianReport,
      });
    } catch (error) {
      final cached = await SessionService.getSerfixCache();
      if (cached != null) {
        _requests = (cached['requests'] as List? ?? [])
            .whereType<Map>()
            .map((item) =>
                SerfixRequest.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _categories = (cached['categories'] as List? ?? [])
            .whereType<Map>()
            .map((item) =>
                ServiceCategory.fromJson(Map<String, dynamic>.from(item)))
            .toList();
        _summary = Map<String, dynamic>.from(cached['summary'] as Map? ?? {});
        _notifications = (cached['notifications'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _assets = (cached['assets'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _technicianReport = (cached['technicianReport'] as List? ?? [])
            .whereType<Map>()
            .map(Map<String, dynamic>.from)
            .toList();
        _errorMessage =
            'Mode offline: menampilkan data terakhir yang tersimpan.';
      } else {
        _errorMessage = error.toString();
      }
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> createRequest({
    required int categoryId,
    required String deviceName,
    required String issue,
    required String address,
    required String area,
    required DateTime scheduledAt,
  }) async {
    await ApiService.createServiceRequest(
      categoryId: categoryId,
      deviceName: deviceName,
      issue: issue,
      address: address,
      area: area,
      scheduledAt: scheduledAt,
    );
    await refresh();
  }

  Future<void> assignRequest({
    required int requestId,
    required int technicianId,
    required DateTime scheduledAt,
  }) async {
    await ApiService.assignServiceRequest(
      requestId: requestId,
      technicianId: technicianId,
      scheduledAt: scheduledAt,
    );
    await refresh();
  }

  Future<List<SerfixTechnician>> findAvailableTechnicians(
    SerfixRequest request,
    DateTime scheduledAt,
  ) =>
      ApiService.getTechnicians(
        area: request.area,
        categoryId: request.categoryId,
        requestedAt: scheduledAt,
        durationMinutes: request.durationMinutes,
      );

  Future<void> approveEstimate(int requestId) async {
    await ApiService.updateServiceRequest(requestId, 'approve_estimate');
    await refresh();
  }

  Future<void> cancelRequest(int requestId) async {
    await ApiService.updateServiceRequest(requestId, 'cancel');
    await refresh();
  }

  Future<void> startWork(int requestId) async {
    await ApiService.updateWorkOrder(requestId, 'start');
    await refresh();
  }

  Future<void> saveWorkOrder({
    required int requestId,
    required String diagnosis,
    required String description,
    required String notes,
    required List<Map<String, int>> parts,
  }) async {
    await ApiService.updateWorkOrder(
      requestId,
      'save',
      diagnosis: diagnosis,
      description: description,
      notes: notes,
      parts: parts,
    );
    await refresh();
  }

  Future<void> completeWork(int requestId) async {
    await ApiService.updateWorkOrder(requestId, 'complete');
    await refresh();
  }

  Future<void> createPayment(
    int requestId,
    String method,
    String reference,
  ) async {
    await ApiService.createPayment(requestId, method, reference);
    await refresh();
  }

  Future<void> verifyPayment(int paymentId, String decision) async {
    await ApiService.verifyPayment(paymentId, decision);
    await refresh();
  }

  Future<void> claimWarranty(int warrantyId, String description) async {
    await ApiService.claimWarranty(warrantyId, description);
    await refresh();
  }

  Future<void> decideWarrantyClaim(
    int claimId,
    String decision,
    String notes,
  ) async {
    await ApiService.decideWarrantyClaim(claimId, decision, notes);
    await refresh();
  }

  Future<void> createStaff({
    required String name,
    required String email,
    required String password,
    required String role,
    String area = '',
    String phone = '',
    List<int> skills = const [],
  }) async {
    await ApiService.createStaff(
      name: name,
      email: email,
      password: password,
      role: role,
      area: area,
      phone: phone,
      skills: skills,
    );
    await refresh();
  }

  Future<void> readNotifications() async {
    await ApiService.readNotifications();
    await refresh();
  }

  Future<List<Map<String, dynamic>>> getMessages(int requestId) =>
      ApiService.getMessages(requestId);

  Future<void> sendMessage(int requestId, String message) =>
      ApiService.sendMessage(requestId, message);

  Future<Map<String, dynamic>?> getTracking(int requestId) =>
      ApiService.getTracking(requestId);

  Future<void> updateTracking({
    required int requestId,
    required String status,
    double? latitude,
    double? longitude,
    int? etaMinutes,
    String note = '',
  }) =>
      ApiService.updateTracking(
        requestId: requestId,
        status: status,
        latitude: latitude,
        longitude: longitude,
        etaMinutes: etaMinutes,
        note: note,
      );

  Future<List<Map<String, dynamic>>> getAttachments(int requestId) =>
      ApiService.getAttachments(requestId);

  Future<void> uploadAttachment({
    required int requestId,
    required String kind,
    required String fileName,
    required String base64,
  }) =>
      ApiService.uploadAttachment(
        requestId: requestId,
        kind: kind,
        fileName: fileName,
        base64: base64,
      );

  Future<void> rescheduleRequest(int requestId, DateTime scheduledAt) async {
    await ApiService.rescheduleRequest(requestId, scheduledAt);
    await refresh();
  }

  Future<Map<String, dynamic>?> getReview(int requestId) =>
      ApiService.getReview(requestId);

  Future<void> saveReview(int requestId, int rating, String review) =>
      ApiService.saveReview(requestId, rating, review);

  Future<void> savePart({
    int? id,
    required String sku,
    required String name,
    required int stock,
    required double unitPrice,
    String description = '',
  }) async {
    await ApiService.savePart(
      id: id,
      sku: sku,
      name: name,
      stock: stock,
      unitPrice: unitPrice,
      description: description,
    );
    await refresh();
  }

  Future<Map<String, dynamic>> createGatewayPayment(
          int requestId, String provider) =>
      ApiService.createGatewayPayment(requestId, provider);

  Future<void> registerPushDevice(String token, String platform) =>
      ApiService.registerPushDevice(token, platform);

  Future<List<Map<String, dynamic>>> getAssets() => ApiService.getAssets();

  Future<void> saveAsset({
    required String name,
    int? categoryId,
    String brand = '',
    String model = '',
    String serialNumber = '',
    String nextServiceAt = '',
    String notes = '',
  }) async {
    await ApiService.saveAsset(
      name: name,
      categoryId: categoryId,
      brand: brand,
      model: model,
      serialNumber: serialNumber,
      nextServiceAt: nextServiceAt,
      notes: notes,
    );
    await refresh();
  }

  Future<Map<String, dynamic>?> getInvoice(int requestId) =>
      ApiService.getInvoice(requestId);

  Future<List<Map<String, dynamic>>> getReschedules(int requestId) =>
      ApiService.getReschedules(requestId);

  Future<void> proposeReschedule({
    required int requestId,
    required DateTime scheduledAt,
    String reason = '',
  }) =>
      ApiService.proposeReschedule(
          requestId: requestId, scheduledAt: scheduledAt, reason: reason);

  Future<void> respondReschedule({
    required int requestId,
    required int proposalId,
    required String decision,
  }) =>
      ApiService.respondReschedule(
          requestId: requestId, proposalId: proposalId, decision: decision);

  Future<void> syncOfflineMutations(
      List<Map<String, dynamic>> mutations) async {
    await ApiService.syncOfflineMutations(mutations);
    await SessionService.clearSerfixMutations();
  }

  Future<List<SerfixRequest>> searchRequests({
    String? status,
    int? categoryId,
    String? area,
    String? search,
  }) =>
      ApiService.getServiceRequests(
          status: status, categoryId: categoryId, area: area, search: search);
}
