<?php

function getBearerToken(): ?string {
    $headers = function_exists('getallheaders') ? getallheaders() : [];
    $authorization = $headers['Authorization'] ?? $headers['authorization'] ??
        $_SERVER['HTTP_AUTHORIZATION'] ?? $_SERVER['REDIRECT_HTTP_AUTHORIZATION'] ?? '';

    if (!is_string($authorization) || !preg_match('/^Bearer ([a-f0-9]{64})$/i', trim($authorization), $matches)) {
        return null;
    }

    return $matches[1];
}

function createUserSession(PDO $db, int $userId): string {
    $token = bin2hex(random_bytes(32));
    $db->exec("DELETE FROM user_sessions WHERE expires_at <= NOW()");
    $stmt = $db->prepare(
        "INSERT INTO user_sessions (user_id, token_hash, expires_at)
         VALUES (:user_id, :token_hash, DATE_ADD(NOW(), INTERVAL 30 DAY))"
    );
    $stmt->execute([
        ':user_id' => $userId,
        ':token_hash' => hash('sha256', $token),
    ]);

    return $token;
}

function requireAuthenticatedUser(PDO $db): int {
    $token = getBearerToken();
    if ($token === null) {
        sendResponse("error", "Autentikasi diperlukan.", null, 401);
    }

    $stmt = $db->prepare(
        "SELECT u.id, u.name, u.email, u.role
         FROM user_sessions s JOIN users u ON u.id = s.user_id
         WHERE s.token_hash = :token_hash AND s.expires_at > NOW()
         LIMIT 1"
    );
    $stmt->execute([':token_hash' => hash('sha256', $token)]);
    $user = $stmt->fetch(PDO::FETCH_ASSOC);

    if ($user === false) {
        sendResponse("error", "Sesi tidak valid atau telah kedaluwarsa. Silakan login kembali.", null, 401);
    }

    $GLOBALS['authenticated_user'] = [
        'id' => (int)$user['id'],
        'name' => $user['name'],
        'email' => $user['email'],
        'role' => $user['role'],
    ];
    return (int)$user['id'];
}

function requireUserRole(PDO $db, array $roles): array {
    requireAuthenticatedUser($db);
    $user = $GLOBALS['authenticated_user'] ?? null;
    if (!is_array($user) || !in_array($user['role'], $roles, true)) {
        sendResponse("error", "Anda tidak memiliki izin untuk melakukan tindakan ini.", null, 403);
    }

    return $user;
}

function requireVehicleOwnership(PDO $db, int $userId, int $vehicleId): void {
    $stmt = $db->prepare(
        "SELECT id FROM vehicles WHERE id = :vehicle_id AND user_id = :user_id LIMIT 1"
    );
    $stmt->execute([
        ':vehicle_id' => $vehicleId,
        ':user_id' => $userId,
    ]);

    if ($stmt->fetchColumn() === false) {
        sendResponse("error", "Kendaraan tidak ditemukan.", null, 404);
    }
}
