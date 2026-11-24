-- SerFix database schema and starter service catalog.
-- Existing AutoLog data is not deleted. Import this file into a fresh SerFix database.
CREATE DATABASE IF NOT EXISTS `serfix_db`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `serfix_db`;

CREATE TABLE IF NOT EXISTS `users` (
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(150) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL,
  `role` ENUM('customer', 'technician', 'admin', 'manager') NOT NULL DEFAULT 'customer',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `user_sessions` (
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT UNSIGNED NOT NULL,
  `token_hash` CHAR(64) NOT NULL UNIQUE,
  `expires_at` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_user_sessions_expiry` (`expires_at`),
  CONSTRAINT `fk_user_sessions_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `admin_users` (
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `email` VARCHAR(150) NOT NULL UNIQUE,
  `password_hash` VARCHAR(255) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_categories` (
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `slug` VARCHAR(80) NOT NULL UNIQUE,
  `name` VARCHAR(120) NOT NULL,
  `description` VARCHAR(500) NOT NULL DEFAULT '',
  `base_fee` DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0,
  `default_duration_minutes` SMALLINT UNSIGNED NOT NULL DEFAULT 120,
  `warranty_months` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `technician_profiles` (
  `user_id` INT UNSIGNED PRIMARY KEY,
  `service_area` VARCHAR(120) NOT NULL,
  `phone` VARCHAR(30) NULL,
  `is_available` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `fk_technician_profile_user` FOREIGN KEY (`user_id`)
    REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `technician_skills` (
  `technician_id` INT UNSIGNED NOT NULL,
  `category_id` INT UNSIGNED NOT NULL,
  PRIMARY KEY (`technician_id`, `category_id`),
  CONSTRAINT `fk_technician_skill_user` FOREIGN KEY (`technician_id`)
    REFERENCES `technician_profiles` (`user_id`) ON DELETE CASCADE,
  CONSTRAINT `fk_technician_skill_category` FOREIGN KEY (`category_id`)
    REFERENCES `service_categories` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `parts` (
  `id` INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `sku` VARCHAR(60) NOT NULL UNIQUE,
  `name` VARCHAR(150) NOT NULL,
  `description` VARCHAR(500) NOT NULL DEFAULT '',
  `stock_quantity` INT UNSIGNED NOT NULL DEFAULT 0,
  `unit_price` DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0,
  `is_active` TINYINT(1) NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_requests` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `customer_id` INT UNSIGNED NOT NULL,
  `technician_id` INT UNSIGNED NULL,
  `category_id` INT UNSIGNED NOT NULL,
  `device_name` VARCHAR(160) NOT NULL,
  `issue_description` TEXT NOT NULL,
  `service_address` VARCHAR(500) NOT NULL,
  `service_area` VARCHAR(120) NOT NULL,
  `requested_at` DATETIME NOT NULL,
  `duration_minutes` SMALLINT UNSIGNED NOT NULL DEFAULT 120,
  `status` ENUM('requested', 'assigned', 'in_progress', 'waiting_approval', 'completed', 'cancelled')
    NOT NULL DEFAULT 'requested',
  `estimate_amount` DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0,
  `final_amount` DECIMAL(12,2) UNSIGNED NULL,
  `estimate_approved_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY `idx_requests_customer` (`customer_id`, `created_at`),
  KEY `idx_requests_technician_schedule` (`technician_id`, `requested_at`, `status`),
  KEY `idx_requests_status` (`status`, `requested_at`),
  CONSTRAINT `fk_request_customer` FOREIGN KEY (`customer_id`)
    REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_request_technician` FOREIGN KEY (`technician_id`)
    REFERENCES `technician_profiles` (`user_id`) ON DELETE SET NULL,
  CONSTRAINT `fk_request_category` FOREIGN KEY (`category_id`)
    REFERENCES `service_categories` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `work_orders` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL UNIQUE,
  `diagnosis` TEXT NULL,
  `work_description` TEXT NULL,
  `technician_notes` TEXT NULL,
  `started_at` DATETIME NULL,
  `completed_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `fk_work_order_request` FOREIGN KEY (`service_request_id`)
    REFERENCES `service_requests` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `work_order_parts` (
  `work_order_id` BIGINT UNSIGNED NOT NULL,
  `part_id` INT UNSIGNED NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  `unit_price` DECIMAL(12,2) UNSIGNED NOT NULL,
  PRIMARY KEY (`work_order_id`, `part_id`),
  CONSTRAINT `fk_work_order_part_order` FOREIGN KEY (`work_order_id`)
    REFERENCES `work_orders` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_work_order_part_part` FOREIGN KEY (`part_id`)
    REFERENCES `parts` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `payments` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL,
  `customer_id` INT UNSIGNED NOT NULL,
  `amount` DECIMAL(12,2) UNSIGNED NOT NULL,
  `method` ENUM('cash', 'bank_transfer', 'qr') NOT NULL,
  `status` ENUM('pending', 'paid', 'rejected', 'refunded') NOT NULL DEFAULT 'pending',
  `reference` VARCHAR(120) NULL,
  `verified_by` INT UNSIGNED NULL,
  `paid_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_payments_request` (`service_request_id`, `created_at`),
  CONSTRAINT `fk_payment_request` FOREIGN KEY (`service_request_id`)
    REFERENCES `service_requests` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_payment_customer` FOREIGN KEY (`customer_id`)
    REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_payment_verifier` FOREIGN KEY (`verified_by`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `warranties` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL UNIQUE,
  `starts_at` DATE NOT NULL,
  `ends_at` DATE NOT NULL,
  `terms` VARCHAR(500) NOT NULL DEFAULT 'Garansi berlaku untuk pekerjaan dan sparepart yang tercatat.',
  `status` ENUM('active', 'expired', 'claimed', 'void') NOT NULL DEFAULT 'active',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_warranty_request` FOREIGN KEY (`service_request_id`)
    REFERENCES `service_requests` (`id`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `warranty_claims` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `warranty_id` BIGINT UNSIGNED NOT NULL,
  `customer_id` INT UNSIGNED NOT NULL,
  `description` TEXT NOT NULL,
  `status` ENUM('pending', 'approved', 'rejected', 'resolved') NOT NULL DEFAULT 'pending',
  `decision_notes` VARCHAR(500) NULL,
  `decided_by` INT UNSIGNED NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `decided_at` DATETIME NULL,
  KEY `idx_warranty_claims` (`warranty_id`, `created_at`),
  CONSTRAINT `fk_warranty_claim_warranty` FOREIGN KEY (`warranty_id`)
    REFERENCES `warranties` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_warranty_claim_customer` FOREIGN KEY (`customer_id`)
    REFERENCES `users` (`id`) ON DELETE RESTRICT,
  CONSTRAINT `fk_warranty_claim_decider` FOREIGN KEY (`decided_by`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_request_events` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL,
  `actor_id` INT UNSIGNED NULL,
  `event_type` VARCHAR(60) NOT NULL,
  `description` VARCHAR(500) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_request_events` (`service_request_id`, `created_at`),
  CONSTRAINT `fk_request_event_request` FOREIGN KEY (`service_request_id`)
    REFERENCES `service_requests` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_request_event_actor` FOREIGN KEY (`actor_id`)
    REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_notifications` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT UNSIGNED NOT NULL,
  `service_request_id` BIGINT UNSIGNED NULL,
  `title` VARCHAR(160) NOT NULL,
  `message` VARCHAR(500) NOT NULL,
  `is_read` TINYINT(1) NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_notifications_user` (`user_id`, `is_read`, `created_at`),
  CONSTRAINT `fk_notification_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_notification_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_messages` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL,
  `sender_id` INT UNSIGNED NOT NULL,
  `message` TEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_messages_request` (`service_request_id`, `created_at`),
  CONSTRAINT `fk_message_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_message_sender` FOREIGN KEY (`sender_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_tracking` (
  `service_request_id` BIGINT UNSIGNED PRIMARY KEY,
  `status` ENUM('not_started','heading','arrived','working','completed') NOT NULL DEFAULT 'not_started',
  `latitude` DECIMAL(10,7) NULL,
  `longitude` DECIMAL(10,7) NULL,
  `eta_minutes` SMALLINT UNSIGNED NULL,
  `note` VARCHAR(500) NULL,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT `fk_tracking_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_attachments` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL,
  `uploaded_by` INT UNSIGNED NOT NULL,
  `kind` ENUM('damage','repair','payment','signature','other') NOT NULL DEFAULT 'other',
  `file_name` VARCHAR(255) NOT NULL,
  `file_path` VARCHAR(255) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_attachments_request` (`service_request_id`, `created_at`),
  CONSTRAINT `fk_attachment_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_attachment_user` FOREIGN KEY (`uploaded_by`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `service_reviews` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL UNIQUE,
  `customer_id` INT UNSIGNED NOT NULL,
  `technician_id` INT UNSIGNED NOT NULL,
  `rating` TINYINT UNSIGNED NOT NULL,
  `review` VARCHAR(1000) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT `fk_review_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_review_customer` FOREIGN KEY (`customer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_review_technician` FOREIGN KEY (`technician_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `chk_review_rating` CHECK (`rating` BETWEEN 1 AND 5)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT INTO `service_categories`
  (`slug`, `name`, `description`, `base_fee`, `default_duration_minutes`, `warranty_months`)
VALUES
  ('servis-ac', 'Servis AC', 'Pembersihan, pemeriksaan, dan perawatan AC rumah.', 150000, 120, 1),
  ('perbaikan-ac', 'Perbaikan AC', 'Diagnosis dan perbaikan kerusakan unit AC.', 200000, 150, 3),
  ('kulkas', 'Perbaikan kulkas', 'Pemeriksaan dan perbaikan kulkas rumah tangga.', 175000, 150, 3),
  ('mesin-cuci', 'Servis mesin cuci', 'Pemeriksaan dan perbaikan mesin cuci.', 150000, 120, 3),
  ('elektronik-rumah', 'Perbaikan elektronik rumah', 'Servis perangkat elektronik rumah tangga lainnya.', 125000, 120, 1)
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `description` = VALUES(`description`);

INSERT INTO `parts` (`sku`, `name`, `description`, `stock_quantity`, `unit_price`) VALUES
  ('AC-FILTER-01', 'Filter AC universal', 'Filter udara pengganti untuk unit AC rumah.', 12, 85000),
  ('AC-CAP-01', 'Kapasitor AC 35 uF', 'Kapasitor pengganti kompresor AC.', 8, 175000),
  ('AC-DRAIN-01', 'Selang pembuangan AC', 'Selang pembuangan air kondensasi.', 15, 35000),
  ('RF-RELAY-01', 'Relay starter kulkas', 'Relay starter untuk kulkas rumah tangga.', 6, 125000),
  ('WM-HOSE-01', 'Selang mesin cuci', 'Selang inlet/outlet mesin cuci universal.', 10, 55000)
ON DUPLICATE KEY UPDATE
  `name` = VALUES(`name`),
  `description` = VALUES(`description`);
