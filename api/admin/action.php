<?php
declare(strict_types=1);

require_once __DIR__ . '/bootstrap.php';
admin_require_login();
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    http_response_code(405);
    header('Allow: POST');
    exit('Metode tidak diizinkan.');
}

admin_verify_csrf();
$db = admin_db();
$action = (string)($_POST['action'] ?? '');
$page = match ($action) {
    'assign_request' => 'requests',
    'create_staff', 'update_technician' => 'staff',
    'save_part' => 'parts',
    'verify_payment' => 'payments',
    'decide_claim' => 'warranties',
    default => 'overview',
};

try {
    if ($action === 'create_staff') {
        $name = trim((string)($_POST['name'] ?? ''));
        $email = strtolower(trim((string)($_POST['email'] ?? '')));
        $password = (string)($_POST['password'] ?? '');
        $role = (string)($_POST['role'] ?? '');
        $area = trim((string)($_POST['service_area'] ?? ''));
        $phone = trim((string)($_POST['phone'] ?? ''));
        $skillIds = $_POST['skill_ids'] ?? [];
        if ($name === '' || strlen($name) > 100 || !filter_var($email, FILTER_VALIDATE_EMAIL) ||
            strlen($email) > 150 || strlen($password) < 8 || strlen($password) > 72 ||
            !in_array($role, ['technician', 'admin', 'manager'], true) ||
            ($role === 'technician' && ($area === '' || strlen($area) > 120 || !is_array($skillIds) || $skillIds === []))) {
            admin_set_flash('error', 'Data akun staf tidak valid; teknisi harus memiliki area dan keahlian.');
            admin_redirect($page);
        }
        $skills = [];
        foreach ($skillIds as $skillId) {
            $parsed = filter_var($skillId, FILTER_VALIDATE_INT);
            if ($parsed === false || $parsed === null || $parsed < 1) {
                admin_set_flash('error', 'Daftar keahlian teknisi tidak valid.');
                admin_redirect($page);
            }
            $skills[] = (int)$parsed;
        }
        $db->beginTransaction();
        $stmt = $db->prepare(
            'INSERT INTO users (name, email, password_hash, role)
             VALUES (:name, :email, :password_hash, :role)'
        );
        $stmt->execute([
            ':name' => $name,
            ':email' => $email,
            ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
            ':role' => $role,
        ]);
        $userId = (int)$db->lastInsertId();
        if ($role === 'technician') {
            $profile = $db->prepare(
                'INSERT INTO technician_profiles (user_id, service_area, phone)
                 VALUES (:user_id, :area, :phone)'
            );
            $profile->execute([':user_id' => $userId, ':area' => $area, ':phone' => $phone ?: null]);
            $skill = $db->prepare(
                'INSERT INTO technician_skills (technician_id, category_id)
                 VALUES (:technician_id, :category_id)'
            );
            foreach (array_unique($skills) as $skillId) {
                $skill->execute([':technician_id' => $userId, ':category_id' => $skillId]);
            }
        }
        $db->commit();
        admin_set_flash('success', 'Akun staf berhasil dibuat.');
        admin_redirect($page);
    }

    if ($action === 'update_technician') {
        $id = filter_input(INPUT_POST, 'id', FILTER_VALIDATE_INT);
        $available = filter_input(INPUT_POST, 'is_available', FILTER_VALIDATE_INT);
        if (!$id || !in_array($available, [0, 1], true)) {
            admin_set_flash('error', 'Status teknisi tidak valid.');
            admin_redirect($page);
        }
        $stmt = $db->prepare(
            'UPDATE technician_profiles SET is_available = :available WHERE user_id = :id'
        );
        $stmt->execute([':available' => $available, ':id' => $id]);
        admin_set_flash('success', 'Status ketersediaan teknisi diperbarui.');
        admin_redirect($page);
    }

    if ($action === 'assign_request') {
        $requestId = filter_input(INPUT_POST, 'request_id', FILTER_VALIDATE_INT);
        $technicianId = filter_input(INPUT_POST, 'technician_id', FILTER_VALIDATE_INT);
        $rawSchedule = trim((string)($_POST['scheduled_at'] ?? ''));
        try {
            $scheduledAt = (new DateTimeImmutable($rawSchedule))->format('Y-m-d H:i:s');
        } catch (Throwable) {
            $scheduledAt = '';
        }
        if (!$requestId || !$technicianId || $scheduledAt === '' ||
            new DateTimeImmutable($scheduledAt) <= new DateTimeImmutable()) {
            admin_set_flash('error', 'Pilih teknisi dan jadwal mendatang yang valid.');
            admin_redirect($page);
        }
        $db->beginTransaction();
        $requestStmt = $db->prepare('SELECT * FROM service_requests WHERE id = :id FOR UPDATE');
        $requestStmt->execute([':id' => $requestId]);
        $request = $requestStmt->fetch(PDO::FETCH_ASSOC);
        if (!$request || $request['status'] !== 'requested') {
            $db->rollBack();
            admin_set_flash('error', 'Pengajuan tidak ditemukan atau sudah ditugaskan.');
            admin_redirect($page);
        }
        $technician = $db->prepare(
            'SELECT tp.user_id FROM technician_profiles tp
             JOIN users u ON u.id = tp.user_id
             JOIN technician_skills ts ON ts.technician_id = tp.user_id
             WHERE tp.user_id = :id AND tp.is_available = 1 AND u.role = "technician"
               AND ts.category_id = :category_id
               AND LOWER(TRIM(tp.service_area)) = LOWER(TRIM(:area))
             FOR UPDATE'
        );
        $technician->execute([
            ':id' => $technicianId,
            ':category_id' => $request['category_id'],
            ':area' => $request['service_area'],
        ]);
        if ($technician->fetchColumn() === false) {
            $db->rollBack();
            admin_set_flash('error', 'Teknisi tidak sesuai keahlian atau area layanan.');
            admin_redirect($page);
        }
        $conflict = $db->prepare(
            'SELECT id FROM service_requests
             WHERE technician_id = :technician_id
               AND status IN ("assigned", "in_progress", "waiting_approval")
               AND requested_at < TIMESTAMPADD(MINUTE, :duration, :new_start)
               AND TIMESTAMPADD(MINUTE, duration_minutes, requested_at) > :slot_start
             LIMIT 1'
        );
        $conflict->execute([
            ':technician_id' => $technicianId,
            ':duration' => (int)$request['duration_minutes'],
            ':new_start' => $scheduledAt,
            ':slot_start' => $scheduledAt,
        ]);
        if ($conflict->fetchColumn() !== false) {
            $db->rollBack();
            admin_set_flash('error', 'Jadwal teknisi bentrok dengan work order lain.');
            admin_redirect($page);
        }
        $db->prepare(
            'UPDATE service_requests SET technician_id = :technician_id,
             requested_at = :requested_at, status = "assigned" WHERE id = :id'
        )->execute([
            ':technician_id' => $technicianId,
            ':requested_at' => $scheduledAt,
            ':id' => $requestId,
        ]);
        $db->prepare(
            'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
             VALUES (:request_id, NULL, "assigned", "Admin menugaskan teknisi dan mengonfirmasi jadwal.")'
        )->execute([':request_id' => $requestId]);
        $db->commit();
        admin_set_flash('success', 'Teknisi ditugaskan dan jadwal dikonfirmasi.');
        admin_redirect($page);
    }

    if ($action === 'save_part') {
        $sku = strtoupper(trim((string)($_POST['sku'] ?? '')));
        $name = trim((string)($_POST['name'] ?? ''));
        $description = trim((string)($_POST['description'] ?? ''));
        $quantity = filter_input(INPUT_POST, 'stock_quantity', FILTER_VALIDATE_INT);
        $price = filter_input(INPUT_POST, 'unit_price', FILTER_VALIDATE_FLOAT);
        if ($sku === '' || strlen($sku) > 60 || $name === '' || strlen($name) > 150 ||
            strlen($description) > 500 || $quantity === false || $quantity === null ||
            $quantity < 0 || $price === false || $price === null || $price < 0) {
            admin_set_flash('error', 'Data sparepart tidak valid.');
            admin_redirect($page);
        }
        $stmt = $db->prepare(
            'INSERT INTO parts (sku, name, description, stock_quantity, unit_price)
             VALUES (:sku, :name, :description, :quantity, :price)'
        );
        $stmt->execute([
            ':sku' => $sku,
            ':name' => $name,
            ':description' => $description,
            ':quantity' => $quantity,
            ':price' => $price,
        ]);
        admin_set_flash('success', 'Sparepart berhasil ditambahkan.');
        admin_redirect($page);
    }

    if ($action === 'verify_payment') {
        $id = filter_input(INPUT_POST, 'id', FILTER_VALIDATE_INT);
        $decision = (string)($_POST['decision'] ?? '');
        if (!$id || !in_array($decision, ['paid', 'rejected'], true)) {
            admin_set_flash('error', 'Keputusan pembayaran tidak valid.');
            admin_redirect($page);
        }
        $db->beginTransaction();
        $payment = $db->prepare('SELECT service_request_id, status FROM payments WHERE id = :id FOR UPDATE');
        $payment->execute([':id' => $id]);
        $row = $payment->fetch(PDO::FETCH_ASSOC);
        if (!$row || $row['status'] !== 'pending') {
            $db->rollBack();
            admin_set_flash('error', 'Pembayaran tidak ditemukan atau sudah diverifikasi.');
            admin_redirect($page);
        }
        $db->prepare(
            'UPDATE payments SET status = :status, verified_by = NULL,
             paid_at = IF(:paid_status = "paid", NOW(), NULL) WHERE id = :id'
        )->execute([':status' => $decision, ':paid_status' => $decision, ':id' => $id]);
        $db->prepare(
            'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
             VALUES (:request_id, NULL, :event_type, :description)'
        )->execute([
            ':request_id' => $row['service_request_id'],
            ':event_type' => 'payment_' . $decision,
            ':description' => $decision === 'paid' ? 'Admin memverifikasi pembayaran.' : 'Admin menolak pembayaran.',
        ]);
        $db->commit();
        admin_set_flash('success', 'Status pembayaran diperbarui.');
        admin_redirect($page);
    }

    if ($action === 'decide_claim') {
        $id = filter_input(INPUT_POST, 'id', FILTER_VALIDATE_INT);
        $decision = (string)($_POST['decision'] ?? '');
        $notes = trim((string)($_POST['decision_notes'] ?? ''));
        if (!$id || !in_array($decision, ['approved', 'rejected'], true) || strlen($notes) > 500) {
            admin_set_flash('error', 'Keputusan klaim tidak valid.');
            admin_redirect($page);
        }
        $db->beginTransaction();
        $claim = $db->prepare('SELECT warranty_id, status FROM warranty_claims WHERE id = :id FOR UPDATE');
        $claim->execute([':id' => $id]);
        $row = $claim->fetch(PDO::FETCH_ASSOC);
        if (!$row || $row['status'] !== 'pending') {
            $db->rollBack();
            admin_set_flash('error', 'Klaim tidak ditemukan atau sudah diputuskan.');
            admin_redirect($page);
        }
        $db->prepare(
            'UPDATE warranty_claims SET status = :status, decision_notes = :notes,
             decided_by = NULL, decided_at = NOW() WHERE id = :id'
        )->execute([':status' => $decision, ':notes' => $notes ?: null, ':id' => $id]);
        if ($decision === 'rejected') {
            $db->prepare('UPDATE warranties SET status = "active" WHERE id = :id')
                ->execute([':id' => $row['warranty_id']]);
        }
        $db->commit();
        admin_set_flash('success', 'Keputusan klaim garansi disimpan.');
        admin_redirect($page);
    }

    admin_set_flash('error', 'Aksi tidak dikenali.');
} catch (PDOException $exception) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    if ((string)$exception->getCode() === '23000') {
        admin_set_flash('error', 'Data bentrok atau sudah terdaftar.');
    } else {
        error_log('SerFix admin action: ' . $exception->getMessage());
        admin_set_flash('error', 'Perubahan gagal disimpan. Coba kembali.');
    }
} catch (Throwable $exception) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    error_log('SerFix admin action: ' . $exception->getMessage());
    admin_set_flash('error', 'Perubahan gagal disimpan. Coba kembali.');
}
admin_redirect($page);
