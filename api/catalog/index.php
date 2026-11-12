<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse('error', 'Gunakan metode GET.', null, 405);
}

$db = (new Database())->getConnection();
$role = requireUserRole($db, ['customer', 'technician', 'admin', 'manager']);
$stmt = $db->query(
    'SELECT id, slug, name, description, base_fee, default_duration_minutes, warranty_months
     FROM service_categories WHERE is_active = 1 ORDER BY name'
);
sendResponse('success', 'Katalog layanan berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
