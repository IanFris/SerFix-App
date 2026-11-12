<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['customer', 'admin', 'manager']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $sql = 'SELECT w.id, w.service_request_id, w.starts_at, w.ends_at, w.terms, w.status,
                   sr.customer_id, sr.device_name, sc.name AS service_name,
                   (SELECT wc.id FROM warranty_claims wc WHERE wc.warranty_id = w.id
                    ORDER BY wc.id DESC LIMIT 1) AS claim_id,
                   (SELECT wc.description FROM warranty_claims wc WHERE wc.warranty_id = w.id
                    ORDER BY wc.id DESC LIMIT 1) AS claim_description,
                   (SELECT wc.status FROM warranty_claims wc WHERE wc.warranty_id = w.id
                    ORDER BY wc.id DESC LIMIT 1) AS claim_status
            FROM warranties w
            JOIN service_requests sr ON sr.id = w.service_request_id
            JOIN service_categories sc ON sc.id = sr.category_id';
    if ($user['role'] === 'customer') {
        $sql .= ' WHERE sr.customer_id = :customer_id';
    }
    $sql .= ' ORDER BY w.ends_at DESC';
    $stmt = $db->prepare($sql);
    $stmt->execute($user['role'] === 'customer' ? [':customer_id' => $user['id']] : []);
    sendResponse('success', 'Garansi servis berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode GET atau POST.', null, 405);
}
$input = getRequestData();
$action = $input['action'] ?? 'claim';
if ($action === 'claim' && $user['role'] === 'customer') {
    $warrantyId = filter_var($input['warranty_id'] ?? null, FILTER_VALIDATE_INT);
    $description = trim((string)($input['description'] ?? ''));
    if ($warrantyId === false || $warrantyId === null || $warrantyId < 1 ||
        $description === '' || mb_strlen($description) > 5000) {
        sendResponse('error', 'Garansi dan keterangan klaim wajib diisi.', null, 400);
    }
    $db->beginTransaction();
    try {
        $stmt = $db->prepare(
            'SELECT w.id, w.ends_at, w.status FROM warranties w
             JOIN service_requests sr ON sr.id = w.service_request_id
             WHERE w.id = :id AND sr.customer_id = :customer_id FOR UPDATE'
        );
        $stmt->execute([':id' => $warrantyId, ':customer_id' => $user['id']]);
        $warranty = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$warranty || $warranty['status'] !== 'active' ||
            $warranty['ends_at'] < date('Y-m-d')) {
            $db->rollBack();
            sendResponse('error', 'Garansi tidak ditemukan, tidak aktif, atau sudah berakhir.', null, 409);
        }
        $claim = $db->prepare(
            'INSERT INTO warranty_claims (warranty_id, customer_id, description)
             VALUES (:warranty_id, :customer_id, :description)'
        );
        $claim->execute([
            ':warranty_id' => $warrantyId,
            ':customer_id' => $user['id'],
            ':description' => $description,
        ]);
        $db->prepare('UPDATE warranties SET status = "claimed" WHERE id = :id')
            ->execute([':id' => $warrantyId]);
        $db->commit();
        sendResponse('success', 'Klaim garansi dikirim untuk ditinjau admin.', [
            'id' => (int)$db->lastInsertId(),
            'status' => 'pending',
        ], 201);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix warranty claim: ' . $exception->getMessage());
        sendResponse('error', 'Klaim garansi gagal dikirim.', null, 500);
    }
}

if ($action === 'decide' && in_array($user['role'], ['admin', 'manager'], true)) {
    $claimId = filter_var($input['claim_id'] ?? null, FILTER_VALIDATE_INT);
    $decision = $input['decision'] ?? '';
    $notes = trim((string)($input['decision_notes'] ?? ''));
    if ($claimId === false || $claimId === null || $claimId < 1 ||
        !in_array($decision, ['approved', 'rejected'], true) || mb_strlen($notes) > 500) {
        sendResponse('error', 'Keputusan klaim tidak valid.', null, 400);
    }
    $db->beginTransaction();
    try {
        $claim = $db->prepare(
            'SELECT id, warranty_id, status FROM warranty_claims WHERE id = :id FOR UPDATE'
        );
        $claim->execute([':id' => $claimId]);
        $row = $claim->fetch(PDO::FETCH_ASSOC);
        if (!$row || $row['status'] !== 'pending') {
            $db->rollBack();
            sendResponse('error', 'Klaim tidak ditemukan atau sudah diputuskan.', null, 409);
        }
        $db->prepare(
            'UPDATE warranty_claims SET status = :status, decision_notes = :notes,
             decided_by = :decided_by, decided_at = NOW() WHERE id = :id'
        )->execute([
            ':status' => $decision,
            ':notes' => $notes ?: null,
            ':decided_by' => $user['id'],
            ':id' => $claimId,
        ]);
        if ($decision === 'rejected') {
            $db->prepare('UPDATE warranties SET status = "active" WHERE id = :id')
                ->execute([':id' => $row['warranty_id']]);
        }
        $db->commit();
        sendResponse('success', 'Keputusan klaim garansi disimpan.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        error_log('SerFix warranty decision: ' . $exception->getMessage());
        sendResponse('error', 'Keputusan klaim gagal disimpan.', null, 500);
    }
}

sendResponse('error', 'Aksi garansi tidak diizinkan.', null, 403);
