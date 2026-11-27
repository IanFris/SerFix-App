<?php
declare(strict_types=1);

require_once __DIR__ . '/../helpers/response.php';
require_once __DIR__ . '/../config/database.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    sendResponse('error', 'Gunakan metode POST.', null, 405);
}

$input = getRequestData();
$action = (string)($input['action'] ?? '');
$db = (new Database())->getConnection();

if ($action === 'request') {
    $email = trim((string)($input['email'] ?? ''));
    if (!filter_var($email, FILTER_VALIDATE_EMAIL)) {
        sendResponse('error', 'Format email tidak valid.', null, 400);
    }

    $stmt = $db->prepare('SELECT id, name FROM users WHERE email = :email LIMIT 1');
    $stmt->execute([':email' => $email]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);
    if ($user) {
        $otp = (string)random_int(100000, 999999);
        $otpHash = hash('sha256', $otp);
        $db->prepare('UPDATE password_reset_otps SET used_at = NOW()
                      WHERE user_id = :user_id AND used_at IS NULL')
           ->execute([':user_id' => (int)$user['id']]);
        $db->prepare('INSERT INTO password_reset_otps
                      (user_id, otp_hash, expires_at)
                      VALUES (:user_id, :otp_hash, DATE_ADD(NOW(), INTERVAL 10 MINUTE))')
           ->execute([':user_id' => (int)$user['id'], ':otp_hash' => $otpHash]);
        error_log('SerFix password reset OTP for ' . $email . ': ' . $otp);
    }

    sendResponse('success',
        'Jika email terdaftar, kode OTP telah dikirim. Kode berlaku 10 menit.',
        null);
}

if ($action === 'reset') {
    $email = trim((string)($input['email'] ?? ''));
    $otp = trim((string)($input['otp'] ?? ''));
    $password = (string)($input['password'] ?? '');
    if (!filter_var($email, FILTER_VALIDATE_EMAIL) ||
        !preg_match('/^\d{6}$/', $otp) ||
        strlen($password) < 6 || strlen($password) > 72) {
        sendResponse('error', 'Email, OTP, atau password baru tidak valid.', null, 400);
    }

    $db->beginTransaction();
    try {
        $stmt = $db->prepare('SELECT id FROM users WHERE email = :email LIMIT 1');
        $stmt->execute([':email' => $email]);
        $user = $stmt->fetch(PDO::FETCH_ASSOC);
        if (!$user) {
            $db->rollBack();
            sendResponse('error', 'Kode OTP tidak valid atau sudah kedaluwarsa.', null, 400);
        }

        $otpHash = hash('sha256', $otp);
        $tokenStmt = $db->prepare('SELECT id, attempts FROM password_reset_otps
                                   WHERE user_id = :user_id AND otp_hash = :otp_hash
                                     AND used_at IS NULL AND expires_at > NOW()
                                   ORDER BY id DESC LIMIT 1 FOR UPDATE');
        $tokenStmt->execute([':user_id' => (int)$user['id'], ':otp_hash' => $otpHash]);
        $token = $tokenStmt->fetch(PDO::FETCH_ASSOC);
        if (!$token) {
            $db->prepare('UPDATE password_reset_otps SET attempts = attempts + 1
                          WHERE user_id = :user_id AND used_at IS NULL')
               ->execute([':user_id' => (int)$user['id']]);
            $db->commit();
            sendResponse('error', 'Kode OTP tidak valid atau sudah kedaluwarsa.', null, 400);
        }
        if ((int)$token['attempts'] >= 5) {
            $db->rollBack();
            sendResponse('error', 'Percobaan OTP terlalu banyak. Minta kode baru.', null, 429);
        }

        $passwordHash = password_hash($password, PASSWORD_BCRYPT);
        $db->prepare('UPDATE users SET password_hash = :password_hash, updated_at = NOW()
                      WHERE id = :id')
           ->execute([':password_hash' => $passwordHash, ':id' => (int)$user['id']]);
        $db->prepare('UPDATE password_reset_otps SET used_at = NOW()
                      WHERE id = :id')
           ->execute([':id' => (int)$token['id']]);
        $db->prepare('DELETE FROM user_sessions WHERE user_id = :user_id')
           ->execute([':user_id' => (int)$user['id']]);
        $db->commit();
        sendResponse('success', 'Password berhasil diperbarui. Silakan login kembali.', null);
    } catch (Throwable $exception) {
        if ($db->inTransaction()) $db->rollBack();
        error_log('SerFix password reset: ' . $exception->getMessage());
        sendResponse('error', 'Password gagal diperbarui.', null, 500);
    }
}

sendResponse('error', 'Aksi reset password tidak valid.', null, 400);
