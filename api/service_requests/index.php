<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

function request_datetime(mixed $value): ?string
{
    if (!is_string($value) || trim($value) === '') {
        return null;
    }

    try {
        return (new DateTimeImmutable($value))->format('Y-m-d H:i:s');
    } catch (Throwable) {
        return null;
    }
}

function request_add_event(PDO $db, int $requestId, ?int $actorId, string $type, string $description): void
{
    $stmt = $db->prepare(
        'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
         VALUES (:request_id, :actor_id, :event_type, :description)'
    );
    $stmt->execute([
        ':request_id' => $requestId,
        ':actor_id' => $actorId,
        ':event_type' => $type,
        ':description' => $description,
    ]);
}

function request_add_notification(PDO $db, int $userId, int $requestId, string $title, string $message): void
{
    $stmt = $db->prepare(
        'INSERT INTO service_notifications (user_id, service_request_id, title, message)
         VALUES (:user_id, :request_id, :title, :message)'
    );
    $stmt->execute([
        ':user_id' => $userId,
        ':request_id' => $requestId,
        ':title' => mb_substr($title, 0, 160),
        ':message' => mb_substr($message, 0, 500),
    ]);
}

function request_list_query(): string
{
    return 'SELECT sr.id, sr.customer_id, customer.name AS customer_name,
                   sr.technician_id, technician.name AS technician_name,
                   sr.category_id, sc.name AS service_name, sc.warranty_months,
                   sr.device_name, sr.issue_description, sr.service_address, sr.service_area,
                   sr.requested_at, sr.duration_minutes, sr.status,
                   sr.estimate_amount, sr.final_amount, sr.estimate_approved_at,
                   wo.id AS work_order_id, wo.diagnosis, wo.work_description,
                   wo.technician_notes, wo.started_at, wo.completed_at,
                   COALESCE((SELECT p.status FROM payments p
                             WHERE p.service_request_id = sr.id
                             ORDER BY p.id DESC LIMIT 1), "unpaid") AS payment_status,
                   (SELECT SUM(wop.quantity) FROM work_order_parts wop
                    WHERE wop.work_order_id = wo.id) AS parts_count,
                   warranty.starts_at AS warranty_starts_at,
                   warranty.ends_at AS warranty_ends_at,
                   warranty.status AS warranty_status
            FROM service_requests sr
            JOIN users customer ON customer.id = sr.customer_id
            LEFT JOIN users technician ON technician.id = sr.technician_id
            JOIN service_categories sc ON sc.id = sr.category_id
            LEFT JOIN work_orders wo ON wo.service_request_id = sr.id
            LEFT JOIN warranties warranty ON warranty.service_request_id = sr.id';
}

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['customer', 'technician', 'admin', 'manager']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $requestId = filter_input(INPUT_GET, 'id', FILTER_VALIDATE_INT);
    $sql = request_list_query();
    $conditions = [];
    $params = [];

    if ($user['role'] === 'customer') {
        $conditions[] = 'sr.customer_id = :user_id';
        $params[':user_id'] = $user['id'];
    } elseif ($user['role'] === 'technician') {
        $conditions[] = 'sr.technician_id = :user_id';
        $params[':user_id'] = $user['id'];
    }
    if ($requestId !== false && $requestId !== null) {
        $conditions[] = 'sr.id = :request_id';
        $params[':request_id'] = $requestId;
    }
    if ($conditions !== []) {
        $sql .= ' WHERE ' . implode(' AND ', $conditions);
    }
    $sql .= ' ORDER BY sr.requested_at DESC, sr.id DESC';
    if ($requestId === false) {
        sendResponse('error', 'ID layanan tidak valid.', null, 400);
    }
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    $requests = $stmt->fetchAll(PDO::FETCH_ASSOC);
    if ($requestId !== null && $requests === []) {
        sendResponse('error', 'Pengajuan servis tidak ditemukan.', null, 404);
    }

    foreach ($requests as &$request) {
        $request['id'] = (int)$request['id'];
        $request['customer_id'] = (int)$request['customer_id'];
        $request['technician_id'] = $request['technician_id'] === null ? null : (int)$request['technician_id'];
        $request['category_id'] = (int)$request['category_id'];
        $request['estimate_amount'] = (float)$request['estimate_amount'];
        $request['final_amount'] = $request['final_amount'] === null ? null : (float)$request['final_amount'];
        $request['duration_minutes'] = (int)$request['duration_minutes'];
        $request['parts_count'] = (int)($request['parts_count'] ?? 0);
        $request['events'] = [];
        $parts = $db->prepare(
            'SELECT p.id, p.sku, p.name, wop.quantity, wop.unit_price
             FROM work_order_parts wop JOIN parts p ON p.id = wop.part_id
             JOIN work_orders wo ON wo.id = wop.work_order_id
             WHERE wo.service_request_id = :request_id ORDER BY p.name'
        );
        $parts->execute([':request_id' => $request['id']]);
        $request['parts'] = $parts->fetchAll(PDO::FETCH_ASSOC);
        if ($requestId !== null) {
            $events = $db->prepare(
                'SELECT event_type, description, created_at FROM service_request_events
                 WHERE service_request_id = :request_id ORDER BY id DESC'
            );
            $events->execute([':request_id' => $requestId]);
            $request['events'] = $events->fetchAll(PDO::FETCH_ASSOC);
            $payments = $db->prepare(
                'SELECT id, amount, method, status, reference, paid_at, created_at
                 FROM payments WHERE service_request_id = :request_id ORDER BY id DESC'
            );
            $payments->execute([':request_id' => $requestId]);
            $request['payments'] = $payments->fetchAll(PDO::FETCH_ASSOC);
        }
    }
    unset($request);
    sendResponse('success', 'Pengajuan servis berhasil diambil.', $requestId !== null ? $requests[0] : $requests);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode GET atau POST.', null, 405);
}

$input = getRequestData();
$action = $input['action'] ?? 'create';
if (!is_string($action)) {
    sendResponse('error', 'Aksi tidak valid.', null, 400);
}

if ($action === 'create') {
    if ($user['role'] !== 'customer') {
        sendResponse('error', 'Hanya pelanggan yang dapat mengajukan servis.', null, 403);
    }
    $categoryId = filter_var($input['category_id'] ?? null, FILTER_VALIDATE_INT);
    $deviceName = trim((string)($input['device_name'] ?? ''));
    $issue = trim((string)($input['issue_description'] ?? ''));
    $address = trim((string)($input['service_address'] ?? ''));
    $area = trim((string)($input['service_area'] ?? ''));
    $requestedAt = request_datetime($input['requested_at'] ?? null);
    if ($categoryId === false || $categoryId === null || $deviceName === '' ||
        mb_strlen($deviceName) > 160 || $issue === '' || mb_strlen($issue) > 5000 ||
        $address === '' || mb_strlen($address) > 500 || $area === '' ||
        mb_strlen($area) > 120 || $requestedAt === null ||
        new DateTimeImmutable($requestedAt) <= new DateTimeImmutable()) {
        sendResponse('error', 'Jenis layanan, perangkat, keluhan, alamat, area, dan jadwal valid wajib diisi.', null, 400);
    }
    $category = $db->prepare(
        'SELECT base_fee, default_duration_minutes FROM service_categories
         WHERE id = :id AND is_active = 1 LIMIT 1'
    );
    $category->execute([':id' => $categoryId]);
    $service = $category->fetch(PDO::FETCH_ASSOC);
    if (!$service) {
        sendResponse('error', 'Jenis layanan tidak tersedia.', null, 404);
    }
    $db->beginTransaction();
    try {
        $stmt = $db->prepare(
            'INSERT INTO service_requests
             (customer_id, category_id, device_name, issue_description, service_address,
              service_area, requested_at, duration_minutes, estimate_amount)
             VALUES (:customer_id, :category_id, :device_name, :issue, :address,
                     :area, :requested_at, :duration, :estimate)'
        );
        $stmt->execute([
            ':customer_id' => $user['id'],
            ':category_id' => $categoryId,
            ':device_name' => $deviceName,
            ':issue' => $issue,
            ':address' => $address,
            ':area' => $area,
            ':requested_at' => $requestedAt,
            ':duration' => (int)$service['default_duration_minutes'],
            ':estimate' => $service['base_fee'],
        ]);
        $id = (int)$db->lastInsertId();
        request_add_event($db, $id, $user['id'], 'requested', 'Pengajuan servis dibuat.');
        $db->commit();
        sendResponse('success', 'Pengajuan servis berhasil dibuat.', ['id' => $id], 201);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix request create: ' . $exception->getMessage());
        sendResponse('error', 'Pengajuan servis gagal disimpan.', null, 500);
    }
}

$requestId = filter_var($input['request_id'] ?? null, FILTER_VALIDATE_INT);
if ($requestId === false || $requestId === null || $requestId < 1) {
    sendResponse('error', 'ID pengajuan tidak valid.', null, 400);
}

if ($action === 'assign') {
    if ($user['role'] !== 'admin') {
        sendResponse('error', 'Hanya admin yang dapat menugaskan teknisi.', null, 403);
    }
    $technicianId = filter_var($input['technician_id'] ?? null, FILTER_VALIDATE_INT);
    $scheduledAt = request_datetime($input['scheduled_at'] ?? null);
    if ($technicianId === false || $technicianId === null || $scheduledAt === null ||
        new DateTimeImmutable($scheduledAt) <= new DateTimeImmutable()) {
        sendResponse('error', 'Teknisi dan jadwal mendatang wajib dipilih.', null, 400);
    }
    $db->beginTransaction();
    try {
        $requestStmt = $db->prepare(
            'SELECT * FROM service_requests WHERE id = :id FOR UPDATE'
        );
        $requestStmt->execute([':id' => $requestId]);
        $request = $requestStmt->fetch(PDO::FETCH_ASSOC);
        if (!$request || $request['status'] !== 'requested') {
            $db->rollBack();
            sendResponse('error', 'Pengajuan tidak ditemukan atau sudah ditugaskan.', null, 409);
        }
        $technicianStmt = $db->prepare(
            'SELECT tp.service_area FROM technician_profiles tp
             JOIN users u ON u.id = tp.user_id
             JOIN technician_skills ts ON ts.technician_id = tp.user_id
             WHERE tp.user_id = :technician_id AND u.role = "technician"
               AND tp.is_available = 1 AND ts.category_id = :category_id
               AND LOWER(TRIM(tp.service_area)) = LOWER(TRIM(:area))
             FOR UPDATE'
        );
        $technicianStmt->execute([
            ':technician_id' => $technicianId,
            ':category_id' => $request['category_id'],
            ':area' => $request['service_area'],
        ]);
        if (!$technicianStmt->fetch(PDO::FETCH_ASSOC)) {
            $db->rollBack();
            sendResponse('error', 'Teknisi tidak aktif, tidak sesuai keahlian, atau tidak melayani area ini.', null, 409);
        }
        $conflictStmt = $db->prepare(
            'SELECT id FROM service_requests
             WHERE technician_id = :technician_id
               AND status IN ("assigned", "in_progress", "waiting_approval")
               AND requested_at < TIMESTAMPADD(MINUTE, :new_duration, :new_start)
               AND TIMESTAMPADD(MINUTE, duration_minutes, requested_at) > :slot_start
             LIMIT 1'
        );
        $conflictStmt->execute([
            ':technician_id' => $technicianId,
            ':new_duration' => (int)$request['duration_minutes'],
            ':new_start' => $scheduledAt,
            ':slot_start' => $scheduledAt,
        ]);
        if ($conflictStmt->fetchColumn() !== false) {
            $db->rollBack();
            sendResponse('error', 'Jadwal teknisi berbenturan dengan work order lain.', null, 409);
        }
        $update = $db->prepare(
            'UPDATE service_requests SET technician_id = :technician_id,
             requested_at = :requested_at, status = "assigned" WHERE id = :id'
        );
        $update->execute([
            ':technician_id' => $technicianId,
            ':requested_at' => $scheduledAt,
            ':id' => $requestId,
        ]);
        request_add_event($db, $requestId, $user['id'], 'assigned', 'Teknisi ditugaskan dan jadwal dikonfirmasi.');
        request_add_notification(
            $db,
            (int)$request['customer_id'],
            $requestId,
            'Teknisi ditugaskan',
            'Jadwal servis Anda telah dikonfirmasi. Pantau teknisi dari halaman layanan.'
        );
        $db->commit();
        sendResponse('success', 'Teknisi berhasil ditugaskan.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix request assignment: ' . $exception->getMessage());
        sendResponse('error', 'Penugasan teknisi gagal diproses.', null, 500);
    }
}

if ($action === 'approve_estimate') {
    if ($user['role'] !== 'customer') {
        sendResponse('error', 'Persetujuan estimasi hanya dapat dilakukan pelanggan.', null, 403);
    }
    $stmt = $db->prepare(
        'UPDATE service_requests SET status = "assigned", estimate_approved_at = NOW()
         WHERE id = :id AND customer_id = :customer_id
           AND status IN ("assigned", "waiting_approval")
           AND estimate_approved_at IS NULL'
    );
    $stmt->execute([':id' => $requestId, ':customer_id' => $user['id']]);
    if (!$stmt->rowCount()) {
        sendResponse('error', 'Estimasi tidak ditemukan atau tidak menunggu persetujuan.', null, 409);
    }
    request_add_event($db, $requestId, $user['id'], 'estimate_approved', 'Pelanggan menyetujui estimasi biaya.');
    sendResponse('success', 'Estimasi biaya disetujui.', null);
}

if ($action === 'cancel') {
    $where = $user['role'] === 'customer' ? ' AND customer_id = :user_id' : '';
    if (!in_array($user['role'], ['customer', 'admin'], true)) {
        sendResponse('error', 'Anda tidak dapat membatalkan pengajuan ini.', null, 403);
    }
    $db->beginTransaction();
    try {
        $request = $db->prepare(
            'SELECT id FROM service_requests WHERE id = :id
             AND status IN ("requested", "assigned", "waiting_approval")' . $where . ' FOR UPDATE'
        );
        $params = [':id' => $requestId];
        if ($user['role'] === 'customer') {
            $params[':user_id'] = $user['id'];
        }
        $request->execute($params);
        if ($request->fetchColumn() === false) {
            $db->rollBack();
            sendResponse('error', 'Pengajuan tidak dapat dibatalkan pada status saat ini.', null, 409);
        }
        $workOrder = $db->prepare(
            'SELECT id FROM work_orders WHERE service_request_id = :request_id'
        );
        $workOrder->execute([':request_id' => $requestId]);
        $workOrderId = $workOrder->fetchColumn();
        if ($workOrderId !== false) {
            $parts = $db->prepare(
                'SELECT part_id, quantity FROM work_order_parts WHERE work_order_id = :work_order_id'
            );
            $parts->execute([':work_order_id' => $workOrderId]);
            $restore = $db->prepare(
                'UPDATE parts SET stock_quantity = stock_quantity + :quantity WHERE id = :id'
            );
            foreach ($parts->fetchAll(PDO::FETCH_ASSOC) as $part) {
                $restore->execute([':quantity' => (int)$part['quantity'], ':id' => (int)$part['part_id']]);
            }
            $db->prepare('DELETE FROM work_order_parts WHERE work_order_id = :id')
                ->execute([':id' => $workOrderId]);
        }
        $db->prepare('UPDATE service_requests SET status = "cancelled" WHERE id = :id')
            ->execute([':id' => $requestId]);
        request_add_event($db, $requestId, $user['id'], 'cancelled', 'Pengajuan servis dibatalkan.');
        $db->commit();
        sendResponse('success', 'Pengajuan servis dibatalkan.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix request cancellation: ' . $exception->getMessage());
        sendResponse('error', 'Pembatalan pengajuan gagal.', null, 500);
    }
}

sendResponse('error', 'Aksi tidak dikenal.', null, 400);
