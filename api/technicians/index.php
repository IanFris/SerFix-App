<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse('error', 'Gunakan metode GET.', null, 405);
}

$db = (new Database())->getConnection();
requireUserRole($db, ['admin', 'manager']);
$area = trim((string)($_GET['area'] ?? ''));
$categoryId = filter_input(INPUT_GET, 'category_id', FILTER_VALIDATE_INT);
$requestedAt = trim((string)($_GET['requested_at'] ?? ''));
$duration = filter_input(INPUT_GET, 'duration_minutes', FILTER_VALIDATE_INT);
$sql = 'SELECT u.id, u.name, tp.service_area, tp.phone, tp.is_available,
               GROUP_CONCAT(DISTINCT sc.name ORDER BY sc.name SEPARATOR ", ") AS skills,
               GROUP_CONCAT(DISTINCT ts.category_id ORDER BY ts.category_id) AS skill_ids
        FROM technician_profiles tp
        JOIN users u ON u.id = tp.user_id
        LEFT JOIN technician_skills ts ON ts.technician_id = tp.user_id
        LEFT JOIN service_categories sc ON sc.id = ts.category_id AND sc.is_active = 1
        WHERE u.role = "technician"';
$params = [];
if ($area !== '') {
    $sql .= ' AND LOWER(TRIM(tp.service_area)) = LOWER(TRIM(:area))';
    $params[':area'] = $area;
}
if ($categoryId !== false && $categoryId !== null) {
    $sql .= ' AND EXISTS (
        SELECT 1 FROM technician_skills skill
        WHERE skill.technician_id = tp.user_id AND skill.category_id = :category_id
    )';
    $params[':category_id'] = $categoryId;
}
if ($requestedAt !== '') {
    try {
        $requestedAt = (new DateTimeImmutable($requestedAt))->format('Y-m-d H:i:s');
    } catch (Throwable) {
        sendResponse('error', 'Jadwal tidak valid.', null, 400);
    }
    if ($duration === false || $duration === null || $duration < 1 || $duration > 1440) {
        sendResponse('error', 'Durasi jadwal tidak valid.', null, 400);
    }
    $sql .= ' AND NOT EXISTS (
        SELECT 1 FROM service_requests sr
        WHERE sr.technician_id = tp.user_id
          AND sr.status IN ("assigned", "in_progress", "waiting_approval")
          AND sr.requested_at < TIMESTAMPADD(MINUTE, :duration, :requested_at)
          AND TIMESTAMPADD(MINUTE, sr.duration_minutes, sr.requested_at) > :slot_start
    )';
    $params[':duration'] = $duration;
    $params[':requested_at'] = $requestedAt;
    $params[':slot_start'] = $requestedAt;
}
$sql .= ' GROUP BY u.id, u.name, tp.service_area, tp.phone, tp.is_available ORDER BY u.name';
$stmt = $db->prepare($sql);
$stmt->execute($params);
sendResponse('success', 'Daftar teknisi berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
