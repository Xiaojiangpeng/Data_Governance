-- =============================================
-- PRESENTATION LAYER: Aggregated fact tables
-- Source: Staging Facts → Presentation
-- Grain: Month + Category + Territory
-- =============================================

-- Presentation: Sales Aggregation
-- Grain: year_month + category + territory
CREATE TABLE [presentation].[salesorder_agg] (
    NM_year_month               CHAR(7)         NOT NULL,   -- YYYY-MM
    NM_category_name            NVARCHAR(50)    NOT NULL,
    NM_subcategory_name         NVARCHAR(50),
    INT_territory_id            SMALLINT,
    NM_territory_name           NVARCHAR(50),
    NM_territory_group          NVARCHAR(50),
    NM_country_region_code      NVARCHAR(3),
    -- Order metrics
    INT_order_count             INT             NOT NULL,
    INT_unique_customers        INT             NOT NULL,
    INT_total_units_sold        INT             NOT NULL,
    -- Revenue metrics
    DC_gross_revenue            DECIMAL(18,2)   NOT NULL,
    DC_total_discount           DECIMAL(18,2)   NOT NULL,
    DC_net_revenue              DECIMAL(18,2)   NOT NULL,
    DC_total_tax                DECIMAL(18,2)   NOT NULL,
    DC_total_freight            DECIMAL(18,2)   NOT NULL,
    -- Cost & margin
    DC_total_cost_of_goods      DECIMAL(18,2)   NOT NULL,
    DC_gross_margin             DECIMAL(18,2)   NOT NULL,
    DC_margin_pct               DECIMAL(5,4),
    -- Order value
    DC_avg_order_value          DECIMAL(18,2)   NOT NULL,
    DC_avg_unit_price           DECIMAL(18,2)   NOT NULL,
    -- Growth (calculated after insert)
    DC_revenue_growth_pct       DECIMAL(8,4),               -- vs prior month
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- Presentation: Product Performance Aggregation
-- Grain: year_month + product + category
CREATE TABLE [presentation].[product_agg] (
    NM_year_month               CHAR(7)         NOT NULL,
    INT_product_id              INT             NOT NULL,
    NM_product_name             NVARCHAR(100)   NOT NULL,
    NM_product_number           NVARCHAR(25),
    NM_category_name            NVARCHAR(50),
    NM_subcategory_name         NVARCHAR(50),
    -- Sales metrics
    INT_total_orders            INT             NOT NULL,
    INT_total_units_sold        INT             NOT NULL,
    DC_gross_revenue            DECIMAL(18,2)   NOT NULL,
    DC_net_revenue              DECIMAL(18,2)   NOT NULL,
    DC_avg_selling_price        DECIMAL(18,2)   NOT NULL,
    -- Cost & margin
    DC_standard_cost            DECIMAL(18,2),
    DC_total_cost               DECIMAL(18,2)   NOT NULL,
    DC_gross_margin             DECIMAL(18,2)   NOT NULL,
    DC_margin_pct               DECIMAL(5,4),
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- Presentation: Inventory Health Aggregation
-- Grain: snapshot_month + category
CREATE TABLE [presentation].[inventory_agg] (
    NM_snapshot_month           CHAR(7)         NOT NULL,
    NM_category_name            NVARCHAR(50),
    NM_subcategory_name         NVARCHAR(50),
    -- Stock counts by status
    INT_total_products          INT             NOT NULL,
    INT_in_stock_count          INT             NOT NULL,
    INT_low_stock_count         INT             NOT NULL,
    INT_critical_stock_count    INT             NOT NULL,
    -- Quantity & value
    INT_total_units_on_hand     INT             NOT NULL,
    DC_estimated_stock_value    DECIMAL(18,2)   NOT NULL,
    DC_avg_stock_per_product    DECIMAL(10,2),
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- =============================================
-- SP: Aggregate Staging → Presentation
-- =============================================
CREATE PROCEDURE [etl].[sp_Aggregate_Presentation]
    @NM_batch_id    VARCHAR(50),
    @DT_load_date   DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @DT_load_date IS NULL SET @DT_load_date = GETDATE();

    -- ── salesorder_agg: month + category + territory ──
    TRUNCATE TABLE presentation.salesorder_agg;
    INSERT INTO presentation.salesorder_agg (
        NM_year_month, NM_category_name, NM_subcategory_name,
        INT_territory_id, NM_territory_name, NM_territory_group, NM_country_region_code,
        INT_order_count, INT_unique_customers, INT_total_units_sold,
        DC_gross_revenue, DC_total_discount, DC_net_revenue,
        DC_total_tax, DC_total_freight,
        DC_total_cost_of_goods, DC_gross_margin, DC_margin_pct,
        DC_avg_order_value, DC_avg_unit_price,
        DT_load_timestamp, NM_batch_id
    )
    SELECT
        FORMAT(so.DT_order_date, 'yyyy-MM'),
        sol.NM_category_name,
        sol.NM_subcategory_name,
        so.INT_territory_id,
        so.NM_territory_name,
        so.NM_territory_group,
        so.NM_country_region_code,
        COUNT(DISTINCT so.INT_sales_order_id),
        COUNT(DISTINCT so.INT_customer_id),
        SUM(sol.INT_order_qty),
        SUM(sol.DC_gross_amount),
        SUM(sol.DC_discount_amt),
        SUM(sol.DC_net_amount),
        SUM(so.DC_tax_amt),
        SUM(so.DC_freight),
        SUM(sol.DC_cost_of_goods),
        SUM(sol.DC_gross_margin),
        CASE WHEN SUM(sol.DC_net_amount) > 0
             THEN SUM(sol.DC_gross_margin) / SUM(sol.DC_net_amount)
             ELSE 0 END,
        AVG(so.DC_total_due),
        AVG(sol.DC_unit_price),
        @DT_load_date,
        @NM_batch_id
    FROM staging.salesorder_stg so
    INNER JOIN staging.salesorderline_stg sol
        ON so.INT_sales_order_id = sol.INT_sales_order_id
    WHERE so.BT_is_valid = 1
      AND sol.BT_is_valid = 1
    GROUP BY
        FORMAT(so.DT_order_date, 'yyyy-MM'),
        sol.NM_category_name, sol.NM_subcategory_name,
        so.INT_territory_id, so.NM_territory_name,
        so.NM_territory_group, so.NM_country_region_code;

    -- Update revenue growth % vs prior month
    UPDATE curr
    SET curr.DC_revenue_growth_pct =
        CASE WHEN prev.DC_net_revenue > 0
             THEN (curr.DC_net_revenue - prev.DC_net_revenue) / prev.DC_net_revenue
             ELSE NULL END
    FROM presentation.salesorder_agg curr
    LEFT JOIN presentation.salesorder_agg prev
        ON curr.INT_territory_id    = prev.INT_territory_id
       AND curr.NM_category_name    = prev.NM_category_name
       AND prev.NM_year_month = FORMAT(
               DATEADD(MONTH, -1, CAST(curr.NM_year_month + '-01' AS DATE)),
               'yyyy-MM');

    -- ── product_agg: month + product ─────────────────
    TRUNCATE TABLE presentation.product_agg;
    INSERT INTO presentation.product_agg (
        NM_year_month, INT_product_id, NM_product_name, NM_product_number,
        NM_category_name, NM_subcategory_name,
        INT_total_orders, INT_total_units_sold,
        DC_gross_revenue, DC_net_revenue, DC_avg_selling_price,
        DC_standard_cost, DC_total_cost, DC_gross_margin, DC_margin_pct,
        DT_load_timestamp, NM_batch_id
    )
    SELECT
        FORMAT(so.DT_order_date, 'yyyy-MM'),
        sol.INT_product_id,
        sol.NM_product_name,
        sol.NM_product_number,
        sol.NM_category_name,
        sol.NM_subcategory_name,
        COUNT(DISTINCT so.INT_sales_order_id),
        SUM(sol.INT_order_qty),
        SUM(sol.DC_gross_amount),
        SUM(sol.DC_net_amount),
        AVG(sol.DC_unit_price),
        AVG(sol.DC_standard_cost),
        SUM(sol.DC_cost_of_goods),
        SUM(sol.DC_gross_margin),
        CASE WHEN SUM(sol.DC_net_amount) > 0
             THEN SUM(sol.DC_gross_margin) / SUM(sol.DC_net_amount)
             ELSE 0 END,
        @DT_load_date,
        @NM_batch_id
    FROM staging.salesorder_stg so
    INNER JOIN staging.salesorderline_stg sol
        ON so.INT_sales_order_id = sol.INT_sales_order_id
    WHERE so.BT_is_valid = 1
    GROUP BY
        FORMAT(so.DT_order_date, 'yyyy-MM'),
        sol.INT_product_id, sol.NM_product_name, sol.NM_product_number,
        sol.NM_category_name, sol.NM_subcategory_name;

    -- ── inventory_agg: month + category ──────────────
    TRUNCATE TABLE presentation.inventory_agg;
    INSERT INTO presentation.inventory_agg (
        NM_snapshot_month, NM_category_name, NM_subcategory_name,
        INT_total_products, INT_in_stock_count, INT_low_stock_count,
        INT_critical_stock_count, INT_total_units_on_hand,
        DC_estimated_stock_value, DC_avg_stock_per_product,
        DT_load_timestamp, NM_batch_id
    )
    SELECT
        FORMAT(@DT_load_date, 'yyyy-MM'),
        NM_category_name,
        NM_subcategory_name,
        COUNT(DISTINCT INT_product_id),
        SUM(CASE WHEN NM_stock_status = 'OK'       THEN 1 ELSE 0 END),
        SUM(CASE WHEN NM_stock_status = 'LOW'      THEN 1 ELSE 0 END),
        SUM(CASE WHEN NM_stock_status = 'CRITICAL' THEN 1 ELSE 0 END),
        SUM(INT_total_quantity),
        SUM(DC_stock_value),
        CAST(AVG(CAST(INT_total_quantity AS DECIMAL(10,2))) AS DECIMAL(10,2)),
        @DT_load_date,
        @NM_batch_id
    FROM staging.inventory_stg
    GROUP BY NM_category_name, NM_subcategory_name;

    PRINT 'Presentation layer loaded. Batch: ' + @NM_batch_id;
END;
GO

-- =============================================
-- MASTER PIPELINE ORCHESTRATOR
-- =============================================
CREATE PROCEDURE [etl].[sp_RunFullPipeline]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @NM_batch_id    VARCHAR(50) = 'ETL_' + CONVERT(VARCHAR, GETDATE(), 120);
    DECLARE @DT_start       DATETIME    = GETDATE();

    PRINT '=== Full ETL Pipeline Start: ' + @NM_batch_id + ' ===';

    -- Step 1: Load dims from OLTP → staging (monthly, SCD2)
    EXEC etl.sp_Load_Dims               @NM_batch_id = @NM_batch_id;

    -- Step 2: Extract facts OLTP → landing
    EXEC etl.sp_Load_Landing            @NM_batch_id = @NM_batch_id;

    -- Step 3: Transform landing → staging facts (join dims)
    EXEC etl.sp_Transform_Staging       @NM_batch_id = @NM_batch_id;

    -- Step 4: Aggregate staging → presentation
    EXEC etl.sp_Aggregate_Presentation  @NM_batch_id = @NM_batch_id;

    PRINT '=== Pipeline Complete. Duration: '
        + CAST(DATEDIFF(SECOND, @DT_start, GETDATE()) AS VARCHAR) + 's ===';
END;
GO
