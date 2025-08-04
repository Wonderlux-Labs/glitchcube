-- MariaDB initialization script for Glitch Cube and Home Assistant
-- This script creates both databases and sets up proper users and permissions

-- Create databases
CREATE DATABASE IF NOT EXISTS `glitchcube` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE DATABASE IF NOT EXISTS `homeassistant` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Create users and grant permissions
-- Glitch Cube application user
CREATE USER IF NOT EXISTS 'glitchcube'@'%' IDENTIFIED BY 'glitchcube';
GRANT ALL PRIVILEGES ON `glitchcube`.* TO 'glitchcube'@'%';

-- Home Assistant user (separate for security)
CREATE USER IF NOT EXISTS 'homeassistant'@'%' IDENTIFIED BY 'homeassistant';
GRANT ALL PRIVILEGES ON `homeassistant`.* TO 'homeassistant'@'%';

-- Shared read-only user for analytics/monitoring
CREATE USER IF NOT EXISTS 'glitchcube_readonly'@'%' IDENTIFIED BY 'readonly123';
GRANT SELECT ON `glitchcube`.* TO 'glitchcube_readonly'@'%';
GRANT SELECT ON `homeassistant`.* TO 'glitchcube_readonly'@'%';

-- Performance and monitoring configuration
-- Enable slow query log
SET GLOBAL slow_query_log = 'ON';
SET GLOBAL long_query_time = 2;

-- Optimize for InnoDB (Home Assistant preference)
SET GLOBAL innodb_buffer_pool_size = 268435456; -- 256MB
SET GLOBAL innodb_log_file_size = 67108864;     -- 64MB

-- Create basic tables for Glitch Cube if they don't exist
USE `glitchcube`;

-- Conversations table for persistence
CREATE TABLE IF NOT EXISTS `conversations` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `session_id` VARCHAR(36) NOT NULL,
  `user_message` TEXT NOT NULL,
  `ai_response` TEXT NOT NULL,
  `mood` VARCHAR(50) DEFAULT 'neutral',
  `suggested_mood` VARCHAR(50) DEFAULT 'neutral',
  `confidence` DECIMAL(3,2) DEFAULT 0.95,
  `model_used` VARCHAR(100) DEFAULT 'unknown',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_session_id` (`session_id`),
  INDEX `idx_created_at` (`created_at`),
  INDEX `idx_mood` (`mood`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Device status and monitoring
CREATE TABLE IF NOT EXISTS `device_status` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `device_id` VARCHAR(50) NOT NULL,
  `status_type` VARCHAR(50) NOT NULL,
  `status_data` JSON,
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_device_id` (`device_id`),
  INDEX `idx_status_type` (`status_type`),
  INDEX `idx_created_at` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Session analytics
CREATE TABLE IF NOT EXISTS `session_analytics` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `session_id` VARCHAR(36) NOT NULL,
  `start_time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `end_time` TIMESTAMP NULL,
  `message_count` INT UNSIGNED DEFAULT 0,
  `duration_seconds` INT UNSIGNED DEFAULT 0,
  `final_mood` VARCHAR(50) DEFAULT 'neutral',
  `visitor_type` VARCHAR(50) DEFAULT 'unknown',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `unique_session` (`session_id`),
  INDEX `idx_start_time` (`start_time`),
  INDEX `idx_visitor_type` (`visitor_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Flush privileges to ensure all changes take effect
FLUSH PRIVILEGES;