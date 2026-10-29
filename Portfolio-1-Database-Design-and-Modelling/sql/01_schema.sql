-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 01 · Relational schema (tables, keys, constraints)
-- Engine: PostgreSQL 16   |   psql -d waynes_clinic -f 01_schema.sql
--
-- Design notes
--   * Surrogate keys use GENERATED ALWAYS AS IDENTITY (SQL:2003 standard)
--     so application code can never supply or overwrite an id.
--   * Natural/business keys (MRN, staff number, licence number, NDC code,
--     ICD-10 code) are enforced with UNIQUE constraints.
--   * Every foreign key states its ON DELETE behaviour explicitly.
--   * Domain rules are declared in the schema (CHECK, EXCLUDE, partial
--     UNIQUE indexes) rather than left to the application.
-- =====================================================================

DROP SCHEMA IF EXISTS clinic CASCADE;
CREATE SCHEMA clinic;
COMMENT ON SCHEMA clinic IS 'Core operational schema for Wayne''s Clinic Baltimore';
SET search_path TO clinic, public;

-- btree_gist lets an exclusion constraint combine "=" on an integer column
-- with "&&" (overlaps) on a time range. Used to stop double booking.
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ---------------------------------------------------------------------
-- Domains and types (re-usable column rules)
-- ---------------------------------------------------------------------
CREATE DOMAIN clinic.phone_number AS varchar(20)
    CHECK (VALUE ~ '^\(?[0-9]{3}\)?[ .-]?[0-9]{3}[ .-]?[0-9]{4}$');
COMMENT ON DOMAIN clinic.phone_number IS 'North American 10-digit phone number, e.g. 410-555-0142';

CREATE DOMAIN clinic.email_address AS varchar(254)
    CHECK (VALUE ~* '^[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}$');

CREATE TYPE clinic.appointment_status AS ENUM
    ('Scheduled', 'CheckedIn', 'Completed', 'Cancelled', 'NoShow');
COMMENT ON TYPE clinic.appointment_status IS 'Life-cycle of an appointment: Scheduled -> CheckedIn -> Completed (or Cancelled / NoShow)';

-- ---------------------------------------------------------------------
-- 1. postal_area  (removes the ZIP -> city/state transitive dependency)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.postal_area (
    zip_code    char(5)      PRIMARY KEY,
    city        varchar(60)  NOT NULL,
    state_code  char(2)      NOT NULL DEFAULT 'MD',
    CONSTRAINT chk_postal_zip   CHECK (zip_code ~ '^[0-9]{5}$'),
    CONSTRAINT chk_postal_state CHECK (state_code ~ '^[A-Z]{2}$')
);
COMMENT ON TABLE clinic.postal_area IS 'US ZIP codes used in patient addresses (3NF: city/state depend on ZIP, not on the patient)';

-- ---------------------------------------------------------------------
-- 2. department
-- ---------------------------------------------------------------------
CREATE TABLE clinic.department (
    department_id   smallint     GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name            varchar(80)  NOT NULL,
    floor_number    smallint     NOT NULL,
    phone_extension varchar(6)   NOT NULL,
    head_doctor_id  integer,                     -- FK added after doctor exists (circular reference)
    CONSTRAINT uq_department_name  UNIQUE (name),
    CONSTRAINT uq_department_ext   UNIQUE (phone_extension),
    CONSTRAINT chk_department_floor CHECK (floor_number BETWEEN -2 AND 12),
    CONSTRAINT chk_department_ext   CHECK (phone_extension ~ '^[0-9]{3,6}$')
);
COMMENT ON TABLE  clinic.department IS 'Clinical departments of the hospital';
COMMENT ON COLUMN clinic.department.head_doctor_id IS 'Doctor who heads the department (deferrable FK to doctor)';

-- ---------------------------------------------------------------------
-- 3. specialty
-- ---------------------------------------------------------------------
CREATE TABLE clinic.specialty (
    specialty_id smallint    GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name         varchar(80) NOT NULL,
    CONSTRAINT uq_specialty_name UNIQUE (name)
);
COMMENT ON TABLE clinic.specialty IS 'Medical specialties (board certifications)';

-- ---------------------------------------------------------------------
-- 4. doctor
-- ---------------------------------------------------------------------
CREATE TABLE clinic.doctor (
    doctor_id            integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    staff_number         varchar(10)  NOT NULL,
    first_name           varchar(50)  NOT NULL,
    last_name            varchar(50)  NOT NULL,
    specialty_id         smallint     NOT NULL,
    department_id        smallint     NOT NULL,
    license_number       varchar(12)  NOT NULL,
    email                clinic.email_address NOT NULL,
    phone                clinic.phone_number,
    hire_date            date         NOT NULL DEFAULT CURRENT_DATE,
    consultation_minutes smallint     NOT NULL DEFAULT 30,
    is_active            boolean      NOT NULL DEFAULT true,
    CONSTRAINT uq_doctor_staff_number UNIQUE (staff_number),
    CONSTRAINT uq_doctor_license      UNIQUE (license_number),
    CONSTRAINT uq_doctor_email        UNIQUE (email),
    CONSTRAINT chk_doctor_staff_number CHECK (staff_number ~ '^WCB-D[0-9]{4}$'),
    CONSTRAINT chk_doctor_license      CHECK (license_number ~ '^D[0-9]{7}$'),
    CONSTRAINT chk_doctor_hire_date    CHECK (hire_date >= DATE '1980-01-01'),
    CONSTRAINT chk_doctor_slot_length  CHECK (consultation_minutes IN (15, 20, 30, 45, 60)),
    CONSTRAINT fk_doctor_specialty  FOREIGN KEY (specialty_id)
        REFERENCES clinic.specialty (specialty_id)   ON UPDATE CASCADE ON DELETE RESTRICT,
    CONSTRAINT fk_doctor_department FOREIGN KEY (department_id)
        REFERENCES clinic.department (department_id) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  clinic.doctor IS 'Physicians employed by the clinic';
COMMENT ON COLUMN clinic.doctor.license_number IS 'Maryland Board of Physicians licence number (format D + 7 digits)';
COMMENT ON COLUMN clinic.doctor.consultation_minutes IS 'Default length of one appointment slot for this doctor';

-- Circular relationship department <-> doctor. DEFERRABLE INITIALLY DEFERRED
-- lets a new department and its head be inserted inside one transaction.
ALTER TABLE clinic.department
    ADD CONSTRAINT fk_department_head FOREIGN KEY (head_doctor_id)
        REFERENCES clinic.doctor (doctor_id) ON DELETE SET NULL
        DEFERRABLE INITIALLY DEFERRED;

-- ---------------------------------------------------------------------
-- 5. doctor_availability  (weekly clinic sessions; weak entity of doctor)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.doctor_availability (
    doctor_id   integer  NOT NULL,
    iso_weekday smallint NOT NULL,          -- 1 = Monday ... 7 = Sunday
    start_time  time     NOT NULL,
    end_time    time     NOT NULL,
    CONSTRAINT pk_doctor_availability PRIMARY KEY (doctor_id, iso_weekday, start_time),
    CONSTRAINT chk_avail_weekday CHECK (iso_weekday BETWEEN 1 AND 7),
    CONSTRAINT chk_avail_times   CHECK (end_time > start_time),
    CONSTRAINT fk_avail_doctor FOREIGN KEY (doctor_id)
        REFERENCES clinic.doctor (doctor_id) ON DELETE CASCADE
);
COMMENT ON TABLE clinic.doctor_availability IS 'Recurring weekly sessions in which a doctor accepts appointments (Baltimore local time)';

-- ---------------------------------------------------------------------
-- 6. patient
-- ---------------------------------------------------------------------
CREATE TABLE clinic.patient (
    patient_id              integer      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    mrn                     varchar(10)  NOT NULL,
    first_name              varchar(50)  NOT NULL,
    last_name               varchar(50)  NOT NULL,
    date_of_birth           date         NOT NULL,
    sex                     char(1)      NOT NULL,
    blood_group             varchar(3),
    phone                   clinic.phone_number,
    email                   clinic.email_address,
    street_address          varchar(120),
    zip_code                char(5),
    emergency_contact_name  varchar(100),
    emergency_contact_phone clinic.phone_number,
    registered_at           timestamptz  NOT NULL DEFAULT now(),
    updated_at              timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT uq_patient_mrn   UNIQUE (mrn),
    CONSTRAINT chk_patient_mrn  CHECK (mrn ~ '^WCB[0-9]{7}$'),
    CONSTRAINT chk_patient_sex  CHECK (sex IN ('F', 'M', 'X', 'U')),
    CONSTRAINT chk_patient_dob  CHECK (date_of_birth >= DATE '1900-01-01'),
    CONSTRAINT chk_patient_blood CHECK (blood_group IN ('A+','A-','B+','B-','AB+','AB-','O+','O-')),
    CONSTRAINT chk_patient_emergency CHECK (
        (emergency_contact_name IS NULL) = (emergency_contact_phone IS NULL)),
    CONSTRAINT fk_patient_zip FOREIGN KEY (zip_code)
        REFERENCES clinic.postal_area (zip_code) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  clinic.patient IS 'Registered patients of the clinic';
COMMENT ON COLUMN clinic.patient.mrn IS 'Medical Record Number: business key printed on wristbands and letters';
COMMENT ON COLUMN clinic.patient.sex IS 'F = female, M = male, X = non-binary/intersex, U = unknown';

-- ---------------------------------------------------------------------
-- 7. medication  (formulary + pharmacy stock)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.medication (
    medication_id  integer       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ndc_code       varchar(13)   NOT NULL,
    generic_name   varchar(80)   NOT NULL,
    brand_name     varchar(80),
    dosage_form    varchar(20)   NOT NULL,
    strength       varchar(30)   NOT NULL,
    unit_price     numeric(10,2) NOT NULL,
    stock_on_hand  integer       NOT NULL DEFAULT 0,
    is_controlled  boolean       NOT NULL DEFAULT false,
    CONSTRAINT uq_medication_ndc UNIQUE (ndc_code),
    CONSTRAINT uq_medication_generic_form_strength UNIQUE (generic_name, dosage_form, strength),
    CONSTRAINT chk_medication_ndc   CHECK (ndc_code ~ '^[0-9]{5}-[0-9]{4}-[0-9]{2}$'),
    CONSTRAINT chk_medication_form  CHECK (dosage_form IN
        ('Tablet','Capsule','Syrup','Injection','Inhaler','Cream','Drops','Patch')),
    CONSTRAINT chk_medication_price CHECK (unit_price >= 0),
    CONSTRAINT chk_medication_stock CHECK (stock_on_hand >= 0)
);
COMMENT ON TABLE  clinic.medication IS 'Hospital formulary and on-hand pharmacy stock';
COMMENT ON COLUMN clinic.medication.ndc_code IS 'National Drug Code (illustrative values in the sample data)';

-- ---------------------------------------------------------------------
-- 8. patient_allergy  (M:N patient <-> medication with attributes)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.patient_allergy (
    patient_id    integer      NOT NULL,
    medication_id integer      NOT NULL,
    reaction      varchar(120) NOT NULL,
    severity      varchar(10)  NOT NULL,
    recorded_at   timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT pk_patient_allergy PRIMARY KEY (patient_id, medication_id),
    CONSTRAINT chk_allergy_severity CHECK (severity IN ('Mild','Moderate','Severe')),
    CONSTRAINT fk_allergy_patient FOREIGN KEY (patient_id)
        REFERENCES clinic.patient (patient_id) ON DELETE CASCADE,
    CONSTRAINT fk_allergy_medication FOREIGN KEY (medication_id)
        REFERENCES clinic.medication (medication_id) ON DELETE RESTRICT
);
COMMENT ON TABLE clinic.patient_allergy IS 'Documented drug allergies; checked automatically before a prescription line is saved';

-- ---------------------------------------------------------------------
-- 9. appointment  (associative entity patient <-> doctor over time)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.appointment (
    appointment_id  bigint       GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    patient_id      integer      NOT NULL,
    doctor_id       integer      NOT NULL,
    scheduled_start timestamptz  NOT NULL,
    scheduled_end   timestamptz  NOT NULL,
    status          clinic.appointment_status NOT NULL DEFAULT 'Scheduled',
    reason          varchar(200),
    booked_at       timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT chk_appt_time_order CHECK (scheduled_end > scheduled_start),
    CONSTRAINT chk_appt_max_length CHECK (scheduled_end - scheduled_start <= interval '2 hours'),
    CONSTRAINT fk_appt_patient FOREIGN KEY (patient_id)
        REFERENCES clinic.patient (patient_id) ON DELETE RESTRICT,
    CONSTRAINT fk_appt_doctor  FOREIGN KEY (doctor_id)
        REFERENCES clinic.doctor (doctor_id)   ON DELETE RESTRICT,
    -- A doctor can never hold two live appointments whose times overlap.
    CONSTRAINT ex_appt_no_doctor_overlap EXCLUDE USING gist (
        doctor_id WITH =,
        tstzrange(scheduled_start, scheduled_end, '[)') WITH &&
    ) WHERE (status <> 'Cancelled'),
    -- Nor can a patient be in two places at once.
    CONSTRAINT ex_appt_no_patient_overlap EXCLUDE USING gist (
        patient_id WITH =,
        tstzrange(scheduled_start, scheduled_end, '[)') WITH &&
    ) WHERE (status <> 'Cancelled')
);
COMMENT ON TABLE clinic.appointment IS 'Bookings of a patient with a doctor. Exclusion constraints prevent double booking.';

-- ---------------------------------------------------------------------
-- 10. icd10_code  (diagnosis reference data)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.icd10_code (
    icd10_code  varchar(8)   PRIMARY KEY,
    description varchar(200) NOT NULL,
    chapter     varchar(80)  NOT NULL,
    CONSTRAINT chk_icd10_format CHECK (icd10_code ~ '^[A-Z][0-9][0-9A-Z](\.[0-9A-Z]{1,4})?$')
);
COMMENT ON TABLE clinic.icd10_code IS 'ICD-10-CM classification codes used to record diagnoses';

-- ---------------------------------------------------------------------
-- 11. diagnosis  (stored against the appointment/encounter)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.diagnosis (
    diagnosis_id   bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id bigint      NOT NULL,
    icd10_code     varchar(8)  NOT NULL,
    diagnosis_type varchar(12) NOT NULL DEFAULT 'Primary',
    clinical_notes text,
    diagnosed_at   timestamptz NOT NULL DEFAULT now(),
    CONSTRAINT uq_diagnosis_appt_code UNIQUE (appointment_id, icd10_code),
    CONSTRAINT chk_diagnosis_type CHECK (diagnosis_type IN ('Primary','Secondary','Differential')),
    CONSTRAINT fk_diagnosis_appt FOREIGN KEY (appointment_id)
        REFERENCES clinic.appointment (appointment_id) ON DELETE RESTRICT,
    CONSTRAINT fk_diagnosis_icd10 FOREIGN KEY (icd10_code)
        REFERENCES clinic.icd10_code (icd10_code) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE clinic.diagnosis IS 'Diagnoses recorded by the treating doctor during an appointment';

-- At most ONE primary diagnosis per appointment (partial unique index).
CREATE UNIQUE INDEX ux_diagnosis_one_primary
    ON clinic.diagnosis (appointment_id) WHERE diagnosis_type = 'Primary';

-- ---------------------------------------------------------------------
-- 12. prescription (header) and 13. prescription_item (lines)
-- ---------------------------------------------------------------------
CREATE TABLE clinic.prescription (
    prescription_id bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id  bigint      NOT NULL,
    issued_at       timestamptz NOT NULL DEFAULT now(),
    status          varchar(10) NOT NULL DEFAULT 'Active',
    notes           varchar(300),
    CONSTRAINT chk_prescription_status CHECK (status IN ('Active','Dispensed','Cancelled','Expired')),
    CONSTRAINT fk_prescription_appt FOREIGN KEY (appointment_id)
        REFERENCES clinic.appointment (appointment_id) ON DELETE RESTRICT
);
COMMENT ON TABLE clinic.prescription IS 'Prescription issued at an appointment (header)';

CREATE TABLE clinic.prescription_item (
    prescription_id bigint      NOT NULL,
    line_no         smallint    NOT NULL,
    medication_id   integer     NOT NULL,
    dosage          varchar(40) NOT NULL,
    frequency       varchar(40) NOT NULL,
    duration_days   smallint    NOT NULL,
    quantity        integer     NOT NULL,
    CONSTRAINT pk_prescription_item PRIMARY KEY (prescription_id, line_no),
    CONSTRAINT uq_prescription_item_med UNIQUE (prescription_id, medication_id),
    CONSTRAINT chk_item_line     CHECK (line_no BETWEEN 1 AND 20),
    CONSTRAINT chk_item_duration CHECK (duration_days BETWEEN 1 AND 365),
    CONSTRAINT chk_item_quantity CHECK (quantity > 0),
    CONSTRAINT fk_item_prescription FOREIGN KEY (prescription_id)
        REFERENCES clinic.prescription (prescription_id) ON DELETE CASCADE,
    CONSTRAINT fk_item_medication FOREIGN KEY (medication_id)
        REFERENCES clinic.medication (medication_id) ON DELETE RESTRICT
);
COMMENT ON TABLE clinic.prescription_item IS 'One medication line on a prescription (removes the repeating group from the paper form)';

-- ---------------------------------------------------------------------
-- 14. lab_test (catalogue), 15. lab_order, 16. lab_result
-- ---------------------------------------------------------------------
CREATE TABLE clinic.lab_test (
    test_code        varchar(10)   PRIMARY KEY,
    test_name        varchar(80)   NOT NULL,
    specimen_type    varchar(10)   NOT NULL,
    unit             varchar(20),
    ref_low          numeric(10,3),
    ref_high         numeric(10,3),
    critical_low     numeric(10,3),
    critical_high    numeric(10,3),
    turnaround_hours smallint      NOT NULL DEFAULT 24,
    CONSTRAINT uq_lab_test_name UNIQUE (test_name),
    CONSTRAINT chk_lab_specimen CHECK (specimen_type IN ('Blood','Urine','Saliva','Swab','Stool','Tissue')),
    CONSTRAINT chk_lab_range    CHECK (ref_low IS NULL OR ref_high IS NULL OR ref_low < ref_high),
    CONSTRAINT chk_lab_crit_low  CHECK (critical_low  IS NULL OR ref_low  IS NULL OR critical_low  <= ref_low),
    CONSTRAINT chk_lab_crit_high CHECK (critical_high IS NULL OR ref_high IS NULL OR critical_high >= ref_high),
    CONSTRAINT chk_lab_tat      CHECK (turnaround_hours BETWEEN 1 AND 720)
);
COMMENT ON TABLE  clinic.lab_test IS 'Catalogue of laboratory tests with adult reference ranges and critical (panic) limits';
COMMENT ON COLUMN clinic.lab_test.critical_low IS 'Result at or below this value must be phoned to the clinician immediately';

CREATE TABLE clinic.lab_order (
    lab_order_id   bigint      GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    appointment_id bigint      NOT NULL,
    ordered_at     timestamptz NOT NULL DEFAULT now(),
    priority       varchar(8)  NOT NULL DEFAULT 'Routine',
    status         varchar(12) NOT NULL DEFAULT 'Ordered',
    CONSTRAINT chk_lab_order_priority CHECK (priority IN ('Routine','Urgent','STAT')),
    CONSTRAINT chk_lab_order_status   CHECK (status IN ('Ordered','Collected','InProgress','Completed','Cancelled')),
    CONSTRAINT fk_lab_order_appt FOREIGN KEY (appointment_id)
        REFERENCES clinic.appointment (appointment_id) ON DELETE RESTRICT
);
COMMENT ON TABLE clinic.lab_order IS 'Request for one or more laboratory tests raised during an appointment';

CREATE TABLE clinic.lab_result (
    lab_result_id bigint        GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    lab_order_id  bigint        NOT NULL,
    test_code     varchar(10)   NOT NULL,
    result_value  numeric(12,3),
    result_text   varchar(200),
    abnormal_flag char(1),
    resulted_at   timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT uq_lab_result_order_test UNIQUE (lab_order_id, test_code),
    CONSTRAINT chk_lab_result_present CHECK (result_value IS NOT NULL OR result_text IS NOT NULL),
    CONSTRAINT chk_lab_result_flag    CHECK (abnormal_flag IN ('N','L','H','C')),
    CONSTRAINT fk_lab_result_order FOREIGN KEY (lab_order_id)
        REFERENCES clinic.lab_order (lab_order_id) ON DELETE CASCADE,
    CONSTRAINT fk_lab_result_test FOREIGN KEY (test_code)
        REFERENCES clinic.lab_test (test_code) ON UPDATE CASCADE ON DELETE RESTRICT
);
COMMENT ON TABLE  clinic.lab_result IS 'Result of one test within a lab order';
COMMENT ON COLUMN clinic.lab_result.abnormal_flag IS 'N normal, L low, H high, C critical. Set by trigger from the reference range in force when the result was filed.';

-- ---------------------------------------------------------------------
-- Indexes on foreign keys used by the core operations.
-- (PostgreSQL does not index FK columns automatically. Portfolio 2
--  measures the effect of these and of further, query-specific indexes.)
-- ---------------------------------------------------------------------
CREATE INDEX ix_doctor_department   ON clinic.doctor (department_id);
CREATE INDEX ix_doctor_specialty    ON clinic.doctor (specialty_id);
CREATE INDEX ix_patient_zip         ON clinic.patient (zip_code);
CREATE INDEX ix_allergy_medication  ON clinic.patient_allergy (medication_id);
CREATE INDEX ix_diagnosis_icd10     ON clinic.diagnosis (icd10_code);
CREATE INDEX ix_item_medication     ON clinic.prescription_item (medication_id);
CREATE INDEX ix_lab_result_test     ON clinic.lab_result (test_code);
-- NB: diagnosis(appointment_id) and lab_result(lab_order_id) are already
--     covered by the leading column of their composite UNIQUE constraints.
--     appointment(patient_id), prescription(appointment_id) and
--     lab_order(appointment_id) are deliberately left un-indexed here so
--     Portfolio 2 can show before/after evidence for the patient-history path.
