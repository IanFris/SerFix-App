import 'package:flutter_test/flutter_test.dart';
import 'package:serfix/models/user.dart';
import 'package:serfix/providers/auth_provider.dart';
import 'package:serfix/providers/serfix_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('guest session enters the app without an API token', () async {
    SharedPreferences.setMockInitialValues({});
    final auth = AuthProvider();
    while (auth.isInitializing) {
      await Future<void>.delayed(Duration.zero);
    }

    await auth.startGuestSession();

    expect(auth.isAuthenticated, isTrue);
    expect(auth.isGuest, isTrue);
    expect(auth.currentUser?.name, 'Tamu');
    expect(auth.currentUser?.token, isNull);

    final serfix = SerfixProvider();
    await serfix.load(auth.currentUser!);
    expect(serfix.errorMessage, isNull);
    expect(serfix.requests, isEmpty);
  });

  test('User stores and restores the server-assigned SerFix role', () {
    final user = User(
      id: 8,
      name: 'Rizky',
      email: 'rizky@example.test',
      token: 'session-token',
      role: 'technician',
    );

    final restored = User.fromJson(user.toJson());
    expect(restored.id, 8);
    expect(restored.role, 'technician');
    expect(restored.token, 'session-token');
  });

  test('service request maps backend status, estimate, schedule, and warranty',
      () {
    final request = SerfixRequest.fromJson({
      'id': '42',
      'customer_id': 3,
      'customer_name': 'Nadia',
      'category_id': 1,
      'service_name': 'Servis AC',
      'device_name': 'AC 1 PK',
      'issue_description': 'Tidak dingin',
      'service_address': 'Jl. Melati',
      'service_area': 'Bandung',
      'requested_at': '2026-11-15 09:00:00',
      'duration_minutes': 120,
      'status': 'waiting_approval',
      'estimate_amount': '375000.00',
      'estimate_approved_at': null,
      'payment_status': 'unpaid',
      'warranty_months': 3,
      'warranty_ends_at': '2027-02-15',
      'parts': [
        {'id': 4, 'quantity': 1},
      ],
    });

    expect(request.id, 42);
    expect(request.status, ServiceRequestStatus.waitingApproval);
    expect(request.estimate, 375000);
    expect(request.parts, hasLength(1));
    expect(request.estimateApproved, isFalse);
    expect(request.warrantyEndsAt, DateTime(2027, 2, 15));
  });

  test('service catalog maps cost, duration and warranty defaults', () {
    final category = ServiceCategory.fromJson({
      'id': '2',
      'name': 'Perbaikan AC',
      'description': 'Diagnosis dan perbaikan',
      'base_fee': '200000.00',
      'default_duration_minutes': 150,
      'warranty_months': 3,
    });

    expect(category.baseFee, 200000);
    expect(category.durationMinutes, 150);
    expect(category.warrantyMonths, 3);
  });
}
