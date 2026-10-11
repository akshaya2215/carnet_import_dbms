-- =============================================================================
-- sql/06_showcase_queries.sql
-- Demonstration queries used in the /reports page.
-- Each query is labelled with the SQL concept it demonstrates.
-- =============================================================================
USE carnet_import;

-- =====================================================================
-- CONCEPT: JOIN (INNER + LEFT)
-- Show all applications with applicant, vehicle, manufacturer, country
-- =====================================================================
SELECT
    ia.application_id,
    ia.application_date,
    ia.status,
    ap.full_name          AS applicant,
    ap.passport_number,
    v.vin,
    v.model               AS vehicle_model,
    v.manufacture_year,
    m.name                AS manufacturer,
    c.country_name        AS origin_country,
    it.type_name          AS import_type
FROM import_application ia
JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
JOIN vehicle     v  ON v.vehicle_id      = ia.vehicle_id
JOIN manufacturer m  ON m.manufacturer_id = v.manufacturer_id
JOIN country      c  ON c.country_id      = v.origin_country_id
JOIN import_type  it ON it.import_type_id = ia.import_type_id
ORDER BY ia.application_id;

-- =====================================================================
-- CONCEPT: GROUP BY / HAVING
-- Applications per origin country; only countries with > 2 applications
-- =====================================================================
SELECT
    c.country_name,
    COUNT(ia.application_id) AS total_applications
FROM import_application ia
JOIN vehicle  v  ON v.vehicle_id    = ia.vehicle_id
JOIN country  c  ON c.country_id    = v.origin_country_id
GROUP BY c.country_id, c.country_name
HAVING COUNT(ia.application_id) > 2
ORDER BY total_applications DESC;

-- =====================================================================
-- CONCEPT: SUBQUERY (correlated)
-- Vehicles older than the average manufacture year of all vehicles
-- =====================================================================
SELECT
    v.vehicle_id,
    v.vin,
    v.model,
    v.manufacture_year,
    m.name AS manufacturer,
    (YEAR(CURDATE()) - v.manufacture_year) AS age_years
FROM vehicle v
JOIN manufacturer m ON m.manufacturer_id = v.manufacturer_id
WHERE v.manufacture_year < (
    SELECT AVG(manufacture_year) FROM vehicle
)
ORDER BY v.manufacture_year;

-- =====================================================================
-- CONCEPT: EXISTS
-- Applications where ALL mandatory documents have been submitted
-- =====================================================================
SELECT
    ia.application_id,
    ap.full_name   AS applicant,
    ia.status,
    it.type_name   AS import_type
FROM import_application ia
JOIN applicant   ap ON ap.applicant_id   = ia.applicant_id
JOIN import_type it ON it.import_type_id = ia.import_type_id
WHERE NOT EXISTS (
    SELECT 1 FROM document d
    WHERE d.is_mandatory = TRUE
      AND NOT EXISTS (
          SELECT 1 FROM submitted_document sd
          WHERE sd.application_id = ia.application_id
            AND sd.document_id    = d.document_id
      )
)
ORDER BY ia.application_id;

-- =====================================================================
-- CONCEPT: CASE expression
-- Classify vehicles by age category and label application status
-- =====================================================================
SELECT
    ia.application_id,
    v.model,
    v.manufacture_year,
    (YEAR(CURDATE()) - v.manufacture_year) AS age_years,
    CASE
        WHEN (YEAR(CURDATE()) - v.manufacture_year) <= 3 THEN 'NEW'
        WHEN (YEAR(CURDATE()) - v.manufacture_year) <= 7 THEN 'MID'
        ELSE 'OLD'
    END AS age_category,
    CASE ia.status
        WHEN 'ELIGIBLE'  THEN 'Approved for Import'
        WHEN 'REJECTED'  THEN 'Rejected'
        WHEN 'PENDING'   THEN 'Awaiting Review'
        WHEN 'UNDER_REVIEW' THEN 'Under Review'
        ELSE ia.status
    END AS status_label
FROM import_application ia
JOIN vehicle v ON v.vehicle_id = ia.vehicle_id
ORDER BY age_years;

-- =====================================================================
-- Most frequently failed rules
-- =====================================================================
SELECT
    er.rule_id,
    er.rule_name,
    COUNT(re.evaluation_id) AS fail_count
FROM eligibility_rule er
JOIN rule_evaluation re ON re.rule_id = er.rule_id
WHERE re.outcome = 'FAIL'
GROUP BY er.rule_id, er.rule_name
ORDER BY fail_count DESC
LIMIT 10;

-- =====================================================================
-- Applications by manufacturer
-- =====================================================================
SELECT
    m.name AS manufacturer,
    COUNT(ia.application_id) AS applications,
    SUM(ia.status = 'ELIGIBLE') AS eligible,
    SUM(ia.status = 'REJECTED') AS rejected
FROM import_application ia
JOIN vehicle      v ON v.vehicle_id      = ia.vehicle_id
JOIN manufacturer m ON m.manufacturer_id = v.manufacturer_id
GROUP BY m.manufacturer_id, m.name
ORDER BY applications DESC;

-- =====================================================================
-- Applications by import type
-- =====================================================================
SELECT
    it.type_name,
    COUNT(ia.application_id) AS total,
    SUM(ia.status = 'ELIGIBLE') AS eligible,
    SUM(ia.status = 'REJECTED') AS rejected,
    SUM(ia.status IN ('PENDING','UNDER_REVIEW')) AS pending
FROM import_application ia
JOIN import_type it ON it.import_type_id = ia.import_type_id
GROUP BY it.import_type_id, it.type_name;

-- =====================================================================
-- Expired carnets
-- =====================================================================
SELECT
    cn.carnet_id,
    cn.carnet_number,
    cn.expiry_date,
    c.country_name AS issuing_country,
    cn.status
FROM carnet cn
JOIN country c ON c.country_id = cn.issuing_country_id
WHERE cn.status = 'EXPIRED'
ORDER BY cn.expiry_date DESC;

-- =====================================================================
-- Carnets expiring soon (from view)
-- =====================================================================
SELECT * FROM v_carnets_expiring_soon ORDER BY days_left;

-- =====================================================================
-- Applications with missing mandatory documents (from view)
-- =====================================================================
SELECT * FROM v_applications_missing_documents;

-- =====================================================================
-- Rejection reasons breakdown
-- =====================================================================
SELECT
    er.rule_name,
    er.rule_type,
    COUNT(re.evaluation_id) AS rejections,
    GROUP_CONCAT(DISTINCT re.actual_value ORDER BY re.actual_value SEPARATOR ', ') AS actual_values_seen
FROM rule_evaluation re
JOIN eligibility_rule er ON er.rule_id = re.rule_id
WHERE re.outcome = 'FAIL'
GROUP BY er.rule_id, er.rule_name, er.rule_type
ORDER BY rejections DESC;
