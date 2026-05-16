# 🔗 Data Lineage Generator

AI-powered SQL data lineage extraction and impact analysis tool built on AdventureWorks2022.

## What it does

- **Parses SQL** stored procedures and views using Claude AI
- **Extracts lineage** — source tables → transformations → target tables
- **Builds a lineage graph** using NetworkX
- **Impact analysis** — select any table and see what breaks if it changes
- **Column-level lineage** — traces individual columns through transformations

## Tech Stack

| Layer | Technology |
|-------|-----------|
| AI Parsing | Claude Sonnet (Anthropic) |
| Graph Engine | NetworkX |
| UI | Streamlit |
| SQL Source | AdventureWorks2022 (Sales + Production) |
| Language | Python 3.11+ |

## Project Structure

```
data-lineage/
├── data/
│   └── sql_scripts/
│       ├── sales_procedures.sql        # Sales schema views + procedures
│       └── production_procedures.sql   # Production schema views + procedures
├── src/
│   ├── sql_parser.py                   # Claude API lineage extraction
│   └── lineage_graph.py               # NetworkX graph builder + impact analysis
├── ui/
│   └── app.py                          # Streamlit UI
├── requirements.txt
└── README.md
```

## Run Locally

```bash
# Install dependencies
pip install -r requirements.txt

# Set your Anthropic API key
export ANTHROPIC_API_KEY=sk-ant-...

# Run the app
streamlit run ui/app.py
```

## Key Features

### Lineage Extraction
Paste any SQL or load from sample scripts. Claude analyzes the SQL and returns:
- Source tables with aliases
- Target tables with DML operations (INSERT/UPDATE/DELETE)
- Column-level lineage with transformation descriptions
- Business logic summary

### Impact Analysis
Select any table from the lineage graph to see:
- **Direct dependents** — views and procedures that read from it
- **All downstream objects** — full cascade of affected objects
- **Upstream dependencies** — what feeds into this table

### AdventureWorks Coverage
- `Sales.SalesOrderHeader` → `Sales.SalesOrderDetail` → `Sales.vSalesOrderDetail`
- `Production.Product` → `Production.ProductInventory` → `Production.vProductInventory`
- `Production.WorkOrder` → `Production.WorkOrderRouting`
- `Sales.SalesPerson` → `Sales.SalesPersonQuotaHistory`

## Portfolio Context

Built as **Project 4** in an AI portfolio targeting Data Architect and Data Governance roles.
Demonstrates applied LLM use for enterprise metadata management — a key capability
in modern data governance platforms (Collibra, Alation, Microsoft Purview).

**Author:** Robert (Xiaojiang) Peng · Senior Manager, Pfizer Montreal
