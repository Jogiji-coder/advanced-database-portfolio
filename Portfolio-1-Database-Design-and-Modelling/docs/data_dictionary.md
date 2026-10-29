# Data Dictionary — Wayne's Clinic Baltimore

_Generated automatically from the PostgreSQL 16 system catalogue (`docs/generate_data_dictionary.py`). Schema: `clinic`._

## Tables at a glance

| # | Table | Purpose | Sample rows |
|---|---|---|---|
| 1 | `postal_area` | US ZIP codes used in patient addresses (3NF: city/state depend on ZIP, not on the patient) | 20 |
| 2 | `department` | Clinical departments of the hospital | 10 |
| 3 | `specialty` | Medical specialties (board certifications) | 11 |
| 4 | `doctor` | Physicians employed by the clinic | 12 |
| 5 | `doctor_availability` | Recurring weekly sessions in which a doctor accepts appointments (Baltimore local time) | 110 |
| 6 | `patient` | Registered patients of the clinic | 20 |
| 7 | `medication` | Hospital formulary and on-hand pharmacy stock | 23 |
| 8 | `patient_allergy` | Documented drug allergies; checked automatically before a prescription line is saved | 5 |
| 9 | `appointment` | Bookings of a patient with a doctor. Exclusion constraints prevent double booking. | 41 |
| 10 | `icd10_code` | ICD-10-CM classification codes used to record diagnoses | 25 |
| 11 | `diagnosis` | Diagnoses recorded by the treating doctor during an appointment | 36 |
| 12 | `prescription` | Prescription issued at an appointment (header) | 23 |
| 13 | `prescription_item` | One medication line on a prescription (removes the repeating group from the paper form) | 28 |
| 14 | `lab_test` | Catalogue of laboratory tests with adult reference ranges and critical (panic) limits | 18 |
| 15 | `lab_order` | Request for one or more laboratory tests raised during an appointment | 19 |
| 16 | `lab_result` | Result of one test within a lab order | 35 |

## `postal_area`

US ZIP codes used in patient addresses (3NF: city/state depend on ZIP, not on the patient)

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `zip_code` | character(5) | NO |  | PK |  |
| `city` | character varying(60) | NO |  |  |  |
| `state_code` | character(2) | NO | 'MD'::bpchar |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `postal_area_pkey` | PRIMARY KEY | `PRIMARY KEY (zip_code)` |
| `chk_postal_state` | CHECK | `CHECK ((state_code ~ '^[A-Z]{2}$'::text))` |
| `chk_postal_zip` | CHECK | `CHECK ((zip_code ~ '^[0-9]{5}$'::text))` |

## `department`

Clinical departments of the hospital

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `department_id` | smallint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `name` | character varying(80) | NO |  | UK |  |
| `floor_number` | smallint | NO |  |  |  |
| `phone_extension` | character varying(6) | NO |  | UK |  |
| `head_doctor_id` | integer | yes |  | FK | Doctor who heads the department (deferrable FK to doctor) |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `department_pkey` | PRIMARY KEY | `PRIMARY KEY (department_id)` |
| `uq_department_ext` | UNIQUE | `UNIQUE (phone_extension)` |
| `uq_department_name` | UNIQUE | `UNIQUE (name)` |
| `fk_department_head` | FOREIGN KEY | `FOREIGN KEY (head_doctor_id) REFERENCES doctor(doctor_id) ON DELETE SET NULL DEFERRABLE INITIALLY DEFERRED` |
| `chk_department_ext` | CHECK | `CHECK (((phone_extension)::text ~ '^[0-9]{3,6}$'::text))` |
| `chk_department_floor` | CHECK | `CHECK (((floor_number >= '-2'::integer) AND (floor_number <= 12)))` |

## `specialty`

Medical specialties (board certifications)

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `specialty_id` | smallint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `name` | character varying(80) | NO |  | UK |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `specialty_pkey` | PRIMARY KEY | `PRIMARY KEY (specialty_id)` |
| `uq_specialty_name` | UNIQUE | `UNIQUE (name)` |

## `doctor`

Physicians employed by the clinic

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `doctor_id` | integer | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `staff_number` | character varying(10) | NO |  | UK |  |
| `first_name` | character varying(50) | NO |  |  |  |
| `last_name` | character varying(50) | NO |  |  |  |
| `specialty_id` | smallint | NO |  | FK |  |
| `department_id` | smallint | NO |  | FK |  |
| `license_number` | character varying(12) | NO |  | UK | Maryland Board of Physicians licence number (format D + 7 digits) |
| `email` | email_address | NO |  | UK |  |
| `phone` | phone_number | yes |  |  |  |
| `hire_date` | date | NO | CURRENT_DATE |  |  |
| `consultation_minutes` | smallint | NO | 30 |  | Default length of one appointment slot for this doctor |
| `is_active` | boolean | NO | true |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `doctor_pkey` | PRIMARY KEY | `PRIMARY KEY (doctor_id)` |
| `uq_doctor_email` | UNIQUE | `UNIQUE (email)` |
| `uq_doctor_license` | UNIQUE | `UNIQUE (license_number)` |
| `uq_doctor_staff_number` | UNIQUE | `UNIQUE (staff_number)` |
| `fk_doctor_department` | FOREIGN KEY | `FOREIGN KEY (department_id) REFERENCES department(department_id) ON UPDATE CASCADE ON DELETE RESTRICT` |
| `fk_doctor_specialty` | FOREIGN KEY | `FOREIGN KEY (specialty_id) REFERENCES specialty(specialty_id) ON UPDATE CASCADE ON DELETE RESTRICT` |
| `chk_doctor_hire_date` | CHECK | `CHECK ((hire_date >= '1980-01-01'::date))` |
| `chk_doctor_license` | CHECK | `CHECK (((license_number)::text ~ '^D[0-9]{7}$'::text))` |
| `chk_doctor_slot_length` | CHECK | `CHECK ((consultation_minutes = ANY (ARRAY[15, 20, 30, 45, 60])))` |
| `chk_doctor_staff_number` | CHECK | `CHECK (((staff_number)::text ~ '^WCB-D[0-9]{4}$'::text))` |
| `ix_doctor_specialty` | INDEX | `btree (specialty_id)` |
| `ix_doctor_department` | INDEX | `btree (department_id)` |

## `doctor_availability`

Recurring weekly sessions in which a doctor accepts appointments (Baltimore local time)

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `doctor_id` | integer | NO |  | PK, FK |  |
| `iso_weekday` | smallint | NO |  | PK |  |
| `start_time` | time without time zone | NO |  | PK |  |
| `end_time` | time without time zone | NO |  |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `pk_doctor_availability` | PRIMARY KEY | `PRIMARY KEY (doctor_id, iso_weekday, start_time)` |
| `fk_avail_doctor` | FOREIGN KEY | `FOREIGN KEY (doctor_id) REFERENCES doctor(doctor_id) ON DELETE CASCADE` |
| `chk_avail_times` | CHECK | `CHECK ((end_time > start_time))` |
| `chk_avail_weekday` | CHECK | `CHECK (((iso_weekday >= 1) AND (iso_weekday <= 7)))` |

## `patient`

Registered patients of the clinic

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `patient_id` | integer | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `mrn` | character varying(10) | NO |  | UK | Medical Record Number: business key printed on wristbands and letters |
| `first_name` | character varying(50) | NO |  |  |  |
| `last_name` | character varying(50) | NO |  |  |  |
| `date_of_birth` | date | NO |  |  |  |
| `sex` | character(1) | NO |  |  | F = female, M = male, X = non-binary/intersex, U = unknown |
| `blood_group` | character varying(3) | yes |  |  |  |
| `phone` | phone_number | yes |  |  |  |
| `email` | email_address | yes |  |  |  |
| `street_address` | character varying(120) | yes |  |  |  |
| `zip_code` | character(5) | yes |  | FK |  |
| `emergency_contact_name` | character varying(100) | yes |  |  |  |
| `emergency_contact_phone` | phone_number | yes |  |  |  |
| `registered_at` | timestamp with time zone | NO | now() |  |  |
| `updated_at` | timestamp with time zone | NO | now() |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `patient_pkey` | PRIMARY KEY | `PRIMARY KEY (patient_id)` |
| `uq_patient_mrn` | UNIQUE | `UNIQUE (mrn)` |
| `fk_patient_zip` | FOREIGN KEY | `FOREIGN KEY (zip_code) REFERENCES postal_area(zip_code) ON UPDATE CASCADE ON DELETE RESTRICT` |
| `chk_patient_blood` | CHECK | `CHECK (((blood_group)::text = ANY ((ARRAY['A+'::character varying, 'A-'::character varying, 'B+'::character varying, 'B-'::character varying, 'AB+'::character varying, 'AB-'::character varying, 'O+'::character varying, 'O-'::character varying])::text[])))` |
| `chk_patient_dob` | CHECK | `CHECK ((date_of_birth >= '1900-01-01'::date))` |
| `chk_patient_emergency` | CHECK | `CHECK (((emergency_contact_name IS NULL) = (emergency_contact_phone IS NULL)))` |
| `chk_patient_mrn` | CHECK | `CHECK (((mrn)::text ~ '^WCB[0-9]{7}$'::text))` |
| `chk_patient_sex` | CHECK | `CHECK ((sex = ANY (ARRAY['F'::bpchar, 'M'::bpchar, 'X'::bpchar, 'U'::bpchar])))` |
| `ix_patient_zip` | INDEX | `btree (zip_code)` |
| `trg_patient_validate` | TRIGGER | `BEFORE INSERT OR UPDATE → fn_patient_validate()` |

## `medication`

Hospital formulary and on-hand pharmacy stock

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `medication_id` | integer | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `ndc_code` | character varying(13) | NO |  | UK | National Drug Code (illustrative values in the sample data) |
| `generic_name` | character varying(80) | NO |  | UK |  |
| `brand_name` | character varying(80) | yes |  |  |  |
| `dosage_form` | character varying(20) | NO |  | UK |  |
| `strength` | character varying(30) | NO |  | UK |  |
| `unit_price` | numeric(10,2) | NO |  |  |  |
| `stock_on_hand` | integer | NO | 0 |  |  |
| `is_controlled` | boolean | NO | false |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `medication_pkey` | PRIMARY KEY | `PRIMARY KEY (medication_id)` |
| `uq_medication_generic_form_strength` | UNIQUE | `UNIQUE (generic_name, dosage_form, strength)` |
| `uq_medication_ndc` | UNIQUE | `UNIQUE (ndc_code)` |
| `chk_medication_form` | CHECK | `CHECK (((dosage_form)::text = ANY ((ARRAY['Tablet'::character varying, 'Capsule'::character varying, 'Syrup'::character varying, 'Injection'::character varying, 'Inhaler'::character varying, 'Cream'::character varying, 'Drops'::character varying, 'Patch'::character varying])::text[])))` |
| `chk_medication_ndc` | CHECK | `CHECK (((ndc_code)::text ~ '^[0-9]{5}-[0-9]{4}-[0-9]{2}$'::text))` |
| `chk_medication_price` | CHECK | `CHECK ((unit_price >= (0)::numeric))` |
| `chk_medication_stock` | CHECK | `CHECK ((stock_on_hand >= 0))` |

## `patient_allergy`

Documented drug allergies; checked automatically before a prescription line is saved

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `patient_id` | integer | NO |  | PK, FK |  |
| `medication_id` | integer | NO |  | PK, FK |  |
| `reaction` | character varying(120) | NO |  |  |  |
| `severity` | character varying(10) | NO |  |  |  |
| `recorded_at` | timestamp with time zone | NO | now() |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `pk_patient_allergy` | PRIMARY KEY | `PRIMARY KEY (patient_id, medication_id)` |
| `fk_allergy_medication` | FOREIGN KEY | `FOREIGN KEY (medication_id) REFERENCES medication(medication_id) ON DELETE RESTRICT` |
| `fk_allergy_patient` | FOREIGN KEY | `FOREIGN KEY (patient_id) REFERENCES patient(patient_id) ON DELETE CASCADE` |
| `chk_allergy_severity` | CHECK | `CHECK (((severity)::text = ANY ((ARRAY['Mild'::character varying, 'Moderate'::character varying, 'Severe'::character varying])::text[])))` |
| `ix_allergy_medication` | INDEX | `btree (medication_id)` |

## `appointment`

Bookings of a patient with a doctor. Exclusion constraints prevent double booking.

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `appointment_id` | bigint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `patient_id` | integer | NO |  | FK |  |
| `doctor_id` | integer | NO |  | FK |  |
| `scheduled_start` | timestamp with time zone | NO |  |  |  |
| `scheduled_end` | timestamp with time zone | NO |  |  |  |
| `status` | appointment_status | NO | 'Scheduled'::appointment_status |  |  |
| `reason` | character varying(200) | yes |  |  |  |
| `booked_at` | timestamp with time zone | NO | now() |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `appointment_pkey` | PRIMARY KEY | `PRIMARY KEY (appointment_id)` |
| `fk_appt_doctor` | FOREIGN KEY | `FOREIGN KEY (doctor_id) REFERENCES doctor(doctor_id) ON DELETE RESTRICT` |
| `fk_appt_patient` | FOREIGN KEY | `FOREIGN KEY (patient_id) REFERENCES patient(patient_id) ON DELETE RESTRICT` |
| `ex_appt_no_doctor_overlap` | EXCLUDE | `EXCLUDE USING gist (doctor_id WITH =, tstzrange(scheduled_start, scheduled_end, '[)'::text) WITH &&) WHERE ((status <> 'Cancelled'::appointment_status))` |
| `ex_appt_no_patient_overlap` | EXCLUDE | `EXCLUDE USING gist (patient_id WITH =, tstzrange(scheduled_start, scheduled_end, '[)'::text) WITH &&) WHERE ((status <> 'Cancelled'::appointment_status))` |
| `chk_appt_max_length` | CHECK | `CHECK (((scheduled_end - scheduled_start) <= '02:00:00'::interval))` |
| `chk_appt_time_order` | CHECK | `CHECK ((scheduled_end > scheduled_start))` |

## `icd10_code`

ICD-10-CM classification codes used to record diagnoses

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `icd10_code` | character varying(8) | NO |  | PK |  |
| `description` | character varying(200) | NO |  |  |  |
| `chapter` | character varying(80) | NO |  |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `icd10_code_pkey` | PRIMARY KEY | `PRIMARY KEY (icd10_code)` |
| `chk_icd10_format` | CHECK | `CHECK (((icd10_code)::text ~ '^[A-Z][0-9][0-9A-Z](\.[0-9A-Z]{1,4})?$'::text))` |

## `diagnosis`

Diagnoses recorded by the treating doctor during an appointment

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `diagnosis_id` | bigint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `appointment_id` | bigint | NO |  | FK, UK |  |
| `icd10_code` | character varying(8) | NO |  | FK, UK |  |
| `diagnosis_type` | character varying(12) | NO | 'Primary'::character varying |  |  |
| `clinical_notes` | text | yes |  |  |  |
| `diagnosed_at` | timestamp with time zone | NO | now() |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `diagnosis_pkey` | PRIMARY KEY | `PRIMARY KEY (diagnosis_id)` |
| `uq_diagnosis_appt_code` | UNIQUE | `UNIQUE (appointment_id, icd10_code)` |
| `fk_diagnosis_appt` | FOREIGN KEY | `FOREIGN KEY (appointment_id) REFERENCES appointment(appointment_id) ON DELETE RESTRICT` |
| `fk_diagnosis_icd10` | FOREIGN KEY | `FOREIGN KEY (icd10_code) REFERENCES icd10_code(icd10_code) ON UPDATE CASCADE ON DELETE RESTRICT` |
| `chk_diagnosis_type` | CHECK | `CHECK (((diagnosis_type)::text = ANY ((ARRAY['Primary'::character varying, 'Secondary'::character varying, 'Differential'::character varying])::text[])))` |
| `ix_diagnosis_icd10` | INDEX | `btree (icd10_code)` |
| `ux_diagnosis_one_primary` | UNIQUE INDEX (partial) | `btree (appointment_id) WHERE ((diagnosis_type)::text = 'Primary'::text)` |
| `trg_diagnosis_attended` | TRIGGER | `BEFORE INSERT OR UPDATE OF appointment_id → fn_require_attended_appointment()` |

## `prescription`

Prescription issued at an appointment (header)

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `prescription_id` | bigint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `appointment_id` | bigint | NO |  | FK |  |
| `issued_at` | timestamp with time zone | NO | now() |  |  |
| `status` | character varying(10) | NO | 'Active'::character varying |  |  |
| `notes` | character varying(300) | yes |  |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `prescription_pkey` | PRIMARY KEY | `PRIMARY KEY (prescription_id)` |
| `fk_prescription_appt` | FOREIGN KEY | `FOREIGN KEY (appointment_id) REFERENCES appointment(appointment_id) ON DELETE RESTRICT` |
| `chk_prescription_status` | CHECK | `CHECK (((status)::text = ANY ((ARRAY['Active'::character varying, 'Dispensed'::character varying, 'Cancelled'::character varying, 'Expired'::character varying])::text[])))` |
| `trg_prescription_attended` | TRIGGER | `BEFORE INSERT OR UPDATE OF appointment_id → fn_require_attended_appointment()` |

## `prescription_item`

One medication line on a prescription (removes the repeating group from the paper form)

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `prescription_id` | bigint | NO |  | PK, FK, UK |  |
| `line_no` | smallint | NO |  | PK |  |
| `medication_id` | integer | NO |  | FK, UK |  |
| `dosage` | character varying(40) | NO |  |  |  |
| `frequency` | character varying(40) | NO |  |  |  |
| `duration_days` | smallint | NO |  |  |  |
| `quantity` | integer | NO |  |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `pk_prescription_item` | PRIMARY KEY | `PRIMARY KEY (prescription_id, line_no)` |
| `uq_prescription_item_med` | UNIQUE | `UNIQUE (prescription_id, medication_id)` |
| `fk_item_medication` | FOREIGN KEY | `FOREIGN KEY (medication_id) REFERENCES medication(medication_id) ON DELETE RESTRICT` |
| `fk_item_prescription` | FOREIGN KEY | `FOREIGN KEY (prescription_id) REFERENCES prescription(prescription_id) ON DELETE CASCADE` |
| `chk_item_duration` | CHECK | `CHECK (((duration_days >= 1) AND (duration_days <= 365)))` |
| `chk_item_line` | CHECK | `CHECK (((line_no >= 1) AND (line_no <= 20)))` |
| `chk_item_quantity` | CHECK | `CHECK ((quantity > 0))` |
| `ix_item_medication` | INDEX | `btree (medication_id)` |
| `trg_prescription_item_allergy` | TRIGGER | `BEFORE INSERT OR UPDATE OF medication_id → fn_prescription_allergy_check()` |

## `lab_test`

Catalogue of laboratory tests with adult reference ranges and critical (panic) limits

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `test_code` | character varying(10) | NO |  | PK |  |
| `test_name` | character varying(80) | NO |  | UK |  |
| `specimen_type` | character varying(10) | NO |  |  |  |
| `unit` | character varying(20) | yes |  |  |  |
| `ref_low` | numeric(10,3) | yes |  |  |  |
| `ref_high` | numeric(10,3) | yes |  |  |  |
| `critical_low` | numeric(10,3) | yes |  |  | Result at or below this value must be phoned to the clinician immediately |
| `critical_high` | numeric(10,3) | yes |  |  |  |
| `turnaround_hours` | smallint | NO | 24 |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `lab_test_pkey` | PRIMARY KEY | `PRIMARY KEY (test_code)` |
| `uq_lab_test_name` | UNIQUE | `UNIQUE (test_name)` |
| `chk_lab_crit_high` | CHECK | `CHECK (((critical_high IS NULL) OR (ref_high IS NULL) OR (critical_high >= ref_high)))` |
| `chk_lab_crit_low` | CHECK | `CHECK (((critical_low IS NULL) OR (ref_low IS NULL) OR (critical_low <= ref_low)))` |
| `chk_lab_range` | CHECK | `CHECK (((ref_low IS NULL) OR (ref_high IS NULL) OR (ref_low < ref_high)))` |
| `chk_lab_specimen` | CHECK | `CHECK (((specimen_type)::text = ANY ((ARRAY['Blood'::character varying, 'Urine'::character varying, 'Saliva'::character varying, 'Swab'::character varying, 'Stool'::character varying, 'Tissue'::character varying])::text[])))` |
| `chk_lab_tat` | CHECK | `CHECK (((turnaround_hours >= 1) AND (turnaround_hours <= 720)))` |

## `lab_order`

Request for one or more laboratory tests raised during an appointment

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `lab_order_id` | bigint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `appointment_id` | bigint | NO |  | FK |  |
| `ordered_at` | timestamp with time zone | NO | now() |  |  |
| `priority` | character varying(8) | NO | 'Routine'::character varying |  |  |
| `status` | character varying(12) | NO | 'Ordered'::character varying |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `lab_order_pkey` | PRIMARY KEY | `PRIMARY KEY (lab_order_id)` |
| `fk_lab_order_appt` | FOREIGN KEY | `FOREIGN KEY (appointment_id) REFERENCES appointment(appointment_id) ON DELETE RESTRICT` |
| `chk_lab_order_priority` | CHECK | `CHECK (((priority)::text = ANY ((ARRAY['Routine'::character varying, 'Urgent'::character varying, 'STAT'::character varying])::text[])))` |
| `chk_lab_order_status` | CHECK | `CHECK (((status)::text = ANY ((ARRAY['Ordered'::character varying, 'Collected'::character varying, 'InProgress'::character varying, 'Completed'::character varying, 'Cancelled'::character varying])::text[])))` |
| `trg_lab_order_attended` | TRIGGER | `BEFORE INSERT OR UPDATE OF appointment_id → fn_require_attended_appointment()` |

## `lab_result`

Result of one test within a lab order

| Column | Data type | Null? | Default | Key | Description |
|---|---|---|---|---|---|
| `lab_result_id` | bigint | NO | GENERATED ALWAYS AS IDENTITY | PK |  |
| `lab_order_id` | bigint | NO |  | FK, UK |  |
| `test_code` | character varying(10) | NO |  | FK, UK |  |
| `result_value` | numeric(12,3) | yes |  |  |  |
| `result_text` | character varying(200) | yes |  |  |  |
| `abnormal_flag` | character(1) | yes |  |  | N normal, L low, H high, C critical. Set by trigger from the reference range in force when the result was filed. |
| `resulted_at` | timestamp with time zone | NO | now() |  |  |

**Constraints**

| Name | Type | Definition |
|---|---|---|
| `lab_result_pkey` | PRIMARY KEY | `PRIMARY KEY (lab_result_id)` |
| `uq_lab_result_order_test` | UNIQUE | `UNIQUE (lab_order_id, test_code)` |
| `fk_lab_result_order` | FOREIGN KEY | `FOREIGN KEY (lab_order_id) REFERENCES lab_order(lab_order_id) ON DELETE CASCADE` |
| `fk_lab_result_test` | FOREIGN KEY | `FOREIGN KEY (test_code) REFERENCES lab_test(test_code) ON UPDATE CASCADE ON DELETE RESTRICT` |
| `chk_lab_result_flag` | CHECK | `CHECK ((abnormal_flag = ANY (ARRAY['N'::bpchar, 'L'::bpchar, 'H'::bpchar, 'C'::bpchar])))` |
| `chk_lab_result_present` | CHECK | `CHECK (((result_value IS NOT NULL) OR (result_text IS NOT NULL)))` |
| `ix_lab_result_test` | INDEX | `btree (test_code)` |
| `trg_lab_result_flag` | TRIGGER | `BEFORE INSERT OR UPDATE OF result_value, test_code → fn_lab_result_flag()` |
