"""
Generates docs/data_dictionary.md from the live PostgreSQL catalogue
(table/column comments, types, nullability, defaults and every constraint).

    python generate_data_dictionary.py
"""
import os
import psycopg

DSN = os.environ.get("WC_DSN", "host=localhost dbname=waynes_clinic user=postgres password=postgres")
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data_dictionary.md")

TABLE_ORDER = ["postal_area", "department", "specialty", "doctor", "doctor_availability", "patient",
               "medication", "patient_allergy", "appointment", "icd10_code", "diagnosis",
               "prescription", "prescription_item", "lab_test", "lab_order", "lab_result"]

KIND = {"p": "PRIMARY KEY", "f": "FOREIGN KEY", "u": "UNIQUE", "c": "CHECK", "x": "EXCLUDE"}


def esc(s):
    return (s or "").replace("|", "\\|").replace("\n", " ")


with psycopg.connect(DSN) as conn:
    lines = ["# Data Dictionary — Wayne's Clinic Baltimore",
             "",
             "_Generated automatically from the PostgreSQL 16 system catalogue "
             "(`docs/generate_data_dictionary.py`). Schema: `clinic`._",
             ""]
    counts = dict(conn.execute("""
        SELECT c.relname, (xpath('/row/n/text()',
               query_to_xml(format('select count(*) as n from clinic.%I', c.relname), false, true, '')))[1]::text::int
        FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'clinic' AND c.relkind = 'r'""").fetchall())

    lines += ["## Tables at a glance", "", "| # | Table | Purpose | Sample rows |", "|---|---|---|---|"]
    for i, t in enumerate(TABLE_ORDER, 1):
        desc = conn.execute("SELECT obj_description(%s::regclass, 'pg_class')", (f"clinic.{t}",)).fetchone()[0]
        lines.append(f"| {i} | `{t}` | {esc(desc)} | {counts.get(t, 0)} |")
    lines.append("")

    for t in TABLE_ORDER:
        reg = f"clinic.{t}"
        desc = conn.execute("SELECT obj_description(%s::regclass, 'pg_class')", (reg,)).fetchone()[0]
        lines += [f"## `{t}`", "", esc(desc), ""]
        cols = conn.execute("""
            SELECT a.attname,
                   format_type(a.atttypid, a.atttypmod),
                   a.attnotnull,
                   pg_get_expr(d.adbin, d.adrelid),
                   a.attidentity,
                   col_description(a.attrelid, a.attnum)
            FROM pg_attribute a
            LEFT JOIN pg_attrdef d ON d.adrelid = a.attrelid AND d.adnum = a.attnum
            WHERE a.attrelid = %s::regclass AND a.attnum > 0 AND NOT a.attisdropped
            ORDER BY a.attnum""", (reg,)).fetchall()
        keys = {}
        for name, ctype, cols_ in conn.execute("""
            SELECT conname, contype,
                   array(SELECT attname FROM pg_attribute WHERE attrelid = conrelid AND attnum = ANY(conkey))
            FROM pg_constraint WHERE conrelid = %s::regclass AND contype IN ('p','f','u')""", (reg,)):
            for c in cols_:
                keys.setdefault(c, set()).add({"p": "PK", "f": "FK", "u": "UK"}[ctype])
        lines += ["| Column | Data type | Null? | Default | Key | Description |",
                  "|---|---|---|---|---|---|"]
        for name, typ, notnull, default, ident, comment in cols:
            if ident == "a":
                default = "GENERATED ALWAYS AS IDENTITY"
            typ = typ.replace("clinic.", "")
            k = ", ".join(sorted(keys.get(name, set()), key=["PK", "FK", "UK"].index))
            lines.append(f"| `{name}` | {typ} | {'NO' if notnull else 'yes'} | {esc(default) or ''} | {k} | {esc(comment)} |")
        lines.append("")
        cons = conn.execute("""
            SELECT conname, contype, pg_get_constraintdef(oid)
            FROM pg_constraint WHERE conrelid = %s::regclass
            ORDER BY CASE contype WHEN 'p' THEN 1 WHEN 'u' THEN 2 WHEN 'f' THEN 3 WHEN 'x' THEN 4 ELSE 5 END, conname""",
                            (reg,)).fetchall()
        idx = conn.execute("""
            SELECT indexrelid::regclass::text, pg_get_indexdef(indexrelid)
            FROM pg_index WHERE indrelid = %s::regclass
              AND NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conindid = indexrelid)""", (reg,)).fetchall()
        lines += ["**Constraints**", "", "| Name | Type | Definition |", "|---|---|---|"]
        for name, ctype, definition in cons:
            lines.append(f"| `{name}` | {KIND[ctype]} | `{esc(definition)}` |")
        for name, definition in idx:
            kind = "UNIQUE INDEX (partial)" if "UNIQUE" in definition and "WHERE" in definition else "INDEX"
            lines.append(f"| `{name.split('.')[-1]}` | {kind} | `{esc(definition.split(' USING ')[1])}` |")
        trg = conn.execute("""
            SELECT tgname, pg_get_triggerdef(oid) FROM pg_trigger
            WHERE tgrelid = %s::regclass AND NOT tgisinternal""", (reg,)).fetchall()
        for name, definition in trg:
            when = definition.split(" ON ")[0].split(name)[1].strip()
            fn = definition.split("EXECUTE FUNCTION ")[1]
            lines.append(f"| `{name}` | TRIGGER | `{esc(when)} → {esc(fn)}` |")
        lines.append("")

with open(OUT, "w") as f:
    f.write("\n".join(lines))
print("wrote", OUT)
