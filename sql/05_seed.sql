-- =============================================================================
-- sql/05_seed.sql  –  Realistic seed data for carnet_import
-- =============================================================================
USE carnet_import;

-- -----------------------------------------------------------------------
-- Countries (12) with correct driving side
-- -----------------------------------------------------------------------
INSERT INTO country (country_name, driving_side, is_carnet_member) VALUES
  ('United Kingdom',  'LEFT',  TRUE),
  ('Japan',           'LEFT',  TRUE),
  ('Germany',         'RIGHT', TRUE),
  ('United States',   'RIGHT', TRUE),
  ('UAE',             'RIGHT', TRUE),
  ('Australia',       'LEFT',  TRUE),
  ('Thailand',        'LEFT',  TRUE),
  ('Nepal',           'LEFT',  TRUE),
  ('South Africa',    'LEFT',  TRUE),
  ('France',          'RIGHT', TRUE),
  ('Singapore',       'LEFT',  TRUE),
  ('Sri Lanka',       'LEFT',  TRUE);

-- -----------------------------------------------------------------------
-- Manufacturers (10)
-- -----------------------------------------------------------------------
INSERT INTO manufacturer (name, country_id) VALUES
  ('Toyota',      (SELECT country_id FROM country WHERE country_name='Japan')),
  ('Honda',       (SELECT country_id FROM country WHERE country_name='Japan')),
  ('BMW',         (SELECT country_id FROM country WHERE country_name='Germany')),
  ('Mercedes-Benz',(SELECT country_id FROM country WHERE country_name='Germany')),
  ('Ford',        (SELECT country_id FROM country WHERE country_name='United States')),
  ('Tesla',       (SELECT country_id FROM country WHERE country_name='United States')),
  ('Land Rover',  (SELECT country_id FROM country WHERE country_name='United Kingdom')),
  ('Renault',     (SELECT country_id FROM country WHERE country_name='France')),
  ('Nissan',      (SELECT country_id FROM country WHERE country_name='Japan')),
  ('Hyundai',     (SELECT country_id FROM country WHERE country_name='South Africa'));

-- -----------------------------------------------------------------------
-- Import types (3)
-- -----------------------------------------------------------------------
INSERT INTO import_type (type_name) VALUES
  ('TEMPORARY_CARNET'),
  ('PERMANENT_IMPORT'),
  ('RETURNING_RESIDENT');

-- -----------------------------------------------------------------------
-- Documents (10)
-- -----------------------------------------------------------------------
INSERT INTO document (document_name, is_mandatory) VALUES
  ('Passport',                  TRUE),
  ('Registration Certificate',  TRUE),
  ('Invoice',                   TRUE),
  ('Insurance',                 TRUE),
  ('Carnet Document',           FALSE),
  ('Compliance Certificate',    TRUE),
  ('Bill of Lading',            TRUE),
  ('Customs Declaration',       TRUE),
  ('Road Worthiness Certificate', FALSE),
  ('Emission Test Certificate', FALSE);

-- -----------------------------------------------------------------------
-- Eligibility rules (~10, including one inactive)
-- NULL import_type_id = applies to ALL types
-- -----------------------------------------------------------------------
INSERT INTO eligibility_rule
  (rule_name, rule_type, operator, expected_value, import_type_id, is_active, effective_date, description)
VALUES
  -- Rule 1: All types – vehicle must have RIGHT-hand steering for India
  ('Right-Hand Drive Requirement', 'DRIVING_SIDE', '=', 'RIGHT', NULL, TRUE, '2020-01-01',
   'India follows left-hand traffic. Only right-hand drive vehicles allowed'),

  -- Rule 2: All types – fuel must not be diesel older standard (allow petrol,diesel,electric,hybrid)
  ('Approved Fuel Types', 'FUEL_TYPE', 'IN', 'PETROL,DIESEL,ELECTRIC,HYBRID', NULL, TRUE, '2020-01-01',
   'CNG vehicles from abroad not approved for import'),

  -- Rule 3: All types – engine <= 3000cc (general restriction)
  ('Engine Displacement Limit', 'ENGINE_CC', '<=', '3000', NULL, TRUE, '2020-01-01',
   'Engine capacity must not exceed 3000cc'),

  -- Rule 4: PERMANENT_IMPORT only – vehicle age <= 3 years
  ('Age Limit for Permanent Import', 'VEHICLE_AGE', '<=', '3',
   (SELECT import_type_id FROM import_type WHERE type_name='PERMANENT_IMPORT'),
   TRUE, '2020-01-01', 'Permanently imported vehicles must be max 3 years old'),

  -- Rule 5: RETURNING_RESIDENT – vehicle age <= 5 years
  ('Age Limit for Returning Resident', 'VEHICLE_AGE', '<=', '5',
   (SELECT import_type_id FROM import_type WHERE type_name='RETURNING_RESIDENT'),
   TRUE, '2020-01-01', 'Returning resident vehicles must be max 5 years old'),

  -- Rule 6: TEMPORARY_CARNET – carnet must be valid
  ('Valid Carnet Required', 'CARNET_VALID', '=', 'YES',
   (SELECT import_type_id FROM import_type WHERE type_name='TEMPORARY_CARNET'),
   TRUE, '2020-01-01', 'Carnet de Passages must be active and not expired'),

  -- Rule 7: All types – Passport must be submitted
  ('Passport Document Required', 'DOCUMENT_REQUIRED', '=', 'Passport', NULL, TRUE, '2020-01-01',
   'A valid passport copy must be submitted'),

  -- Rule 8: All types – Registration Certificate required
  ('Registration Certificate Required', 'DOCUMENT_REQUIRED', '=', 'Registration Certificate',
   NULL, TRUE, '2020-01-01', 'Vehicle registration certificate from country of origin required'),

  -- Rule 9: All types – Insurance required
  ('Insurance Document Required', 'DOCUMENT_REQUIRED', '=', 'Insurance',
   NULL, TRUE, '2020-01-01', 'Valid insurance document required'),

  -- Rule 10: INACTIVE rule (example of a retired rule)
  ('Old Age Restriction (Retired)', 'VEHICLE_AGE', '<=', '10', NULL, FALSE, '2015-01-01',
   'This rule was retired in 2020. Vehicles up to 10 years were once allowed');

-- -----------------------------------------------------------------------
-- Vehicles (20) – mix of years, fuels, steering sides
-- Some will PASS all rules, some will FAIL on various criteria
-- -----------------------------------------------------------------------
INSERT INTO vehicle (vin, manufacturer_id, model, manufacture_year, fuel_type, engine_cc, steering_side, origin_country_id)
VALUES
  -- RIGHT-hand drive, recent, good fuel – likely to PASS permanent import
  ('JT3HZ89R1V4012301', (SELECT manufacturer_id FROM manufacturer WHERE name='Toyota'),
   'Land Cruiser', 2024, 'PETROL', 2700, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- RIGHT-hand drive, recent, electric – PASS
  ('JTMAB3FV8ND112345', (SELECT manufacturer_id FROM manufacturer WHERE name='Toyota'),
   'RAV4 Hybrid', 2023, 'HYBRID', 2500, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- RIGHT-hand drive but too old for permanent (2018) – FAIL age rule
  ('SAJWA2BZ2GMC12345', (SELECT manufacturer_id FROM manufacturer WHERE name='Land Rover'),
   'Defender 110', 2018, 'DIESEL', 2200, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='United Kingdom')),

  -- LEFT-hand drive – FAIL driving side
  ('WBA3A5C58DF123456', (SELECT manufacturer_id FROM manufacturer WHERE name='BMW'),
   '3 Series', 2022, 'PETROL', 2000, 'LEFT',
   (SELECT country_id FROM country WHERE country_name='Germany')),

  -- CNG fuel – FAIL fuel type
  ('1HGBH41JXMN109876', (SELECT manufacturer_id FROM manufacturer WHERE name='Honda'),
   'Civic CNG', 2023, 'CNG', 1500, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- Engine > 3000cc – FAIL engine limit
  ('WDDZF8JB8KA123789', (SELECT manufacturer_id FROM manufacturer WHERE name='Mercedes-Benz'),
   'S 450', 2022, 'PETROL', 3500, 'LEFT',
   (SELECT country_id FROM country WHERE country_name='Germany')),

  -- Good vehicle for RETURNING_RESIDENT (age=4, RIGHT, petrol, 1600cc)
  ('JTDKB20U913456789', (SELECT manufacturer_id FROM manufacturer WHERE name='Toyota'),
   'Yaris', 2022, 'PETROL', 1600, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- Good vehicle for TEMPORARY_CARNET
  ('MRHGJ6520NP123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Honda'),
   'CR-V', 2024, 'HYBRID', 1995, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- RIGHT, 2023, diesel 2000cc – good for all
  ('VF1RFD00XH1234567', (SELECT manufacturer_id FROM manufacturer WHERE name='Renault'),
   'Koleos', 2023, 'DIESEL', 2000, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='France')),

  -- Electric, RIGHT, 2024 – PASS all
  ('5YJ3E1EA8PF123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Tesla'),
   'Model 3', 2024, 'ELECTRIC', 0, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='United States')),

  -- LEFT, 2020, petrol – FAIL driving side
  ('1FTFW1ET2DFC12345', (SELECT manufacturer_id FROM manufacturer WHERE name='Ford'),
   'F-150', 2020, 'PETROL', 2700, 'LEFT',
   (SELECT country_id FROM country WHERE country_name='United States')),

  -- RIGHT, 2025, petrol, 1500cc – NEW vehicle
  ('MHFAX53G8J4123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Toyota'),
   'Corolla Cross', 2025, 'PETROL', 1500, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- RIGHT, 2021, diesel, 2200cc
  ('SJNFFAJ11U2345678', (SELECT manufacturer_id FROM manufacturer WHERE name='Nissan'),
   'X-Trail', 2021, 'DIESEL', 2200, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- LEFT, old 2010 – FAIL multiple
  ('KMHFH41S7AA123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Hyundai'),
   'Santa Fe', 2010, 'PETROL', 2400, 'LEFT',
   (SELECT country_id FROM country WHERE country_name='South Africa')),

  -- RIGHT, 2019, 3000cc exactly (boundary – PASS engine)
  ('KNMAT2MTXKP123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Nissan'),
   'Patrol', 2019, 'DIESEL', 3000, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Japan')),

  -- RIGHT, 2022, ELECTRIC, 0cc
  ('YV4L12UE5P2123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Land Rover'),
   'Range Rover Sport', 2022, 'HYBRID', 2000, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='United Kingdom')),

  -- RIGHT, 2023, petrol 1200cc – Singapore origin
  ('RLHGJ6520NP456789', (SELECT manufacturer_id FROM manufacturer WHERE name='Honda'),
   'Jazz', 2023, 'PETROL', 1200, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Singapore')),

  -- RIGHT, 2024, Hybrid – Australia
  ('6FPAAAJ3XER123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Toyota'),
   'Prius', 2024, 'HYBRID', 1800, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='Australia')),

  -- RIGHT, 2020, petrol 2500cc – UK
  ('SALWA2BZ3HA123456', (SELECT manufacturer_id FROM manufacturer WHERE name='Land Rover'),
   'Discovery Sport', 2020, 'PETROL', 2500, 'RIGHT',
   (SELECT country_id FROM country WHERE country_name='United Kingdom')),

  -- LEFT, 2024, electric – FAIL driving side
  ('WBA7F2C52JG123456', (SELECT manufacturer_id FROM manufacturer WHERE name='BMW'),
   'iX3', 2024, 'ELECTRIC', 0, 'LEFT',
   (SELECT country_id FROM country WHERE country_name='Germany'));

-- -----------------------------------------------------------------------
-- Applicants (10)
-- -----------------------------------------------------------------------
INSERT INTO applicant (full_name, passport_number, phone, email, address) VALUES
  ('Arjun Sharma',      'IN1234567', '+91-9876543210', 'arjun@example.com',   '12 MG Road, Bengaluru, India'),
  ('Priya Patel',       'IN2345678', '+91-9876543211', 'priya@example.com',   '45 Nehru Nagar, Mumbai, India'),
  ('Rahul Gupta',       'IN3456789', '+91-9876543212', 'rahul@example.com',   '78 Civil Lines, Delhi, India'),
  ('Ananya Krishnan',   'IN4567890', '+91-9876543213', 'ananya@example.com',  '23 Anna Salai, Chennai, India'),
  ('Vikram Singh',      'IN5678901', '+91-9876543214', 'vikram@example.com',  '56 Park Street, Kolkata, India'),
  ('Sunita Rao',        'IN6789012', '+91-9876543215', 'sunita@example.com',  '34 Banjara Hills, Hyderabad, India'),
  ('Deepak Nair',       'IN7890123', '+91-9876543216', 'deepak@example.com',  '89 Marine Drive, Kochi, India'),
  ('Kavita Mehta',      'IN8901234', '+91-9876543217', 'kavita@example.com',  '67 Mall Road, Shimla, India'),
  ('Rohit Agarwal',     'IN9012345', '+91-9876543218', 'rohit@example.com',   '11 Civil Lines, Jaipur, India'),
  ('Meera Iyer',        'IN0123456', '+91-9876543219', 'meera@example.com',   '28 Residency Road, Bengaluru, India');

-- -----------------------------------------------------------------------
-- Carnets (12) – some expired, some expiring soon, some long validity
-- -----------------------------------------------------------------------
INSERT INTO carnet (carnet_number, issuing_country_id, issue_date, expiry_date)
VALUES
  -- Active, long validity
  ('CPD-UK-2024-001', (SELECT country_id FROM country WHERE country_name='United Kingdom'),
   '2024-01-15', '2026-12-31'),
  ('CPD-JP-2024-002', (SELECT country_id FROM country WHERE country_name='Japan'),
   '2024-03-01', '2026-11-30'),
  ('CPD-AU-2024-003', (SELECT country_id FROM country WHERE country_name='Australia'),
   '2024-06-01', '2026-10-31'),
  -- Active but expiring within 30 days
  ('CPD-SG-2026-004', (SELECT country_id FROM country WHERE country_name='Singapore'),
   '2026-01-01', DATE_ADD(CURDATE(), INTERVAL 15 DAY)),
  ('CPD-TH-2026-005', (SELECT country_id FROM country WHERE country_name='Thailand'),
   '2026-01-01', DATE_ADD(CURDATE(), INTERVAL 25 DAY)),
  ('CPD-NP-2026-006', (SELECT country_id FROM country WHERE country_name='Nepal'),
   '2026-02-01', DATE_ADD(CURDATE(), INTERVAL 10 DAY)),
  -- Expired (these will be set to EXPIRED by trigger)
  ('CPD-ZA-2023-007', (SELECT country_id FROM country WHERE country_name='South Africa'),
   '2023-01-01', '2024-12-31'),
  ('CPD-FR-2023-008', (SELECT country_id FROM country WHERE country_name='France'),
   '2023-06-01', '2025-01-01'),
  ('CPD-DE-2024-009', (SELECT country_id FROM country WHERE country_name='Germany'),
   '2024-01-01', '2025-06-30'),
  -- Active carnets
  ('CPD-UAE-2025-010', (SELECT country_id FROM country WHERE country_name='UAE'),
   '2025-01-01', '2027-01-01'),
  ('CPD-LK-2025-011', (SELECT country_id FROM country WHERE country_name='Sri Lanka'),
   '2025-06-01', '2027-06-01'),
  ('CPD-US-2024-012', (SELECT country_id FROM country WHERE country_name='United States'),
   '2024-09-01', '2026-09-01');

-- -----------------------------------------------------------------------
-- Import Applications (15) – covering different import types and vehicles
-- -----------------------------------------------------------------------
-- Temporary carnet applications (need valid carnet + docs)
INSERT INTO import_application (applicant_id, vehicle_id, carnet_id, import_type_id, application_date)
VALUES
  (1,  1,  1, (SELECT import_type_id FROM import_type WHERE type_name='TEMPORARY_CARNET'),  '2026-08-10'),
  (2,  8,  2, (SELECT import_type_id FROM import_type WHERE type_name='TEMPORARY_CARNET'),  '2026-08-15'),
  (3,  3,  3, (SELECT import_type_id FROM import_type WHERE type_name='TEMPORARY_CARNET'),  '2026-09-01'),
  (4,  5,  4, (SELECT import_type_id FROM import_type WHERE type_name='TEMPORARY_CARNET'),  '2026-09-10'),
  (5,  6,  7, (SELECT import_type_id FROM import_type WHERE type_name='TEMPORARY_CARNET'),  '2026-09-20');

-- Permanent import applications
INSERT INTO import_application (applicant_id, vehicle_id, carnet_id, import_type_id, application_date)
VALUES
  (1,  1,  NULL, (SELECT import_type_id FROM import_type WHERE type_name='PERMANENT_IMPORT'),  '2026-08-20'),
  (2,  2,  NULL, (SELECT import_type_id FROM import_type WHERE type_name='PERMANENT_IMPORT'),  '2026-08-25'),
  (3,  4,  NULL, (SELECT import_type_id FROM import_type WHERE type_name='PERMANENT_IMPORT'),  '2026-09-05'),
  (6,  10, NULL, (SELECT import_type_id FROM import_type WHERE type_name='PERMANENT_IMPORT'),  '2026-09-15'),
  (7,  12, NULL, (SELECT import_type_id FROM import_type WHERE type_name='PERMANENT_IMPORT'),  '2026-09-25');

-- Returning resident applications
INSERT INTO import_application (applicant_id, vehicle_id, carnet_id, import_type_id, application_date)
VALUES
  (8,  7,  NULL, (SELECT import_type_id FROM import_type WHERE type_name='RETURNING_RESIDENT'), '2026-08-30'),
  (9,  13, NULL, (SELECT import_type_id FROM import_type WHERE type_name='RETURNING_RESIDENT'), '2026-09-08'),
  (10, 9,  NULL, (SELECT import_type_id FROM import_type WHERE type_name='RETURNING_RESIDENT'), '2026-09-18'),
  (5,  11, NULL, (SELECT import_type_id FROM import_type WHERE type_name='RETURNING_RESIDENT'), '2026-09-28'),
  (6,  14, NULL, (SELECT import_type_id FROM import_type WHERE type_name='RETURNING_RESIDENT'), '2026-10-01');

-- -----------------------------------------------------------------------
-- Submitted Documents for each application
-- -----------------------------------------------------------------------
-- Application 1: all mandatory docs – should PASS carnet check
INSERT INTO submitted_document (application_id, document_id)
SELECT 1, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration','Carnet Document');

-- Application 2: all mandatory docs
INSERT INTO submitted_document (application_id, document_id)
SELECT 2, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 3: missing Insurance – will FAIL that doc rule
INSERT INTO submitted_document (application_id, document_id)
SELECT 3, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 4: all mandatory docs but carnet is expiring soon (still ACTIVE)
INSERT INTO submitted_document (application_id, document_id)
SELECT 4, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 5: all docs, but carnet #7 is EXPIRED
INSERT INTO submitted_document (application_id, document_id)
SELECT 5, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 6 (permanent): all mandatory docs, good vehicle
INSERT INTO submitted_document (application_id, document_id)
SELECT 6, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 7 (permanent): all mandatory docs, good vehicle
INSERT INTO submitted_document (application_id, document_id)
SELECT 7, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 8 (permanent): vehicle is LEFT-hand drive – FAIL
INSERT INTO submitted_document (application_id, document_id)
SELECT 8, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 9 (permanent): Tesla Model 3 – should PASS
INSERT INTO submitted_document (application_id, document_id)
SELECT 9, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 10 (permanent): Corolla Cross – should PASS
INSERT INTO submitted_document (application_id, document_id)
SELECT 10, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 11 (returning): Yaris 2022 – should PASS (age=4, <=5 rule)
INSERT INTO submitted_document (application_id, document_id)
SELECT 11, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 12 (returning): X-Trail 2021 – age=5, should PASS
INSERT INTO submitted_document (application_id, document_id)
SELECT 12, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 13 (returning): Renault Koleos 2023 – PASS
INSERT INTO submitted_document (application_id, document_id)
SELECT 13, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 14 (returning): Ford F-150 LEFT-hand – FAIL driving side
INSERT INTO submitted_document (application_id, document_id)
SELECT 14, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- Application 15 (returning): Hyundai Santa Fe 2010 LEFT – FAIL multiple
INSERT INTO submitted_document (application_id, document_id)
SELECT 15, document_id FROM document
WHERE document_name IN ('Passport','Registration Certificate','Invoice','Insurance','Compliance Certificate','Bill of Lading','Customs Declaration');

-- -----------------------------------------------------------------------
-- Run CheckEligibility for all 15 applications to populate results
-- -----------------------------------------------------------------------
CALL CheckEligibility(1);
CALL CheckEligibility(2);
CALL CheckEligibility(3);
CALL CheckEligibility(4);
CALL CheckEligibility(5);
CALL CheckEligibility(6);
CALL CheckEligibility(7);
CALL CheckEligibility(8);
CALL CheckEligibility(9);
CALL CheckEligibility(10);
CALL CheckEligibility(11);
CALL CheckEligibility(12);
CALL CheckEligibility(13);
CALL CheckEligibility(14);
CALL CheckEligibility(15);
