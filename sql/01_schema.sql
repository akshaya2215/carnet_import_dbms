-- =============================================================================
-- sql/01_schema.sql  –  carnet_import database schema
-- =============================================================================
-- 3NF JUSTIFICATION
-- -----------------------------------------------------------------------
-- First Normal Form (1NF):
--   Every column holds a single atomic value (no repeating groups).
--   Every table has a primary key.
-- Second Normal Form (2NF):
--   Every non-key column depends on the WHOLE primary key.
--   The only composite PK tables are submitted_document (application_id,
--   document_id) where both non-key columns (submitted_date, is_verified)
--   depend on the full pair, not just one part. All other tables have a
--   single-column surrogate PK so 2NF is automatically satisfied.
-- Third Normal Form (3NF):
--   No transitive dependencies. For example:
--   - manufacturer.country_id → country.country_name/driving_side are
--     stored in `country`, not repeated in `manufacturer`.
--   - vehicle links to `manufacturer` by FK; manufacturer details live
--     only in `manufacturer`.
--   - eligibility_rule.import_type_id → import_type.type_name lives in
--     `import_type`, not repeated in `eligibility_rule`.
--   - No non-key column determines another non-key column within the
--     same table.
-- =============================================================================

DROP DATABASE IF EXISTS carnet_import;
CREATE DATABASE carnet_import CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE carnet_import;

-- 1. Country of origin / registration
CREATE TABLE country (
    country_id       INT AUTO_INCREMENT PRIMARY KEY,
    country_name     VARCHAR(100) UNIQUE NOT NULL,
    driving_side     ENUM('LEFT','RIGHT') NOT NULL,
    is_carnet_member BOOLEAN DEFAULT TRUE,
    CONSTRAINT chk_country_name CHECK (CHAR_LENGTH(country_name) > 0)
) ENGINE=InnoDB;

-- 2. Vehicle manufacturer (linked to its home country)
CREATE TABLE manufacturer (
    manufacturer_id INT AUTO_INCREMENT PRIMARY KEY,
    name            VARCHAR(100) UNIQUE NOT NULL,
    country_id      INT NOT NULL,
    CONSTRAINT fk_mfr_country FOREIGN KEY (country_id)
        REFERENCES country(country_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 3. Vehicle being imported
CREATE TABLE vehicle (
    vehicle_id        INT AUTO_INCREMENT PRIMARY KEY,
    vin               VARCHAR(50) UNIQUE NOT NULL,
    manufacturer_id   INT NOT NULL,
    model             VARCHAR(100) NOT NULL,
    manufacture_year  INT NOT NULL,
    fuel_type         ENUM('PETROL','DIESEL','ELECTRIC','HYBRID','CNG'),
    engine_cc         INT,
    steering_side     ENUM('LEFT','RIGHT'),
    origin_country_id INT NOT NULL,
    CONSTRAINT chk_year CHECK (manufacture_year >= 1900),
    CONSTRAINT chk_engine_cc CHECK (engine_cc >= 0),
    CONSTRAINT fk_veh_mfr FOREIGN KEY (manufacturer_id)
        REFERENCES manufacturer(manufacturer_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_veh_country FOREIGN KEY (origin_country_id)
        REFERENCES country(country_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 4. Person applying to import the vehicle
CREATE TABLE applicant (
    applicant_id    INT AUTO_INCREMENT PRIMARY KEY,
    full_name       VARCHAR(200) NOT NULL,
    passport_number VARCHAR(50)  UNIQUE NOT NULL,
    phone           VARCHAR(20),
    email           VARCHAR(150),
    address         TEXT
) ENGINE=InnoDB;

-- 5. Carnet de Passages en Douane document
CREATE TABLE carnet (
    carnet_id         INT AUTO_INCREMENT PRIMARY KEY,
    carnet_number     VARCHAR(50) UNIQUE NOT NULL,
    issuing_country_id INT NOT NULL,
    issue_date        DATE,
    expiry_date       DATE,
    status            ENUM('ACTIVE','EXPIRED','CANCELLED') DEFAULT 'ACTIVE',
    CONSTRAINT chk_carnet_dates CHECK (expiry_date > issue_date),
    CONSTRAINT fk_carnet_country FOREIGN KEY (issuing_country_id)
        REFERENCES country(country_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 6. Type of import request
CREATE TABLE import_type (
    import_type_id INT AUTO_INCREMENT PRIMARY KEY,
    type_name      VARCHAR(60) UNIQUE NOT NULL   -- TEMPORARY_CARNET, PERMANENT_IMPORT, RETURNING_RESIDENT
) ENGINE=InnoDB;

-- 7. A single import application
CREATE TABLE import_application (
    application_id   INT AUTO_INCREMENT PRIMARY KEY,
    applicant_id     INT NOT NULL,
    vehicle_id       INT NOT NULL,
    carnet_id        INT DEFAULT NULL,            -- NULL for non-carnet imports
    import_type_id   INT NOT NULL,
    application_date DATE DEFAULT (CURDATE()),
    status           ENUM('PENDING','UNDER_REVIEW','ELIGIBLE','REJECTED') DEFAULT 'PENDING',
    CONSTRAINT fk_app_applicant FOREIGN KEY (applicant_id)
        REFERENCES applicant(applicant_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_app_vehicle FOREIGN KEY (vehicle_id)
        REFERENCES vehicle(vehicle_id) ON DELETE RESTRICT ON UPDATE CASCADE,
    CONSTRAINT fk_app_carnet FOREIGN KEY (carnet_id)
        REFERENCES carnet(carnet_id) ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_app_type FOREIGN KEY (import_type_id)
        REFERENCES import_type(import_type_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 8. Rules that the DB evaluates (not hardcoded in Python)
CREATE TABLE eligibility_rule (
    rule_id        INT AUTO_INCREMENT PRIMARY KEY,
    rule_name      VARCHAR(100) NOT NULL,
    rule_type      ENUM('VEHICLE_AGE','DRIVING_SIDE','FUEL_TYPE','ENGINE_CC',
                        'CARNET_VALID','DOCUMENT_REQUIRED') NOT NULL,
    operator       ENUM('=','!=','<','<=','>','>=','IN') NOT NULL,
    expected_value VARCHAR(100) NOT NULL,
    import_type_id INT DEFAULT NULL,              -- NULL = applies to ALL import types
    is_active      BOOLEAN DEFAULT TRUE,
    effective_date DATE NOT NULL,
    last_updated   TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    description    VARCHAR(255),
    CONSTRAINT fk_rule_type FOREIGN KEY (import_type_id)
        REFERENCES import_type(import_type_id) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 9. Required documents (master list)
CREATE TABLE document (
    document_id   INT AUTO_INCREMENT PRIMARY KEY,
    document_name VARCHAR(150) UNIQUE NOT NULL,
    is_mandatory  BOOLEAN DEFAULT TRUE
) ENGINE=InnoDB;

-- 10. Documents submitted per application  (M:N)
CREATE TABLE submitted_document (
    application_id INT NOT NULL,
    document_id    INT NOT NULL,
    submitted_date DATE DEFAULT (CURDATE()),
    is_verified    BOOLEAN DEFAULT FALSE,
    PRIMARY KEY (application_id, document_id),
    CONSTRAINT fk_sd_app FOREIGN KEY (application_id)
        REFERENCES import_application(application_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_sd_doc FOREIGN KEY (document_id)
        REFERENCES document(document_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 11. Overall eligibility result for an application run
CREATE TABLE eligibility_result (
    result_id       INT AUTO_INCREMENT PRIMARY KEY,
    application_id  INT NOT NULL,
    evaluation_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    overall_result  ENUM('PASSED','FAILED') NOT NULL,
    summary_reason  TEXT,
    CONSTRAINT fk_er_app FOREIGN KEY (application_id)
        REFERENCES import_application(application_id) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 12. Per-rule outcome within one result  (M:N between result and rule)
CREATE TABLE rule_evaluation (
    evaluation_id INT AUTO_INCREMENT PRIMARY KEY,
    result_id     INT NOT NULL,
    rule_id       INT NOT NULL,
    outcome       ENUM('PASS','FAIL') NOT NULL,
    actual_value  VARCHAR(100),
    message       VARCHAR(255),
    CONSTRAINT fk_re_result FOREIGN KEY (result_id)
        REFERENCES eligibility_result(result_id) ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_re_rule FOREIGN KEY (rule_id)
        REFERENCES eligibility_rule(rule_id) ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB;

-- 13. Audit log for rule changes (trigger-written)
CREATE TABLE rule_audit_log (
    log_id             INT AUTO_INCREMENT PRIMARY KEY,
    rule_id            INT,
    action             VARCHAR(20),
    old_expected_value VARCHAR(100),
    new_expected_value VARCHAR(100),
    old_is_active      TINYINT(1),
    new_is_active      TINYINT(1),
    changed_at         TIMESTAMP DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- 14. Admin users for the management UI
CREATE TABLE admin_user (
    admin_id      INT AUTO_INCREMENT PRIMARY KEY,
    username      VARCHAR(80) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL
) ENGINE=InnoDB;

-- =============================================================================
-- Additional indexes for performance
-- =============================================================================
CREATE INDEX idx_vehicle_vin          ON vehicle(vin);
CREATE INDEX idx_vehicle_mfr          ON vehicle(manufacturer_id);
CREATE INDEX idx_applicant_passport   ON applicant(passport_number);
CREATE INDEX idx_carnet_number        ON carnet(carnet_number);
CREATE INDEX idx_application_status   ON import_application(status);
