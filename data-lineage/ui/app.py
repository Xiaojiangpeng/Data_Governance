"""
app.py — Data Governance Platform
Tabs: Lineage Graph, STTM, Impact Analysis,
      Data Dictionary, PII Detection, Data Quality,
      Ownership & Stewardship, Audit Trail
"""

import streamlit as st
import json
import os
import sys
import pandas as pd
from anthropic import Anthropic

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from src.sql_parser import parse_sql_object, parse_sql_file
from src.lineage_graph import build_graph, get_impact_analysis, get_graph_data_for_viz

client = Anthropic()

st.set_page_config(page_title="Data Governance Platform", page_icon="🏛️", layout="wide")
st.title("🏛️ Data Governance Platform")
st.caption("AdventureWorks · Landing → Staging → Presentation · Powered by Claude AI · Robert Peng")

LAYER_ORDER = {
    "01_oltp_source_tables.sql":    "⚪ OLTP Source",
    "02_staging_dims.sql":          "🟣 Staging Dims (SCD2)",
    "03_layer1_landing.sql":        "🟡 Landing",
    "04_layer2_staging_facts.sql":  "🟠 Staging Facts",
    "05_layer3_presentation.sql":   "🔵 Presentation",
}

STEWARDS = ["Steward1 - Alice Martin", "Steward2 - Bob Chen", "Unassigned"]
BIZ_OWNERS = ["BusinessOwner1 - Sarah Johnson (Sales)", "BusinessOwner2 - Mike Peters (Operations)", "Unassigned"]
DOMAINS = ["Sales", "Production", "Finance", "HR", "Shared", "Unassigned"]

PII_KEYWORDS = [
    "customer", "person", "name", "email", "phone", "address", "contact",
    "birth", "gender", "ssn", "passport", "license", "salary", "credit",
    "account", "owner", "employee", "manager"
]

DQ_RULES_DIMS = {
    "Product_Dim": [
        {"rule": "No duplicate active records", "check": "COUNT(*) WHERE BT_is_current=1 GROUP BY INT_product_id HAVING COUNT(*)>1 = 0", "severity": "Critical"},
        {"rule": "Effective date must be before expiry date", "check": "DT_effective_date < DT_expiry_date", "severity": "Critical"},
        {"rule": "List price must be >= standard cost", "check": "DC_list_price >= DC_standard_cost", "severity": "High"},
        {"rule": "Product name must not be null", "check": "NM_product_name IS NOT NULL", "severity": "Critical"},
        {"rule": "Standard cost must be > 0", "check": "DC_standard_cost > 0", "severity": "High"},
    ],
    "ProductCategory_Dim": [
        {"rule": "No duplicate active subcategories", "check": "COUNT(*) WHERE BT_is_current=1 GROUP BY INT_subcategory_id HAVING COUNT(*)>1 = 0", "severity": "Critical"},
        {"rule": "Category name must not be null", "check": "NM_category_name IS NOT NULL", "severity": "Critical"},
        {"rule": "Subcategory name must not be null", "check": "NM_subcategory_name IS NOT NULL", "severity": "Critical"},
        {"rule": "Category ID must be valid", "check": "INT_category_id > 0", "severity": "High"},
    ],
    "Territory_Dim": [
        {"rule": "No duplicate active territories", "check": "COUNT(*) WHERE BT_is_current=1 GROUP BY INT_territory_id HAVING COUNT(*)>1 = 0", "severity": "Critical"},
        {"rule": "Territory name must not be null", "check": "NM_territory_name IS NOT NULL", "severity": "Critical"},
        {"rule": "Country region code must be 2-3 chars", "check": "LEN(NM_country_region_code) BETWEEN 2 AND 3", "severity": "High"},
        {"rule": "Sales YTD must be >= 0", "check": "DC_sales_ytd >= 0", "severity": "Medium"},
    ],
}

# ── Sidebar ───────────────────────────────────────────────────
with st.sidebar:
    st.header("⚙️ Options")
    mode = st.radio("Input Mode", ["📂 Load Scripts", "✏️ Paste SQL"], index=0)
    st.divider()
    st.markdown("**ETL Architecture**")
    st.markdown("⚪ **OLTP** — source system")
    st.markdown("🟣 **Staging Dims** — SCD2")
    st.markdown("🟡 **Landing** — raw extract")
    st.markdown("🟠 **Staging Facts** — cleansed")
    st.markdown("🔵 **Presentation** — aggregated")
    st.divider()
    st.markdown("**Stack:** Claude · NetworkX · Streamlit")

# ── Tabs ─────────────────────────────────────────────────────
tab1, tab2, tab3, tab4, tab5, tab6, tab7, tab8 = st.tabs([
    "📊 Lineage Graph",
    "📋 STTM",
    "🔍 Impact Analysis",
    "📖 Data Dictionary",
    "🔒 PII Detection",
    "✅ Data Quality",
    "👤 Ownership",
    "⏱️ Audit Trail"
])

# ── Input ─────────────────────────────────────────────────────
script_dir = os.path.join(os.path.dirname(__file__), "..", "data", "sql_scripts")

if mode == "📂 Load Scripts":
    available = sorted([f for f in os.listdir(script_dir) if f.endswith(".sql")])
    selected_files = st.multiselect(
        "Select SQL script files to analyze:",
        options=available,
        format_func=lambda f: LAYER_ORDER.get(f, f),
        default=available
    )
    if st.button("🚀 Extract Lineage", type="primary"):
        if not selected_files:
            st.warning("Please select at least one SQL file.")
        else:
            all_lineage = []
            progress = st.progress(0)
            for i, fname in enumerate(selected_files):
                fpath = os.path.join(script_dir, fname)
                with st.spinner(f"Parsing {LAYER_ORDER.get(fname, fname)}..."):
                    results = parse_sql_file(fpath)
                    for r in results:
                        r["_layer"] = LAYER_ORDER.get(fname, "Unknown")
                    all_lineage.extend(results)
                progress.progress((i + 1) / len(selected_files))
            st.session_state["lineage_data"] = all_lineage
            st.success(f"✅ Extracted lineage from {len(all_lineage)} SQL objects")
else:
    sql_input = st.text_area("Paste SQL:", height=200)
    if st.button("🚀 Extract Lineage", type="primary"):
        if sql_input.strip():
            with st.spinner("Analyzing with Claude..."):
                result = parse_sql_object(sql_input)
                result["_layer"] = "Custom"
                st.session_state["lineage_data"] = [result]
            st.success("✅ Done!")

# ── Helper ────────────────────────────────────────────────────
def get_valid():
    return [o for o in st.session_state.get("lineage_data", []) if "error" not in o]

def no_data():
    st.info("👆 Select scripts and click Extract Lineage to begin.")

# ══════════════════════════════════════════════════════════════
# TAB 1: LINEAGE GRAPH
# ══════════════════════════════════════════════════════════════
with tab1:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        G = build_graph(valid)
        viz = get_graph_data_for_viz(G)

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Total Objects", viz["stats"]["total_nodes"])
        c2.metric("Tables", viz["stats"]["tables"])
        c3.metric("Views", viz["stats"]["views"])
        c4.metric("Procedures", viz["stats"]["procedures"])

        st.markdown("**Legend:** 🟢 Table &nbsp; 🔵 View &nbsp; 🟡 Procedure")
        st.divider()

        for obj in valid:
            obj_name = obj.get("object_name", "Unknown")
            obj_type = obj.get("object_type", "")
            layer = obj.get("_layer", "")
            icon = "🔵" if obj_type == "VIEW" else "🟡"

            with st.expander(f"{icon} {layer} · **{obj_name}**"):
                st.markdown(f"**Description:** {obj.get('description', 'N/A')}")
                ca, cb = st.columns(2)
                with ca:
                    st.markdown("**📥 Source Tables:**")
                    for src in obj.get("source_tables", []):
                        st.markdown(f"- 🟢 `{src.get('schema','')}.{src.get('table','')}`"
                                    + (f" *(as {src['alias']})*" if src.get("alias") else ""))
                    if not obj.get("source_tables"):
                        st.markdown("- *(none)*")
                with cb:
                    st.markdown("**📤 Target Tables:**")
                    write_tgts = [t for t in obj.get("target_tables", [])
                                  if t.get("operation", "SELECT") != "SELECT"]
                    if write_tgts:
                        for t in write_tgts:
                            st.markdown(f"- 🔴 `{t.get('schema','')}.{t.get('table','')}` **({t.get('operation','WRITE')})**")
                    else:
                        st.markdown("- *(read-only)*")
                if obj.get("business_logic"):
                    st.info(f"💡 {obj['business_logic']}")

# ══════════════════════════════════════════════════════════════
# TAB 2: STTM
# ══════════════════════════════════════════════════════════════
with tab2:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        st.subheader("📋 Source-to-Target Mapping (STTM)")
        rows = []
        for obj in valid:
            obj_name = obj.get("object_name", "Unknown")
            obj_type = obj.get("object_type", "")
            layer = obj.get("_layer", "")
            sources = obj.get("source_tables", [])
            targets = obj.get("target_tables", [])
            cols = obj.get("columns_lineage", [])
            filters = "; ".join(obj.get("filters", []))
            biz = obj.get("business_logic", "")
            src_str = "; ".join([f"{s.get('schema','')}.{s.get('table','')}" for s in sources])
            write_tgts = [t for t in targets if t.get("operation", "SELECT") != "SELECT"]
            tgt_str = "; ".join([f"{t.get('schema','')}.{t.get('table','')}" for t in write_tgts]) \
                      if write_tgts else f"→ {obj_name}"

            if cols:
                for col in cols:
                    tgt_tbl = f"{write_tgts[0].get('schema','')}.{write_tgts[0].get('table','')}" \
                              if write_tgts else obj_name
                    rows.append({
                        "Layer": layer, "ETL Object": obj_name, "Object Type": obj_type,
                        "Source Table(s)": src_str,
                        "Source Column / Expression": col.get("source_expression", ""),
                        "Transformation Rule": col.get("transformation", ""),
                        "Target Table": tgt_tbl,
                        "Target Column": col.get("target_column", ""),
                        "Filter / Where": filters, "Business Logic": biz
                    })
            else:
                rows.append({
                    "Layer": layer, "ETL Object": obj_name, "Object Type": obj_type,
                    "Source Table(s)": src_str,
                    "Source Column / Expression": "*(table level)*",
                    "Transformation Rule": biz, "Target Table": tgt_str,
                    "Target Column": "*(table level)*",
                    "Filter / Where": filters, "Business Logic": biz
                })

        if rows:
            df = pd.DataFrame(rows)
            c1, c2 = st.columns(2)
            with c1:
                lf = st.multiselect("Filter by Layer:", df["Layer"].unique().tolist(),
                                    default=df["Layer"].unique().tolist())
            with c2:
                of = st.multiselect("Filter by Object:", df["ETL Object"].unique().tolist(), default=[])
            fdf = df[df["Layer"].isin(lf)]
            if of:
                fdf = fdf[fdf["ETL Object"].isin(of)]
            st.dataframe(fdf, use_container_width=True, height=450)
            st.download_button("⬇️ Download STTM CSV",
                data=fdf.to_csv(index=False).encode("utf-8"),
                file_name="STTM_AdventureWorks.csv", mime="text/csv")

# ══════════════════════════════════════════════════════════════
# TAB 3: IMPACT ANALYSIS
# ══════════════════════════════════════════════════════════════
with tab3:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        G = build_graph(valid)
        selected = st.selectbox("Select any table, view, or procedure:", sorted(G.nodes()))
        if st.button("🔍 Run Impact Analysis") and selected:
            impact = get_impact_analysis(G, selected)
            st.info(impact.get("impact_summary", ""))
            c1, c2 = st.columns(2)
            with c1:
                st.markdown("### 🎯 Direct Dependents")
                if impact["direct_dependents"]:
                    for d in impact["direct_dependents"]:
                        icon = "🔵" if d["type"] == "VIEW" else "🟡"
                        st.markdown(f"{icon} **{d['name']}**")
                else:
                    st.success("No direct dependents — safe to modify!")
            with c2:
                st.markdown("### ⬆️ Upstream Dependencies")
                if impact["upstream_dependencies"]:
                    for d in impact["upstream_dependencies"]:
                        icon = "🟢" if d["type"] == "TABLE" else "🔵"
                        st.markdown(f"{icon} **{d['name']}**")
                else:
                    st.info("No upstream dependencies.")
            if impact["all_downstream"]:
                st.markdown("### 🌊 Full Downstream Cascade")
                cols = st.columns(3)
                for i, o in enumerate(impact["all_downstream"]):
                    icon = "🔵" if o["type"] == "VIEW" else "🟡" if o["type"] == "STORED_PROCEDURE" else "🟢"
                    cols[i % 3].markdown(f"{icon} `{o['name']}`")

# ══════════════════════════════════════════════════════════════
# TAB 4: DATA DICTIONARY
# ══════════════════════════════════════════════════════════════
with tab4:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        st.subheader("📖 Data Dictionary")
        st.caption("Auto-generated by Claude AI · Editable · Exportable")

        if "data_dict" not in st.session_state:
            st.session_state["data_dict"] = {}

        # Auto-generate button
        if st.button("🤖 Auto-Generate Definitions", type="primary"):
            progress = st.progress(0)
            for i, obj in enumerate(valid):
                obj_name = obj.get("object_name", "Unknown")
                obj_type = obj.get("object_type", "")
                cols = obj.get("columns_lineage", [])
                src_tables = obj.get("source_tables", [])
                biz_logic = obj.get("business_logic", "")

                prompt = f"""You are a data governance expert. Generate a data dictionary for this SQL object.

Object: {obj_name}
Type: {obj_type}
Source Tables: {[f"{s['schema']}.{s['table']}" for s in src_tables]}
Business Logic: {biz_logic}
Columns: {[c.get('target_column') for c in cols[:10]]}

Return ONLY a JSON object:
{{
  "object_description": "clear business description in 1-2 sentences",
  "business_purpose": "why this object exists and who uses it",
  "data_domain": "Sales|Production|Finance|HR|Shared",
  "update_frequency": "Daily|Weekly|Monthly|Real-time",
  "columns": [
    {{
      "column_name": "col",
      "business_definition": "what this column means in business terms",
      "data_type": "type",
      "example_values": "example1, example2"
    }}
  ]
}}"""

                try:
                    response = client.messages.create(
                        model="claude-sonnet-4-20250514",
                        max_tokens=1500,
                        messages=[{"role": "user", "content": prompt}]
                    )
                    import re
                    raw = response.content[0].text.strip()
                    raw = re.sub(r"```json|```", "", raw).strip()
                    json_match = re.search(r'\{.*\}', raw, re.DOTALL)
                    if json_match:
                        definition = json.loads(json_match.group(0))
                        st.session_state["data_dict"][obj_name] = definition
                except Exception as e:
                    st.session_state["data_dict"][obj_name] = {"error": str(e)}

                progress.progress((i + 1) / len(valid))
            st.success("✅ Data dictionary generated!")

        # Display and edit
        if st.session_state.get("data_dict"):
            dd = st.session_state["data_dict"]

            obj_select = st.selectbox("Select object:", list(dd.keys()))
            if obj_select and obj_select in dd:
                entry = dd[obj_select]
                if "error" in entry:
                    st.error(f"Generation failed: {entry['error']}")
                else:
                    st.divider()
                    c1, c2 = st.columns(2)
                    with c1:
                        new_desc = st.text_area("Business Description",
                            value=entry.get("object_description", ""), height=80, key=f"desc_{obj_select}")
                        new_purpose = st.text_area("Business Purpose",
                            value=entry.get("business_purpose", ""), height=80, key=f"purpose_{obj_select}")
                    with c2:
                        new_domain = st.selectbox("Data Domain",
                            DOMAINS, index=DOMAINS.index(entry.get("data_domain", "Unassigned"))
                            if entry.get("data_domain") in DOMAINS else 0, key=f"domain_{obj_select}")
                        new_freq = st.selectbox("Update Frequency",
                            ["Daily", "Weekly", "Monthly", "Real-time"],
                            index=["Daily", "Weekly", "Monthly", "Real-time"].index(
                                entry.get("update_frequency", "Daily"))
                            if entry.get("update_frequency") in ["Daily", "Weekly", "Monthly", "Real-time"] else 0,
                            key=f"freq_{obj_select}")

                    if st.button("💾 Save Changes", key=f"save_{obj_select}"):
                        st.session_state["data_dict"][obj_select]["object_description"] = new_desc
                        st.session_state["data_dict"][obj_select]["business_purpose"] = new_purpose
                        st.session_state["data_dict"][obj_select]["data_domain"] = new_domain
                        st.session_state["data_dict"][obj_select]["update_frequency"] = new_freq
                        st.success("Saved!")

                    if entry.get("columns"):
                        st.markdown("**Column Definitions:**")
                        col_df = pd.DataFrame(entry["columns"])
                        st.dataframe(col_df, use_container_width=True)

            # Export
            if dd:
                st.download_button("⬇️ Export Data Dictionary JSON",
                    data=json.dumps(dd, indent=2).encode("utf-8"),
                    file_name="DataDictionary_AdventureWorks.json", mime="application/json")

# ══════════════════════════════════════════════════════════════
# TAB 5: PII DETECTION
# ══════════════════════════════════════════════════════════════
with tab5:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        st.subheader("🔒 PII Detection")
        st.caption("Automatically flags columns that may contain personal or sensitive data")

        pii_rows = []
        for obj in valid:
            obj_name = obj.get("object_name", "Unknown")
            layer = obj.get("_layer", "")
            cols = obj.get("columns_lineage", [])
            src_tables = obj.get("source_tables", [])

            # Check column names against PII keywords
            all_cols = [c.get("target_column", "") for c in cols]
            # Also check source table names
            for col in all_cols:
                if not col or col == "*(table level)*":
                    continue
                col_lower = col.lower()
                matched_keywords = [kw for kw in PII_KEYWORDS if kw in col_lower]
                if matched_keywords:
                    risk = "🔴 High" if any(k in col_lower for k in ["ssn", "passport", "credit", "salary", "birth"]) \
                           else "🟡 Medium" if any(k in col_lower for k in ["email", "phone", "address"]) \
                           else "🟠 Low"
                    pii_rows.append({
                        "Layer": layer,
                        "Object": obj_name,
                        "Column": col,
                        "Matched Keywords": ", ".join(matched_keywords),
                        "Risk Level": risk,
                        "Recommended Action": "Mask/Encrypt" if "High" in risk else
                                             "Pseudonymize" if "Medium" in risk else "Monitor",
                        "GDPR Article": "Art. 9" if "High" in risk else "Art. 6",
                        "Confirmed PII": "✅ Confirm" if matched_keywords else ""
                    })

        if pii_rows:
            pii_df = pd.DataFrame(pii_rows)

            # Summary metrics
            c1, c2, c3 = st.columns(3)
            c1.metric("Total PII Columns", len(pii_df))
            c2.metric("High Risk", len(pii_df[pii_df["Risk Level"].str.contains("High")]))
            c3.metric("Objects Affected", pii_df["Object"].nunique())

            st.divider()

            risk_filter = st.multiselect("Filter by Risk:",
                ["🔴 High", "🟡 Medium", "🟠 Low"],
                default=["🔴 High", "🟡 Medium", "🟠 Low"])
            filtered_pii = pii_df[pii_df["Risk Level"].isin(risk_filter)]
            st.dataframe(filtered_pii, use_container_width=True, height=400)

            st.download_button("⬇️ Export PII Report CSV",
                data=filtered_pii.to_csv(index=False).encode("utf-8"),
                file_name="PII_Report_AdventureWorks.csv", mime="text/csv")
        else:
            st.success("✅ No PII columns detected in extracted lineage.")
            st.info("Note: PII detection is based on column name patterns. "
                    "Run lineage extraction first to populate column data.")

# ══════════════════════════════════════════════════════════════
# TAB 6: DATA QUALITY RULES
# ══════════════════════════════════════════════════════════════
with tab6:
    st.subheader("✅ Data Quality Rules")
    st.caption("Focused on Dimension tables — SCD2 integrity, uniqueness, and business rules")

    dim_select = st.selectbox("Select Dimension Table:", list(DQ_RULES_DIMS.keys()))

    if dim_select:
        rules = DQ_RULES_DIMS[dim_select]

        # Summary
        critical = sum(1 for r in rules if r["severity"] == "Critical")
        high = sum(1 for r in rules if r["severity"] == "High")
        medium = sum(1 for r in rules if r["severity"] == "Medium")

        c1, c2, c3, c4 = st.columns(4)
        c1.metric("Total Rules", len(rules))
        c2.metric("🔴 Critical", critical)
        c3.metric("🟠 High", high)
        c4.metric("🟡 Medium", medium)

        st.divider()

        # Display rules with status toggle
        if "dq_status" not in st.session_state:
            st.session_state["dq_status"] = {}

        for i, rule in enumerate(rules):
            key = f"{dim_select}_{i}"
            sev_icon = "🔴" if rule["severity"] == "Critical" else \
                       "🟠" if rule["severity"] == "High" else "🟡"

            with st.expander(f"{sev_icon} [{rule['severity']}] {rule['rule']}"):
                st.markdown(f"**SQL Check:**")
                st.code(rule["check"], language="sql")

                col_a, col_b, col_c = st.columns(3)
                with col_a:
                    status = st.selectbox("Status:",
                        ["⬜ Not Tested", "✅ Passed", "❌ Failed", "⚠️ Warning"],
                        key=f"status_{key}")
                with col_b:
                    st.markdown(f"**Severity:** {rule['severity']}")
                with col_c:
                    st.markdown(f"**Table:** `staging.{dim_select}`")

                notes = st.text_input("Notes / Resolution:", key=f"notes_{key}",
                                      placeholder="Add notes or resolution steps...")

        st.divider()

        # Add custom rule
        st.markdown("**➕ Add Custom Rule:**")
        ca, cb, cc = st.columns(3)
        with ca:
            new_rule = st.text_input("Rule Description:", placeholder="e.g. Price must be positive")
        with cb:
            new_check = st.text_input("SQL Check:", placeholder="e.g. DC_list_price > 0")
        with cc:
            new_sev = st.selectbox("Severity:", ["Critical", "High", "Medium", "Low"])

        if st.button("➕ Add Rule"):
            if new_rule and new_check:
                DQ_RULES_DIMS[dim_select].append({
                    "rule": new_rule, "check": new_check, "severity": new_sev
                })
                st.success(f"Rule added to {dim_select}!")
                st.rerun()

        # Export rules
        rules_df = pd.DataFrame(rules)
        rules_df["table"] = f"staging.{dim_select}"
        st.download_button("⬇️ Export DQ Rules CSV",
            data=rules_df.to_csv(index=False).encode("utf-8"),
            file_name=f"DQ_Rules_{dim_select}.csv", mime="text/csv")

# ══════════════════════════════════════════════════════════════
# TAB 7: OWNERSHIP & STEWARDSHIP
# ══════════════════════════════════════════════════════════════
with tab7:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        st.subheader("👤 Data Ownership & Stewardship")
        st.caption("Assign data owners, stewards, and domains to each object")

        if "ownership" not in st.session_state:
            # Initialize with defaults
            st.session_state["ownership"] = {
                obj.get("object_name", "Unknown"): {
                    "steward": "Unassigned",
                    "business_owner": "Unassigned",
                    "domain": "Unassigned",
                    "classification": "Internal",
                    "retention_years": 7,
                    "notes": ""
                } for obj in valid
            }

        ownership = st.session_state["ownership"]

        # Bulk assign
        with st.expander("⚡ Bulk Assign by Layer"):
            bc1, bc2, bc3 = st.columns(3)
            with bc1:
                bulk_layer = st.selectbox("Layer:", list(set(o.get("_layer","") for o in valid)))
            with bc2:
                bulk_steward = st.selectbox("Assign Steward:", STEWARDS, key="bulk_st")
            with bc3:
                bulk_owner = st.selectbox("Assign Owner:", BIZ_OWNERS, key="bulk_ow")

            if st.button("Apply Bulk Assignment"):
                for obj in valid:
                    if obj.get("_layer") == bulk_layer:
                        name = obj.get("object_name", "Unknown")
                        ownership[name]["steward"] = bulk_steward
                        ownership[name]["business_owner"] = bulk_owner
                st.success(f"Applied to all {bulk_layer} objects!")

        st.divider()

        # Individual assignment
        obj_names = [o.get("object_name", "Unknown") for o in valid]
        sel_obj = st.selectbox("Select Object:", obj_names)

        if sel_obj and sel_obj in ownership:
            entry = ownership[sel_obj]
            layer = next((o.get("_layer","") for o in valid
                         if o.get("object_name") == sel_obj), "")
            st.markdown(f"**Layer:** {layer}")
            st.divider()

            c1, c2 = st.columns(2)
            with c1:
                entry["steward"] = st.selectbox("Data Steward:",
                    STEWARDS, index=STEWARDS.index(entry["steward"])
                    if entry["steward"] in STEWARDS else 0, key=f"st_{sel_obj}")
                entry["domain"] = st.selectbox("Data Domain:",
                    DOMAINS, index=DOMAINS.index(entry["domain"])
                    if entry["domain"] in DOMAINS else 0, key=f"dm_{sel_obj}")
                entry["classification"] = st.selectbox("Data Classification:",
                    ["Public", "Internal", "Confidential", "Restricted"],
                    index=["Public", "Internal", "Confidential", "Restricted"].index(
                        entry.get("classification", "Internal")), key=f"cl_{sel_obj}")
            with c2:
                entry["business_owner"] = st.selectbox("Business Owner:",
                    BIZ_OWNERS, index=BIZ_OWNERS.index(entry["business_owner"])
                    if entry["business_owner"] in BIZ_OWNERS else 0, key=f"ow_{sel_obj}")
                entry["retention_years"] = st.number_input("Retention Period (years):",
                    min_value=1, max_value=99, value=entry.get("retention_years", 7),
                    key=f"ret_{sel_obj}")
                entry["notes"] = st.text_area("Notes:",
                    value=entry.get("notes", ""), height=80, key=f"nt_{sel_obj}")

        st.divider()

        # Summary table
        st.markdown("**📊 Ownership Summary:**")
        own_rows = []
        for obj in valid:
            name = obj.get("object_name", "Unknown")
            layer = obj.get("_layer", "")
            o = ownership.get(name, {})
            own_rows.append({
                "Layer": layer, "Object": name,
                "Steward": o.get("steward", "Unassigned"),
                "Business Owner": o.get("business_owner", "Unassigned"),
                "Domain": o.get("domain", "Unassigned"),
                "Classification": o.get("classification", "Internal"),
                "Retention (yrs)": o.get("retention_years", 7)
            })

        own_df = pd.DataFrame(own_rows)
        unassigned = len(own_df[own_df["Steward"] == "Unassigned"])
        st.metric("Unassigned Objects", unassigned,
                  delta=f"{len(own_df)-unassigned} assigned", delta_color="normal")
        st.dataframe(own_df, use_container_width=True, height=300)

        st.download_button("⬇️ Export Ownership CSV",
            data=own_df.to_csv(index=False).encode("utf-8"),
            file_name="Ownership_AdventureWorks.csv", mime="text/csv")

# ══════════════════════════════════════════════════════════════
# TAB 8: AUDIT TRAIL
# ══════════════════════════════════════════════════════════════
with tab8:
    if not st.session_state.get("lineage_data"):
        no_data()
    else:
        valid = get_valid()
        st.subheader("⏱️ Audit Trail & Data Freshness")
        st.caption("Tracks ETL metadata columns across all layers")

        # ETL metadata columns per layer
        AUDIT_COLS = {
            "⚪ OLTP Source":       ["ModifiedDate"],
            "🟣 Staging Dims (SCD2)": ["DT_effective_date", "DT_expiry_date", "BT_is_current",
                                        "NM_checksum_val", "DT_load_timestamp", "NM_batch_id"],
            "🟡 Landing":           ["NM_source_system", "DT_load_timestamp", "NM_batch_id", "DT_modified_date"],
            "🟠 Staging Facts":     ["BT_is_valid", "NM_validation_notes", "DT_load_timestamp", "NM_batch_id"],
            "🔵 Presentation":      ["DT_load_timestamp", "NM_batch_id"],
        }

        # Audit column coverage
        audit_rows = []
        for obj in valid:
            obj_name = obj.get("object_name", "Unknown")
            layer = obj.get("_layer", "")
            cols = [c.get("target_column", "") for c in obj.get("columns_lineage", [])]
            expected = AUDIT_COLS.get(layer, [])
            present = [c for c in expected if any(c.lower() in col.lower() for col in cols)]
            missing = [c for c in expected if c not in present]
            coverage = f"{len(present)}/{len(expected)}" if expected else "N/A"

            audit_rows.append({
                "Layer": layer,
                "Object": obj_name,
                "Expected Audit Cols": len(expected),
                "Present": len(present),
                "Coverage": coverage,
                "Missing Columns": ", ".join(missing) if missing else "✅ Complete",
                "Has Batch ID": "✅" if any("batch" in c.lower() for c in cols) else "❌",
                "Has Load Timestamp": "✅" if any("timestamp" in c.lower() or "load" in c.lower()
                                                   for c in cols) else "❌",
                "Has Valid Flag": "✅" if any("valid" in c.lower() for c in cols) else "—",
                "Has SCD2 Tracking": "✅" if any("current" in c.lower() or "expiry" in c.lower()
                                                   for c in cols) else "—",
            })

        audit_df = pd.DataFrame(audit_rows)

        # Metrics
        c1, c2, c3 = st.columns(3)
        complete = len(audit_df[audit_df["Missing Columns"] == "✅ Complete"])
        c1.metric("Objects with Full Coverage", f"{complete}/{len(audit_df)}")
        c2.metric("With Batch ID", audit_df["Has Batch ID"].value_counts().get("✅", 0))
        c3.metric("With Load Timestamp", audit_df["Has Load Timestamp"].value_counts().get("✅", 0))

        st.divider()

        # ETL Pipeline metadata flow
        st.markdown("**🔄 ETL Metadata Flow Across Layers:**")
        flow_data = {
            "Metadata Column": ["NM_batch_id", "DT_load_timestamp", "NM_source_system",
                                "BT_is_valid", "NM_checksum_val", "BT_is_current"],
            "OLTP":       ["—", "ModifiedDate", "—", "—", "—", "—"],
            "Landing":    ["✅", "✅", "✅", "—", "—", "—"],
            "Staging Dims":["✅", "✅", "—", "—", "✅", "✅"],
            "Staging Facts":["✅", "✅", "—", "✅", "—", "—"],
            "Presentation":["✅", "✅", "—", "—", "—", "—"],
        }
        st.dataframe(pd.DataFrame(flow_data), use_container_width=True)

        st.divider()
        st.markdown("**📋 Object-Level Audit Coverage:**")
        st.dataframe(audit_df, use_container_width=True, height=350)

        st.download_button("⬇️ Export Audit Report CSV",
            data=audit_df.to_csv(index=False).encode("utf-8"),
            file_name="AuditTrail_AdventureWorks.csv", mime="text/csv")
