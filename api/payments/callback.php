<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Callback payment gateway menggunakan POST.', null, 405);
}

$db = (new Database())->getConnection();
$input = getRequestData();
$gatewayReference = trim((string)($input['gateway_reference'] ?? ''));
$rawStatus = strtolower(trim((string)($input['status'] ?? '')));
$signature = trim((string)($input['signature'] ?? ''));

$secret = getenv('SERFIX_PAYMENT_WEBHOOK_SECRET') ?: '';
if ($secret !== '' && !hash_equals(hash_hmac('sha256', json_encode($input), $secret), $signature)) {
    sendResponse('error', 'Signature callback tidak valid.', null, 401);
}
if ($gatewayReference === '') {
    sendResponse('error', 'Referensi gateway wajib diisi.', null, 400);
}

$status = in_array($rawStatus, ['paid', 'settlement', 'success', 'capture'], true)
    ? 'paid'
    : (in_array($rawStatus, ['expired', 'failed', 'rejected', 'denied'], true)
        ? 'rejected'
        : 'pending');

$db->beginTransaction();
try {
    $txn = $db->prepare('SELECT payment_id FROM payment_gateway_transactions
                         WHERE gateway_reference = :reference FOR UPDATE');
    $txn->execute([':reference' => $gatewayReference]);
    $paymentId = $txn->fetchColumn();
    if ($paymentId === false) {
        $db->rollBack();
        sendResponse('error', 'Transaksi gateway tidak ditemukan.', null, 404);
    }
    $db->prepare('UPDATE payment_gateway_transactions SET raw_status = :raw_status
                  WHERE gateway_reference = :reference')
       ->execute([':raw_status' => $rawStatus ?: 'pending',
                  ':reference' => $gatewayReference]);
    if ($status !== 'pending') {
        $db->prepare('UPDATE payments SET status = :status,
                      paid_at = IF(:paid_status = "paid", NOW(), NULL)
                      WHERE id = :payment_id')
           ->execute([
               ':status' => $status,
               ':paid_status' => $status,
               ':payment_id' => (int)$paymentId,
           ]);
        $payment = $db->prepare('SELECT service_request_id, customer_id
                                 FROM payments WHERE id = :payment_id');
        $payment->execute([':payment_id' => (int)$paymentId]);
        $paymentRow = $payment->fetch(PDO::FETCH_ASSOC);
        if ($paymentRow) {
            $db->prepare('INSERT INTO service_notifications
                          (user_id, service_request_id, title, message)
                          VALUES (:user_id, :request_id, :title, :message)')
               ->execute([
                   ':user_id' => (int)$paymentRow['customer_id'],
                   ':request_id' => (int)$paymentRow['service_request_id'],
                   ':title' => 'Pembayaran diperbarui',
                   ':message' => $status === 'paid'
                       ? 'Pembayaran Anda telah diterima.'
                       : 'Pembayaran ditolak atau tidak berhasil.',
               ]);
        }
    }
    $db->commit();
    sendResponse('success', 'Callback payment gateway diproses.', ['status' => $status]);
} catch (Throwable $exception) {
    if ($db->inTransaction()) $db->rollBack();
    error_log('SerFix gateway callback: ' . $exception->getMessage());
    sendResponse('error', 'Callback payment gateway gagal diproses.', null, 500);
}
