<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['technician', 'admin', 'manager']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $db->query(
        'SELECT id, sku, name, description, stock_quantity, unit_price
         FROM parts WHERE is_active = 1 ORDER BY name'
    );
    sendResponse('success', 'Stok sparepart berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || $user['role'] !== 'admin') {
    sendResponse('error', 'Hanya admin yang dapat mengelola stok sparepart.', null, 403);
}

$input = getRequestData();
$sku = strtoupper(trim((string)($input['sku'] ?? '')));
$name = trim((string)($input['name'] ?? ''));
$description = trim((string)($input['description'] ?? ''));
$quantity = filter_var($input['stock_quantity'] ?? null, FILTER_VALIDATE_INT);
$price = filter_var($input['unit_price'] ?? null, FILTER_VALIDATE_FLOAT);
$id = filter_var($input['id'] ?? null, FILTER_VALIDATE_INT);
if ($sku === '' || strlen($sku) > 60 || $name === '' || mb_strlen($name) > 150 ||
    mb_strlen($description) > 500 || $quantity === false || $quantity === null ||
    $quantity < 0 || $price === false || $price === null || $price < 0) {
    sendResponse('error', 'SKU, nama, stok, dan harga sparepart wajib valid.', null, 400);
}

try {
    if ($id === false || $id === null) {
        $stmt = $db->prepare(
            'INSERT INTO parts (sku, name, description, stock_quantity, unit_price)
             VALUES (:sku, :name, :description, :quantity, :price)'
        );
        $stmt->execute([
            ':sku' => $sku,
            ':name' => $name,
            ':description' => $description,
            ':quantity' => $quantity,
            ':price' => $price,
        ]);
        sendResponse('success', 'Sparepart berhasil ditambahkan.', ['id' => (int)$db->lastInsertId()], 201);
    }

    $stmt = $db->prepare(
        'UPDATE parts SET sku = :sku, name = :name, description = :description,
         stock_quantity = :quantity, unit_price = :price WHERE id = :id AND is_active = 1'
    );
    $stmt->execute([
        ':sku' => $sku,
        ':name' => $name,
        ':description' => $description,
        ':quantity' => $quantity,
        ':price' => $price,
        ':id' => $id,
    ]);
    if (!$stmt->rowCount()) {
        sendResponse('error', 'Sparepart tidak ditemukan atau tidak ada perubahan.', null, 404);
    }
    sendResponse('success', 'Sparepart berhasil diperbarui.', null);
} catch (PDOException $exception) {
    if ((string)$exception->getCode() === '23000') {
        sendResponse('error', 'SKU sparepart sudah digunakan.', null, 409);
    }
    error_log('SerFix parts: ' . $exception->getMessage());
    sendResponse('error', 'Data sparepart gagal disimpan.', null, 500);
}
