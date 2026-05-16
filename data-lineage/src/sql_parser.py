"""
sql_parser.py
Parses SQL stored procedures and views using Claude API
to extract data lineage (source tables -> transformations -> targets).
"""

import os
import json
import re
from anthropic import Anthropic

client = Anthropic()

LINEAGE_PROMPT_TEMPLATE = """You are a data lineage expert. Analyze the following SQL code and extract complete data lineage.

Return ONLY a valid JSON object with this exact structure:
{{
  "object_name": "schema.object_name",
  "object_type": "VIEW|STORED_PROCEDURE",
  "description": "brief description of what this object does",
  "source_tables": [
    {{"schema": "schema_name", "table": "table_name", "alias": "alias_if_any"}}
  ],
  "target_tables": [
    {{"schema": "schema_name", "table": "table_name", "operation": "INSERT|UPDATE|DELETE|SELECT"}}
  ],
  "columns_lineage": [
    {{
      "target_column": "column_name",
      "source_expression": "source table.column or expression",
      "transformation": "description of any transformation applied"
    }}
  ],
  "joins": [
    {{
      "left_table": "schema.table",
      "right_table": "schema.table",
      "join_type": "INNER|LEFT|RIGHT",
      "condition": "join condition"
    }}
  ],
  "filters": ["list of WHERE conditions as strings"],
  "business_logic": "description of key business rules embedded in this object"
}}

SQL to analyze:
{sql_code}
"""


def parse_sql_object(sql_code: str) -> dict:
    """
    Send SQL to Claude API and extract lineage as structured JSON.
    """
    response = client.messages.create(
        model="claude-sonnet-4-20250514",
        max_tokens=2000,
        messages=[
            {
                "role": "user",
                "content": LINEAGE_PROMPT_TEMPLATE.format(sql_code=sql_code)
            }
        ]
    )

    raw = response.content[0].text.strip()

    # Strip markdown fences if present
    raw = re.sub(r"```json|```", "", raw).strip()

    try:
        return json.loads(raw)
    except json.JSONDecodeError as e:
        return {"error": str(e), "raw_response": raw}


def split_sql_objects(sql_file_content: str) -> list[str]:
    """
    Split a SQL file into individual objects (views, procedures).
    Splits on GO statements.
    """
    objects = []
    current = []

    for line in sql_file_content.splitlines():
        if line.strip().upper() == "GO":
            block = "\n".join(current).strip()
            if block and (
                "CREATE VIEW" in block.upper() or
                "CREATE PROCEDURE" in block.upper() or
                "ALTER PROCEDURE" in block.upper()
            ):
                objects.append(block)
            current = []
        else:
            current.append(line)

    return objects


def parse_sql_file(filepath: str) -> list[dict]:
    """
    Parse all SQL objects in a file and return list of lineage dicts.
    """
    with open(filepath, "r") as f:
        content = f.read()

    sql_objects = split_sql_objects(content)
    results = []

    print(f"Found {len(sql_objects)} SQL objects in {filepath}")

    for i, sql_obj in enumerate(sql_objects):
        # Extract object name for logging
        name_match = re.search(
            r"CREATE\s+(?:VIEW|PROCEDURE)\s+(\[?\w+\]?\.\[?\w+\]?)",
            sql_obj, re.IGNORECASE
        )
        name = name_match.group(1) if name_match else f"Object_{i+1}"
        print(f"  Parsing: {name}")

        lineage = parse_sql_object(sql_obj)
        lineage["_source_file"] = filepath
        lineage["_raw_sql"] = sql_obj
        results.append(lineage)

    return results


if __name__ == "__main__":
    # Quick test
    import sys
    filepath = sys.argv[1] if len(sys.argv) > 1 else "data/sql_scripts/sales_procedures.sql"

    results = parse_sql_file(filepath)

    output_path = filepath.replace(".sql", "_lineage.json")
    with open(output_path, "w") as f:
        json.dump(results, f, indent=2)

    print(f"\nLineage saved to: {output_path}")
    print(f"Total objects parsed: {len(results)}")
