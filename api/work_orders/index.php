<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['technician', 'admin', 'manager', 'customer']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $requestId = filter_input(INPUT_GET, 'request_id', FILTER_VALIDATE_INT);
    if ($requestId === false || $requestId === null || $requestId < 1) {
        sendResponse('error', 'ID pengajuan tidak valid.', null, 400);
    }
    $stmt = $db->prepare(
        'SELECT wo.*, sr.customer_id, sr.technician_id, sr.status AS request_status,
                sr.estimate_amount, sr.final_amount
         FROM work_orders wo JOIN service_requests sr ON sr.id = wo.service_request_id
         WHERE wo.service_request_id = :request_id'
    );
    $stmt->execute([':request_id' => $requestId]);
    $workOrder = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$workOrder) {
        sendResponse('error', 'Work order belum dibuat.', null, 404);
    }
    if (($user['role'] === 'customer' && (int)$workOrder['customer_id'] !== $user['id']) ||
        ($user['role'] === 'technician' && (int)$workOrder['technician_id'] !== $user['id'])) {
        sendResponse('error', 'Anda tidak memiliki akses ke work order ini.', null, 403);
    }
    $parts = $db->prepare(
        'SELECT p.id, p.sku, p.name, wop.quantity, wop.unit_price
         FROM work_order_parts wop JOIN parts p ON p.id = wop.part_id
         WHERE wop.work_order_id = :work_order_id ORDER BY p.name'
    );
    $parts->execute([':work_order_id' => $workOrder['id']]);
    $workOrder['parts'] = $parts->fetchAll(PDO::FETCH_ASSOC);
    sendResponse('success', 'Work order berhasil diambil.', $workOrder);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode GET atau POST.', null, 405);
}
if ($user['role'] !== 'technician') {
    sendResponse('error', 'Hanya teknisi yang dapat memperbarui work order.', null, 403);
}

$input = getRequestData();
$action = $input['action'] ?? '';
$requestId = filter_var($input['request_id'] ?? null, FILTER_VALIDATE_INT);
if (!is_string($action) || $requestId === false || $requestId === null || $requestId < 1) {
    sendResponse('error', 'Aksi dan ID pengajuan tidak valid.', null, 400);
}

$db->beginTransaction();
try {
    $requestStmt = $db->prepare(
        'SELECT sr.*, sc.base_fee, sc.warranty_months
         FROM service_requests sr JOIN service_categories sc ON sc.id = sr.category_id
         WHERE sr.id = :id AND sr.technician_id = :technician_id FOR UPDATE'
    );
    $requestStmt->execute([':id' => $requestId, ':technician_id' => $user['id']]);
    $request = $requestStmt->fetch(PDO::FETCH_ASSOC);
    if (!$request) {
        $db->rollBack();
        sendResponse('error', 'Penugasan tidak ditemukan.', null, 404);
    }
    $orderStmt = $db->prepare(
        'INSERT INTO work_orders (service_request_id) VALUES (:request_id)
         ON DUPLICATE KEY UPDATE id = LAST_INSERT_ID(id)'
    );
    $orderStmt->execute([':request_id' => $requestId]);
    $workOrderId = (int)$db->lastInsertId();

    if ($action === 'start') {
        if ($request['status'] !== 'assigned' || $request['estimate_approved_at'] === null) {
            $db->rollBack();
            sendResponse('error', 'Pelanggan harus menyetujui estimasi sebelum pekerjaan dimulai.', null, 409);
        }
        $updateOrder = $db->prepare('UPDATE work_orders SET started_at = NOW() WHERE id = :id');
        $updateOrder->execute([':id' => $workOrderId]);
        $updateRequest = $db->prepare(
            'UPDATE service_requests SET status = "in_progress" WHERE id = :id'
        );
        $updateRequest->execute([':id' => $requestId]);
        $db->prepare(
            'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
             VALUES (:request_id, :actor_id, "work_started", "Teknisi memulai pekerjaan.")'
        )->execute([':request_id' => $requestId, ':actor_id' => $user['id']]);
        $db->commit();
        sendResponse('success', 'Pekerjaan dimulai.', null);
    }

    if ($action === 'save') {
        if (!in_array($request['status'], ['assigned', 'in_progress', 'waiting_approval'], true)) {
            $db->rollBack();
            sendResponse('error', 'Work order tidak dapat diubah pada status saat ini.', null, 409);
        }
        $diagnosis = trim((string)($input['diagnosis'] ?? ''));
        $description = trim((string)($input['work_description'] ?? ''));
        $notes = trim((string)($input['technician_notes'] ?? ''));
        $partsInput = $input['parts'] ?? [];
        if ($diagnosis === '' || $description === '' ||
            mb_strlen($diagnosis) > 5000 || mb_strlen($description) > 5000 ||
            mb_strlen($notes) > 5000 || !is_array($partsInput)) {
            $db->rollBack();
            sendResponse('error', 'Diagnosis, pekerjaan, catatan, atau sparepart tidak valid.', null, 400);
        }

        $oldPartsStmt = $db->prepare(
            'SELECT part_id, quantity, unit_price FROM work_order_parts
             WHERE work_order_id = :work_order_id'
        );
        $oldPartsStmt->execute([':work_order_id' => $workOrderId]);
        $oldParts = [];
        foreach ($oldPartsStmt->fetchAll(PDO::FETCH_ASSOC) as $oldPart) {
            $oldParts[(int)$oldPart['part_id']] = [
                'quantity' => (int)$oldPart['quantity'],
                'unit_price' => (float)$oldPart['unit_price'],
            ];
        }
        $newParts = [];
        foreach ($partsInput as $part) {
            if (!is_array($part)) {
                $db->rollBack();
                sendResponse('error', 'Daftar sparepart tidak valid.', null, 400);
            }
            $partId = filter_var($part['part_id'] ?? null, FILTER_VALIDATE_INT);
            $quantity = filter_var($part['quantity'] ?? null, FILTER_VALIDATE_INT);
            if ($partId === false || $partId === null || $partId < 1 ||
                $quantity === false || $quantity === null || $quantity < 1 ||
                isset($newParts[$partId])) {
                $db->rollBack();
                sendResponse('error', 'ID sparepart dan jumlah wajib valid serta tidak boleh duplikat.', null, 400);
            }
            $newParts[(int)$partId] = (int)$quantity;
        }

        $partIds = array_values(array_unique(array_merge(array_keys($oldParts), array_keys($newParts))));
        sort($partIds);
        $partRows = [];
        if ($partIds !== []) {
            $placeholders = implode(',', array_fill(0, count($partIds), '?'));
            $stockStmt = $db->prepare(
                "SELECT id, stock_quantity, unit_price FROM parts
                 WHERE id IN ($placeholders) AND is_active = 1 ORDER BY id FOR UPDATE"
            );
            $stockStmt->execute($partIds);
            foreach ($stockStmt->fetchAll(PDO::FETCH_ASSOC) as $partRow) {
                $partRows[(int)$partRow['id']] = $partRow;
            }
            if (count($partRows) !== count($partIds)) {
                $db->rollBack();
                sendResponse('error', 'Salah satu sparepart sudah tidak aktif atau tidak ditemukan.', null, 409);
            }
        }

        $total = (float)$request['base_fee'];
        foreach ($partIds as $partId) {
            $oldQuantity = $oldParts[$partId]['quantity'] ?? 0;
            $newQuantity = $newParts[$partId] ?? 0;
            $stock = (int)$partRows[$partId]['stock_quantity'];
            if ($newQuantity > $oldQuantity && $stock < $newQuantity - $oldQuantity) {
                $db->rollBack();
                sendResponse('error', 'Stok ' . $partId . ' tidak mencukupi.', null, 409);
            }
            $adjust = $oldQuantity - $newQuantity;
            if ($adjust !== 0) {
                $stockUpdate = $db->prepare(
                    'UPDATE parts SET stock_quantity = stock_quantity + :adjust WHERE id = :id'
                );
                $stockUpdate->execute([':adjust' => $adjust, ':id' => $partId]);
            }
            if ($newQuantity > 0) {
                $unitPrice = isset($oldParts[$partId])
                    ? $oldParts[$partId]['unit_price']
                    : (float)$partRows[$partId]['unit_price'];
                $total += $unitPrice * $newQuantity;
                $savePart = $db->prepare(
                    'INSERT INTO work_order_parts (work_order_id, part_id, quantity, unit_price)
                     VALUES (:work_order_id, :part_id, :quantity, :unit_price)
                     ON DUPLICATE KEY UPDATE quantity = VALUES(quantity)'
                );
                $savePart->execute([
                    ':work_order_id' => $workOrderId,
                    ':part_id' => $partId,
                    ':quantity' => $newQuantity,
                    ':unit_price' => $unitPrice,
                ]);
            } elseif (isset($oldParts[$partId])) {
                $deletePart = $db->prepare(
                    'DELETE FROM work_order_parts WHERE work_order_id = :work_order_id AND part_id = :part_id'
                );
                $deletePart->execute([':work_order_id' => $workOrderId, ':part_id' => $partId]);
            }
        }

        $oldEstimate = (float)$request['estimate_amount'];
        $changedEstimate = abs($oldEstimate - $total) >= 0.01;
        $newStatus = $request['status'];
        $approvedAt = $request['estimate_approved_at'];
        if ($changedEstimate &&
            ($request['status'] === 'in_progress' || $approvedAt !== null)) {
            $newStatus = 'waiting_approval';
            $approvedAt = null;
        }
        $saveOrder = $db->prepare(
            'UPDATE work_orders SET diagnosis = :diagnosis, work_description = :description,
             technician_notes = :notes WHERE id = :id'
        );
        $saveOrder->execute([
            ':diagnosis' => $diagnosis ?: null,
            ':description' => $description ?: null,
            ':notes' => $notes ?: null,
            ':id' => $workOrderId,
        ]);
        $saveRequest = $db->prepare(
            'UPDATE service_requests SET estimate_amount = :estimate,
             status = :status, estimate_approved_at = :approved_at WHERE id = :id'
        );
        $saveRequest->execute([
            ':estimate' => $total,
            ':status' => $newStatus,
            ':approved_at' => $approvedAt,
            ':id' => $requestId,
        ]);
        if ($changedEstimate) {
            $db->prepare(
                'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
                 VALUES (:request_id, :actor_id, "estimate_updated", "Teknisi memperbarui diagnosis, sparepart, dan estimasi biaya.")'
            )->execute([':request_id' => $requestId, ':actor_id' => $user['id']]);
        }
        $db->commit();
        sendResponse(
            'success',
            $newStatus === 'waiting_approval'
                ? 'Estimasi berubah; pekerjaan menunggu persetujuan pelanggan.'
                : 'Work order berhasil disimpan.',
            ['estimate_amount' => $total, 'status' => $newStatus]
        );
    }

    if ($action === 'complete') {
        if ($request['status'] !== 'in_progress' || $request['estimate_approved_at'] === null) {
            $db->rollBack();
            sendResponse('error', 'Pekerjaan hanya dapat diselesaikan setelah estimasi disetujui.', null, 409);
        }
        $details = $db->prepare(
            'SELECT diagnosis, work_description FROM work_orders WHERE id = :id'
        );
        $details->execute([':id' => $workOrderId]);
        $workDetails = $details->fetch(PDO::FETCH_ASSOC);
        if (!$workDetails || trim((string)$workDetails['diagnosis']) === '' ||
            trim((string)$workDetails['work_description']) === '') {
            $db->rollBack();
            sendResponse('error', 'Lengkapi diagnosis dan pekerjaan sebelum menyelesaikan servis.', null, 409);
        }
        $completeOrder = $db->prepare(
            'UPDATE work_orders SET completed_at = NOW() WHERE id = :id'
        );
        $completeOrder->execute([':id' => $workOrderId]);
        $completeRequest = $db->prepare(
            'UPDATE service_requests SET status = "completed", final_amount = estimate_amount
             WHERE id = :id'
        );
        $completeRequest->execute([':id' => $requestId]);
        if ((int)$request['warranty_months'] > 0) {
            $warranty = $db->prepare(
                'INSERT INTO warranties (service_request_id, starts_at, ends_at, terms)
                 VALUES (:request_id, CURDATE(),
                         DATE_ADD(CURDATE(), INTERVAL :months MONTH),
                         "Garansi berlaku untuk pekerjaan dan sparepart yang tercatat.")'
            );
            $warranty->execute([
                ':request_id' => $requestId,
                ':months' => (int)$request['warranty_months'],
            ]);
        }
        $db->prepare(
            'INSERT INTO service_request_events (service_request_id, actor_id, event_type, description)
             VALUES (:request_id, :actor_id, "completed", "Servis selesai; riwayat dan garansi diperbarui.")'
        )->execute([':request_id' => $requestId, ':actor_id' => $user['id']]);
        $db->commit();
        sendResponse('success', 'Servis selesai dan garansi diterbitkan.', null);
    }

    $db->rollBack();
    sendResponse('error', 'Aksi work order tidak dikenal.', null, 400);
} catch (Throwable $exception) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    error_log('SerFix work order: ' . $exception->getMessage());
    sendResponse('error', 'Work order gagal diperbarui.', null, 500);
}
