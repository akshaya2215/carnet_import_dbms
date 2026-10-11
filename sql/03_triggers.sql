-- =============================================================================
-- sql/03_triggers.sql
-- =============================================================================
USE carnet_import;

DELIMITER $$

-- -----------------------------------------------------------------------
-- TRIGGER 1: trg_carnet_before_insert
-- If a carnet being inserted already has an expiry date in the past,
-- automatically set its status to EXPIRED instead of ACTIVE.
-- -----------------------------------------------------------------------
CREATE TRIGGER trg_carnet_before_insert
BEFORE INSERT ON carnet
FOR EACH ROW
BEGIN
  IF NEW.expiry_date IS NOT NULL AND NEW.expiry_date < CURDATE() THEN
    SET NEW.status = 'EXPIRED';
  END IF;
END$$

-- -----------------------------------------------------------------------
-- TRIGGER 2: trg_carnet_before_update
-- Same logic applied whenever a carnet row is updated.
-- -----------------------------------------------------------------------
CREATE TRIGGER trg_carnet_before_update
BEFORE UPDATE ON carnet
FOR EACH ROW
BEGIN
  IF NEW.expiry_date IS NOT NULL AND NEW.expiry_date < CURDATE() THEN
    SET NEW.status = 'EXPIRED';
  END IF;
END$$

-- -----------------------------------------------------------------------
-- TRIGGER 3: trg_rule_after_insert
-- Whenever a new eligibility rule is created, write an audit log entry.
-- -----------------------------------------------------------------------
CREATE TRIGGER trg_rule_after_insert
AFTER INSERT ON eligibility_rule
FOR EACH ROW
BEGIN
  INSERT INTO rule_audit_log
    (rule_id, action, old_expected_value, new_expected_value, old_is_active, new_is_active)
  VALUES
    (NEW.rule_id, 'INSERT', NULL, NEW.expected_value, NULL, NEW.is_active);
END$$

-- -----------------------------------------------------------------------
-- TRIGGER 4: trg_rule_after_update
-- Whenever a rule is changed, record what changed in the audit log.
-- -----------------------------------------------------------------------
CREATE TRIGGER trg_rule_after_update
AFTER UPDATE ON eligibility_rule
FOR EACH ROW
BEGIN
  INSERT INTO rule_audit_log
    (rule_id, action, old_expected_value, new_expected_value, old_is_active, new_is_active)
  VALUES
    (NEW.rule_id, 'UPDATE', OLD.expected_value, NEW.expected_value, OLD.is_active, NEW.is_active);
END$$

-- -----------------------------------------------------------------------
-- TRIGGER 5: trg_submitted_document_after_insert
-- When a document is submitted, move the application from PENDING to
-- UNDER_REVIEW so staff know it needs attention.
-- -----------------------------------------------------------------------
CREATE TRIGGER trg_submitted_document_after_insert
AFTER INSERT ON submitted_document
FOR EACH ROW
BEGIN
  UPDATE import_application
  SET status = 'UNDER_REVIEW'
  WHERE application_id = NEW.application_id
    AND status = 'PENDING';
END$$

DELIMITER ;
