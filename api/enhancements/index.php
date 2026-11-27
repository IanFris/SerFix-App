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
    if ($action === 'assets') {
        if ($user['role'] !== 'customer') {
            sendResponse('error', 'Hanya pelanggan yang dapat melihat aset.', null, 403);
        }
        $stmt = $db->prepare('SELECT a.*, c.name AS category_name
                              FROM customer_assets a
                              LEFT JOIN service_categories c ON c.id = a.category_id
                              WHERE a.customer_id = :customer_id
                              ORDER BY COALESCE(a.next_service_at, "9999-12-31") ASC, a.name');
        $stmt->execute([':customer_id' => $user['id']]);
        sendResponse('success', 'Aset pelanggan berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
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
    if ($action === 'reschedules') {
        $stmt = $db->prepare('SELECT rp.*, sr.customer_id, sr.technician_id
                              FROM reschedule_proposals rp
                              JOIN service_requests sr ON sr.id = rp.service_request_id
                              WHERE rp.service_request_id = :request_id
                              ORDER BY rp.created_at DESC');
        $stmt->execute([':request_id' => $requestId]);
        sendResponse('success', 'Usulan jadwal berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
    }
    if ($action === 'invoice') {
        $stmt = $db->prepare('SELECT sr.id, sr.device_name, sr.service_address, sr.requested_at,
                                     sr.estimate_amount, sr.final_amount, sr.status,
                                     customer.name AS customer_name, customer.email AS customer_email,
                                     sc.name AS service_name
                              FROM service_requests sr
                              JOIN users customer ON customer.id = sr.customer_id
                              JOIN service_categories sc ON sc.id = sr.category_id
                              WHERE sr.id = :request_id');
        $stmt->execute([':request_id' => $requestId]);
        $invoice = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$invoice || $invoice['status'] !== 'completed') {
            sendResponse('error', 'Invoice hanya tersedia setelah servis selesai.', null, 409);
        }
        $parts = $db->prepare('SELECT p.name, wop.quantity, wop.unit_price
                               FROM work_orders wo
                               JOIN work_order_parts wop ON wop.work_order_id = wo.id
                               JOIN parts p ON p.id = wop.part_id
                               WHERE wo.service_request_id = :request_id');
        $parts->execute([':request_id' => $requestId]);
        $invoice['parts'] = $parts->fetchAll(PDO::FETCH_ASSOC);
        sendResponse('success', 'Data invoice berhasil diambil.', $invoice);
    }
    if ($action === 'technician_report') {
        if (!in_array($user['role'], ['admin', 'manager'], true)) {
            sendResponse('error', 'Laporan teknisi hanya untuk admin atau manajer.', null, 403);
        }
        $stmt = $db->query('SELECT u.id, u.name,
                                   COUNT(DISTINCT sr.id) AS completed_jobs,
                                   COALESCE(AVG(r.rating), 0) AS average_rating,
                                   COALESCE(SUM(sr.final_amount), 0) AS revenue
                            FROM users u
                            LEFT JOIN service_requests sr ON sr.technician_id = u.id AND sr.status = "completed"
                            LEFT JOIN service_reviews r ON r.technician_id = u.id
                            WHERE u.role = "technician"
                            GROUP BY u.id, u.name
                            ORDER BY revenue DESC');
        sendResponse('success', 'Laporan teknisi berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
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
if ($action === 'register_push') {
    $token = trim((string)($input['token'] ?? ''));
    $platform = trim((string)($input['platform'] ?? 'unknown'));
    if ($token === '' || mb_strlen($token) > 500) {
     sendResponse('error', 'Token perangkat tidak valid.', null, 400);
    }
    $db->prepare('INSERT INTO push_devices (user_id, token, platform)
               VALUES (:user_id, :token, :platform)
               ON DUPLICATE KEY UPDATE platform = VALUES(platform), updated_at = CURRENT_TIMESTAMP')
    ->execute([':user_id' => $user['id'], ':token' => $token,
               ':platform' => mb_substr($platform, 0, 30)]);
    sendResponse('success', 'Perangkat berhasil didaftarkan untuk notifikasi push.', null);
}
if ($action === 'asset') {
    if ($user['role'] !== 'customer') {
     sendResponse('error', 'Hanya pelanggan yang dapat mengelola aset.', null, 403);
    }
    $name = trim((string)($input['name'] ?? ''));
    if ($name === '' || mb_strlen($name) > 160) {
     sendResponse('error', 'Nama aset wajib diisi.', null, 400);
    }
    $categoryId = filter_var($input['category_id'] ?? null, FILTER_VALIDATE_INT);
    $nextService = $input['next_service_at'] ?? null;
    $nextServiceDate = null;
    if (is_string($nextService) && $nextService !== '') {
     try { $nextServiceDate = (new DateTimeImmutable($nextService))->format('Y-m-d'); }
     catch (Throwable) { sendResponse('error', 'Tanggal layanan berikutnya tidak valid.', null, 400); }
    }
    $db->prepare('INSERT INTO customer_assets
               (customer_id, name, category_id, brand, model, serial_number, installed_at, next_service_at, notes)
               VALUES (:customer_id, :name, :category_id, :brand, :model, :serial, :installed, :next_service, :notes)')
    ->execute([
       ':customer_id' => $user['id'], ':name' => $name,
       ':category_id' => $categoryId === false ? null : $categoryId,
       ':brand' => mb_substr(trim((string)($input['brand'] ?? '')), 0, 120),
       ':model' => mb_substr(trim((string)($input['model'] ?? '')), 0, 120),
       ':serial' => mb_substr(trim((string)($input['serial_number'] ?? '')), 0, 160),
       ':installed' => null,
       ':next_service' => $nextServiceDate,
       ':notes' => mb_substr(trim((string)($input['notes'] ?? '')), 0, 500),
    ]);
    sendResponse('success', 'Aset pelanggan berhasil ditambahkan.', null, 201);
}
if ($action === 'offline_sync') {
    $mutations = $input['mutations'] ?? [];
    if (!is_array($mutations)) sendResponse('error', 'Daftar sinkronisasi tidak valid.', null, 400);
    $synced = 0;
    $stmt = $db->prepare('INSERT IGNORE INTO offline_mutations
                       (user_id, client_mutation_id, endpoint, payload_json, status)
                       VALUES (:user_id, :mutation_id, :endpoint, :payload, "synced")');
    foreach ($mutations as $mutation) {
     if (!is_array($mutation)) continue;
     $id = trim((string)($mutation['id'] ?? ''));
     $endpoint = trim((string)($mutation['endpoint'] ?? ''));
     if ($id === '' || mb_strlen($id) > 100 || $endpoint === '') continue;
     $stmt->execute([
         ':user_id' => $user['id'], ':mutation_id' => $id,
         ':endpoint' => mb_substr($endpoint, 0, 255),
         ':payload' => json_encode($mutation['payload'] ?? [], JSON_UNESCAPED_UNICODE),
     ]);
     $synced++;
    }
    sendResponse('success', 'Data offline berhasil direkam untuk sinkronisasi.', ['synced' => $synced]);
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
if ($action === 'propose_reschedule') {
    if (!in_array($user['role'], ['customer', 'admin', 'technician'], true)) {
        sendResponse('error', 'Peran Anda tidak dapat mengusulkan jadwal.', null, 403);
    }
    $scheduledAt = $input['scheduled_at'] ?? '';
    try {
        $scheduled = (new DateTimeImmutable((string)$scheduledAt))->format('Y-m-d H:i:s');
        if (new DateTimeImmutable($scheduled) <= new DateTimeImmutable()) throw new Exception();
    } catch (Throwable) {
        sendResponse('error', 'Waktu jadwal baru tidak valid.', null, 400);
    }
    $reason = mb_substr(trim((string)($input['reason'] ?? '')), 0, 500);
    $db->beginTransaction();
    try {
        $stmt = $db->prepare('SELECT technician_id, duration_minutes FROM service_requests WHERE id = :id FOR UPDATE');
        $stmt->execute([':id' => $requestId]);
        $request = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$request) {
            $db->rollBack();
            sendResponse('error', 'Pengajuan servis tidak ditemukan.', null, 404);
        }
        if (!empty($request['technician_id'])) {
            $conflict = $db->prepare('SELECT id FROM service_requests
                                      WHERE technician_id = :technician_id
                                        AND id != :request_id
                                        AND status IN ("assigned","in_progress","waiting_approval")
                                        AND requested_at < TIMESTAMPADD(MINUTE, :duration, :start)
                                        AND TIMESTAMPADD(MINUTE, duration_minutes, requested_at) > :start
                                      LIMIT 1');
            $conflict->execute([
                ':technician_id' => (int)$request['technician_id'],
                ':request_id' => $requestId,
                ':duration' => (int)$request['duration_minutes'],
                ':start' => $scheduled,
            ]);
            if ($conflict->fetchColumn() !== false) {
                $db->rollBack();
                sendResponse('error', 'Jadwal teknisi berbenturan dengan servis lain.', null, 409);
            }
        }
        $db->prepare('UPDATE reschedule_proposals SET status = "cancelled"
                      WHERE service_request_id = :request_id AND status = "pending"')
           ->execute([':request_id' => $requestId]);
        $db->prepare('INSERT INTO reschedule_proposals
                      (service_request_id, proposed_by, proposed_at, reason)
                      VALUES (:request_id, :proposed_by, :proposed_at, :reason)')
           ->execute([':request_id' => $requestId, ':proposed_by' => $user['id'],
                      ':proposed_at' => $scheduled, ':reason' => $reason]);
        $db->prepare('INSERT INTO service_request_events
                      (service_request_id, actor_id, event_type, description)
                      VALUES (:request_id, :actor_id, "reschedule_proposed", "Usulan jadwal baru menunggu persetujuan.")')
           ->execute([':request_id' => $requestId, ':actor_id' => $user['id']]);
        $db->commit();
        sendResponse('success', 'Usulan jadwal berhasil dikirim.', null, 201);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) $db->rollBack();
        error_log('SerFix reschedule proposal: ' . $exception->getMessage());
        sendResponse('error', 'Usulan jadwal gagal disimpan.', null, 500);
    }
}
if ($action === 'respond_reschedule') {
    $proposalId = filter_var($input['proposal_id'] ?? null, FILTER_VALIDATE_INT);
    $decision = $input['decision'] ?? '';
    if ($proposalId === false || $proposalId === null ||
        !in_array($decision, ['approved', 'rejected'], true)) {
        sendResponse('error', 'Usulan atau keputusan tidak valid.', null, 400);
    }
    $db->beginTransaction();
    try {
        $proposal = $db->prepare('SELECT rp.*, sr.customer_id
                                  FROM reschedule_proposals rp
                                  JOIN service_requests sr ON sr.id = rp.service_request_id
                                  WHERE rp.id = :id AND rp.service_request_id = :request_id
                                    AND rp.status = "pending" FOR UPDATE');
        $proposal->execute([':id' => $proposalId, ':request_id' => $requestId]);
        $row = $proposal->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $db->rollBack();
            sendResponse('error', 'Usulan jadwal tidak ditemukan atau sudah ditanggapi.', null, 409);
        }
        if ($user['role'] !== 'customer' || (int)$row['customer_id'] !== (int)$user['id']) {
            $db->rollBack();
            sendResponse('error', 'Hanya pelanggan pemilik pengajuan yang dapat menanggapi.', null, 403);
        }
        $db->prepare('UPDATE reschedule_proposals SET status = :status, responded_at = NOW()
                      WHERE id = :id')
           ->execute([':status' => $decision, ':id' => $proposalId]);
        if ($decision === 'approved') {
            $db->prepare('UPDATE service_requests SET requested_at = :scheduled_at
                          WHERE id = :request_id')
               ->execute([':scheduled_at' => $row['proposed_at'], ':request_id' => $requestId]);
            $db->prepare('INSERT INTO service_request_events
                          (service_request_id, actor_id, event_type, description)
                          VALUES (:request_id, :actor_id, "reschedule_approved", "Pelanggan menyetujui jadwal baru.")')
               ->execute([':request_id' => $requestId, ':actor_id' => $user['id']]);
        }
        $db->commit();
        sendResponse('success', $decision === 'approved' ? 'Jadwal baru disetujui.' : 'Jadwal baru ditolak.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) $db->rollBack();
        error_log('SerFix reschedule response: ' . $exception->getMessage());
        sendResponse('error', 'Keputusan jadwal gagal disimpan.', null, 500);
    }
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
