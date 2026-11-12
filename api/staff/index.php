<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';
require_once __DIR__ . '/../helpers/auth.php';

$db = (new Database())->getConnection();
requireUserRole($db, ['admin']);

if ($_SERVER['REQUEST_METHOD'] === 'GET') {
    $stmt = $db->query(
        'SELECT u.id, u.name, u.email, u.role, tp.service_area, tp.phone, tp.is_available,
                GROUP_CONCAT(DISTINCT ts.category_id ORDER BY ts.category_id) AS skill_ids
         FROM users u LEFT JOIN technician_profiles tp ON tp.user_id = u.id
         LEFT JOIN technician_skills ts ON ts.technician_id = u.id
         WHERE u.role IN ("technician", "admin", "manager")
         GROUP BY u.id, u.name, u.email, u.role, tp.service_area, tp.phone, tp.is_available
         ORDER BY u.name'
    );
    sendResponse('success', 'Data staf berhasil diambil.', $stmt->fetchAll(PDO::FETCH_ASSOC));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode GET atau POST.', null, 405);
}

$input = getRequestData();
$action = $input['action'] ?? 'create';
$staffId = filter_var($input['id'] ?? null, FILTER_VALIDATE_INT);
if ($action === 'update_technician') {
    $area = trim((string)($input['service_area'] ?? ''));
    $phone = trim((string)($input['phone'] ?? ''));
    $available = filter_var($input['is_available'] ?? null, FILTER_VALIDATE_BOOLEAN, FILTER_NULL_ON_FAILURE);
    $skills = $input['skill_ids'] ?? [];
    if ($staffId === false || $staffId === null || $staffId < 1 ||
        $area === '' || mb_strlen($area) > 120 || mb_strlen($phone) > 30 ||
        $available === null || !is_array($skills)) {
        sendResponse('error', 'Profil teknisi tidak valid.', null, 400);
    }
    $skillIds = [];
    foreach ($skills as $skillId) {
        $validId = filter_var($skillId, FILTER_VALIDATE_INT);
        if ($validId === false || $validId === null || $validId < 1) {
            sendResponse('error', 'Keahlian teknisi tidak valid.', null, 400);
        }
        $skillIds[] = (int)$validId;
    }
    $skillIds = array_values(array_unique($skillIds));
    if ($skillIds === []) {
        sendResponse('error', 'Teknisi harus memiliki minimal satu keahlian.', null, 400);
    }
    $db->beginTransaction();
    try {
        $profile = $db->prepare(
            'UPDATE technician_profiles tp JOIN users u ON u.id = tp.user_id
             SET tp.service_area = :area, tp.phone = :phone, tp.is_available = :available
             WHERE tp.user_id = :id AND u.role = "technician"'
        );
        $profile->execute([
            ':area' => $area,
            ':phone' => $phone ?: null,
            ':available' => $available ? 1 : 0,
            ':id' => $staffId,
        ]);
        if (!$profile->rowCount()) {
            $exists = $db->prepare(
                'SELECT user_id FROM technician_profiles WHERE user_id = :id'
            );
            $exists->execute([':id' => $staffId]);
            if ($exists->fetchColumn() === false) {
                $db->rollBack();
                sendResponse('error', 'Profil teknisi tidak ditemukan.', null, 404);
            }
        }
        $db->prepare('DELETE FROM technician_skills WHERE technician_id = :id')
            ->execute([':id' => $staffId]);
        $insertSkill = $db->prepare(
            'INSERT INTO technician_skills (technician_id, category_id)
             VALUES (:technician_id, :category_id)'
        );
        foreach ($skillIds as $skillId) {
            $insertSkill->execute([
                ':technician_id' => $staffId,
                ':category_id' => $skillId,
            ]);
        }
        $db->commit();
        sendResponse('success', 'Profil teknisi diperbarui.', null);
    } catch (PDOException $exception) {
        if ($db->inTransaction()) {
            $db->rollBack();
        }
        if ((string)$exception->getCode() === '23000') {
            sendResponse('error', 'Salah satu keahlian tidak tersedia.', null, 409);
        }
        error_log('SerFix technician update: ' . $exception->getMessage());
        sendResponse('error', 'Profil teknisi gagal diperbarui.', null, 500);
    }
}
if ($action !== 'create') {
    sendResponse('error', 'Aksi staf tidak dikenal.', null, 400);
}
$name = trim((string)($input['name'] ?? ''));
$email = strtolower(trim((string)($input['email'] ?? '')));
$password = $input['password'] ?? '';
$role = $input['role'] ?? '';
$area = trim((string)($input['service_area'] ?? ''));
$phone = trim((string)($input['phone'] ?? ''));
$skills = $input['skill_ids'] ?? [];
if (!is_string($password) || $name === '' || mb_strlen($name) > 100 ||
    !filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($email) > 150 ||
    strlen($password) < 8 || strlen($password) > 72 ||
    !in_array($role, ['technician', 'admin', 'manager'], true) ||
    ($role === 'technician' && ($area === '' || mb_strlen($area) > 120 || !is_array($skills))) ||
    mb_strlen($phone) > 30) {
    sendResponse('error', 'Data staf tidak valid. Password minimal 8 karakter; teknisi wajib memiliki area dan keahlian.', null, 400);
}

$skillIds = [];
foreach ($skills as $skillId) {
    $validId = filter_var($skillId, FILTER_VALIDATE_INT);
    if ($validId === false || $validId === null || $validId < 1) {
        sendResponse('error', 'Daftar keahlian tidak valid.', null, 400);
    }
    $skillIds[] = (int)$validId;
}
$skillIds = array_values(array_unique($skillIds));
if ($role === 'technician' && $skillIds === []) {
    sendResponse('error', 'Teknisi harus memiliki minimal satu keahlian.', null, 400);
}

$db->beginTransaction();
try {
    $stmt = $db->prepare(
        'INSERT INTO users (name, email, password_hash, role)
         VALUES (:name, :email, :password_hash, :role)'
    );
    $stmt->execute([
        ':name' => $name,
        ':email' => $email,
        ':password_hash' => password_hash($password, PASSWORD_DEFAULT),
        ':role' => $role,
    ]);
    $userId = (int)$db->lastInsertId();
    if ($role === 'technician') {
        $profile = $db->prepare(
            'INSERT INTO technician_profiles (user_id, service_area, phone)
             VALUES (:user_id, :area, :phone)'
        );
        $profile->execute([':user_id' => $userId, ':area' => $area, ':phone' => $phone ?: null]);
        $skillStmt = $db->prepare(
            'INSERT INTO technician_skills (technician_id, category_id) VALUES (:user_id, :category_id)'
        );
        foreach ($skillIds as $skillId) {
            $skillStmt->execute([':user_id' => $userId, ':category_id' => $skillId]);
        }
    }
    $db->commit();
    sendResponse('success', 'Akun staf berhasil dibuat.', ['id' => $userId, 'role' => $role], 201);
} catch (PDOException $exception) {
    if ($db->inTransaction()) {
        $db->rollBack();
    }
    if ((string)$exception->getCode() === '23000') {
        sendResponse('error', 'Email sudah terdaftar atau keahlian tidak valid.', null, 409);
    }
    error_log('SerFix staff create: ' . $exception->getMessage());
    sendResponse('error', 'Akun staf gagal dibuat.', null, 500);
}
