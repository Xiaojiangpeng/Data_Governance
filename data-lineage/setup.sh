#!/bin/bash
# =============================================
# Master Setup Script: AdventureWorks DW
# Unzips project, creates all schemas, tables,
# stored procedures, and runs full ETL pipeline
# Usage: bash ~/Downloads/setup.sh
# =============================================

# Step 0: Unzip the project
echo "Step 0: Unzipping project..."
cd ~/Downloads
unzip -o data-lineage.zip -d data-lineage-new
cd ~/Downloads/data-lineage-new/data-lineage
echo "✅ Unzip done"
echo ""

SERVER="localhost,1433"
USER="sa"
PASSWORD="YourPass123!"
DB="AdventureWorks2019"
SCRIPT_DIR="$(pwd)/data/sql_scripts"

echo "=== AdventureWorks DW Setup ==="
echo "Server: $SERVER"
echo "Database: $DB"
echo ""

# Step 1: Create schemas
echo "Step 1: Creating schemas..."
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -Q "
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'landing')
    EXEC('CREATE SCHEMA landing');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'presentation')
    EXEC('CREATE SCHEMA presentation');
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'etl')
    EXEC('CREATE SCHEMA etl');
PRINT 'Schemas created.';
"
echo "✅ Schemas done"

# Step 2: Create staging dimension tables + sp_Load_Dims
echo "Step 2: Creating staging dimension tables..."
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -i "$SCRIPT_DIR/02_staging_dims.sql"
echo "✅ Staging dims done"

# Step 3: Create landing tables + sp_Load_Landing
echo "Step 3: Creating landing tables..."
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -i "$SCRIPT_DIR/03_layer1_landing.sql"
echo "✅ Landing done"

# Step 4: Create staging fact tables + sp_Transform_Staging
echo "Step 4: Creating staging fact tables..."
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -i "$SCRIPT_DIR/04_layer2_staging_facts.sql"
echo "✅ Staging facts done"

# Step 5: Create presentation tables + sp_Aggregate_Presentation
echo "Step 5: Creating presentation tables..."
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -i "$SCRIPT_DIR/05_layer3_presentation.sql"
echo "✅ Presentation done"

# Step 6: Run full ETL pipeline
echo ""
echo "Step 6: Running full ETL pipeline..."
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -Q "EXEC etl.sp_RunFullPipeline"
echo "✅ ETL pipeline done"

# Step 7: Verify row counts
echo ""
echo "=== Row Count Verification ==="
sqlcmd -S $SERVER -U $USER -P "$PASSWORD" -d $DB -Q "
SELECT 'staging.Product_Dim'        AS TableName, COUNT(*) AS RowCount FROM staging.Product_Dim
UNION ALL
SELECT 'staging.ProductCategory_Dim',              COUNT(*) FROM staging.ProductCategory_Dim
UNION ALL
SELECT 'staging.Territory_Dim',                    COUNT(*) FROM staging.Territory_Dim
UNION ALL
SELECT 'landing.product_lnd',                      COUNT(*) FROM landing.product_lnd
UNION ALL
SELECT 'landing.salesorder_lnd',                   COUNT(*) FROM landing.salesorder_lnd
UNION ALL
SELECT 'landing.salesorderline_lnd',               COUNT(*) FROM landing.salesorderline_lnd
UNION ALL
SELECT 'landing.inventory_lnd',                    COUNT(*) FROM landing.inventory_lnd
UNION ALL
SELECT 'staging.product_stg',                      COUNT(*) FROM staging.product_stg
UNION ALL
SELECT 'staging.salesorder_stg',                   COUNT(*) FROM staging.salesorder_stg
UNION ALL
SELECT 'staging.salesorderline_stg',               COUNT(*) FROM staging.salesorderline_stg
UNION ALL
SELECT 'staging.inventory_stg',                    COUNT(*) FROM staging.inventory_stg
UNION ALL
SELECT 'presentation.salesorder_agg',              COUNT(*) FROM presentation.salesorder_agg
UNION ALL
SELECT 'presentation.product_agg',                 COUNT(*) FROM presentation.product_agg
UNION ALL
SELECT 'presentation.inventory_agg',               COUNT(*) FROM presentation.inventory_agg
ORDER BY TableName;
"

echo ""
echo "=== Setup Complete! ==="
echo "Open DBeaver and refresh AdventureWorks2019 to see all tables."
