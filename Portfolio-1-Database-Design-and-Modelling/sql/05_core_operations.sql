-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 05 · The three core operations, end to end
--   1. Book an appointment
--   2. Store a diagnosis (with the prescription and lab order raised in the same visit)
--   3. Retrieve a patient's history
-- Run:  psql -d waynes_clinic -f 05_core_operations.sql
-- =====================================================================
\set ON_ERROR_STOP 1
\pset footer off
SET search_path TO clinic, public;
SET timezone TO 'America/New_York';

SELECT (date_trunc('week', now() AT TIME ZONE 'America/New_York')::date + 7)::text AS next_monday \gset

\echo ''
\echo '================ OPERATION 1: BOOK AN APPOINTMENT ================'
\echo 'Step 1a - Kevin Park (WCB0000019) asks for a cardiology slot next Monday.'
\echo '          Free slots for Dr Priya Raman (doctor_id 3) that morning:'
SELECT to_char(slot_start, 'Dy DD Mon HH24:MI') AS slot_start,
       to_char(slot_end,   'HH24:MI')           AS slot_end
FROM available_slots(3, :'next_monday'::date)
WHERE slot_start < (:'next_monday' || ' 12:30')::timestamptz
LIMIT 7;

\echo 'Step 1b - Book the 11:00 slot through the booking function:'
SELECT book_appointment(
           (SELECT patient_id FROM patient WHERE mrn = 'WCB0000019'),
           3,
           (:'next_monday' || ' 11:00')::timestamptz,
           'Palpitations after COVID-19 infection') AS appointment_id \gset
\echo '          new appointment_id =' :appointment_id

\echo 'Step 1c - Dr Raman''s list for that day now shows the booking:'
SELECT start_local, end_local, mrn, patient, status, reason
FROM v_doctor_schedule
WHERE doctor_id = 3 AND clinic_date = :'next_monday'::date
ORDER BY start_local;

\echo 'Step 1d - The 11:00 slot is no longer offered:'
SELECT count(*) FILTER (WHERE to_char(slot_start, 'HH24:MI') = '11:00') AS slots_at_11
FROM available_slots(3, :'next_monday'::date);

\echo ''
\echo '================ OPERATION 2: STORE A DIAGNOSIS ================'
\echo 'Zara Ahmed (WCB0000016) is checked in with Dr Okafor today (appointment 34).'
SELECT appointment_id, status, reason FROM appointment WHERE appointment_id = 34;

\echo 'The diagnosis, prescription and lab order from one consultation are saved'
\echo 'as ONE transaction: either all three are stored or none is.'
BEGIN;
  SELECT record_diagnosis(34, 'F41.1', 'Primary',
         'Review: GAD-7 down from 14 to 8. Sleeping better. Continue sertraline.') AS diagnosis_id;

  WITH rx AS (
      INSERT INTO prescription (appointment_id, notes)
      VALUES (34, 'Repeat prescription')
      RETURNING prescription_id
  )
  INSERT INTO prescription_item (prescription_id, line_no, medication_id, dosage, frequency, duration_days, quantity)
  SELECT prescription_id, 1, m.medication_id, '50 mg', 'Once daily', 90, 90
  FROM rx, medication m
  WHERE m.generic_name = 'Sertraline';

  WITH lo AS (
      INSERT INTO lab_order (appointment_id, priority) VALUES (34, 'Routine')
      RETURNING lab_order_id
  )
  INSERT INTO lab_result (lab_order_id, test_code, result_value)
  SELECT lab_order_id, 'TSH', 2.1 FROM lo;
COMMIT;

\echo 'After COMMIT the appointment is Completed and the records are linked to it:'
SELECT a.appointment_id, a.status, dx.icd10_code, dx.diagnosis_type, left(dx.clinical_notes, 45) AS notes
FROM appointment a JOIN diagnosis dx USING (appointment_id)
WHERE a.appointment_id = 34;

\echo ''
\echo '================ OPERATION 3: RETRIEVE PATIENT HISTORY ================'
\echo 'Full history for Tyrone Jackson (WCB0000003), newest first:'
\pset format aligned
SELECT to_char(event_time, 'YYYY-MM-DD HH24:MI') AS event_time,
       event_type, appointment_id AS appt, clinician, detail
FROM get_patient_history('WCB0000003');

\echo 'History for Zara Ahmed (WCB0000016), including the records just stored:'
SELECT to_char(event_time, 'YYYY-MM-DD HH24:MI') AS event_time,
       event_type, appointment_id AS appt, detail
FROM get_patient_history('WCB0000016');

\echo 'Patient summary card: demographics, allergies and active problems in one query'
SELECT p.mrn,
       p.first_name || ' ' || p.last_name                         AS patient,
       date_part('year', age(p.date_of_birth))::int               AS age,
       p.blood_group,
       coalesce((SELECT string_agg(m.generic_name || ' (' || pa.severity || ')', ', ')
                 FROM patient_allergy pa JOIN medication m USING (medication_id)
                 WHERE pa.patient_id = p.patient_id), 'None recorded') AS allergies,
       (SELECT string_agg(DISTINCT dx.icd10_code, ', ')
        FROM diagnosis dx JOIN appointment a USING (appointment_id)
        WHERE a.patient_id = p.patient_id AND dx.diagnosis_type <> 'Differential') AS problem_list
FROM patient p
WHERE p.mrn IN ('WCB0000001', 'WCB0000003', 'WCB0000016')
ORDER BY p.mrn;
