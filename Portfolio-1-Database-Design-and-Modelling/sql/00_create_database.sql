-- =====================================================================
-- Wayne's Clinic Baltimore — Advanced Database Systems Portfolio
-- Portfolio 1 · Script 00 · Create the database
-- Engine: PostgreSQL 16   |   Run as a superuser:  psql -U postgres -f 00_create_database.sql
-- =====================================================================

DROP DATABASE IF EXISTS waynes_clinic;

CREATE DATABASE waynes_clinic
    WITH ENCODING   = 'UTF8'
         TEMPLATE   = template0
         LC_COLLATE = 'C.UTF-8'
         LC_CTYPE   = 'C.UTF-8';

COMMENT ON DATABASE waynes_clinic IS
    'Operational database for Wayne''s Clinic Baltimore: patients, doctors, appointments, diagnoses, prescriptions and laboratory records.';

-- The clinic operates in Baltimore, Maryland, so local time is US Eastern.
ALTER DATABASE waynes_clinic SET timezone TO 'America/New_York';
ALTER DATABASE waynes_clinic SET search_path TO clinic, public;
