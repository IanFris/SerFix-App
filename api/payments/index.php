<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['customer', 'admin', 'manager']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $requestId = filter_input(INPUT_GET, 'request_id', FILTER_VALIDATE_INT);
    if ($requestId === false) {
        sendResponse('error', 'ID pengajuan tidak valid.', null, 400);
    }
    $sql = 'SELECT p.id, p.service_request_id, p.amount, p.method, p.status,
                   p.reference, p.paid_at, p.created_at, customer.name AS customer_name
            FROM payments p JOIN users customer ON customer.id = p.customer_id';
    $conditions = [];
    $params = [];
    if ($user['role'] === 'customer') {
        $conditions[] = 'p.customer_id = :customer_id';
        $params[':customer_id'] = $user['id'];
    }
    if ($requestId !== null) {
        $conditions[] = 'p.service_request_id = :request_id';
        $params[':request_id'] = $requestId;
    }
    if ($conditions !== []) {
        $sql .= ' WHERE ' . implode(' AND ', $conditions);
    }
    $sql .= ' ORDER BY p.id DESC';
    $stmt = $db->prepare($sql);
    $stmt->execute($params);
    sendResponse('success', 'Riwayat pembayaran berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode GET atau POST.', null, 405);
}
$input = getRequestData();
$action = $input['action'] ?? '';
if (!is_string($action)) {
    sendResponse('error', 'Aksi pembayaran tidak valid.', null, 400);
}

if ($action === 'create' && $user['role'] === 'customer') {
    $requestId = filter_var($input['request_id'] ?? null, FILTER_VALIDATE_INT);
    $method = $input['method'] ?? '';
    $reference = trim((string)($input['reference'] ?? ''));
    if ($requestId === false || $requestId === null || $requestId < 1 ||
        !in_array($method, ['cash', 'bank_transfer', 'qr'], true) ||
        mb_strlen($reference) > 120) {
        sendResponse('error', 'Pengajuan, metode, atau referensi pembayaran tidak valid.', null, 400);
    }
    $db->beginTransaction();
    try {
        $requestStmt = $db->prepare(
            'SELECT final_amount FROM service_requests
             WHERE id = :id AND customer_id = :customer_id AND status = "completed"
             FOR UPDATE'
        );
        $requestStmt->execute([':id' => $requestId, ':customer_id' => $user['id']]);
        $amount = $requestStmt->fetchColumn();
        if ($amount === false) {
            $db->rollBack();
            sendResponse('error', 'Pembayaran hanya tersedia untuk servis selesai milik Anda.', null, 404);
        }
        $existing = $db->prepare(
            'SELECT status FROM payments WHERE service_request_id = :request_id
             ORDER BY id DESC LIMIT 1'
        );
        $existing->execute([':request_id' => $requestId]);
        if (in_array($existing->fetchColumn(), ['pending', 'paid'], true)) {
            $db->rollBack();
            sendResponse('error', 'Pembayaran sebelumnya masih menunggu verifikasi atau sudah lunas.', null, 409);
        }
        $stmt = $db->prepare(
            'INSERT INTO payments (service_request_id, customer_id, amount, method, reference)
             VALUES (:request_id, :customer_id, :amount, :method, :reference)'
        );
        $stmt->execute([
            ':request_id' => $requestId,
            ':customer_id' => $user['id'],
            ':amount' => $amount,
            ':method' => $method,
            ':reference' => $reference !== '' ? $reference : null,
        ]);
        $paymentId = (int)$db->lastInsertId();
        $db->prepare(
            'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
             VALUES (:request_id, :actor_id, "payment_pending", "Pembayaran dicatat dan menunggu verifikasi admin.")'
        )->execute([':request_id' => $requestId, ':actor_id' => $user['id']]);
        $db->commit();
        sendResponse('success', 'Pembayaran dicatat dan menunggu verifikasi admin.', [
            'id' => $paymentId,
            'status' => 'pending',
        ], 201);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix payment create: ' . $exception->getMessage());
        sendResponse('error', 'Pembayaran gagal dicatat.', null, 500);
    }
}

if ($action === 'gateway_create' && $user['role'] === 'customer') {
    $requestId = filter_var($input['request_id'] ?? null, FILTER_VALIDATE_INT);
    $provider = mb_substr(trim((string)($input['provider'] ?? 'qris')), 0, 60);
    if ($requestId === false || $requestId === null || $requestId < 1) {
        sendResponse('error', 'ID pengajuan pembayaran tidak valid.', null, 400);
    }
    $db->beginTransaction();
    try {
        $request = $db->prepare('SELECT final_amount FROM service_requests
                                 WHERE id = :id AND customer_id = :customer_id
                                   AND status = "completed" FOR UPDATE');
        $request->execute([':id' => $requestId, ':customer_id' => $user['id']]);
        $amount = $request->fetchColumn();
        if ($amount === false) {
            $db->rollBack();
            sendResponse('error', 'Payment gateway hanya tersedia untuk servis selesai milik Anda.', null, 404);
        }
        $existing = $db->prepare('SELECT status FROM payments
                                  WHERE service_request_id = :request_id
                                  ORDER BY id DESC LIMIT 1');
        $existing->execute([':request_id' => $requestId]);
        if (in_array($existing->fetchColumn(), ['pending', 'paid'], true)) {
            $db->rollBack();
            sendResponse('error', 'Pembayaran untuk servis ini masih aktif atau sudah lunas.', null, 409);
        }
        $db->prepare('INSERT INTO payments
                      (service_request_id, customer_id, amount, method, status, reference)
                      VALUES (:request_id, :customer_id, :amount, "qr", "pending", :reference)')
           ->execute([
               ':request_id' => $requestId,
               ':customer_id' => $user['id'],
               ':amount' => $amount,
               ':reference' => 'gateway-' . $requestId . '-' . time(),
           ]);
        $paymentId = (int)$db->lastInsertId();
        $gatewayReference = 'SF-' . $paymentId . '-' . bin2hex(random_bytes(8));
        $checkoutUrl = '';
        $db->prepare('INSERT INTO payment_gateway_transactions
                      (payment_id, provider, gateway_reference, checkout_url, raw_status)
                      VALUES (:payment_id, :provider, :reference, :checkout, "pending")')
           ->execute([
               ':payment_id' => $paymentId,
               ':provider' => $provider,
               ':reference' => $gatewayReference,
               ':checkout' => $checkoutUrl,
           ]);
        $db->commit();
        sendResponse('success', 'Transaksi payment gateway dibuat.', [
            'payment_id' => $paymentId,
            'gateway_reference' => $gatewayReference,
            'provider' => $provider,
            'amount' => (float)$amount,
            'status' => 'pending',
        ], 201);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) $db->rollBack();
        error_log('SerFix gateway create: ' . $exception->getMessage());
        sendResponse('error', 'Pembuatan transaksi gateway gagal.', null, 500);
    }
}

if ($action === 'verify' && in_array($user['role'], ['admin', 'manager'], true)) {
    $paymentId = filter_var($input['payment_id'] ?? null, FILTER_VALIDATE_INT);
    $decision = $input['decision'] ?? '';
    if ($paymentId === false || $paymentId === null || $paymentId < 1 ||
        !in_array($decision, ['paid', 'rejected'], true)) {
        sendResponse('error', 'Pembayaran dan keputusan verifikasi tidak valid.', null, 400);
    }
    $db->beginTransaction();
    try {
        $payment = $db->prepare(
            'SELECT id, service_request_id, status FROM payments WHERE id = :id FOR UPDATE'
        );
        $payment->execute([':id' => $paymentId]);
        $row = $payment->fetch(PDO::FETCH_ASSOC);
        if (!$row || $row['status'] !== 'pending') {
            $db->rollBack();
            sendResponse('error', 'Pembayaran tidak ditemukan atau sudah diverifikasi.', null, 409);
        }
        $update = $db->prepare(
            'UPDATE payments SET status = :status, verified_by = :verifier,
             paid_at = IF(:paid_status = "paid", NOW(), NULL) WHERE id = :id'
        );
        $update->execute([
            ':status' => $decision,
            ':verifier' => $user['id'],
            ':paid_status' => $decision,
            ':id' => $paymentId,
        ]);
        $db->prepare(
            'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
             VALUES (:request_id, :actor_id, :event_type, :description)'
        )->execute([
            ':request_id' => $row['service_request_id'],
            ':actor_id' => $user['id'],
            ':event_type' => 'payment_' . $decision,
            ':description' => $decision === 'paid'
                ? 'Admin memverifikasi pembayaran.'
                : 'Admin menolak pembayaran; pelanggan dapat mengirim ulang bukti.',
        ]);
        $db->commit();
        sendResponse('success', 'Status pembayaran diperbarui.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix payment verification: ' . $exception->getMessage());
        sendResponse('error', 'Verifikasi pembayaran gagal.', null, 500);
    }
}

sendResponse('error', 'Aksi pembayaran tidak diizinkan.', null, 403);
