enum SerfixRole { customer, technician, admin, manager }

enum ServiceRequestStatus {
  requested,
  assigned,
  inProgress,
  waitingApproval,
  completed,
  cancelled,
}

int _requiredInt(dynamic value, String field) {
  if (value is num) return value.toInt();
  final parsed = int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    throw FormatException('Nilai $field dari server tidak valid.');
  }
  return parsed;
}

int _intOr(dynamic value, int fallback) =>
    value == null ? fallback : _requiredInt(value, 'angka');

double _doubleOr(dynamic value, double fallback) {
  if (value == null) return fallback;
  final parsed = value is num ? value.toDouble() : double.tryParse('$value');
  if (parsed == null || !parsed.isFinite) {
    throw const FormatException('Nilai biaya dari server tidak valid.');
  }
  return parsed;
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
        ServiceRequestStatus.assigned => 'Menunggu persetujuan',
        ServiceRequestStatus.inProgress => 'Sedang dikerjakan',
        ServiceRequestStatus.waitingApproval => 'Menunggu persetujuan biaya',
        ServiceRequestStatus.completed => 'Selesai',
        ServiceRequestStatus.cancelled => 'Dibatalkan',
      };
}

class ServiceCategory {
  const ServiceCategory({
    required this.id,
    required this.name,
    required this.description,
    required this.baseFee,
    required this.durationMinutes,
    required this.warrantyMonths,
  });

  final int id;
  final String name;
  final String description;
  final double baseFee;
  final int durationMinutes;
  final int warrantyMonths;

  factory ServiceCategory.fromJson(Map<String, dynamic> json) =>
      ServiceCategory(
        id: _requiredInt(json['id'], 'id'),
        name: json['name'] as String? ?? '',
        description: json['description'] as String? ?? '',
        baseFee: _doubleOr(json['base_fee'], 0),
        durationMinutes: _intOr(json['default_duration_minutes'], 120),
        warrantyMonths: _intOr(json['warranty_months'], 0),
      );
}

class SerfixTechnician {
  const SerfixTechnician({
    required this.id,
    required this.name,
    required this.area,
    required this.skills,
    required this.skillIds,
  });

  final int id;
  final String name;
  final String area;
  final String skills;
  final List<int> skillIds;

  factory SerfixTechnician.fromJson(Map<String, dynamic> json) =>
      SerfixTechnician(
        id: _requiredInt(json['id'], 'id'),
        name: json['name'] as String? ?? '',
        area: json['service_area'] as String? ?? '',
        skills: json['skills'] as String? ?? '',
        skillIds: (json['skill_ids'] as String? ?? '')
            .split(',')
            .where((value) => value.isNotEmpty)
            .map(int.parse)
            .toList(),
      );
}

class SerfixPart {
  const SerfixPart({
    required this.id,
    required this.sku,
    required this.name,
    required this.stock,
    required this.unitPrice,
  });

  final int id;
  final String sku;
  final String name;
  final int stock;
  final double unitPrice;

  factory SerfixPart.fromJson(Map<String, dynamic> json) => SerfixPart(
        id: _requiredInt(json['id'], 'id'),
        sku: json['sku'] as String? ?? '',
        name: json['name'] as String? ?? '',
        stock: _intOr(json['stock_quantity'], 0),
        unitPrice: _doubleOr(json['unit_price'], 0),
      );
}

class SerfixRequest {
  const SerfixRequest({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.categoryId,
    required this.service,
    required this.device,
    required this.issue,
    required this.address,
    required this.area,
    required this.scheduledAt,
    required this.durationMinutes,
    required this.status,
    required this.estimate,
    required this.paymentStatus,
    this.technicianName,
    this.technicianId,
    this.finalAmount,
    this.diagnosis,
    this.workDescription,
    this.technicianNotes,
    this.parts = const [],
    this.warrantyMonths = 0,
    this.warrantyEndsAt,
    this.estimateApproved = false,
  });

  final int id;
  final int customerId;
  final String customerName;
  final int categoryId;
  final String service;
  final String device;
  final String issue;
  final String address;
  final String area;
  final DateTime scheduledAt;
  final int durationMinutes;
  final ServiceRequestStatus status;
  final double estimate;
  final double? finalAmount;
  final String paymentStatus;
  final String? technicianName;
  final int? technicianId;
  final String? diagnosis;
  final String? workDescription;
  final String? technicianNotes;
  final List<Map<String, dynamic>> parts;
  final int warrantyMonths;
  final DateTime? warrantyEndsAt;
  final bool estimateApproved;

  factory SerfixRequest.fromJson(Map<String, dynamic> json) {
    final partsJson = json['parts'];
    final rawStatus = json['status'] as String? ?? 'requested';
    return SerfixRequest(
      id: _requiredInt(json['id'], 'id'),
      customerId: _intOr(json['customer_id'], 0),
      customerName: json['customer_name'] as String? ?? '',
      categoryId: _intOr(json['category_id'], 0),
      service: json['service_name'] as String? ?? '',
      device: json['device_name'] as String? ?? '',
      issue: json['issue_description'] as String? ?? '',
      address: json['service_address'] as String? ?? '',
      area: json['service_area'] as String? ?? '',
      scheduledAt: DateTime.tryParse(json['requested_at']?.toString() ?? '') ??
          DateTime.now(),
      durationMinutes: _intOr(json['duration_minutes'], 120),
      status: switch (rawStatus) {
        'assigned' => ServiceRequestStatus.assigned,
        'in_progress' => ServiceRequestStatus.inProgress,
        'waiting_approval' => ServiceRequestStatus.waitingApproval,
        'completed' => ServiceRequestStatus.completed,
        'cancelled' => ServiceRequestStatus.cancelled,
        _ => ServiceRequestStatus.requested,
      },
      estimate: _doubleOr(json['estimate_amount'], 0),
      finalAmount: json['final_amount'] == null
          ? null
          : _doubleOr(json['final_amount'], 0),
      paymentStatus: json['payment_status'] as String? ?? 'unpaid',
      technicianName: json['technician_name'] as String?,
      technicianId: json['technician_id'] == null
          ? null
          : _requiredInt(json['technician_id'], 'id teknisi'),
      diagnosis: json['diagnosis'] as String?,
      workDescription: json['work_description'] as String?,
      technicianNotes: json['technician_notes'] as String?,
      parts: partsJson is List
          ? partsJson.whereType<Map>().map(Map<String, dynamic>.from).toList()
          : const [],
      warrantyMonths: (json['warranty_months'] as num?)?.toInt() ?? 0,
      warrantyEndsAt:
          DateTime.tryParse(json['warranty_ends_at']?.toString() ?? ''),
      estimateApproved: json['estimate_approved_at'] != null,
    );
  }
}
