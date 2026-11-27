<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['customer', 'technician', 'admin', 'manager']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $db->query('SELECT id, name, radius_km, travel_fee, opening_time,
                               closing_time, operating_days, is_active
                        FROM service_areas
                        WHERE is_active = 1
                        ORDER BY name');
    sendResponse('success', 'Area layanan berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST' ||
    !in_array($user['role'], ['admin', 'manager'], true)) {
    sendResponse('error', 'Hanya admin atau manajer yang dapat mengelola area layanan.', null, 403);
}

$input = getRequestData();
$name = trim((string)($input['name'] ?? ''));
$radius = filter_var($input['radius_km'] ?? null, FILTER_VALIDATE_INT);
$travelFee = filter_var($input['travel_fee'] ?? null, FILTER_VALIDATE_FLOAT);
if ($name === '' || mb_strlen($name) > 120 || $radius === false || $radius < 1 ||
    $travelFee === false || $travelFee < 0) {
    sendResponse('error', 'Nama, radius, atau biaya perjalanan tidak valid.', null, 400);
}

$opening = trim((string)($input['opening_time'] ?? '08:00'));
$closing = trim((string)($input['closing_time'] ?? '17:00'));
$days = mb_substr(trim((string)($input['operating_days'] ?? 'Senin-Sabtu')), 0, 100);
$id = filter_var($input['id'] ?? null, FILTER_VALIDATE_INT);

try {
    if ($id === false || $id === null) {
        $stmt = $db->prepare('INSERT INTO service_areas
                              (name, radius_km, travel_fee, opening_time, closing_time, operating_days)
                              VALUES (:name, :radius, :fee, :opening, :closing, :days)');
        $stmt->execute([
            ':name' => $name, ':radius' => $radius, ':fee' => $travelFee,
            ':opening' => $opening, ':closing' => $closing, ':days' => $days,
        ]);
        sendResponse('success', 'Area layanan berhasil ditambahkan.',
            ['id' => (int)$db->lastInsertId()], 201);
    }

    $stmt = $db->prepare('UPDATE service_areas SET name = :name, radius_km = :radius,
                          travel_fee = :fee, opening_time = :opening,
                          closing_time = :closing, operating_days = :days
                          WHERE id = :id');
    $stmt->execute([
        ':name' => $name, ':radius' => $radius, ':fee' => $travelFee,
        ':opening' => $opening, ':closing' => $closing, ':days' => $days,
        ':id' => $id,
    ]);
    if (!$stmt->rowCount()) {
        sendResponse('error', 'Area layanan tidak ditemukan atau tidak ada perubahan.', null, 404);
    }
    sendResponse('success', 'Area layanan berhasil diperbarui.', null);
} catch (PDOException $exception) {
    if ((string)$exception->getCode() === '23000') {
        sendResponse('error', 'Nama area sudah digunakan.', null, 409);
    }
    error_log('SerFix areas: ' . $exception->getMessage());
    sendResponse('error', 'Data area gagal disimpan.', null, 500);
}
