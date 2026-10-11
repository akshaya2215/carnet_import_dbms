-- =============================================================================
-- sql/02_functions_procedures.sql
-- Function: CalculateVehicleAge
-- Procedure: CheckEligibility
-- =============================================================================
USE carnet_import;

DELIMITER $$

-- -----------------------------------------------------------------------
-- FUNCTION: CalculateVehicleAge
-- Returns how many years old a vehicle is based on its manufacture year.
-- -----------------------------------------------------------------------
CREATE FUNCTION CalculateVehicleAge(p_vehicle_id INT)
RETURNS INT
READS SQL DATA
NOT DETERMINISTIC
BEGIN
  DECLARE v_year INT;
  SELECT manufacture_year INTO v_year
  FROM vehicle WHERE vehicle_id = p_vehicle_id;
  RETURN YEAR(CURDATE()) - v_year;
END$$

-- -----------------------------------------------------------------------
-- PROCEDURE: CheckEligibility
-- Evaluates every active eligibility rule for a given application.
-- For each rule it computes the actual value from the DB and compares it
-- to the expected value using the rule's operator.
-- Results are stored in eligibility_result and rule_evaluation.
-- The application status is updated to ELIGIBLE or REJECTED.
-- IMPORTANT: This procedure does NOT issue START TRANSACTION / COMMIT.
-- The CALLER (Flask) owns the transaction.
-- -----------------------------------------------------------------------
CREATE PROCEDURE CheckEligibility(IN p_application_id INT)
BEGIN
  -- Control variables
  DECLARE done INT DEFAULT 0;
  DECLARE v_vehicle_id     INT;
  DECLARE v_carnet_id      INT;
  DECLARE v_import_type_id INT;
  DECLARE v_result_id      INT;
  DECLARE v_fail_count     INT DEFAULT 0;
  DECLARE v_exists         INT DEFAULT 0;

  -- Cursor row variables
  DECLARE r_id       INT;
  DECLARE r_name     VARCHAR(100);
  DECLARE r_type     VARCHAR(30);
  DECLARE r_op       VARCHAR(5);
  DECLARE r_expected VARCHAR(100);

  -- Working variables
  DECLARE v_actual   VARCHAR(100);
  DECLARE v_cmp      VARCHAR(100);
  DECLARE v_pass     TINYINT;
  DECLARE v_msg      VARCHAR(255);
  DECLARE v_summary  TEXT;

  -- Cursor fetches all active rules that apply to this import type
  -- (NULL import_type_id on a rule means it applies to ALL types)
  DECLARE cur CURSOR FOR
    SELECT rule_id, rule_name, rule_type, operator, expected_value
    FROM   eligibility_rule
    WHERE  is_active = 1
      AND  effective_date <= CURDATE()
      AND  (import_type_id IS NULL OR import_type_id = v_import_type_id);

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET done = 1;

  -- Validate the application exists
  SELECT COUNT(*) INTO v_exists
  FROM import_application WHERE application_id = p_application_id;

  IF v_exists = 0 THEN
    SIGNAL SQLSTATE '45000'
      SET MESSAGE_TEXT = 'Application not found';
  END IF;

  -- Load the IDs we need for rule evaluation
  SELECT vehicle_id, carnet_id, import_type_id
  INTO   v_vehicle_id, v_carnet_id, v_import_type_id
  FROM   import_application
  WHERE  application_id = p_application_id;

  -- Create a fresh result row (history is kept; every run adds a new row)
  INSERT INTO eligibility_result (application_id, overall_result, summary_reason)
  VALUES (p_application_id, 'FAILED', 'Evaluation in progress');
  SET v_result_id = LAST_INSERT_ID();

  OPEN cur;
  read_loop: LOOP
    FETCH cur INTO r_id, r_name, r_type, r_op, r_expected;
    IF done = 1 THEN LEAVE read_loop; END IF;

    SET v_actual = NULL;
    SET v_cmp    = r_expected;   -- default comparison value

    -- Compute the actual value from the DB based on rule type
    CASE r_type
      WHEN 'VEHICLE_AGE' THEN
        SET v_actual = CAST(CalculateVehicleAge(v_vehicle_id) AS CHAR);

      WHEN 'DRIVING_SIDE' THEN
        SELECT steering_side INTO v_actual
        FROM vehicle WHERE vehicle_id = v_vehicle_id;

      WHEN 'FUEL_TYPE' THEN
        SELECT fuel_type INTO v_actual
        FROM vehicle WHERE vehicle_id = v_vehicle_id;

      WHEN 'ENGINE_CC' THEN
        SELECT CAST(engine_cc AS CHAR) INTO v_actual
        FROM vehicle WHERE vehicle_id = v_vehicle_id;

      WHEN 'CARNET_VALID' THEN
        -- We compare actual vs 'YES'; expected_value in the rule is also 'YES'
        SET v_cmp = 'YES';
        SELECT IF(COUNT(*) > 0, 'YES', 'NO') INTO v_actual
        FROM carnet
        WHERE carnet_id = v_carnet_id
          AND status = 'ACTIVE'
          AND expiry_date >= CURDATE();

      WHEN 'DOCUMENT_REQUIRED' THEN
        -- expected_value holds the document NAME; we check if it was submitted
        SET v_cmp = 'YES';
        SELECT IF(COUNT(*) > 0, 'YES', 'NO') INTO v_actual
        FROM submitted_document sd
        JOIN document d ON d.document_id = sd.document_id
        WHERE sd.application_id = p_application_id
          AND d.document_name    = r_expected;

      ELSE
        SET v_actual = NULL;
    END CASE;

    -- Evaluate the operator; COALESCE handles NULL actual → FAIL
    SET v_pass = COALESCE(
      CASE r_op
        WHEN '='  THEN v_actual =  v_cmp
        WHEN '!=' THEN v_actual <> v_cmp
        WHEN '<'  THEN CAST(v_actual AS DECIMAL(10,2)) <  CAST(v_cmp AS DECIMAL(10,2))
        WHEN '<=' THEN CAST(v_actual AS DECIMAL(10,2)) <= CAST(v_cmp AS DECIMAL(10,2))
        WHEN '>'  THEN CAST(v_actual AS DECIMAL(10,2)) >  CAST(v_cmp AS DECIMAL(10,2))
        WHEN '>=' THEN CAST(v_actual AS DECIMAL(10,2)) >= CAST(v_cmp AS DECIMAL(10,2))
        WHEN 'IN' THEN FIND_IN_SET(v_actual, v_cmp) > 0
        ELSE 0
      END, 0);

    -- Build a human-readable message
    IF v_pass = 1 THEN
      SET v_msg = CONCAT(r_name, ': OK (actual ', COALESCE(v_actual,'N/A'), ')');
    ELSE
      SET v_msg = CONCAT(r_name, ': FAILED (actual ', COALESCE(v_actual,'N/A'),
                         ', required ', r_op, ' ', r_expected, ')');
      SET v_fail_count = v_fail_count + 1;
    END IF;

    -- Save the per-rule outcome
    INSERT INTO rule_evaluation (result_id, rule_id, outcome, actual_value, message)
    VALUES (v_result_id, r_id, IF(v_pass = 1, 'PASS', 'FAIL'), v_actual, v_msg);

  END LOOP;
  CLOSE cur;

  -- Build the overall summary from failed rules
  SELECT GROUP_CONCAT(message SEPARATOR '; ') INTO v_summary
  FROM rule_evaluation
  WHERE result_id = v_result_id AND outcome = 'FAIL';

  -- Finalise the eligibility_result row
  UPDATE eligibility_result
  SET overall_result = IF(v_fail_count = 0, 'PASSED', 'FAILED'),
      summary_reason  = IF(v_fail_count = 0, 'All active rules passed', v_summary)
  WHERE result_id = v_result_id;

  -- Update the application status
  UPDATE import_application
  SET status = IF(v_fail_count = 0, 'ELIGIBLE', 'REJECTED')
  WHERE application_id = p_application_id;

END$$

DELIMITER ;
