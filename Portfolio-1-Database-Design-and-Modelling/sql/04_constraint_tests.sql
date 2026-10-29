-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 04 · Integrity-constraint test suite
-- Run:  psql -d waynes_clinic -f 04_constraint_tests.sql
--
-- Every test states the SQLSTATE it expects. "00000" means the statement
-- must succeed. The whole suite runs inside one transaction that is rolled
-- back at the end, so the sample data is left untouched.
-- ON_ERROR_ROLLBACK makes psql wrap each statement in a savepoint, so one
-- failing test does not abort the transaction for the tests that follow.
-- =====================================================================
\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\set SHOW_CONTEXT never
\pset footer off
SET search_path TO clinic, public;
SET timezone TO 'America/New_York';

-- Next Monday (Baltimore time) for the booking tests, so they never fall in the past
SELECT (date_trunc('week', now() AT TIME ZONE 'America/New_York')::date + 7)::text AS next_monday \gset
SELECT (date_trunc('week', now() AT TIME ZONE 'America/New_York')::date + 12)::text AS next_saturday \gset

BEGIN;

\echo ''
\echo '=== ENTITY INTEGRITY & KEYS ==================================='
\echo 'TEST 01 [expect 23505] Duplicate Medical Record Number (UNIQUE uq_patient_mrn)'
INSERT INTO patient (mrn, first_name, last_name, date_of_birth, sex)
VALUES ('WCB0000001', 'Duplicate', 'Person', '1990-01-01', 'F');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 02 [expect 23505] Two doctors with the same licence number (UNIQUE uq_doctor_license)'
INSERT INTO doctor (staff_number, first_name, last_name, specialty_id, department_id, license_number, email)
VALUES ('WCB-D0099', 'Test', 'Doctor', 1, 1, 'D0071423', 'test.doctor@wayneclinic.example');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 03 [expect 428C9] Client tries to supply its own identity value (GENERATED ALWAYS)'
INSERT INTO patient (patient_id, mrn, first_name, last_name, date_of_birth, sex)
VALUES (500, 'WCB0000500', 'Id', 'Forger', '1990-01-01', 'M');
\echo '        -> SQLSTATE' :SQLSTATE

\echo ''
\echo '=== DOMAIN / CHECK CONSTRAINTS ================================='
\echo 'TEST 04 [expect 23514] MRN in the wrong format (CHECK chk_patient_mrn)'
INSERT INTO patient (mrn, first_name, last_name, date_of_birth, sex)
VALUES ('12345', 'Bad', 'Mrn', '1990-01-01', 'F');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 05 [expect 23514] Unknown blood group C+ (CHECK chk_patient_blood)'
UPDATE patient SET blood_group = 'C+' WHERE mrn = 'WCB0000002';
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 06 [expect 23514] Malformed phone number (DOMAIN phone_number)'
UPDATE patient SET phone = '555-CALL-NOW' WHERE mrn = 'WCB0000002';
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 07 [expect 23514] Malformed e-mail address (DOMAIN email_address)'
UPDATE patient SET email = 'maria.santos(at)mail' WHERE mrn = 'WCB0000002';
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 08 [expect 23514] Emergency contact name without a phone (CHECK chk_patient_emergency)'
UPDATE patient SET emergency_contact_name = 'Someone', emergency_contact_phone = NULL WHERE mrn = 'WCB0000004';
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 09 [expect 23514] Appointment that ends before it starts (CHECK chk_appt_time_order)'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (2, 1, '2026-12-01 10:00', '2026-12-01 09:30');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 10 [expect 23514] Pharmacy stock driven below zero (CHECK chk_medication_stock)'
UPDATE medication SET stock_on_hand = stock_on_hand - 100000 WHERE generic_name = 'Warfarin';
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 11 [expect 23514] Prescription line with quantity 0 (CHECK chk_item_quantity)'
INSERT INTO prescription_item (prescription_id, line_no, medication_id, dosage, frequency, duration_days, quantity)
VALUES (1, 9, 6, '500 mg', 'Once daily', 5, 0);
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 12 [expect 23514] ICD-10 code in an invalid format (CHECK chk_icd10_format)'
INSERT INTO icd10_code VALUES ('XYZ-1', 'Not a code', 'None');
\echo '        -> SQLSTATE' :SQLSTATE

\echo ''
\echo '=== REFERENTIAL INTEGRITY ======================================'
\echo 'TEST 13 [expect 23503] Appointment for a patient that does not exist (FK fk_appt_patient)'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (9999, 1, '2026-12-01 09:00', '2026-12-01 09:30');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 14 [expect 23503] Delete a patient who has clinical history (ON DELETE RESTRICT)'
DELETE FROM patient WHERE mrn = 'WCB0000003';
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 15 [expect 23503] Department head who does not exist, deferred FK forced IMMEDIATE'
SET CONSTRAINTS clinic.fk_department_head IMMEDIATE;
INSERT INTO department (name, floor_number, phone_extension, head_doctor_id)
VALUES ('Radiology', 0, '0200', 999);
\echo '        -> SQLSTATE' :SQLSTATE
SET CONSTRAINTS clinic.fk_department_head DEFERRED;

\echo ''
\echo '=== EXCLUSION CONSTRAINTS (NO DOUBLE BOOKING) ==================='
\echo 'TEST 16 [expect 23P01] Second patient booked into Dr Okafor''s 13-Oct 09:00 slot'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (5, 1, '2026-10-13 09:15', '2026-10-13 09:45');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 17 [expect 23P01] Tyrone Jackson booked with two doctors at overlapping times'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end)
VALUES (3, 1, '2026-09-02 10:15', '2026-09-02 10:45');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 18 [expect 00000] A cancelled appointment frees its slot (partial EXCLUDE ... WHERE status <> Cancelled)'
INSERT INTO appointment (patient_id, doctor_id, scheduled_start, scheduled_end, status)
VALUES (5, 2, '2026-10-08 15:20', '2026-10-08 15:40', 'Completed');
\echo '        -> SQLSTATE' :SQLSTATE

\echo ''
\echo '=== BUSINESS RULES (PARTIAL INDEX + TRIGGERS) ==================='
\echo 'TEST 19 [expect 23505] Second PRIMARY diagnosis on one appointment (partial unique index)'
INSERT INTO diagnosis (appointment_id, icd10_code, diagnosis_type) VALUES (1, 'E78.5', 'Primary');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 20 [expect 00000] Extra SECONDARY diagnosis on the same appointment is allowed'
INSERT INTO diagnosis (appointment_id, icd10_code, diagnosis_type) VALUES (1, 'E78.5', 'Secondary');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 21 [expect WC002] Diagnosis on an appointment that has not happened yet (trigger)'
INSERT INTO diagnosis (appointment_id, icd10_code) VALUES (36, 'I10');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 22 [expect WC001] Penicillin prescribed to James Holloway, who is allergic (trigger)'
INSERT INTO prescription (appointment_id, notes) VALUES (21, 'Allergy test') RETURNING prescription_id AS test_rx \gset
INSERT INTO prescription_item (prescription_id, line_no, medication_id, dosage, frequency, duration_days, quantity)
VALUES (:test_rx, 1, (SELECT medication_id FROM medication WHERE generic_name = 'Penicillin V Potassium'),
        '500 mg', 'Four times daily', 10, 40);
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 23 [expect WC006] Patient registered with a date of birth in the future (trigger)'
INSERT INTO patient (mrn, first_name, last_name, date_of_birth, sex)
VALUES ('WCB0000777', 'Future', 'Baby', CURRENT_DATE + 30, 'U');
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 24 [expect 00000] Lab trigger flags potassium 6.8 as CRITICAL and sodium 128 as LOW'
INSERT INTO lab_result (lab_order_id, test_code, result_value)
SELECT lab_order_id, t.code, t.val
FROM lab_order, (VALUES ('K', 6.8), ('NA', 128)) AS t(code, val)
WHERE appointment_id = 1;
\echo '        -> SQLSTATE' :SQLSTATE
SELECT lo.appointment_id, r.test_code, r.result_value, r.abnormal_flag
FROM lab_result r JOIN lab_order lo USING (lab_order_id)
WHERE lo.appointment_id = 1 AND r.test_code IN ('K', 'NA');

\echo ''
\echo '=== CORE OPERATION GUARDS: book_appointment() =================='
\echo 'TEST 25 [expect WC003] Booking Dr Okafor on a Saturday, when she holds no clinic'
SELECT book_appointment(2, 1, (:'next_saturday' || ' 10:00')::timestamptz);
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 26 [expect WC005] Booking an appointment in the past'
SELECT book_appointment(2, 1, '2025-01-06 10:00'::timestamptz);
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 27 [expect 00000] Valid booking: Maria Santos with Dr Okafor next Monday 10:00'
SELECT book_appointment(2, 1, (:'next_monday' || ' 10:00')::timestamptz, 'Constraint-suite booking') AS new_appointment_id;
\echo '        -> SQLSTATE' :SQLSTATE

\echo 'TEST 28 [expect 23P01] Same slot requested for Kwame Mensah (friendly message from function)'
SELECT book_appointment(5, 1, (:'next_monday' || ' 10:00')::timestamptz);
\echo '        -> SQLSTATE' :SQLSTATE

ROLLBACK;
\echo ''
\echo 'Suite finished - transaction rolled back, sample data unchanged.'
