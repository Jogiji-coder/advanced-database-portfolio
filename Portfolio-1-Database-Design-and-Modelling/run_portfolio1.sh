#!/usr/bin/env bash
# =====================================================================
# Portfolio 1 - rebuild the database from scratch and regenerate every
# artefact (evidence logs, test summary, ERDs, data dictionary, images).
# Requires: PostgreSQL 16 client/server, Python 3 with psycopg + Pillow, Graphviz.
# =====================================================================
set -euo pipefail
cd "$(dirname "$0")"
export PGHOST=${PGHOST:-localhost} PGUSER=${PGUSER:-postgres} PGPASSWORD=${PGPASSWORD:-postgres}

echo ">> Creating database and loading schema, logic and sample data"
psql -X -q -v ON_ERROR_STOP=1 -f sql/00_create_database.sql 2>/dev/null
for f in 01_schema 02_functions_triggers_views 03_seed_data; do
  psql -X -q -v ON_ERROR_STOP=1 -d waynes_clinic -f "sql/$f.sql" > /dev/null 2>&1
done

echo ">> Running constraint tests, core operations and security scripts"
psql -X -d waynes_clinic -f sql/04_constraint_tests.sql > evidence/04_constraint_tests_output.txt 2>&1 || true
psql -X -d waynes_clinic -f sql/05_core_operations.sql  > evidence/05_core_operations_output.txt  2>&1
psql -X -d waynes_clinic -f sql/06_roles_security.sql   > evidence/06_roles_security_output.txt   2>&1 || true
python3 docs/summarise_constraint_tests.py

echo ">> Generating ERDs and data dictionary from the live catalogue"
python3 diagrams/generate_erd.py
python3 docs/generate_data_dictionary.py

echo ">> Rendering evidence images"
R=../tools/render_terminal.py
E=evidence
python3 $R $E/04_constraint_tests_output.txt $E/fig_constraint_tests_keys_checks.png \
  --title "psql - waynes_clinic - constraint suite: keys, domains, CHECK" --start "=== ENTITY" --end "=== REFERENTIAL"
python3 $R $E/04_constraint_tests_output.txt $E/fig_constraint_tests_fk_exclusion_rules.png \
  --title "psql - waynes_clinic - constraint suite: FK, EXCLUDE, triggers, booking guards" --start "=== REFERENTIAL" --end "Suite finished"
python3 $R $E/05_core_operations_output.txt $E/fig_core_op1_booking.png \
  --title "psql - waynes_clinic - Operation 1: book an appointment" --start "OPERATION 1" --end "OPERATION 2"
python3 $R $E/05_core_operations_output.txt $E/fig_core_op2_diagnosis.png \
  --title "psql - waynes_clinic - Operation 2: store a diagnosis" --start "OPERATION 2" --end "OPERATION 3"
python3 $R $E/05_core_operations_output.txt $E/fig_core_op3_history.png \
  --title "psql - waynes_clinic - Operation 3: retrieve patient history" --start "OPERATION 3" --width 150
python3 $R $E/06_roles_security_output.txt $E/fig_roles_privileges.png \
  --title "psql - waynes_clinic - role-based access control" --start "Privilege matrix"
echo ">> Portfolio 1 done"
