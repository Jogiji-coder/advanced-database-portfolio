-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 06 · Role-based access control (least privilege)
-- Run as superuser:  psql -d waynes_clinic -f 06_roles_security.sql
--
-- Patient records are Protected Health Information under HIPAA, so each
-- job role is granted only what it needs. Group roles are NOLOGIN; real
-- staff logins would be members of these groups.
-- =====================================================================
\set ON_ERROR_STOP 1
SET search_path TO clinic, public;

DO $$
DECLARE r text;
BEGIN
    FOREACH r IN ARRAY ARRAY['wc_receptionist','wc_doctor','wc_lab_scientist','wc_pharmacist','wc_analyst']
    LOOP
        IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
            EXECUTE format('REASSIGN OWNED BY %I TO postgres', r);
            EXECUTE format('DROP OWNED BY %I', r);
            EXECUTE format('DROP ROLE %I', r);
        END IF;
        EXECUTE format('CREATE ROLE %I NOLOGIN', r);
    END LOOP;
END $$;

REVOKE ALL ON SCHEMA clinic FROM PUBLIC;
GRANT USAGE ON SCHEMA clinic TO wc_receptionist, wc_doctor, wc_lab_scientist, wc_pharmacist, wc_analyst;

-- Reference data is readable by every clinical role
GRANT SELECT ON postal_area, department, specialty, doctor, doctor_availability,
                icd10_code, medication, lab_test
      TO wc_receptionist, wc_doctor, wc_lab_scientist, wc_pharmacist;

-- Receptionist: registers patients and books appointments; never sees clinical notes
GRANT SELECT, INSERT, UPDATE ON patient     TO wc_receptionist;
GRANT SELECT, INSERT          ON appointment TO wc_receptionist;
GRANT UPDATE (status, scheduled_start, scheduled_end, reason) ON appointment TO wc_receptionist;
GRANT EXECUTE ON FUNCTION book_appointment(integer, integer, timestamptz, varchar),
                          available_slots(integer, date) TO wc_receptionist;
GRANT SELECT ON v_doctor_schedule TO wc_receptionist;

-- Doctor: full clinical read, records diagnoses, prescriptions and lab orders
GRANT SELECT ON patient, patient_allergy, appointment, diagnosis, prescription,
                prescription_item, lab_order, lab_result TO wc_doctor;
GRANT INSERT, UPDATE ON diagnosis, prescription, prescription_item, lab_order, patient_allergy TO wc_doctor;
GRANT UPDATE (status) ON appointment TO wc_doctor;
GRANT EXECUTE ON FUNCTION record_diagnosis(bigint, varchar, varchar, text),
                          get_patient_history(varchar) TO wc_doctor;
GRANT SELECT ON v_patient_history, v_doctor_schedule TO wc_doctor;

-- Lab scientist: sees orders and files results; no diagnoses or prescriptions
GRANT SELECT ON lab_order, appointment TO wc_lab_scientist;
GRANT UPDATE (status) ON lab_order TO wc_lab_scientist;
GRANT SELECT, INSERT, UPDATE ON lab_result TO wc_lab_scientist;

-- Pharmacist: reads prescriptions and allergies, adjusts stock
GRANT SELECT ON prescription, prescription_item, patient_allergy, appointment TO wc_pharmacist;
GRANT SELECT (patient_id, mrn, first_name, last_name, date_of_birth) ON patient TO wc_pharmacist;
GRANT UPDATE (status) ON prescription TO wc_pharmacist;
GRANT UPDATE (stock_on_hand) ON medication TO wc_pharmacist;

-- Analyst: de-identified aggregate access only (no names, contacts or notes)
CREATE OR REPLACE VIEW clinic.v_deidentified_encounters AS
SELECT a.appointment_id,
       date_trunc('month', a.scheduled_start)::date          AS visit_month,
       (floor(date_part('year', age(a.scheduled_start, p.date_of_birth)) / 10) * 10)::int AS age_band,
       p.sex,
       left(p.zip_code, 3)                                   AS zip3,
       dpt.name                                              AS department,
       a.status,
       dx.icd10_code
FROM appointment a
JOIN patient    p   ON p.patient_id = a.patient_id
JOIN doctor     d   ON d.doctor_id  = a.doctor_id
JOIN department dpt ON dpt.department_id = d.department_id
LEFT JOIN diagnosis dx ON dx.appointment_id = a.appointment_id AND dx.diagnosis_type = 'Primary';
COMMENT ON VIEW clinic.v_deidentified_encounters IS 'HIPAA Safe-Harbor style extract: age bands, 3-digit ZIP, month only, no identifiers';
GRANT SELECT ON v_deidentified_encounters TO wc_analyst;

-- Evidence: privilege matrix
-- r = SELECT, a = INSERT, w = UPDATE (column-level grants count, shown as w*)
CREATE OR REPLACE FUNCTION pg_temp.privs(p_role text, p_rel oid) RETURNS text
LANGUAGE sql STABLE AS $$
    SELECT concat(
        CASE WHEN has_table_privilege(p_role, p_rel, 'SELECT') THEN 'r'
             WHEN has_any_column_privilege(p_role, p_rel, 'SELECT') THEN 'r*' END,
        CASE WHEN has_table_privilege(p_role, p_rel, 'INSERT') THEN 'a' END,
        CASE WHEN has_table_privilege(p_role, p_rel, 'UPDATE') THEN 'w'
             WHEN has_any_column_privilege(p_role, p_rel, 'UPDATE') THEN 'w*' END)
$$;
\pset footer off
\echo 'Privilege matrix (r=SELECT a=INSERT w=UPDATE, *=selected columns only):'
SELECT c.relname AS object,
       CASE c.relkind WHEN 'v' THEN 'view' ELSE 'table' END AS kind,
       pg_temp.privs('wc_receptionist',  c.oid) AS receptionist,
       pg_temp.privs('wc_doctor',        c.oid) AS doctor,
       pg_temp.privs('wc_lab_scientist', c.oid) AS lab_scientist,
       pg_temp.privs('wc_pharmacist',    c.oid) AS pharmacist,
       pg_temp.privs('wc_analyst',       c.oid) AS analyst
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'clinic' AND c.relkind IN ('r', 'v')
ORDER BY c.relkind, c.relname;

\echo ''
\echo 'Proof 1: a receptionist cannot read diagnoses'
\set ON_ERROR_STOP 0
SET ROLE wc_receptionist;
SELECT * FROM clinic.diagnosis LIMIT 1;
RESET ROLE;
\echo 'Proof 2: an analyst sees only de-identified rows'
SET ROLE wc_analyst;
SELECT * FROM clinic.v_deidentified_encounters ORDER BY appointment_id LIMIT 5;
SELECT first_name FROM clinic.patient LIMIT 1;
RESET ROLE;
