-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 03 · Sample data (all people are fictional)
-- Engine: PostgreSQL 16   |   psql -d waynes_clinic -f 03_seed_data.sql
--
-- Phone numbers use the reserved fictional range 555-01xx. NDC codes use
-- the made-up labeller prefix 99001 and are illustrative only.
-- ICD-10-CM codes and descriptions are real (public classification).
-- =====================================================================
SET search_path TO clinic, public;
SET timezone TO 'America/New_York';

BEGIN;

-- ---------------------------------------------------------------- ZIPs
INSERT INTO postal_area (zip_code, city, state_code) VALUES
 ('21201','Baltimore','MD'), ('21202','Baltimore','MD'), ('21205','Baltimore','MD'),
 ('21206','Baltimore','MD'), ('21209','Baltimore','MD'), ('21210','Baltimore','MD'),
 ('21211','Baltimore','MD'), ('21212','Baltimore','MD'), ('21213','Baltimore','MD'),
 ('21215','Baltimore','MD'), ('21217','Baltimore','MD'), ('21218','Baltimore','MD'),
 ('21224','Baltimore','MD'), ('21230','Baltimore','MD'), ('21231','Baltimore','MD'),
 ('21204','Towson','MD'),    ('21228','Catonsville','MD'), ('21043','Ellicott City','MD'),
 ('21061','Glen Burnie','MD'), ('21093','Lutherville-Timonium','MD');

-- ------------------------------------------------- specialties, departments
INSERT INTO specialty (name) VALUES
 ('Family Medicine'), ('Internal Medicine'), ('Cardiology'), ('Pediatrics'),
 ('Orthopedic Surgery'), ('Endocrinology'), ('Clinical Pathology'),
 ('Emergency Medicine'), ('Neurology'), ('Dermatology'), ('Obstetrics and Gynecology');

-- head_doctor_id points at doctors that do not exist yet. This is legal
-- because fk_department_head is DEFERRABLE INITIALLY DEFERRED: it is only
-- checked at COMMIT, by which time the doctors below have been inserted.
INSERT INTO department (name, floor_number, phone_extension, head_doctor_id) VALUES
 ('General Medicine',                 1, '1100',  1),
 ('Cardiology',                       3, '3100',  3),
 ('Pediatrics',                       2, '2100',  5),
 ('Orthopedics',                      2, '2200',  6),
 ('Endocrinology',                    4, '4100',  7),
 ('Pathology and Laboratory Medicine',-1,'0900',  8),
 ('Emergency Medicine',               0, '0100',  9),
 ('Neurology',                        4, '4200', 10),
 ('Dermatology',                      1, '1200', 11),
 ('Obstetrics and Gynecology',        3, '3200', 12);

-- ------------------------------------------------------------- doctors
INSERT INTO doctor (staff_number, first_name, last_name, specialty_id, department_id,
                    license_number, email, phone, hire_date, consultation_minutes) VALUES
 ('WCB-D0001','Amara',  'Okafor',     1, 1,'D0071423','a.okafor@wayneclinic.example',     '410-555-0101','2014-03-01',30),
 ('WCB-D0002','Daniel', 'Brennan',    2, 1,'D0068810','d.brennan@wayneclinic.example',    '410-555-0102','2016-07-15',20),
 ('WCB-D0003','Priya',  'Raman',      3, 2,'D0059932','p.raman@wayneclinic.example',      '410-555-0103','2012-01-09',30),
 ('WCB-D0004','Marcus', 'Whitfield',  3, 2,'D0080147','m.whitfield@wayneclinic.example',  '410-555-0104','2019-09-02',45),
 ('WCB-D0005','Sofia',  'Delgado',    4, 3,'D0074556','s.delgado@wayneclinic.example',    '410-555-0105','2015-05-18',20),
 ('WCB-D0006','Ethan',  'Caldwell',   5, 4,'D0066201','e.caldwell@wayneclinic.example',   '410-555-0106','2013-11-04',30),
 ('WCB-D0007','Grace',  'Lindqvist',  6, 5,'D0083390','g.lindqvist@wayneclinic.example',  '410-555-0107','2020-02-10',30),
 ('WCB-D0008','Hassan', 'Yusuf',      7, 6,'D0061178','h.yusuf@wayneclinic.example',      '410-555-0108','2011-08-22',30),
 ('WCB-D0009','Naomi',  'Fairbanks',  8, 7,'D0077645','n.fairbanks@wayneclinic.example',  '410-555-0109','2017-04-03',15),
 ('WCB-D0010','Tobias', 'Reinhardt',  9, 8,'D0070012','t.reinhardt@wayneclinic.example',  '410-555-0110','2014-10-27',45),
 ('WCB-D0011','Leah',   'Morrison',  10, 9,'D0085521','l.morrison@wayneclinic.example',   '410-555-0111','2021-06-14',20),
 ('WCB-D0012','Chidi',  'Nwosu',     11,10,'D0072298','c.nwosu@wayneclinic.example',      '410-555-0112','2015-12-01',30);

-- ------------------------------------------------- weekly availability
-- Standard clinic sessions: Mon-Fri 09:00-12:30 and 13:30-17:00
INSERT INTO doctor_availability (doctor_id, iso_weekday, start_time, end_time)
SELECT d.doctor_id, wd, s.start_t, s.end_t
FROM doctor d
CROSS JOIN generate_series(1, 5) AS wd
CROSS JOIN (VALUES (time '09:00', time '12:30'), (time '13:30', time '17:00')) AS s(start_t, end_t)
WHERE d.staff_number NOT IN ('WCB-D0008', 'WCB-D0009');

-- Pediatrics also runs a Saturday-morning clinic
INSERT INTO doctor_availability VALUES (5, 6, '09:00', '13:00');
-- Pathologist: Tuesday and Thursday result-review clinics only
INSERT INTO doctor_availability VALUES (8, 2, '10:00', '12:00'), (8, 4, '10:00', '12:00');
-- Emergency physician: 08:00-20:00 every day of the week
INSERT INTO doctor_availability
SELECT 9, wd, '08:00', '20:00' FROM generate_series(1, 7) wd;

-- ------------------------------------------------------------ patients
INSERT INTO patient (mrn, first_name, last_name, date_of_birth, sex, blood_group, phone, email,
                     street_address, zip_code, emergency_contact_name, emergency_contact_phone, registered_at) VALUES
 ('WCB0000001','James',    'Holloway',  '1958-03-14','M','O+','410-555-0121','j.holloway@mail.example',  '1204 Charles St',        '21201','Ruth Holloway',    '410-555-0161','2018-04-02'),
 ('WCB0000002','Maria',    'Santos',    '1985-07-22','F','A+','443-555-0122','m.santos@mail.example',    '33 Aliceanna St',        '21231','Paulo Santos',     '443-555-0162','2019-01-15'),
 ('WCB0000003','Tyrone',   'Jackson',   '1972-11-05','M','B+','410-555-0123','t.jackson@mail.example',   '718 N Fulton Ave',       '21217','Denise Jackson',   '410-555-0163','2017-06-20'),
 ('WCB0000004','Emily',    'Carter',    '1994-02-18','F','O-','443-555-0124','e.carter@mail.example',    '2910 Elliott St',        '21224',NULL,NULL,'2021-09-30'),
 ('WCB0000005','Kwame',    'Mensah',    '1966-09-30','M','AB+','410-555-0125','k.mensah@mail.example',   '4501 Liberty Heights Ave','21215','Abena Mensah',    '410-555-0165','2016-03-11'),
 ('WCB0000006','Olivia',   'Nguyen',    '2016-05-11','F','A-','443-555-0126',NULL,                       '1617 Light St',          '21230','Linh Nguyen',      '443-555-0166','2016-05-20'),
 ('WCB0000007','Robert',   'Kowalski',  '1949-12-02','M','O+','410-555-0127',NULL,                       '609 S Ann St',           '21231','Teresa Kowalski',  '410-555-0167','2015-08-08'),
 ('WCB0000008','Aisha',    'Bello',     '1990-04-27','F','B-','443-555-0128','a.bello@mail.example',     '3402 Greenmount Ave',    '21218','Musa Bello',       '443-555-0168','2022-02-14'),
 ('WCB0000009','Samuel',   'Greene',    '2001-08-15','M','O+','410-555-0129','s.greene@mail.example',    '3100 St Paul St',        '21218',NULL,NULL,'2023-09-01'),
 ('WCB0000010','Hannah',   'Fitzgerald','1978-01-09','F','A+','443-555-0130','h.fitz@mail.example',      '5 E Lake Ave',           '21212','Conor Fitzgerald', '443-555-0170','2018-11-23'),
 ('WCB0000011','Diego',    'Ramirez',   '1983-06-03','M','O+','410-555-0131','d.ramirez@mail.example',   '2214 Eastern Ave',       '21224','Lucia Ramirez',    '410-555-0171','2020-07-07'),
 ('WCB0000012','Chloe',    'Dubois',    '1999-10-21','F','AB-','443-555-0132','c.dubois@mail.example',   '3611 Keswick Rd',        '21211',NULL,NULL,'2024-01-19'),
 ('WCB0000013','Benjamin', 'Adeyemi',   '2019-03-08','M','B+','410-555-0133',NULL,                       '1010 E Pratt St',        '21202','Folake Adeyemi',   '410-555-0173','2019-03-15'),
 ('WCB0000014','Grace',    'Whitaker',  '1962-07-17','F','O-','443-555-0134','g.whitaker@mail.example',  '402 Murdock Rd',         '21212','Paul Whitaker',    '443-555-0174','2014-05-05'),
 ('WCB0000015','Liam',     'O''Connor', '1975-05-25','M','A+','410-555-0135','l.oconnor@mail.example',   '800 Frederick Rd',       '21228','Siobhan O''Connor','410-555-0175','2019-10-10'),
 ('WCB0000016','Zara',     'Ahmed',     '1988-12-12','F','B+','443-555-0136','z.ahmed@mail.example',     '6100 Park Heights Ave',  '21215',NULL,NULL,'2021-03-03'),
 ('WCB0000017','Marcus',   'Bell',      '1955-02-28','M','A-','410-555-0137',NULL,                       '210 Allegheny Ave',      '21204','Carol Bell',       '410-555-0177','2013-12-12'),
 ('WCB0000018','Isabella', 'Rossi',     '2008-09-19','F','O+','443-555-0138',NULL,                       '9000 Frederick Rd',      '21043','Marco Rossi',      '443-555-0178','2008-10-01'),
 ('WCB0000019','Kevin',    'Park',      '1993-11-30','M','A+','410-555-0139','k.park@mail.example',      '1 W Mount Vernon Pl',    '21201',NULL,NULL,'2022-08-18'),
 ('WCB0000020','Fatima',   'Diallo',    '1970-03-03','F','B+','443-555-0140','f.diallo@mail.example',    '7 Crain Hwy',            '21061','Ibrahima Diallo',  '443-555-0180','2017-02-27');

-- ---------------------------------------------------------- medications
INSERT INTO medication (ndc_code, generic_name, brand_name, dosage_form, strength, unit_price, stock_on_hand, is_controlled) VALUES
 ('99001-0001-01','Metformin',              'Glucophage', 'Tablet',   '500 mg',           0.15, 5000, false),
 ('99001-0002-01','Lisinopril',             'Zestril',    'Tablet',   '10 mg',            0.12, 4000, false),
 ('99001-0003-01','Atorvastatin',           'Lipitor',    'Tablet',   '20 mg',            0.20, 3500, false),
 ('99001-0004-01','Amoxicillin',            'Amoxil',     'Capsule',  '500 mg',           0.25, 2500, false),
 ('99001-0005-01','Ibuprofen',              'Advil',      'Tablet',   '400 mg',           0.05, 8000, false),
 ('99001-0006-01','Acetaminophen',          'Tylenol',    'Tablet',   '500 mg',           0.04, 9000, false),
 ('99001-0007-01','Albuterol',              'ProAir HFA', 'Inhaler',  '90 mcg/actuation',28.00,  300, false),
 ('99001-0008-01','Amlodipine',             'Norvasc',    'Tablet',   '5 mg',             0.10, 3000, false),
 ('99001-0009-01','Omeprazole',             'Prilosec',   'Capsule',  '20 mg',            0.18, 2800, false),
 ('99001-0010-01','Levothyroxine',          'Synthroid',  'Tablet',   '50 mcg',           0.22, 2600, false),
 ('99001-0011-01','Sertraline',             'Zoloft',     'Tablet',   '50 mg',            0.30, 1500, false),
 ('99001-0012-01','Penicillin V Potassium', NULL,         'Tablet',   '500 mg',           0.20, 1200, false),
 ('99001-0013-01','Cetirizine',             'Zyrtec',     'Tablet',   '10 mg',            0.08, 3000, false),
 ('99001-0014-01','Prednisone',             NULL,         'Tablet',   '20 mg',            0.10, 1800, false),
 ('99001-0015-01','Insulin Glargine',       'Lantus',     'Injection','100 units/mL',    95.00,  150, false),
 ('99001-0016-01','Azithromycin',           'Zithromax',  'Tablet',   '250 mg',           0.90, 1400, false),
 ('99001-0017-01','Hydrochlorothiazide',    'Microzide',  'Capsule',  '12.5 mg',          0.09, 2200, false),
 ('99001-0018-01','Warfarin',               'Coumadin',   'Tablet',   '5 mg',             0.35,  900, false),
 ('99001-0019-01','Hydrocortisone',         'Cortaid',    'Cream',    '1%',               6.50,  400, false),
 ('99001-0020-01','Oxycodone',              'Roxicodone', 'Tablet',   '5 mg',             1.20,  200, true),
 ('99001-0021-01','Losartan',               'Cozaar',     'Tablet',   '50 mg',            0.14, 2600, false),
 ('99001-0022-01','Sumatriptan',            'Imitrex',    'Tablet',   '50 mg',            1.10,  600, false),
 ('99001-0023-01','Nitrofurantoin',         'Macrobid',   'Capsule',  '100 mg',           0.60,  800, false);

-- ------------------------------------------------------------ allergies
INSERT INTO patient_allergy (patient_id, medication_id, reaction, severity, recorded_at) VALUES
 ( 1, 12, 'Anaphylaxis',                       'Severe',   '2018-04-02'),
 ( 4,  4, 'Hives',                             'Moderate', '2021-09-30'),
 ( 6,  4, 'Maculopapular rash',                'Mild',     '2019-02-11'),
 (15, 20, 'Severe nausea and vomiting',        'Moderate', '2020-01-06'),
 (20,  5, 'Bronchospasm',                      'Moderate', '2017-02-27');

-- ------------------------------------------------------------ ICD-10-CM
INSERT INTO icd10_code (icd10_code, description, chapter) VALUES
 ('I10',     'Essential (primary) hypertension',                                      'Diseases of the circulatory system'),
 ('I25.10',  'Atherosclerotic heart disease of native coronary artery without angina pectoris', 'Diseases of the circulatory system'),
 ('I48.91',  'Unspecified atrial fibrillation',                                       'Diseases of the circulatory system'),
 ('E11.9',   'Type 2 diabetes mellitus without complications',                        'Endocrine, nutritional and metabolic diseases'),
 ('E78.5',   'Hyperlipidemia, unspecified',                                           'Endocrine, nutritional and metabolic diseases'),
 ('E03.9',   'Hypothyroidism, unspecified',                                           'Endocrine, nutritional and metabolic diseases'),
 ('E66.9',   'Obesity, unspecified',                                                  'Endocrine, nutritional and metabolic diseases'),
 ('J45.909', 'Unspecified asthma, uncomplicated',                                     'Diseases of the respiratory system'),
 ('J06.9',   'Acute upper respiratory infection, unspecified',                        'Diseases of the respiratory system'),
 ('J02.9',   'Acute pharyngitis, unspecified',                                        'Diseases of the respiratory system'),
 ('J18.9',   'Pneumonia, unspecified organism',                                       'Diseases of the respiratory system'),
 ('K21.9',   'Gastro-esophageal reflux disease without esophagitis',                  'Diseases of the digestive system'),
 ('N39.0',   'Urinary tract infection, site not specified',                           'Diseases of the genitourinary system'),
 ('F41.1',   'Generalized anxiety disorder',                                          'Mental, behavioral and neurodevelopmental disorders'),
 ('G43.909', 'Migraine, unspecified, not intractable, without status migrainosus',    'Diseases of the nervous system'),
 ('M54.50',  'Low back pain, unspecified',                                            'Diseases of the musculoskeletal system and connective tissue'),
 ('S93.401A','Sprain of unspecified ligament of right ankle, initial encounter',       'Injury, poisoning and certain other consequences of external causes'),
 ('L20.9',   'Atopic dermatitis, unspecified',                                        'Diseases of the skin and subcutaneous tissue'),
 ('D64.9',   'Anemia, unspecified',                                                   'Diseases of the blood and blood-forming organs'),
 ('U07.1',   'COVID-19',                                                              'Codes for special purposes'),
 ('R07.9',   'Chest pain, unspecified',                                               'Symptoms, signs and abnormal clinical and laboratory findings'),
 ('R10.9',   'Unspecified abdominal pain',                                            'Symptoms, signs and abnormal clinical and laboratory findings'),
 ('R51.9',   'Headache, unspecified',                                                 'Symptoms, signs and abnormal clinical and laboratory findings'),
 ('Z00.00',  'Encounter for general adult medical examination without abnormal findings','Factors influencing health status and contact with health services'),
 ('Z23',     'Encounter for immunization',                                            'Factors influencing health status and contact with health services');

-- ------------------------------------------------------- lab catalogue
INSERT INTO lab_test (test_code, test_name, specimen_type, unit, ref_low, ref_high, critical_low, critical_high, turnaround_hours) VALUES
 ('HGB',  'Hemoglobin',                    'Blood','g/dL',    12.0,  17.5,   7.0,  20.0,  4),
 ('WBC',  'White blood cell count',        'Blood','10^9/L',   4.5,  11.0,   2.0,  30.0,  4),
 ('PLT',  'Platelet count',                'Blood','10^9/L', 150,   450,    50,  1000,    4),
 ('GLU',  'Fasting plasma glucose',        'Blood','mg/dL',   70,    99,    40,   450,    2),
 ('HBA1C','Hemoglobin A1c',                'Blood','%',        4.0,   5.6,  NULL,  NULL,  24),
 ('CHOL', 'Total cholesterol',             'Blood','mg/dL',  125,   200,  NULL,  NULL,  24),
 ('LDL',  'LDL cholesterol',               'Blood','mg/dL',  NULL,   99,  NULL,  NULL,  24),
 ('HDL',  'HDL cholesterol',               'Blood','mg/dL',   40,  NULL,  NULL,  NULL,  24),
 ('TSH',  'Thyroid stimulating hormone',   'Blood','mIU/L',    0.4,   4.0,  NULL,  NULL,  24),
 ('CREAT','Creatinine',                    'Blood','mg/dL',    0.6,   1.3,  NULL,   4.0,   4),
 ('NA',   'Sodium',                        'Blood','mmol/L', 135,   145,   120,   160,    2),
 ('K',    'Potassium',                     'Blood','mmol/L',   3.5,   5.1,   2.8,   6.2,   2),
 ('ALT',  'Alanine aminotransferase',      'Blood','U/L',      7,    56,   NULL,  NULL,   4),
 ('CRP',  'C-reactive protein',            'Blood','mg/L',   NULL,   10,   NULL,  NULL,   4),
 ('TROP', 'Troponin I (high-sensitivity)', 'Blood','ng/L',   NULL,   14,   NULL,    52,   1),
 ('INR',  'Prothrombin time (INR)',        'Blood','ratio',    0.8,   1.1,  NULL,   5.0,   2),
 ('UA',   'Urinalysis (dipstick)',         'Urine', NULL,    NULL,  NULL,  NULL,  NULL,   2),
 ('COVID','SARS-CoV-2 RNA (PCR)',          'Swab',  NULL,    NULL,  NULL,  NULL,  NULL,  24);

-- --------------------------------------------------------- appointments
-- Explicit ids keep the sample readable; the identity sequence is reset below.
INSERT INTO appointment (appointment_id, patient_id, doctor_id, scheduled_start, scheduled_end, status, reason, booked_at)
OVERRIDING SYSTEM VALUE
SELECT v.id, v.pid, v.did, v.st::timestamptz,
       v.st::timestamptz + make_interval(mins => d.consultation_minutes),
       v.status::appointment_status, v.reason, v.st::timestamptz - interval '9 days'
FROM (VALUES
 ( 1,  1,  2, '2026-09-01 09:00', 'Completed', 'Annual check-up; raised BP readings at home'),
 ( 2,  3,  3, '2026-09-02 10:00', 'Completed', 'Intermittent chest pain on exertion'),
 ( 3,  4,  1, '2026-09-03 11:00', 'Completed', 'Wheezing and shortness of breath'),
 ( 4,  6,  5, '2026-09-04 09:20', 'Completed', 'Sore throat and fever'),
 ( 5,  9,  6, '2026-09-08 14:00', 'Completed', 'Twisted right ankle playing basketball'),
 ( 6, 10,  7, '2026-09-09 10:30', 'Completed', 'Fatigue, weight gain, feeling cold'),
 ( 7, 14,  7, '2026-09-10 13:30', 'Completed', 'Diabetes review'),
 ( 8,  7,  4, '2026-09-14 09:00', 'Completed', 'Follow-up after coronary stent'),
 ( 9,  2,  1, '2026-09-15 15:00', 'NoShow',    'Routine physical'),
 (10, 11,  2, '2026-09-16 11:20', 'Completed', 'Heartburn after meals'),
 (11, 12, 10, '2026-09-17 14:15', 'Completed', 'Recurring severe headaches with aura'),
 (12, 13,  5, '2026-09-21 10:00', 'Completed', 'Runny nose and cough for four days'),
 (13, 16,  1, '2026-09-22 09:30', 'Completed', 'Persistent worry and poor sleep'),
 (14,  8, 12, '2026-09-23 10:00', 'Completed', 'Prenatal visit; tiredness'),
 (15, 17,  2, '2026-09-24 09:40', 'Completed', 'Blood pressure follow-up'),
 (16, 18, 11, '2026-09-28 11:00', 'Completed', 'Itchy rash on both forearms'),
 (17, 20,  1, '2026-09-29 14:00', 'Completed', 'Burning on urination'),
 (18, 19,  9, '2026-09-30 18:00', 'Completed', 'Fever, cough, loss of taste'),
 (19,  5,  3, '2026-10-01 09:30', 'Completed', 'Cholesterol review'),
 (20, 15,  6, '2026-10-05 10:00', 'Completed', 'Lower back pain after lifting'),
 (21,  1,  7, '2026-10-06 11:00', 'Completed', 'Diabetes education and review'),
 (22,  3,  4, '2026-10-07 14:15', 'Completed', 'Palpitations; irregular rhythm on ECG'),
 (23, 14,  2, '2026-10-08 15:20', 'Cancelled', 'Flu vaccine'),
 (24, 14,  2, '2026-10-12 15:20', 'Completed', 'Flu vaccine (rebooked)'),
 (25,  2,  1, '2026-10-13 09:00', 'Completed', 'Routine physical (rebooked after no-show)'),
 (26,  4,  1, '2026-10-14 10:30', 'Completed', 'Asthma follow-up; productive cough'),
 (27,  7,  3, '2026-10-15 13:30', 'NoShow',    'Echocardiogram review'),
 (28,  9,  6, '2026-10-19 14:30', 'Completed', 'Ankle sprain follow-up'),
 (29, 12, 10, '2026-10-20 09:00', 'Completed', 'Migraine follow-up'),
 (30,  3,  4, '2026-10-21 09:45', 'Completed', 'Anticoagulation (INR) check'),
 (31, 10,  7, '2026-10-22 10:00', 'Completed', 'Thyroid recheck'),
 (32, 11,  9, '2026-10-26 19:00', 'Completed', 'Severe upper abdominal pain'),
 (33, 17,  2, '2026-10-27 10:00', 'Completed', 'BP check; low potassium follow-up'),
 (34, 16,  1, '2026-10-28 09:00', 'CheckedIn', 'Medication review'),
 (35,  8, 12, '2026-11-02 10:30', 'Scheduled', 'Prenatal visit'),
 (36,  1,  2, '2026-11-03 09:00', 'Scheduled', 'Blood pressure review'),
 (37,  5,  3, '2026-11-04 14:00', 'Scheduled', 'Lipid follow-up'),
 (38, 13,  5, '2026-11-05 09:40', 'Scheduled', 'Childhood vaccination'),
 (39, 19,  1, '2026-11-09 11:00', 'Scheduled', 'Post-COVID check'),
 (40,  6, 11, '2026-11-10 10:20', 'Scheduled', 'Skin check')
) AS v(id, pid, did, st, status, reason)
JOIN doctor d ON d.doctor_id = v.did;

SELECT setval(pg_get_serial_sequence('clinic.appointment', 'appointment_id'),
              (SELECT max(appointment_id) FROM appointment));

-- ----------------------------------------------------------- diagnoses
INSERT INTO diagnosis (appointment_id, icd10_code, diagnosis_type, clinical_notes, diagnosed_at)
SELECT v.appt, v.code, v.dtype, v.notes, a.scheduled_start + interval '20 minutes'
FROM (VALUES
 ( 1,'I10',     'Primary',     'BP 158/96 in clinic, consistent with home readings.'),
 ( 1,'E11.9',   'Secondary',   'HbA1c 7.4%. Lifestyle advice and metformin.'),
 ( 2,'R07.9',   'Primary',     'Exertional chest tightness relieved by rest.'),
 ( 2,'I25.10',  'Differential','Rule out stable angina; exercise stress test requested.'),
 ( 3,'J45.909', 'Primary',     'Mild persistent asthma; peak flow 72% of predicted.'),
 ( 4,'J02.9',   'Primary',     'Rapid strep negative. Amoxicillin allergy noted - macrolide chosen.'),
 ( 5,'S93.401A','Primary',     'Grade II lateral sprain; X-ray shows no fracture.'),
 ( 6,'E03.9',   'Primary',     'TSH 9.8 mIU/L. Start levothyroxine.'),
 ( 7,'E11.9',   'Primary',     'Poor glycemic control; starting basal insulin.'),
 ( 7,'E66.9',   'Secondary',   'BMI 33.'),
 ( 8,'I25.10',  'Primary',     'Stable; continue high-intensity statin.'),
 (10,'K21.9',   'Primary',     'Typical reflux symptoms; trial of PPI.'),
 (11,'G43.909', 'Primary',     'Migraine with visual aura, 3-4 episodes per month.'),
 (12,'J06.9',   'Primary',     'Viral URI; supportive care, fluids and rest.'),
 (13,'F41.1',   'Primary',     'GAD-7 score 14; referred for CBT.'),
 (14,'D64.9',   'Primary',     'Hb 9.8 g/dL at 24 weeks; oral iron advised.'),
 (15,'I10',     'Primary',     'BP 148/92; add thiazide.'),
 (15,'E66.9',   'Secondary',   'BMI 31.'),
 (16,'L20.9',   'Primary',     'Flexural eczema; emollients and topical steroid.'),
 (17,'N39.0',   'Primary',     'Uncomplicated cystitis; ibuprofen allergy noted.'),
 (18,'U07.1',   'Primary',     'PCR positive; mild disease, no hypoxia.'),
 (19,'E78.5',   'Primary',     'LDL 151 mg/dL despite diet.'),
 (20,'M54.50',  'Primary',     'Mechanical back pain, no red flags. Opioid intolerance noted.'),
 (21,'E11.9',   'Primary',     'Improving; HbA1c 7.1%.'),
 (22,'I48.91',  'Primary',     'New atrial fibrillation; CHA2DS2-VASc 2; start anticoagulation.'),
 (24,'Z23',     'Primary',     'Influenza vaccine administered, left deltoid.'),
 (25,'Z00.00',  'Primary',     'Well adult examination; routine bloods normal.'),
 (26,'J45.909', 'Primary',     'Asthma control fair.'),
 (26,'J18.9',   'Secondary',   'Right lower lobe crackles; CRP 18 mg/L.'),
 (28,'S93.401A','Primary',     'Healing well; return to sport in 2 weeks.'),
 (29,'G43.909', 'Primary',     'Frequency reduced to 1-2 per month.'),
 (30,'I48.91',  'Primary',     'INR 2.1 - within therapeutic target of 2.0-3.0.'),
 (31,'E03.9',   'Primary',     'TSH improving on levothyroxine.'),
 (32,'R10.9',   'Primary',     'Epigastric pain with raised ALT; ultrasound requested.'),
 (33,'I10',     'Primary',     'Potassium back in range; BP controlled.')
) AS v(appt, code, dtype, notes)
JOIN appointment a ON a.appointment_id = v.appt;

-- ------------------------------------------------------- prescriptions
WITH lines (appt, line_no, med, dosage, frequency, days, qty) AS (VALUES
 ( 1,1, 2,'10 mg',      'Once daily',                               90, 90),
 ( 1,2, 1,'500 mg',     'Twice daily with meals',                   90,180),
 ( 2,1, 3,'20 mg',      'Once daily at night',                      90, 90),
 ( 3,1, 7,'2 puffs',    'Every 4-6 hours as needed',                30,  1),
 ( 3,2,14,'40 mg',      'Once daily with breakfast',                 5, 10),
 ( 4,1,16,'250 mg',     'Once daily',                                5,  5),
 ( 4,2, 6,'250 mg',     'Every 6 hours as needed for fever',         3,  6),
 ( 5,1, 5,'400 mg',     'Three times daily with food',               7, 21),
 ( 6,1,10,'50 mcg',     'Once daily before breakfast',              90, 90),
 ( 7,1, 1,'1000 mg',    'Twice daily with meals',                   90,360),
 ( 7,2,15,'10 units',   'Once daily at bedtime',                    30,  1),
 ( 8,1, 3,'20 mg',      'Once daily',                               90, 90),
 (10,1, 9,'20 mg',      'Once daily before breakfast',              30, 30),
 (11,1,22,'50 mg',      'At migraine onset; may repeat after 2 h',  30,  9),
 (13,1,11,'50 mg',      'Once daily',                               30, 30),
 (15,1, 8,'5 mg',       'Once daily',                               90, 90),
 (15,2,17,'12.5 mg',    'Once daily in the morning',                90, 90),
 (16,1,19,'Thin layer', 'Twice daily to affected areas',            14,  1),
 (17,1,23,'100 mg',     'Twice daily',                               5, 10),
 (18,1, 6,'1000 mg',    'Every 6 hours as needed',                   5, 20),
 (19,1, 3,'20 mg',      'Once daily',                               90, 90),
 (20,1, 5,'400 mg',     'Three times daily with food',              10, 30),
 (21,1, 1,'500 mg',     'Twice daily with meals',                   90,180),
 (22,1,18,'5 mg',       'Once daily in the evening',                30, 30),
 (26,1,16,'500 mg',     'Once daily',                                3,  6),
 (29,1,22,'50 mg',      'At migraine onset',                        30,  9),
 (33,1, 8,'5 mg',       'Once daily',                               90, 90)
),
headers AS (
    INSERT INTO prescription (appointment_id, issued_at, status)
    SELECT a.appointment_id, a.scheduled_start + interval '25 minutes', 'Dispensed'
    FROM appointment a
    WHERE a.appointment_id IN (SELECT DISTINCT appt FROM lines)
    RETURNING prescription_id, appointment_id
)
INSERT INTO prescription_item (prescription_id, line_no, medication_id, dosage, frequency, duration_days, quantity)
SELECT h.prescription_id, l.line_no, l.med, l.dosage, l.frequency, l.days, l.qty
FROM lines l JOIN headers h ON h.appointment_id = l.appt;

-- --------------------------------------------------- lab orders/results
WITH res (appt, test, val, txt, flag) AS (VALUES
 ( 1,'HBA1C', 7.4,  NULL::varchar, NULL::char(1)),
 ( 1,'GLU',   142,  NULL, NULL), ( 1,'CREAT', 1.1, NULL, NULL),
 ( 2,'TROP',  8,    NULL, NULL), ( 2,'CHOL',  245, NULL, NULL), ( 2,'LDL', 162, NULL, NULL),
 ( 6,'TSH',   9.8,  NULL, NULL),
 ( 7,'HBA1C', 8.9,  NULL, NULL), ( 7,'GLU',   188, NULL, NULL),
 ( 8,'LDL',   92,   NULL, NULL), ( 8,'CHOL',  170, NULL, NULL),
 (14,'HGB',   9.8,  NULL, NULL),
 (15,'NA',    139,  NULL, NULL), (15,'K',     3.3, NULL, NULL), (15,'CREAT', 1.0, NULL, NULL),
 (17,'UA',    NULL, 'Leukocyte esterase positive; nitrite positive', 'H'),
 (18,'COVID', NULL, 'SARS-CoV-2 RNA detected',                       'H'),
 (19,'CHOL',  232,  NULL, NULL), (19,'LDL',   151, NULL, NULL), (19,'HDL', 38, NULL, NULL),
 (21,'HBA1C', 7.1,  NULL, NULL), (21,'GLU',   128, NULL, NULL),
 (22,'INR',   1.0,  NULL, NULL),
 (25,'HGB',   13.5, NULL, NULL), (25,'WBC',   6.2, NULL, NULL), (25,'PLT', 250, NULL, NULL), (25,'CHOL', 185, NULL, NULL),
 (26,'CRP',   18,   NULL, NULL), (26,'WBC',   12.4,NULL, NULL),
 (30,'INR',   2.1,  NULL, NULL),
 (31,'TSH',   4.6,  NULL, NULL),
 (32,'ALT',   72,   NULL, NULL), (32,'CRP',   4,   NULL, NULL),
 (33,'K',     3.9,  NULL, NULL)
),
orders AS (
    INSERT INTO lab_order (appointment_id, ordered_at, priority, status)
    SELECT a.appointment_id,
           a.scheduled_start + interval '15 minutes',
           CASE WHEN a.doctor_id = 9 THEN 'STAT' ELSE 'Routine' END,
           'Completed'
    FROM appointment a
    WHERE a.appointment_id IN (SELECT DISTINCT appt FROM res)
    ORDER BY a.appointment_id
    RETURNING lab_order_id, appointment_id
)
INSERT INTO lab_result (lab_order_id, test_code, result_value, result_text, abnormal_flag, resulted_at)
SELECT o.lab_order_id, r.test, r.val, r.txt, r.flag,
       a.scheduled_start + CASE WHEN a.doctor_id = 9 THEN interval '2 hours' ELSE interval '1 day' END
FROM res r
JOIN orders o      ON o.appointment_id = r.appt
JOIN appointment a ON a.appointment_id = r.appt;

COMMIT;   -- deferred FK on department.head_doctor_id is checked here

ANALYZE;
