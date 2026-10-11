-- =============================================================================
-- sql/04_views.sql
-- =============================================================================
USE carnet_import;

-- -----------------------------------------------------------------------
-- VIEW 1: v_eligible_vehicles
-- All vehicles that have at least one ELIGIBLE import application.
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_eligible_vehicles AS
SELECT
    v.vehicle_id,
    v.vin,
    v.model,
    v.manufacture_year,
    v.fuel_type,
    v.steering_side,
    m.name   AS manufacturer_name,
    c.country_name AS origin_country
FROM vehicle v
JOIN manufacturer m ON m.manufacturer_id = v.manufacturer_id
JOIN country      c ON c.country_id       = v.origin_country_id
WHERE EXISTS (
    SELECT 1 FROM import_application ia
    WHERE ia.vehicle_id = v.vehicle_id AND ia.status = 'ELIGIBLE'
);

-- -----------------------------------------------------------------------
-- VIEW 2: v_active_carnets
-- Carnets that are currently ACTIVE and not yet expired.
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_active_carnets AS
SELECT
    cn.carnet_id,
    cn.carnet_number,
    cn.issue_date,
    cn.expiry_date,
    cn.status,
    c.country_name AS issuing_country,
    DATEDIFF(cn.expiry_date, CURDATE()) AS days_until_expiry
FROM carnet cn
JOIN country c ON c.country_id = cn.issuing_country_id
WHERE cn.status = 'ACTIVE'
  AND cn.expiry_date >= CURDATE();

-- -----------------------------------------------------------------------
-- VIEW 3: v_pending_applications
-- Applications still in PENDING or UNDER_REVIEW status.
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_pending_applications AS
SELECT
    ia.application_id,
    ia.application_date,
    ia.status,
    ap.full_name        AS applicant_name,
    ap.passport_number,
    v.vin,
    v.model,
    it.type_name        AS import_type
FROM import_application ia
JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
JOIN vehicle     v  ON v.vehicle_id      = ia.vehicle_id
JOIN import_type it ON it.import_type_id = ia.import_type_id
WHERE ia.status IN ('PENDING','UNDER_REVIEW');

-- -----------------------------------------------------------------------
-- VIEW 4: v_applications_missing_documents
-- Applications where at least one mandatory document has NOT been submitted.
-- Uses NOT EXISTS to find mandatory documents not in submitted_document.
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_applications_missing_documents AS
SELECT
    ia.application_id,
    ap.full_name    AS applicant_name,
    ap.passport_number,
    v.model         AS vehicle_model,
    ia.status,
    ia.application_date
FROM import_application ia
JOIN applicant ap ON ap.applicant_id = ia.applicant_id
JOIN vehicle   v  ON v.vehicle_id    = ia.vehicle_id
WHERE NOT EXISTS (
    -- Check: is every mandatory document present?
    SELECT 1
    FROM document d
    WHERE d.is_mandatory = TRUE
      AND NOT EXISTS (
          SELECT 1
          FROM submitted_document sd
          WHERE sd.application_id = ia.application_id
            AND sd.document_id    = d.document_id
      )
) = FALSE   -- i.e. there IS a missing mandatory document
OR EXISTS (
    SELECT 1
    FROM document d
    WHERE d.is_mandatory = TRUE
      AND NOT EXISTS (
          SELECT 1
          FROM submitted_document sd
          WHERE sd.application_id = ia.application_id
            AND sd.document_id    = d.document_id
      )
);

-- -----------------------------------------------------------------------
-- VIEW 5: v_carnets_expiring_soon
-- Active carnets whose expiry date is within the next 30 days.
-- -----------------------------------------------------------------------
CREATE OR REPLACE VIEW v_carnets_expiring_soon AS
SELECT
    cn.carnet_id,
    cn.carnet_number,
    cn.expiry_date,
    DATEDIFF(cn.expiry_date, CURDATE()) AS days_left,
    c.country_name AS issuing_country,
    cn.status
FROM carnet cn
JOIN country c ON c.country_id = cn.issuing_country_id
WHERE cn.status = 'ACTIVE'
  AND cn.expiry_date BETWEEN CURDATE() AND DATE_ADD(CURDATE(), INTERVAL 30 DAY);
