import 'package:flutter/foundation.dart';

enum SerfixRole { customer, technician, admin, manager }

enum ServiceRequestStatus {
  requested,
  scheduled,
  inProgress,
  waitingApproval,
  completed
}

extension SerfixRoleLabel on SerfixRole {
  String get label => switch (this) {
        SerfixRole.customer => 'Pelanggan',
        SerfixRole.technician => 'Teknisi',
        SerfixRole.admin => 'Admin',
        SerfixRole.manager => 'Manajer',
      };
}

extension ServiceRequestStatusLabel on ServiceRequestStatus {
  String get label => switch (this) {
        ServiceRequestStatus.requested => 'Menunggu penugasan',
        ServiceRequestStatus.scheduled => 'Teknisi ditugaskan',
        ServiceRequestStatus.inProgress => 'Sedang dikerjakan',
        ServiceRequestStatus.waitingApproval => 'Menunggu persetujuan biaya',
        ServiceRequestStatus.completed => 'Selesai',
      };
}

class SerfixRequest {
  const SerfixRequest({
    required this.id,
    required this.customerName,
    required this.service,
    required this.device,
    required this.address,
    required this.scheduledAt,
    required this.status,
    required this.estimate,
    this.technicianName,
    this.technicianId,
    this.parts = const [],
    this.warrantyMonths = 0,
  });

  final int id;
  final String customerName;
  final String service;
  final String device;
  final String address;
  final DateTime scheduledAt;
  final ServiceRequestStatus status;
  final int estimate;
  final String? technicianName;
  final int? technicianId;
  final List<String> parts;
  final int warrantyMonths;

  DateTime get scheduledEnd => scheduledAt.add(const Duration(hours: 2));
}

class SerfixProvider extends ChangeNotifier {
  SerfixRole _role = SerfixRole.customer;
  int _nextId = 1004;
  final List<SerfixRequest> _requests = [];

  SerfixProvider() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final lastWeek = DateTime.now().subtract(const Duration(days: 7));
    _requests.addAll([
      SerfixRequest(
        id: 1001,
        customerName: 'Nadia Putri',
        service: 'Servis AC',
        device: 'AC Daikin 1 PK',
        address: 'Jl. Melati No. 8, Bandung',
        scheduledAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 9),
        status: ServiceRequestStatus.scheduled,
        estimate: 350000,
        technicianName: 'Rizky Pratama',
        technicianId: 7,
      ),
      SerfixRequest(
        id: 1002,
        customerName: 'Budi Santoso',
        service: 'Perbaikan kulkas',
        device: 'Kulkas 2 pintu',
        address: 'Jl. Anggrek No. 10, Bandung',
        scheduledAt: DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10),
        status: ServiceRequestStatus.inProgress,
        estimate: 425000,
        technicianName: 'Rizky Pratama',
        technicianId: 7,
        parts: ['Relay starter'],
      ),
      SerfixRequest(
        id: 1003,
        customerName: 'Nadia Putri',
        service: 'Perbaikan mesin cuci',
        device: 'Mesin cuci front load',
        address: 'Jl. Melati No. 8, Bandung',
        scheduledAt: DateTime(lastWeek.year, lastWeek.month, lastWeek.day, 13),
        status: ServiceRequestStatus.completed,
        estimate: 280000,
        technicianName: 'Dewi Lestari',
        technicianId: 9,
        parts: ['Selang pembuangan'],
        warrantyMonths: 3,
      ),
    ]);
  }

  SerfixRole get role => _role;
  List<SerfixRequest> get requests => List.unmodifiable(_requests);
  List<SerfixRequest> get technicianRequests => List.unmodifiable(
      _requests.where((request) => request.technicianId == 7));

  void setRole(SerfixRole role) {
    if (_role == role) return;
    _role = role;
    notifyListeners();
  }

  bool hasTechnicianConflict(SerfixRequest request) {
    if (request.technicianId == null) return false;
    return _requests.any((other) =>
        other.id != request.id &&
        other.technicianId == request.technicianId &&
        other.scheduledAt.year == request.scheduledAt.year &&
        other.scheduledAt.month == request.scheduledAt.month &&
        other.scheduledAt.day == request.scheduledAt.day &&
        request.scheduledAt.isBefore(other.scheduledEnd) &&
        other.scheduledAt.isBefore(request.scheduledEnd));
  }

  bool isSlotAvailable(DateTime slot) {
    return !_requests.any((request) =>
        request.status != ServiceRequestStatus.completed &&
        request.scheduledAt.year == slot.year &&
        request.scheduledAt.month == slot.month &&
        request.scheduledAt.day == slot.day &&
        slot.isBefore(request.scheduledEnd) &&
        request.scheduledAt.isBefore(slot.add(const Duration(hours: 2))));
  }

  void createRequest({
    required String customerName,
    required String service,
    required String device,
    required String address,
    required DateTime scheduledAt,
  }) {
    if (!isSlotAvailable(scheduledAt)) {
      throw StateError(
          'Jadwal tersebut berbenturan. Silakan pilih waktu lain.');
    }
    _requests.insert(
      0,
      SerfixRequest(
        id: _nextId++,
        customerName: customerName,
        service: service,
        device: device,
        address: address,
        scheduledAt: scheduledAt,
        status: ServiceRequestStatus.requested,
        estimate: service == 'Servis AC' ? 350000 : 300000,
      ),
    );
    notifyListeners();
  }
}
