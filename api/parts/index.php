<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
$user = requireUserRole($db, ['technician', 'admin', 'manager']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $action = trim((string)($_GET['action'] ?? ''));
    if ($action === 'transactions') {
        $stmt = $db->query(
            'SELECT st.id, st.part_id, p.name AS part_name, st.type, st.quantity,
                    st.unit_cost, st.reference, st.notes, st.created_at,
                    u.name AS actor_name
             FROM stock_transactions st
             JOIN parts p ON p.id = st.part_id
             LEFT JOIN users u ON u.id = st.actor_id
             ORDER BY st.created_at DESC, st.id DESC LIMIT 100'
        );
        sendResponse('success', 'Riwayat stok berhasil diambil.',
            $stmt->fetchAll(PDO::FETCH_ASSOC));
    }
    $stmt = $db->query(
        'SELECT id, sku, name, description, stock_quantity, minimum_stock, unit_price
         FROM parts WHERE is_active = 1 ORDER BY name'
    );
    sendResponse('success', 'Stok sparepart berhasil diambil.',
        $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST' || $user['role'] !== 'admin') {
    sendResponse('error', 'Hanya admin yang dapat mengelola stok sparepart.', null, 403);
}

$input = getRequestData();
$action = (string)($input['action'] ?? '');
if ($action === 'stock_adjust') {
    $partId = filter_var($input['part_id'] ?? null, FILTER_VALIDATE_INT);
    $type = (string)($input['type'] ?? '');
    $quantity = filter_var($input['quantity'] ?? null, FILTER_VALIDATE_INT);
    $unitCost = filter_var($input['unit_cost'] ?? null, FILTER_VALIDATE_FLOAT);
    if ($partId === false || $partId === null || $quantity === false ||
        $quantity === null || $quantity < 1 ||
        !in_array($type, ['in', 'out', 'adjustment', 'return'], true) ||
        $unitCost === false || $unitCost === null || $unitCost < 0) {
        sendResponse('error', 'Data transaksi stok tidak valid.', null, 400);
    }

    $db->beginTransaction();
    try {
        $part = $db->prepare('SELECT stock_quantity FROM parts WHERE id = :id AND is_active = 1 FOR UPDATE');
        $part->execute([':id' => $partId]);
        $row = $part->fetch(PDO::FETCH_ASSOC);
        if (!$row) {
            $db->rollBack();
            sendResponse('error', 'Sparepart tidak ditemukan.', null, 404);
        }
        $current = (int)$row['stock_quantity'];
        $next = $type === 'out' ? $current - $quantity : $current + $quantity;
        if ($type === 'adjustment') {
            $next = $quantity;
        }
        if ($next < 0) {
            $db->rollBack();
            sendResponse('error', 'Stok tidak mencukupi untuk transaksi keluar.', null, 409);
        }
        $db->prepare('UPDATE parts SET stock_quantity = :stock WHERE id = :id')
           ->execute([':stock' => $next, ':id' => $partId]);
        $db->prepare('INSERT INTO stock_transactions
                      (part_id, supplier_id, actor_id, type, quantity, unit_cost, reference, notes)
                      VALUES (:part_id, NULL, :actor_id, :type, :quantity, :unit_cost, :reference, :notes)')
           ->execute([
               ':part_id' => $partId,
               ':actor_id' => $user['id'],
               ':type' => $type,
               ':quantity' => $quantity,
               ':unit_cost' => $unitCost,
               ':reference' => mb_substr(trim((string)($input['reference'] ?? '')), 0, 150),
               ':notes' => mb_substr(trim((string)($input['notes'] ?? '')), 0, 500),
           ]);
        $db->commit();
        sendResponse('success', 'Transaksi stok berhasil disimpan.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) $db->rollBack();
        error_log('SerFix stock transaction: ' . $exception->getMessage());
        sendResponse('error', 'Transaksi stok gagal disimpan.', null, 500);
    }
}

$sku = strtoupper(trim((string)($input['sku'] ?? '')));
$name = trim((string)($input['name'] ?? ''));
$description = trim((string)($input['description'] ?? ''));
$quantity = filter_var($input['stock_quantity'] ?? null, FILTER_VALIDATE_INT);
$minimumStock = filter_var($input['minimum_stock'] ?? 3, FILTER_VALIDATE_INT);
$price = filter_var($input['unit_price'] ?? null, FILTER_VALIDATE_FLOAT);
$id = filter_var($input['id'] ?? null, FILTER_VALIDATE_INT);
if ($sku === '' || strlen($sku) > 60 || $name === '' || mb_strlen($name) > 150 ||
    mb_strlen($description) > 500 || $quantity === false || $quantity === null ||
    $quantity < 0 || $minimumStock === false || $minimumStock === null ||
    $minimumStock < 0 || $price === false || $price === null || $price < 0) {
    sendResponse('error', 'SKU, nama, stok, dan harga sparepart wajib valid.', null, 400);
}

try {
    if ($id === false || $id === null) {
        $stmt = $db->prepare(
            'INSERT INTO parts (sku, name, description, stock_quantity, minimum_stock, unit_price)
             VALUES (:sku, :name, :description, :quantity, :minimum_stock, :price)'
        );
        $stmt->execute([
            ':sku' => $sku,
            ':name' => $name,
            ':description' => $description,
            ':quantity' => $quantity,
            ':minimum_stock' => $minimumStock,
            ':price' => $price,
        ]);
        sendResponse('success', 'Sparepart berhasil ditambahkan.', ['id' => (int)$db->lastInsertId()], 201);
    }

    $stmt = $db->prepare(
        'UPDATE parts SET sku = :sku, name = :name, description = :description,
         stock_quantity = :quantity, minimum_stock = :minimum_stock,
         unit_price = :price WHERE id = :id AND is_active = 1'
    );
    $stmt->execute([
        ':sku' => $sku,
        ':name' => $name,
        ':description' => $description,
        ':quantity' => $quantity,
        ':minimum_stock' => $minimumStock,
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
