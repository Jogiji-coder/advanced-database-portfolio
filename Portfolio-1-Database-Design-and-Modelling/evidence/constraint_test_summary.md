**Constraint test suite: 28/28 tests behaved as expected.**

| # | What is attempted | Expected SQLSTATE | Actual | Result |
|---|---|---|---|---|
| 01 | Duplicate Medical Record Number (UNIQUE uq_patient_mrn) | `23505` | `23505` | PASS |
| 02 | Two doctors with the same licence number (UNIQUE uq_doctor_license) | `23505` | `23505` | PASS |
| 03 | Client tries to supply its own identity value (GENERATED ALWAYS) | `428C9` | `428C9` | PASS |
| 04 | MRN in the wrong format (CHECK chk_patient_mrn) | `23514` | `23514` | PASS |
| 05 | Unknown blood group C+ (CHECK chk_patient_blood) | `23514` | `23514` | PASS |
| 06 | Malformed phone number (DOMAIN phone_number) | `23514` | `23514` | PASS |
| 07 | Malformed e-mail address (DOMAIN email_address) | `23514` | `23514` | PASS |
| 08 | Emergency contact name without a phone (CHECK chk_patient_emergency) | `23514` | `23514` | PASS |
| 09 | Appointment that ends before it starts (CHECK chk_appt_time_order) | `23514` | `23514` | PASS |
| 10 | Pharmacy stock driven below zero (CHECK chk_medication_stock) | `23514` | `23514` | PASS |
| 11 | Prescription line with quantity 0 (CHECK chk_item_quantity) | `23514` | `23514` | PASS |
| 12 | ICD-10 code in an invalid format (CHECK chk_icd10_format) | `23514` | `23514` | PASS |
| 13 | Appointment for a patient that does not exist (FK fk_appt_patient) | `23503` | `23503` | PASS |
| 14 | Delete a patient who has clinical history (ON DELETE RESTRICT) | `23503` | `23503` | PASS |
| 15 | Department head who does not exist, deferred FK forced IMMEDIATE | `23503` | `23503` | PASS |
| 16 | Second patient booked into Dr Okafor's 13-Oct 09:00 slot | `23P01` | `23P01` | PASS |
| 17 | Tyrone Jackson booked with two doctors at overlapping times | `23P01` | `23P01` | PASS |
| 18 | A cancelled appointment frees its slot (partial EXCLUDE ... WHERE status <> Cancelled) | `00000` | `00000` | PASS |
| 19 | Second PRIMARY diagnosis on one appointment (partial unique index) | `23505` | `23505` | PASS |
| 20 | Extra SECONDARY diagnosis on the same appointment is allowed | `00000` | `00000` | PASS |
| 21 | Diagnosis on an appointment that has not happened yet (trigger) | `WC002` | `WC002` | PASS |
| 22 | Penicillin prescribed to James Holloway, who is allergic (trigger) | `WC001` | `WC001` | PASS |
| 23 | Patient registered with a date of birth in the future (trigger) | `WC006` | `WC006` | PASS |
| 24 | Lab trigger flags potassium 6.8 as CRITICAL and sodium 128 as LOW | `00000` | `00000` | PASS |
| 25 | Booking Dr Okafor on a Saturday, when she holds no clinic | `WC003` | `WC003` | PASS |
| 26 | Booking an appointment in the past | `WC005` | `WC005` | PASS |
| 27 | Valid booking: Maria Santos with Dr Okafor next Monday 10:00 | `00000` | `00000` | PASS |
| 28 | Same slot requested for Kwame Mensah (friendly message from function) | `23P01` | `23P01` | PASS |
