"""
lineage_graph.py
Builds a directed lineage graph from parsed SQL lineage data.
Supports impact analysis: "if table X changes, what is affected?"
"""

import json
import networkx as nx
from collections import defaultdict


def build_graph(lineage_data: list[dict]) -> nx.DiGraph:
    """
    Build a directed graph from lineage data.
    Nodes = tables/views/procedures
    Edges = data flow (source -> target)
    """
    G = nx.DiGraph()

    for obj in lineage_data:
        if "error" in obj:
            continue

        obj_name = obj.get("object_name", "unknown")
        obj_type = obj.get("object_type", "UNKNOWN")
        description = obj.get("description", "")

        # Add the SQL object as a node
        G.add_node(
            obj_name,
            node_type=obj_type,
            description=description,
            color="#4A90D9" if obj_type == "VIEW" else "#E8A838"
        )

        # Add source table nodes and edges
        for src in obj.get("source_tables", []):
            src_name = f"{src['schema']}.{src['table']}"
            if not G.has_node(src_name):
                G.add_node(src_name, node_type="TABLE", color="#2ECC71")
            G.add_edge(src_name, obj_name, relationship="reads_from")

        # Add target table nodes and edges
        for tgt in obj.get("target_tables", []):
            if tgt.get("operation", "SELECT") == "SELECT":
                continue  # SELECT targets are the object itself
            tgt_name = f"{tgt['schema']}.{tgt['table']}"
            if not G.has_node(tgt_name):
                G.add_node(tgt_name, node_type="TABLE", color="#2ECC71")
            G.add_edge(
                obj_name, tgt_name,
                relationship=tgt.get("operation", "writes_to")
            )

    return G


def get_impact_analysis(G: nx.DiGraph, table_name: str) -> dict:
    """
    Given a table name, find all downstream objects that would be
    impacted if this table changes.
    """
    if table_name not in G:
        # Try partial match
        matches = [n for n in G.nodes if table_name.lower() in n.lower()]
        if not matches:
            return {"error": f"Table '{table_name}' not found in lineage graph"}
        table_name = matches[0]

    # Get all descendants (downstream objects)
    downstream = nx.descendants(G, table_name)

    # Get all ancestors (upstream dependencies)
    upstream = nx.ancestors(G, table_name)

    # Categorize by type
    impact = {
        "table": table_name,
        "direct_dependents": [],
        "all_downstream": [],
        "upstream_dependencies": [],
        "impact_summary": ""
    }

    for node in G.successors(table_name):
        node_data = G.nodes[node]
        impact["direct_dependents"].append({
            "name": node,
            "type": node_data.get("node_type", "UNKNOWN"),
            "description": node_data.get("description", "")
        })

    for node in downstream:
        node_data = G.nodes[node]
        impact["all_downstream"].append({
            "name": node,
            "type": node_data.get("node_type", "UNKNOWN")
        })

    for node in upstream:
        node_data = G.nodes[node]
        impact["upstream_dependencies"].append({
            "name": node,
            "type": node_data.get("node_type", "UNKNOWN")
        })

    impact["impact_summary"] = (
        f"Changing '{table_name}' directly affects "
        f"{len(impact['direct_dependents'])} objects and "
        f"{len(impact['all_downstream'])} total downstream objects."
    )

    return impact


def get_graph_data_for_viz(G: nx.DiGraph) -> dict:
    """
    Convert NetworkX graph to format suitable for visualization.
    Returns nodes and edges as lists of dicts.
    """
    nodes = []
    for node_id, data in G.nodes(data=True):
        nodes.append({
            "id": node_id,
            "label": node_id.split(".")[-1],  # Short name for display
            "full_name": node_id,
            "type": data.get("node_type", "UNKNOWN"),
            "color": data.get("color", "#999999"),
            "description": data.get("description", "")
        })

    edges = []
    for src, tgt, data in G.edges(data=True):
        edges.append({
            "source": src,
            "target": tgt,
            "relationship": data.get("relationship", "flows_to")
        })

    return {
        "nodes": nodes,
        "edges": edges,
        "stats": {
            "total_nodes": G.number_of_nodes(),
            "total_edges": G.number_of_edges(),
            "tables": len([n for n, d in G.nodes(data=True) if d.get("node_type") == "TABLE"]),
            "views": len([n for n, d in G.nodes(data=True) if d.get("node_type") == "VIEW"]),
            "procedures": len([n for n, d in G.nodes(data=True) if d.get("node_type") == "STORED_PROCEDURE"])
        }
    }


if __name__ == "__main__":
    # Test with sample lineage JSON
    import sys

    filepath = sys.argv[1] if len(sys.argv) > 1 else "data/sql_scripts/sales_procedures_lineage.json"

    with open(filepath) as f:
        lineage_data = json.load(f)

    G = build_graph(lineage_data)
    viz_data = get_graph_data_for_viz(G)

    print(f"Graph built: {viz_data['stats']}")

    # Test impact analysis
    test_table = "Sales.SalesOrderHeader"
    impact = get_impact_analysis(G, test_table)
    print(f"\nImpact analysis for {test_table}:")
    print(json.dumps(impact, indent=2))
