<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    sendResponse('error', 'Gunakan metode GET.', null, 405);
}

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['customer', 'technician', 'admin', 'manager']);
$conditions = [];
$params = [];
if ($user['role'] === 'customer') {
    $conditions[] = 'customer_id = :user_id';
    $params[':user_id'] = $user['id'];
} elseif ($user['role'] === 'technician') {
    $conditions[] = 'technician_id = :user_id';
    $params[':user_id'] = $user['id'];
}
$where = $conditions === [] ? '' : ' WHERE ' . implode(' AND ', $conditions);
$stmt = $db->prepare(
    'SELECT COUNT(*) AS total,
            SUM(status = "requested") AS requested,
            SUM(status = "assigned") AS assigned,
            SUM(status = "in_progress") AS in_progress,
            SUM(status = "waiting_approval") AS waiting_approval,
            SUM(status = "completed") AS completed,
            COALESCE(SUM(CASE WHEN status = "completed" THEN final_amount ELSE 0 END), 0) AS completed_revenue
     FROM service_requests' . $where
);
$stmt->execute($params);
$summary = $stmt->fetch(PDO::FETCH_ASSOC);
foreach (['total', 'requested', 'assigned', 'in_progress', 'waiting_approval', 'completed'] as $field) {
    $summary[$field] = (int)($summary[$field] ?? 0);
}
$summary['completed_revenue'] = (float)$summary['completed_revenue'];
if ($user['role'] === 'admin' || $user['role'] === 'manager') {
    $summary['technicians'] = (int)$db->query(
        'SELECT COUNT(*) FROM technician_profiles WHERE is_available = 1'
    )->fetchColumn();
    $summary['low_stock_parts'] = (int)$db->query(
        'SELECT COUNT(*) FROM parts WHERE is_active = 1 AND stock_quantity <= minimum_stock'
    )->fetchColumn();
    $summary['pending_payments'] = (int)$db->query(
        'SELECT COUNT(*) FROM payments WHERE status = "pending"'
    )->fetchColumn();
    $summary['pending_warranty_claims'] = (int)$db->query(
        'SELECT COUNT(*) FROM warranty_claims WHERE status = "pending"'
    )->fetchColumn();
    $summary['average_rating'] = (float)$db->query(
        'SELECT COALESCE(AVG(rating), 0) FROM service_reviews'
    )->fetchColumn();
    $topCategory = $db->query(
        'SELECT sc.name, COUNT(*) AS total
         FROM service_requests sr JOIN service_categories sc ON sc.id = sr.category_id
         GROUP BY sc.id, sc.name ORDER BY total DESC LIMIT 1'
    )->fetch(PDO::FETCH_ASSOC);
    $summary['top_category'] = $topCategory['name'] ?? '-';
    $summary['top_category_count'] = (int)($topCategory['total'] ?? 0);
    $monthStart = date('Y-m-01');
    $monthEnd = date('Y-m-t');
    $monthly = $db->prepare('SELECT COUNT(*) AS jobs,
                                    COALESCE(SUM(CASE WHEN status = "completed" THEN final_amount ELSE 0 END), 0) AS revenue
                             FROM service_requests
                             WHERE requested_at BETWEEN :month_start AND :month_end');
    $monthly->execute([':month_start' => $monthStart . ' 00:00:00',
                       ':month_end' => $monthEnd . ' 23:59:59']);
    $monthlyRow = $monthly->fetch(PDO::FETCH_ASSOC);
    $summary['monthly_jobs'] = (int)($monthlyRow['jobs'] ?? 0);
    $summary['monthly_revenue'] = (float)($monthlyRow['revenue'] ?? 0);
}
sendResponse('success', 'Ringkasan SerFix berhasil diambil.', $summary);
