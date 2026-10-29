-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 02 · Business-rule triggers, core operations, views
-- Engine: PostgreSQL 16   |   psql -d waynes_clinic -f 02_functions_triggers_views.sql
--
-- Custom SQLSTATE codes raised by this script
--   WC001  prescribed medication conflicts with a recorded allergy
--   WC002  clinical record attached to an appointment the patient has not attended
--   WC003  requested time is outside the doctor's clinic sessions
--   WC004  doctor is unknown or inactive
--   WC005  appointment would start in the past
--   WC006  date of birth is in the future
-- =====================================================================
SET search_path TO clinic, public;

-- ---------------------------------------------------------------------
-- Trigger 1: patient — no future date of birth, keep updated_at current
-- (CHECK constraints must be immutable, so "not in the future" is a trigger)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinic.fn_patient_validate()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.date_of_birth > CURRENT_DATE THEN
        RAISE EXCEPTION 'Date of birth % is in the future', NEW.date_of_birth
              USING ERRCODE = 'WC006';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        NEW.updated_at := now();
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_patient_validate
    BEFORE INSERT OR UPDATE ON clinic.patient
    FOR EACH ROW EXECUTE FUNCTION clinic.fn_patient_validate();

-- ---------------------------------------------------------------------
-- Trigger 2: diagnoses, prescriptions and lab orders can only be attached
-- to an appointment the patient actually attended (CheckedIn / Completed)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinic.fn_require_attended_appointment()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_status clinic.appointment_status;
BEGIN
    SELECT status INTO v_status
    FROM clinic.appointment
    WHERE appointment_id = NEW.appointment_id;

    IF v_status IS NULL THEN
        RETURN NEW;                       -- let the foreign key report the missing appointment
    ELSIF v_status NOT IN ('CheckedIn', 'Completed') THEN
        RAISE EXCEPTION '% cannot be recorded: appointment % has status %',
              initcap(replace(TG_TABLE_NAME, '_', ' ')), NEW.appointment_id, v_status
              USING ERRCODE = 'WC002';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_diagnosis_attended
    BEFORE INSERT OR UPDATE OF appointment_id ON clinic.diagnosis
    FOR EACH ROW EXECUTE FUNCTION clinic.fn_require_attended_appointment();

CREATE TRIGGER trg_prescription_attended
    BEFORE INSERT OR UPDATE OF appointment_id ON clinic.prescription
    FOR EACH ROW EXECUTE FUNCTION clinic.fn_require_attended_appointment();

CREATE TRIGGER trg_lab_order_attended
    BEFORE INSERT OR UPDATE OF appointment_id ON clinic.lab_order
    FOR EACH ROW EXECUTE FUNCTION clinic.fn_require_attended_appointment();

-- ---------------------------------------------------------------------
-- Trigger 3: patient-safety check — refuse a prescription line for a drug
-- the patient is documented as allergic to.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinic.fn_prescription_allergy_check()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    v_patient  integer;
    v_reaction varchar;
    v_severity varchar;
    v_drug     varchar;
BEGIN
    SELECT a.patient_id INTO v_patient
    FROM clinic.prescription p
    JOIN clinic.appointment  a ON a.appointment_id = p.appointment_id
    WHERE p.prescription_id = NEW.prescription_id;

    SELECT pa.reaction, pa.severity, m.generic_name
      INTO v_reaction, v_severity, v_drug
    FROM clinic.patient_allergy pa
    JOIN clinic.medication m ON m.medication_id = pa.medication_id
    WHERE pa.patient_id = v_patient
      AND pa.medication_id = NEW.medication_id;

    IF FOUND THEN
        RAISE EXCEPTION 'Allergy conflict: patient % is allergic to % (% reaction: %)',
              v_patient, v_drug, v_severity, v_reaction
              USING ERRCODE = 'WC001',
                    HINT    = 'Choose an alternative medication or record a clinical override.';
    END IF;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_prescription_item_allergy
    BEFORE INSERT OR UPDATE OF medication_id ON clinic.prescription_item
    FOR EACH ROW EXECUTE FUNCTION clinic.fn_prescription_allergy_check();

-- ---------------------------------------------------------------------
-- Trigger 4: set the abnormal flag of a numeric lab result from the
-- reference range in force at the time the result is filed.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION clinic.fn_lab_result_flag()
RETURNS trigger LANGUAGE plpgsql AS $$
DECLARE
    t clinic.lab_test%ROWTYPE;
BEGIN
    IF NEW.result_value IS NULL THEN
        RETURN NEW;                       -- qualitative results keep the flag the scientist set
    END IF;

    SELECT * INTO t FROM clinic.lab_test WHERE test_code = NEW.test_code;

    NEW.abnormal_flag := CASE
        WHEN t.critical_high IS NOT NULL AND NEW.result_value >= t.critical_high THEN 'C'
        WHEN t.critical_low  IS NOT NULL AND NEW.result_value <= t.critical_low  THEN 'C'
        WHEN t.ref_high      IS NOT NULL AND NEW.result_value >  t.ref_high      THEN 'H'
        WHEN t.ref_low       IS NOT NULL AND NEW.result_value <  t.ref_low       THEN 'L'
        ELSE 'N'
    END;
    RETURN NEW;
END $$;

CREATE TRIGGER trg_lab_result_flag
    BEFORE INSERT OR UPDATE OF result_value, test_code ON clinic.lab_result
    FOR EACH ROW EXECUTE FUNCTION clinic.fn_lab_result_flag();

-- =====================================================================
-- CORE OPERATION 1 — BOOK AN APPOINTMENT
-- =====================================================================

-- Free slots for a doctor on a given local (Baltimore) date.
CREATE OR REPLACE FUNCTION clinic.available_slots(p_doctor_id integer, p_date date)
RETURNS TABLE (slot_start timestamptz, slot_end timestamptz)
LANGUAGE sql STABLE AS $$
    WITH doc AS (
        SELECT doctor_id, make_interval(mins => consultation_minutes) AS slot_len
        FROM clinic.doctor
        WHERE doctor_id = p_doctor_id AND is_active
    ),
    sessions AS (
        SELECT (p_date + av.start_time) AT TIME ZONE 'America/New_York' AS s_start,
               (p_date + av.end_time)   AT TIME ZONE 'America/New_York' AS s_end,
               doc.slot_len
        FROM clinic.doctor_availability av
        JOIN doc USING (doctor_id)
        WHERE av.iso_weekday = EXTRACT(ISODOW FROM p_date)
    ),
    slots AS (
        SELECT gs AS slot_start, gs + s.slot_len AS slot_end
        FROM sessions s,
             generate_series(s.s_start, s.s_end - s.slot_len, s.slot_len) AS gs
    )
    SELECT sl.slot_start, sl.slot_end
    FROM slots sl
    WHERE NOT EXISTS (
        SELECT 1 FROM clinic.appointment a
        WHERE a.doctor_id = p_doctor_id
          AND a.status <> 'Cancelled'
          AND tstzrange(a.scheduled_start, a.scheduled_end, '[)')
              && tstzrange(sl.slot_start, sl.slot_end, '[)')
    )
    ORDER BY sl.slot_start;
$$;
COMMENT ON FUNCTION clinic.available_slots IS 'Lists bookable slots for a doctor on a Baltimore-local date';

CREATE OR REPLACE FUNCTION clinic.book_appointment(
    p_patient_id integer,
    p_doctor_id  integer,
    p_start      timestamptz,
    p_reason     varchar DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_minutes    smallint;
    v_end        timestamptz;
    v_local      timestamp := p_start AT TIME ZONE 'America/New_York';
    v_id         bigint;
    v_constraint text;
BEGIN
    SELECT consultation_minutes INTO v_minutes
    FROM clinic.doctor WHERE doctor_id = p_doctor_id AND is_active;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Doctor % does not exist or is not active', p_doctor_id
              USING ERRCODE = 'WC004';
    END IF;

    IF p_start <= now() THEN
        RAISE EXCEPTION 'Cannot book an appointment in the past (%)', p_start
              USING ERRCODE = 'WC005';
    END IF;

    v_end := p_start + make_interval(mins => v_minutes);

    IF NOT EXISTS (
        SELECT 1 FROM clinic.doctor_availability av
        WHERE av.doctor_id   = p_doctor_id
          AND av.iso_weekday = EXTRACT(ISODOW FROM v_local)
          AND v_local::time >= av.start_time
          AND (v_end AT TIME ZONE 'America/New_York')::time <= av.end_time
    ) THEN
        RAISE EXCEPTION 'Doctor % does not hold a clinic session at % (Baltimore time)',
              p_doctor_id, to_char(v_local, 'Dy DD Mon YYYY HH24:MI')
              USING ERRCODE = 'WC003';
    END IF;

    BEGIN
        INSERT INTO clinic.appointment (patient_id, doctor_id, scheduled_start, scheduled_end, reason)
        VALUES (p_patient_id, p_doctor_id, p_start, v_end, p_reason)
        RETURNING appointment_id INTO v_id;
    EXCEPTION WHEN exclusion_violation THEN
        GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
        IF v_constraint = 'ex_appt_no_doctor_overlap' THEN
            RAISE EXCEPTION 'Slot taken: doctor % already has an appointment at %', p_doctor_id, v_local
                  USING ERRCODE = 'exclusion_violation';
        ELSE
            RAISE EXCEPTION 'Clash: patient % already has an appointment overlapping %', p_patient_id, v_local
                  USING ERRCODE = 'exclusion_violation';
        END IF;
    END;

    RETURN v_id;
END $$;
COMMENT ON FUNCTION clinic.book_appointment IS 'Books a slot after checking doctor status, clinic sessions and overlaps; returns appointment_id';

-- =====================================================================
-- CORE OPERATION 2 — STORE A DIAGNOSIS
-- =====================================================================
CREATE OR REPLACE FUNCTION clinic.record_diagnosis(
    p_appointment_id bigint,
    p_icd10_code     varchar,
    p_type           varchar DEFAULT 'Primary',
    p_notes          text    DEFAULT NULL
) RETURNS bigint
LANGUAGE plpgsql AS $$
DECLARE
    v_id bigint;
BEGIN
    INSERT INTO clinic.diagnosis (appointment_id, icd10_code, diagnosis_type, clinical_notes)
    VALUES (p_appointment_id, upper(p_icd10_code), p_type, p_notes)
    RETURNING diagnosis_id INTO v_id;

    -- Recording a diagnosis completes a checked-in consultation.
    UPDATE clinic.appointment
       SET status = 'Completed'
     WHERE appointment_id = p_appointment_id
       AND status = 'CheckedIn';

    RETURN v_id;
END $$;
COMMENT ON FUNCTION clinic.record_diagnosis IS 'Stores a diagnosis against an attended appointment and marks it Completed';

-- =====================================================================
-- CORE OPERATION 3 — RETRIEVE PATIENT HISTORY
-- =====================================================================
CREATE OR REPLACE VIEW clinic.v_patient_history AS
SELECT a.patient_id,
       a.scheduled_start                         AS event_time,
       'Appointment'::text                       AS event_type,
       a.appointment_id,
       'Dr ' || d.first_name || ' ' || d.last_name AS clinician,
       a.status::text || ' — ' || s.name || coalesce(' — ' || a.reason, '') AS detail
FROM clinic.appointment a
JOIN clinic.doctor    d ON d.doctor_id    = a.doctor_id
JOIN clinic.specialty s ON s.specialty_id = d.specialty_id
UNION ALL
SELECT a.patient_id, dx.diagnosed_at, 'Diagnosis', a.appointment_id,
       'Dr ' || d.first_name || ' ' || d.last_name,
       dx.icd10_code || ' ' || ic.description || ' (' || dx.diagnosis_type || ')'
FROM clinic.diagnosis  dx
JOIN clinic.appointment a  ON a.appointment_id = dx.appointment_id
JOIN clinic.doctor      d  ON d.doctor_id      = a.doctor_id
JOIN clinic.icd10_code  ic ON ic.icd10_code    = dx.icd10_code
UNION ALL
SELECT a.patient_id, pr.issued_at, 'Prescription', a.appointment_id,
       'Dr ' || d.first_name || ' ' || d.last_name,
       m.generic_name || ' ' || m.strength || ' — ' || pi.dosage || ', ' || pi.frequency
           || ' for ' || pi.duration_days || ' days (qty ' || pi.quantity || ')'
FROM clinic.prescription      pr
JOIN clinic.prescription_item pi ON pi.prescription_id = pr.prescription_id
JOIN clinic.medication        m  ON m.medication_id    = pi.medication_id
JOIN clinic.appointment       a  ON a.appointment_id   = pr.appointment_id
JOIN clinic.doctor            d  ON d.doctor_id        = a.doctor_id
UNION ALL
SELECT a.patient_id, r.resulted_at, 'Lab result', a.appointment_id,
       'Dr ' || d.first_name || ' ' || d.last_name,
       lt.test_name || ': ' || coalesce(trim_scale(r.result_value)::text, r.result_text)
           || coalesce(' ' || lt.unit, '')
           || CASE r.abnormal_flag WHEN 'H' THEN '  [HIGH]' WHEN 'L' THEN '  [LOW]'
                                   WHEN 'C' THEN '  [CRITICAL]' ELSE '' END
FROM clinic.lab_result r
JOIN clinic.lab_order  lo ON lo.lab_order_id  = r.lab_order_id
JOIN clinic.lab_test   lt ON lt.test_code     = r.test_code
JOIN clinic.appointment a ON a.appointment_id = lo.appointment_id
JOIN clinic.doctor      d ON d.doctor_id      = a.doctor_id;
COMMENT ON VIEW clinic.v_patient_history IS 'One chronological event stream per patient: appointments, diagnoses, prescriptions, lab results';

CREATE OR REPLACE FUNCTION clinic.get_patient_history(p_mrn varchar)
RETURNS TABLE (event_time timestamptz, event_type text, appointment_id bigint,
               clinician text, detail text)
LANGUAGE sql STABLE AS $$
    SELECT h.event_time, h.event_type, h.appointment_id, h.clinician, h.detail
    FROM clinic.v_patient_history h
    JOIN clinic.patient p ON p.patient_id = h.patient_id
    WHERE p.mrn = p_mrn
    ORDER BY h.event_time DESC,
             CASE h.event_type WHEN 'Appointment' THEN 4 WHEN 'Diagnosis' THEN 3
                               WHEN 'Prescription' THEN 2 ELSE 1 END DESC;
$$;
COMMENT ON FUNCTION clinic.get_patient_history IS 'Full medical history for one patient (by MRN), newest first';

-- Convenience view: a doctor's day list
CREATE OR REPLACE VIEW clinic.v_doctor_schedule AS
SELECT d.doctor_id,
       'Dr ' || d.first_name || ' ' || d.last_name AS doctor,
       (a.scheduled_start AT TIME ZONE 'America/New_York')::date AS clinic_date,
       to_char(a.scheduled_start AT TIME ZONE 'America/New_York', 'HH24:MI') AS start_local,
       to_char(a.scheduled_end   AT TIME ZONE 'America/New_York', 'HH24:MI') AS end_local,
       p.mrn,
       p.first_name || ' ' || p.last_name AS patient,
       a.status,
       a.reason
FROM clinic.appointment a
JOIN clinic.doctor  d ON d.doctor_id  = a.doctor_id
JOIN clinic.patient p ON p.patient_id = a.patient_id;
