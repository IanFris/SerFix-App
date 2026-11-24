<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['customer', 'technician', 'admin', 'manager']);

function canAccessRequest(PDO $db, array $user, int $requestId): bool
{
    $stmt = $db->prepare('SELECT customer_id, technician_id FROM service_requests WHERE id = :id');
    $stmt->execute([':id' => $requestId]);
    $request = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$request) return false;
    return in_array($user['role'], ['admin', 'manager'], true)
        || (int)$request['customer_id'] === (int)$user['id']
        || (int)$request['technician_id'] === (int)$user['id'];
}

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $action = trim((string)($_GET['action'] ?? ''));
    if ($action === 'notifications') {
        $stmt = $db->prepare('SELECT id, service_request_id, title, message, is_read, created_at
                              FROM service_notifications WHERE user_id = :user_id
                              ORDER BY created_at DESC, id DESC LIMIT 100');
        $stmt->execute([':user_id' => $user['id']]);
        sendResponse('success', 'Notifikasi berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
    }
    $requestId = filter_input(INPUT_GET, 'request_id', FILTER_VALIDATE_INT);
    if ($requestId === false || $requestId === null || !canAccessRequest($db, $user, (int)$requestId)) {
        sendResponse('error', 'Pengajuan tidak ditemukan atau Anda tidak memiliki akses.', null, 404);
    }
    if ($action === 'messages') {
        $stmt = $db->prepare('SELECT m.id, m.sender_id, u.name AS sender_name, m.message, m.created_at
                              FROM service_messages m JOIN users u ON u.id = m.sender_id
                              WHERE m.service_request_id = :request_id ORDER BY m.created_at ASC, m.id ASC');
        $stmt->execute([':request_id' => $requestId]);
        sendResponse('success', 'Percakapan berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
    }
    if ($action === 'tracking') {
        $stmt = $db->prepare('SELECT status, latitude, longitude, eta_minutes, note, updated_at
                              FROM service_tracking WHERE service_request_id = :request_id');
        $stmt->execute([':request_id' => $requestId]);
        sendResponse('success', 'Status lokasi berhasil diambil.', $stmt->fetch(PDO::FETCH_ASSOC) ?: [
            'status' => 'not_started', 'latitude' => null, 'longitude' => null,
            'eta_minutes' => null, 'note' => 'Teknisi belum memulai perjalanan.',
        ]);
    }
    if ($action === 'attachments') {
        $stmt = $db->prepare('SELECT a.id, a.kind, a.file_name, a.file_path, a.created_at, u.name AS uploader_name
                              FROM service_attachments a JOIN users u ON u.id = a.uploaded_by
                              WHERE a.service_request_id = :request_id ORDER BY a.created_at DESC');
        $stmt->execute([':request_id' => $requestId]);
        sendResponse('success', 'Lampiran berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
    }
    if ($action === 'review') {
        $stmt = $db->prepare('SELECT rating, review, created_at FROM service_reviews
                              WHERE service_request_id = :request_id');
        $stmt->execute([':request_id' => $requestId]);
        sendResponse('success', 'Ulasan berhasil diambil.', $stmt->fetch(PDO::FETCH_ASSOC) ?: null);
    }
    sendResponse('error', 'Aksi fitur tambahan tidak valid.', null, 400);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode GET atau POST.', null, 405);
}
$input = getRequestData();
$action = $input['action'] ?? '';
$requestId = filter_var($input['request_id'] ?? null, FILTER_VALIDATE_INT);

if (!is_string($action)) sendResponse('error', 'Aksi tidak valid.', null, 400);

if ($action === 'read_notifications') {
    $db->prepare('UPDATE service_notifications SET is_read = 1 WHERE user_id = :user_id')
       ->execute([':user_id' => $user['id']]);
    sendResponse('success', 'Semua notifikasi telah dibaca.', null);
}
if ($action === 'notification') {
    $title = trim((string)($input['title'] ?? ''));
    $message = trim((string)($input['message'] ?? ''));
    if ($title === '' || $message === '') sendResponse('error', 'Judul dan pesan notifikasi wajib diisi.', null, 400);
    $db->prepare('INSERT INTO service_notifications (user_id, service_request_id, title, message)
                  VALUES (:user_id, :request_id, :title, :message)')
       ->execute([':user_id' => $user['id'], ':request_id' => $requestId ?: null,
                  ':title' => mb_substr($title, 0, 160), ':message' => mb_substr($message, 0, 500)]);
    sendResponse('success', 'Notifikasi berhasil dibuat.', null, 201);
}

if ($requestId === false || $requestId === null || !canAccessRequest($db, $user, (int)$requestId)) {
    sendResponse('error', 'Pengajuan tidak ditemukan atau Anda tidak memiliki akses.', null, 404);
}

if ($action === 'message') {
    $message = trim((string)($input['message'] ?? ''));
    if ($message === '' || mb_strlen($message) > 5000) {
        sendResponse('error', 'Pesan tidak boleh kosong atau lebih dari 5000 karakter.', null, 400);
    }
    $db->prepare('INSERT INTO service_messages (service_request_id, sender_id, message)
                  VALUES (:request_id, :sender_id, :message)')
       ->execute([':request_id' => $requestId, ':sender_id' => $user['id'], ':message' => $message]);
    sendResponse('success', 'Pesan berhasil dikirim.', null, 201);
}

if ($action === 'tracking') {
    if (!in_array($user['role'], ['technician', 'admin'], true)) {
        sendResponse('error', 'Hanya teknisi atau admin yang dapat memperbarui lokasi.', null, 403);
    }
    $status = (string)($input['status'] ?? 'heading');
    if (!in_array($status, ['not_started','heading','arrived','working','completed'], true)) {
        sendResponse('error', 'Status pelacakan tidak valid.', null, 400);
    }
    $latitude = filter_var($input['latitude'] ?? null, FILTER_VALIDATE_FLOAT);
    $longitude = filter_var($input['longitude'] ?? null, FILTER_VALIDATE_FLOAT);
    $eta = filter_var($input['eta_minutes'] ?? null, FILTER_VALIDATE_INT);
    $note = mb_substr(trim((string)($input['note'] ?? '')), 0, 500);
    $db->prepare('INSERT INTO service_tracking
                  (service_request_id, status, latitude, longitude, eta_minutes, note)
                  VALUES (:request_id, :status, :latitude, :longitude, :eta, :note)
                  ON DUPLICATE KEY UPDATE status=:status, latitude=:latitude, longitude=:longitude,
                  eta_minutes=:eta, note=:note')
       ->execute([':request_id' => $requestId, ':status' => $status,
                  ':latitude' => $latitude === false ? null : $latitude,
                  ':longitude' => $longitude === false ? null : $longitude,
                  ':eta' => $eta === false ? null : $eta, ':note' => $note !== '' ? $note : null]);
    sendResponse('success', 'Status pelacakan diperbarui.', null);
}

if ($action === 'attachment') {
    $kind = (string)($input['kind'] ?? 'other');
    if (!in_array($kind, ['damage','repair','payment','signature','other'], true)) {
        sendResponse('error', 'Jenis lampiran tidak valid.', null, 400);
    }
    $base64 = (string)($input['base64'] ?? '');
    $fileName = preg_replace('/[^a-zA-Z0-9._-]/', '_', (string)($input['file_name'] ?? 'lampiran.jpg'));
    $data = base64_decode($base64, true);
    if ($base64 === '' || $data === false || strlen($data) > 5 * 1024 * 1024) {
        sendResponse('error', 'Lampiran wajib berupa foto atau file maksimal 5 MB.', null, 400);
    }
    $uploadDir = dirname(__DIR__) . '/uploads/';
    if (!is_dir($uploadDir)) mkdir($uploadDir, 0755, true);
    $safeName = time() . '_' . bin2hex(random_bytes(6)) . '_' . $fileName;
    if (!file_put_contents($uploadDir . $safeName, $data)) {
        sendResponse('error', 'Lampiran gagal disimpan.', null, 500);
    }
    $db->prepare('INSERT INTO service_attachments
                  (service_request_id, uploaded_by, kind, file_name, file_path)
                  VALUES (:request_id, :uploaded_by, :kind, :file_name, :file_path)')
       ->execute([':request_id' => $requestId, ':uploaded_by' => $user['id'],
                  ':kind' => $kind, ':file_name' => $fileName,
                  ':file_path' => 'uploads/' . $safeName]);
    sendResponse('success', 'Lampiran berhasil diunggah.', ['file_name' => $safeName], 201);
}

if ($action === 'reschedule') {
    $scheduledAt = $input['scheduled_at'] ?? '';
    try {
        $scheduled = (new DateTimeImmutable((string)$scheduledAt))->format('Y-m-d H:i:s');
        if (new DateTimeImmutable($scheduled) <= new DateTimeImmutable()) throw new Exception();
    } catch (Throwable) {
        sendResponse('error', 'Waktu jadwal baru tidak valid.', null, 400);
    }
    if (!in_array($user['role'], ['customer', 'admin'], true)) {
        sendResponse('error', 'Hanya pelanggan atau admin yang dapat mengubah jadwal.', null, 403);
    }
    $db->prepare('UPDATE service_requests SET requested_at = :scheduled_at,
                  status = IF(status = "assigned", "requested", status)
                  WHERE id = :request_id')
       ->execute([':scheduled_at' => $scheduled, ':request_id' => $requestId]);
    $db->prepare('UPDATE service_requests SET technician_id = NULL
                  WHERE id = :request_id AND status = "requested"')
       ->execute([':request_id' => $requestId]);
    sendResponse('success', 'Jadwal servis diperbarui.', null);
}

if ($action === 'review') {
    if ($user['role'] !== 'customer') sendResponse('error', 'Hanya pelanggan yang dapat memberi ulasan.', null, 403);
    $stmt = $db->prepare('SELECT technician_id, status FROM service_requests WHERE id = :request_id');
    $stmt->execute([':request_id' => $requestId]);
    $request = $stmt->fetch(PDO::FETCH_ASSOC);
    if (!$request || $request['status'] !== 'completed' || (int)$request['technician_id'] < 1) {
        sendResponse('error', 'Ulasan hanya tersedia setelah servis selesai.', null, 409);
    }
    $rating = filter_var($input['rating'] ?? null, FILTER_VALIDATE_INT);
    $review = mb_substr(trim((string)($input['review'] ?? '')), 0, 1000);
    if ($rating === false || $rating < 1 || $rating > 5) {
        sendResponse('error', 'Rating harus bernilai 1 sampai 5.', null, 400);
    }
    $db->prepare('INSERT INTO service_reviews
                  (service_request_id, customer_id, technician_id, rating, review)
                  VALUES (:request_id, :customer_id, :technician_id, :rating, :review)
                  ON DUPLICATE KEY UPDATE rating=:rating, review=:review')
       ->execute([':request_id' => $requestId, ':customer_id' => $user['id'],
                  ':technician_id' => (int)$request['technician_id'],
                  ':rating' => $rating, ':review' => $review]);
    sendResponse('success', 'Ulasan berhasil disimpan.', null);
}

sendResponse('error', 'Aksi fitur tambahan tidak diizinkan.', null, 403);
