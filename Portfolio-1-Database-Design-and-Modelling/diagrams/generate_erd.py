"""
Wayne's Clinic Baltimore - ERD generator (Portfolio 1)

Reads the live PostgreSQL catalogue so the logical ERD can never drift from
the schema, then renders Crow's-Foot diagrams with Graphviz.

    python generate_erd.py            # needs the waynes_clinic database loaded
Outputs: erd_logical.{dot,svg,png}, erd_conceptual.{dot,svg,png}
"""
import os
import subprocess
import psycopg

DSN = os.environ.get("WC_DSN", "host=localhost dbname=waynes_clinic user=postgres password=postgres")
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = "Inter"

GROUPS = {
    "Patients":   ("#1d4ed8", ["patient", "patient_allergy", "postal_area"]),
    "Staff":      ("#6d28d9", ["doctor", "department", "specialty", "doctor_availability"]),
    "Scheduling": ("#0f766e", ["appointment"]),
    "Clinical":   ("#15803d", ["diagnosis", "icd10_code"]),
    "Pharmacy":   ("#b45309", ["prescription", "prescription_item", "medication"]),
    "Laboratory": ("#be123c", ["lab_order", "lab_result", "lab_test"]),
}
COLOUR = {t: c for c, ts in GROUPS.values() for t in ts}

COLS_SQL = """
SELECT c.relname, a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull, a.attnum
FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'clinic' AND c.relkind = 'r' AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY c.relname, a.attnum
"""
CONS_SQL = """
SELECT c.relname, con.contype, con.conname,
       array(SELECT attname FROM pg_attribute WHERE attrelid = con.conrelid AND attnum = ANY(con.conkey)),
       fc.relname,
       array(SELECT attname FROM pg_attribute WHERE attrelid = con.confrelid AND attnum = ANY(con.confkey))
FROM pg_constraint con
JOIN pg_class c ON c.oid = con.conrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_class fc ON fc.oid = con.confrelid
WHERE n.nspname = 'clinic' AND con.contype IN ('p', 'f', 'u')
"""


def short_type(t: str) -> str:
    return (t.replace("character varying", "varchar").replace("timestamp with time zone", "timestamptz")
             .replace("character", "char").replace("time without time zone", "time")
             .replace("clinic.", ""))


def load():
    with psycopg.connect(DSN) as conn:
        cols = conn.execute(COLS_SQL).fetchall()
        cons = conn.execute(CONS_SQL).fetchall()
    tables = {}
    for rel, col, typ, notnull, _ in cols:
        tables.setdefault(rel, []).append((col, short_type(typ), notnull))
    pk, uk, fks = {}, {}, []
    for rel, typ, name, keys, frel, fkeys in cons:
        if typ == "p":
            pk[rel] = set(keys)
        elif typ == "u":
            uk.setdefault(rel, set()).update(keys)
        else:
            fks.append((rel, list(keys), frel, list(fkeys), name))
    return tables, pk, uk, fks


def table_label(name, cols, pk, uk, fkcols):
    colour = COLOUR.get(name, "#334155")
    rows = [f'<TR><TD COLSPAN="3" BGCOLOR="{colour}" ALIGN="LEFT" CELLPADDING="6">'
            f'<FONT COLOR="white" POINT-SIZE="13"><B>{name}</B></FONT></TD></TR>']
    for col, typ, notnull in cols:
        tags = []
        if col in pk.get(name, set()):
            tags.append("PK")
        if col in fkcols:
            tags.append("FK")
        if col in uk.get(name, set()) and "PK" not in tags:
            tags.append("UK")
        tag = ",".join(tags)
        weight_open, weight_close = ("<B>", "</B>") if "PK" in tags else ("", "")
        nn = "" if notnull else '<FONT COLOR="#94a3b8"> ?</FONT>'
        rows.append(
            (f'<TR><TD ALIGN="LEFT" WIDTH="34"><FONT COLOR="{colour}" POINT-SIZE="9"><B>{tag}</B></FONT></TD>' if tag
             else '<TR><TD ALIGN="LEFT" WIDTH="34"> </TD>') +
            f'<TD ALIGN="LEFT" PORT="{col}">{weight_open}{col}{weight_close}{nn}</TD>'
            f'<TD ALIGN="LEFT"><FONT COLOR="#64748b" POINT-SIZE="10">{typ}</FONT></TD></TR>')
    return ('<<TABLE BORDER="1" CELLBORDER="0" CELLSPACING="0" CELLPADDING="3" COLOR="#cbd5e1" BGCOLOR="white">'
            + "".join(rows) + "</TABLE>>")


def logical(tables, pk, uk, fks):
    fkcols = {}
    for rel, keys, *_ in fks:
        fkcols.setdefault(rel, set()).update(keys)
    notnull = {(t, c): nn for t, cols in tables.items() for c, _, nn in cols}
    out = [
        "digraph ERD {",
        f'  graph [rankdir=LR, splines=spline, nodesep=0.5, ranksep=1.3, newrank=true, pad=0.4, bgcolor="white", '
        f'fontname="{FONT}", label=<<B>Wayne\'s Clinic Baltimore — Logical ERD (Crow\'s Foot)</B><BR/>'
        f'<FONT POINT-SIZE="11" COLOR="#475569">Generated from the PostgreSQL 16 catalogue · '
        f'PK primary key · FK foreign key · UK unique · ? nullable · solid line = identifying, dashed = non-identifying</FONT>>, '
        f'labelloc=t, fontsize=20];',
        f'  node [shape=plain, fontname="{FONT}", fontsize=11];',
        f'  edge [fontname="{FONT}", color="#475569", penwidth=1.3, arrowsize=0.9];',
    ]
    for gname, (colour, members) in GROUPS.items():
        out.append(f'  subgraph cluster_{gname} {{ label=<<B>{gname}</B>>; fontcolor="{colour}"; '
                   f'color="{colour}40"; style="rounded,dashed"; fontsize=13;')
        for t in members:
            out.append(f"    {t} [label={table_label(t, tables[t], pk, uk, fkcols.get(t, set()))}];")
        out.append("  }")
    for rel, keys, frel, fkeys, name in fks:
        mandatory = all(notnull[(rel, k)] for k in keys)
        unique_child = set(keys) == pk.get(rel, set()) or set(keys) <= uk.get(rel, set()) and len(keys) == len(uk.get(rel, set()))
        identifying = set(keys) <= pk.get(rel, set())
        parent_end = "teetee" if mandatory else "teeodot"
        child_end = "teeodot" if unique_child else "crowodot"
        style = "solid" if identifying else "dashed"
        out.append(f'  {frel} -> {rel} [dir=both, arrowtail={parent_end}, '
                   f'arrowhead={child_end}, style={style}, tooltip="{name}"];')
    out.append("}")
    return "\n".join(out)


def conceptual():
    """Entity-level view: business vocabulary, no attributes."""
    ent = {
        "Patient": "#1d4ed8", "Doctor": "#6d28d9", "Department": "#6d28d9", "Specialty": "#6d28d9",
        "Clinic Session": "#6d28d9", "Appointment": "#0f766e", "Diagnosis": "#15803d",
        "ICD-10 Code": "#15803d", "Prescription": "#b45309", "Medication": "#b45309",
        "Lab Order": "#be123c", "Lab Result": "#be123c", "Lab Test": "#be123c", "Postal Area": "#1d4ed8",
    }
    # (parent, child, verb, parent_end, child_end)
    rels = [
        ("Patient", "Appointment", "books", "teetee", "crowodot"),
        ("Doctor", "Appointment", "attends", "teetee", "crowodot"),
        ("Department", "Doctor", "employs", "teetee", "crowodot"),
        ("Specialty", "Doctor", "certifies", "teetee", "crowodot"),
        ("Doctor", "Clinic Session", "holds", "teetee", "crowodot"),
        ("Doctor", "Department", "heads", "teeodot", "teeodot"),
        ("Appointment", "Diagnosis", "results in", "teetee", "crowodot"),
        ("ICD-10 Code", "Diagnosis", "classifies", "teetee", "crowodot"),
        ("Appointment", "Prescription", "issues", "teetee", "crowodot"),
        ("Prescription", "Medication", "lists (M:N via line)", "crowodot", "crowtee"),
        ("Patient", "Medication", "is allergic to (M:N)", "crowodot", "crowodot"),
        ("Appointment", "Lab Order", "requests", "teetee", "crowodot"),
        ("Lab Order", "Lab Result", "produces", "teetee", "crowodot"),
        ("Lab Test", "Lab Result", "measured by", "teetee", "crowodot"),
        ("Postal Area", "Patient", "locates", "teeodot", "crowodot"),
    ]
    out = [
        "digraph Conceptual {",
        f'  graph [rankdir=LR, nodesep=0.6, ranksep=1.1, pad=0.4, fontname="{FONT}", '
        f'label=<<B>Wayne\'s Clinic Baltimore — Conceptual ER Model</B><BR/>'
        f'<FONT POINT-SIZE="11" COLOR="#475569">Entities and business relationships (Crow\'s Foot). '
        f'Attributes are shown in the logical ERD.</FONT>>, labelloc=t, fontsize=20];',
        f'  node [shape=box, style="rounded,filled", fontname="{FONT}", fontsize=13, fontcolor=white, '
        f'margin="0.25,0.12", penwidth=0];',
        f'  edge [fontname="{FONT}", fontsize=10, fontcolor="#334155", color="#475569", penwidth=1.3, dir=both];',
    ]
    for e, c in ent.items():
        out.append(f'  "{e}" [fillcolor="{c}"];')
    for p, c, verb, pe, ce in rels:
        out.append(f'  "{p}" -> "{c}" [label="  {verb}  ", arrowtail={pe}, arrowhead={ce}];')
    out.append("}")
    return "\n".join(out)


def render(dot_src, stem):
    dot_path = os.path.join(HERE, f"{stem}.dot")
    with open(dot_path, "w") as f:
        f.write(dot_src)
    subprocess.run(["dot", "-Tsvg", dot_path, "-o", os.path.join(HERE, f"{stem}.svg")], check=True)
    subprocess.run(["dot", "-Tpng", "-Gdpi=170", dot_path, "-o", os.path.join(HERE, f"{stem}.png")], check=True)
    print("wrote", stem)


if __name__ == "__main__":
    t, p, u, f = load()
    render(logical(t, p, u, f), "erd_logical")
    render(conceptual(), "erd_conceptual")
