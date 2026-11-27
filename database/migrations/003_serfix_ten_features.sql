USE `serfix_db`;

CREATE TABLE IF NOT EXISTS `push_devices` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT UNSIGNED NOT NULL,
  `token` VARCHAR(500) NOT NULL,
  `platform` VARCHAR(30) NOT NULL DEFAULT 'unknown',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_push_user_token` (`user_id`, `token`),
  CONSTRAINT `fk_push_device_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `customer_assets` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `customer_id` INT UNSIGNED NOT NULL,
  `name` VARCHAR(160) NOT NULL,
  `category_id` INT UNSIGNED NULL,
  `brand` VARCHAR(120) NOT NULL DEFAULT '',
  `model` VARCHAR(120) NOT NULL DEFAULT '',
  `serial_number` VARCHAR(160) NOT NULL DEFAULT '',
  `installed_at` DATE NULL,
  `next_service_at` DATE NULL,
  `notes` VARCHAR(500) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  KEY `idx_assets_customer_service` (`customer_id`, `next_service_at`),
  CONSTRAINT `fk_asset_customer` FOREIGN KEY (`customer_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_asset_category` FOREIGN KEY (`category_id`) REFERENCES `service_categories` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `asset_service_history` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `asset_id` BIGINT UNSIGNED NOT NULL,
  `service_request_id` BIGINT UNSIGNED NULL,
  `performed_at` DATETIME NOT NULL,
  `description` VARCHAR(500) NOT NULL,
  `cost` DECIMAL(12,2) UNSIGNED NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_asset_history` (`asset_id`, `performed_at`),
  CONSTRAINT `fk_asset_history_asset` FOREIGN KEY (`asset_id`) REFERENCES `customer_assets` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_asset_history_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `reschedule_proposals` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `service_request_id` BIGINT UNSIGNED NOT NULL,
  `proposed_by` INT UNSIGNED NOT NULL,
  `proposed_at` DATETIME NOT NULL,
  `status` ENUM('pending','approved','rejected','cancelled') NOT NULL DEFAULT 'pending',
  `reason` VARCHAR(500) NOT NULL DEFAULT '',
  `responded_at` DATETIME NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY `idx_reschedule_request_status` (`service_request_id`, `status`),
  CONSTRAINT `fk_reschedule_request` FOREIGN KEY (`service_request_id`) REFERENCES `service_requests` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_reschedule_user` FOREIGN KEY (`proposed_by`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `payment_gateway_transactions` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `payment_id` BIGINT UNSIGNED NOT NULL,
  `provider` VARCHAR(60) NOT NULL,
  `gateway_reference` VARCHAR(160) NOT NULL,
  `checkout_url` VARCHAR(1000) NOT NULL DEFAULT '',
  `raw_status` VARCHAR(80) NOT NULL DEFAULT 'pending',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_gateway_reference` (`gateway_reference`),
  CONSTRAINT `fk_gateway_payment` FOREIGN KEY (`payment_id`) REFERENCES `payments` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `offline_mutations` (
  `id` BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id` INT UNSIGNED NOT NULL,
  `client_mutation_id` VARCHAR(100) NOT NULL,
  `endpoint` VARCHAR(255) NOT NULL,
  `payload_json` JSON NOT NULL,
  `status` ENUM('pending','synced','failed') NOT NULL DEFAULT 'pending',
  `error_message` VARCHAR(500) NOT NULL DEFAULT '',
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_offline_mutation` (`user_id`, `client_mutation_id`),
  CONSTRAINT `fk_offline_mutation_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
