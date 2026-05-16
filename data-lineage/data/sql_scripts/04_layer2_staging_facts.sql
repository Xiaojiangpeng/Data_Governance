-- =============================================
-- STAGING LAYER: FACT TABLES
-- Source: Landing → Staging (join staging dims)
-- Cleanse, decode, integrate, derive columns
-- =============================================

-- Staging Fact: Product
CREATE TABLE [staging].[product_stg] (
    INT_product_sk              INT             NOT NULL,   -- from staging.Product_Dim
    INT_product_id              INT             NOT NULL,
    NM_product_number           NVARCHAR(25)    NOT NULL,
    NM_product_name             NVARCHAR(100)   NOT NULL,
    DC_standard_cost            DECIMAL(18,2)   NOT NULL,
    DC_list_price               DECIMAL(18,2)   NOT NULL,
    DC_margin                   DECIMAL(18,2)   NOT NULL,   -- DERIVED: list_price - standard_cost
    DC_margin_pct               DECIMAL(5,4),               -- DERIVED: margin / list_price
    INT_safety_stock_level      SMALLINT        NOT NULL,
    INT_reorder_point           SMALLINT        NOT NULL,
    BT_is_finished_good         BIT             NOT NULL,
    NM_color                    NVARCHAR(15),
    NM_size                     NVARCHAR(5),
    -- Resolved from staging.ProductCategory_Dim
    INT_subcategory_id          INT,
    NM_subcategory_name         NVARCHAR(50),               -- INTEGRATED from ProductCategory_Dim
    INT_category_id             INT,
    NM_category_name            NVARCHAR(50),               -- INTEGRATED from ProductCategory_Dim
    -- Validation
    BT_is_valid                 BIT             DEFAULT 1,
    NM_validation_notes         VARCHAR(500),
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- Staging Fact: Sales Order Header
CREATE TABLE [staging].[salesorder_stg] (
    INT_sales_order_id          INT             NOT NULL,
    DT_order_date               DATE            NOT NULL,   -- CAST from DATETIME
    DT_due_date                 DATE            NOT NULL,
    DT_ship_date                DATE,
    NM_order_status             VARCHAR(20)     NOT NULL,   -- DECODED from tinyint
    INT_customer_id             INT             NOT NULL,
    INT_sales_person_id         INT,
    -- Resolved from staging.Territory_Dim
    INT_territory_id            SMALLINT,
    NM_territory_name           NVARCHAR(50),               -- INTEGRATED from Territory_Dim
    NM_territory_group          NVARCHAR(50),               -- INTEGRATED from Territory_Dim
    NM_country_region_code      NVARCHAR(3),                -- INTEGRATED from Territory_Dim
    DC_sub_total                DECIMAL(18,2)   NOT NULL,
    DC_tax_amt                  DECIMAL(18,2)   NOT NULL,
    DC_freight                  DECIMAL(18,2)   NOT NULL,
    DC_total_due                DECIMAL(18,2)   NOT NULL,
    -- Validation
    BT_is_valid                 BIT             DEFAULT 1,
    NM_validation_notes         VARCHAR(500),
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- Staging Fact: Sales Order Line
CREATE TABLE [staging].[salesorderline_stg] (
    INT_sales_order_id          INT             NOT NULL,
    INT_sales_order_detail_id   INT             NOT NULL,
    INT_order_qty               INT             NOT NULL,
    -- Resolved from staging.Product_Dim + ProductCategory_Dim
    INT_product_sk              INT,                        -- INTEGRATED from Product_Dim
    INT_product_id              INT             NOT NULL,
    NM_product_name             NVARCHAR(100),              -- INTEGRATED from Product_Dim
    NM_product_number           NVARCHAR(25),               -- INTEGRATED from Product_Dim
    NM_subcategory_name         NVARCHAR(50),               -- INTEGRATED from ProductCategory_Dim
    NM_category_name            NVARCHAR(50),               -- INTEGRATED from ProductCategory_Dim
    DC_unit_price               DECIMAL(18,2)   NOT NULL,
    DC_discount_pct             DECIMAL(5,4)    NOT NULL,
    DC_discount_amt             DECIMAL(18,2)   NOT NULL,   -- DERIVED: unit_price * discount_pct * qty
    DC_gross_amount             DECIMAL(18,2)   NOT NULL,   -- DERIVED: unit_price * order_qty
    DC_net_amount               DECIMAL(18,2)   NOT NULL,   -- DERIVED: gross_amount - discount_amt
    DC_standard_cost            DECIMAL(18,2),              -- INTEGRATED from Product_Dim
    DC_cost_of_goods            DECIMAL(18,2),              -- DERIVED: standard_cost * order_qty
    DC_gross_margin             DECIMAL(18,2),              -- DERIVED: net_amount - cost_of_goods
    -- Validation
    BT_is_valid                 BIT             DEFAULT 1,
    NM_validation_notes         VARCHAR(500),
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- Staging Fact: Inventory
CREATE TABLE [staging].[inventory_stg] (
    INT_product_id              INT             NOT NULL,
    -- Resolved from staging.Product_Dim + ProductCategory_Dim
    INT_product_sk              INT,                        -- INTEGRATED from Product_Dim
    NM_product_name             NVARCHAR(100),              -- INTEGRATED from Product_Dim
    NM_subcategory_name         NVARCHAR(50),               -- INTEGRATED from ProductCategory_Dim
    NM_category_name            NVARCHAR(50),               -- INTEGRATED from ProductCategory_Dim
    DC_standard_cost            DECIMAL(18,2),              -- INTEGRATED from Product_Dim
    INT_location_id             SMALLINT        NOT NULL,
    NM_location_name            NVARCHAR(50),               -- INTEGRATED from Production.Location
    INT_total_quantity          INT             NOT NULL,   -- AGGREGATED across shelf/bin
    INT_safety_stock_level      SMALLINT,                   -- INTEGRATED from Product_Dim
    INT_reorder_point           SMALLINT,                   -- INTEGRATED from Product_Dim
    DC_stock_value              DECIMAL(18,2),              -- DERIVED: total_quantity * standard_cost
    NM_stock_status             VARCHAR(10)     NOT NULL,   -- DERIVED: OK / LOW / CRITICAL
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- =============================================
-- SP: Transform Landing → Staging Facts
-- Joins landing tables with staging dim tables
-- =============================================
CREATE PROCEDURE [etl].[sp_Transform_Staging]
    @NM_batch_id    VARCHAR(50),
    @DT_load_date   DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @DT_load_date IS NULL SET @DT_load_date = GETDATE();

    -- ── product_stg: landing.product_lnd + staging dims ──
    TRUNCATE TABLE staging.product_stg;
    INSERT INTO staging.product_stg (
        INT_product_sk, INT_product_id, NM_product_number, NM_product_name,
        DC_standard_cost, DC_list_price, DC_margin, DC_margin_pct,
        INT_safety_stock_level, INT_reorder_point, BT_is_finished_good,
        NM_color, NM_size,
        INT_subcategory_id, NM_subcategory_name, INT_category_id, NM_category_name,
        BT_is_valid, NM_validation_notes, DT_load_timestamp, NM_batch_id
    )
    SELECT
        pd.INT_product_sk,
        lnd.INT_product_id,
        lnd.NM_product_number,
        lnd.NM_product_name,
        CAST(lnd.DC_standard_cost AS DECIMAL(18,2)),
        CAST(lnd.DC_list_price AS DECIMAL(18,2)),
        CAST(lnd.DC_list_price - lnd.DC_standard_cost AS DECIMAL(18,2)),
        CASE WHEN lnd.DC_list_price > 0
             THEN CAST((lnd.DC_list_price - lnd.DC_standard_cost) / lnd.DC_list_price AS DECIMAL(5,4))
             ELSE 0 END,
        lnd.INT_safety_stock_level,
        lnd.INT_reorder_point,
        lnd.BT_finished_goods_flag,
        lnd.NM_color,
        lnd.NM_size,
        cat.INT_subcategory_id,
        cat.NM_subcategory_name,
        cat.INT_category_id,
        cat.NM_category_name,
        CASE WHEN lnd.DC_list_price < 0 THEN 0 ELSE 1 END,
        CASE WHEN lnd.DC_list_price < 0 THEN 'Negative list price' ELSE NULL END,
        @DT_load_date,
        @NM_batch_id
    FROM landing.product_lnd lnd
    LEFT JOIN staging.Product_Dim pd
        ON lnd.INT_product_id = pd.INT_product_id AND pd.BT_is_current = 1
    LEFT JOIN staging.ProductCategory_Dim cat
        ON lnd.INT_subcategory_id = cat.INT_subcategory_id AND cat.BT_is_current = 1;

    -- ── salesorder_stg: landing.salesorder_lnd + staging.Territory_Dim ──
    TRUNCATE TABLE staging.salesorder_stg;
    INSERT INTO staging.salesorder_stg (
        INT_sales_order_id, DT_order_date, DT_due_date, DT_ship_date,
        NM_order_status, INT_customer_id, INT_sales_person_id,
        INT_territory_id, NM_territory_name, NM_territory_group, NM_country_region_code,
        DC_sub_total, DC_tax_amt, DC_freight, DC_total_due,
        BT_is_valid, NM_validation_notes, DT_load_timestamp, NM_batch_id
    )
    SELECT
        lnd.INT_sales_order_id,
        CAST(lnd.DT_order_date AS DATE),
        CAST(lnd.DT_due_date AS DATE),
        CAST(lnd.DT_ship_date AS DATE),
        CASE lnd.INT_status
            WHEN 1 THEN 'In Process'
            WHEN 2 THEN 'Approved'
            WHEN 3 THEN 'Backordered'
            WHEN 4 THEN 'Rejected'
            WHEN 5 THEN 'Shipped'
            WHEN 6 THEN 'Cancelled'
            ELSE 'Unknown'
        END,
        lnd.INT_customer_id,
        lnd.INT_sales_person_id,
        lnd.INT_territory_id,
        td.NM_territory_name,
        td.NM_territory_group,
        td.NM_country_region_code,
        CAST(lnd.DC_sub_total AS DECIMAL(18,2)),
        CAST(lnd.DC_tax_amt AS DECIMAL(18,2)),
        CAST(lnd.DC_freight AS DECIMAL(18,2)),
        CAST(lnd.DC_total_due AS DECIMAL(18,2)),
        CASE WHEN lnd.DC_total_due < 0 THEN 0 ELSE 1 END,
        CASE WHEN lnd.DC_total_due < 0 THEN 'Negative total_due' ELSE NULL END,
        @DT_load_date,
        @NM_batch_id
    FROM landing.salesorder_lnd lnd
    LEFT JOIN staging.Territory_Dim td
        ON lnd.INT_territory_id = td.INT_territory_id AND td.BT_is_current = 1;

    -- ── salesorderline_stg: landing + staging.Product_Dim + ProductCategory_Dim ──
    TRUNCATE TABLE staging.salesorderline_stg;
    INSERT INTO staging.salesorderline_stg (
        INT_sales_order_id, INT_sales_order_detail_id, INT_order_qty,
        INT_product_sk, INT_product_id, NM_product_name, NM_product_number,
        NM_subcategory_name, NM_category_name,
        DC_unit_price, DC_discount_pct, DC_discount_amt,
        DC_gross_amount, DC_net_amount,
        DC_standard_cost, DC_cost_of_goods, DC_gross_margin,
        BT_is_valid, DT_load_timestamp, NM_batch_id
    )
    SELECT
        lnd.INT_sales_order_id,
        lnd.INT_sales_order_detail_id,
        lnd.INT_order_qty,
        pd.INT_product_sk,
        lnd.INT_product_id,
        pd.NM_product_name,
        pd.NM_product_number,
        cat.NM_subcategory_name,
        cat.NM_category_name,
        CAST(lnd.DC_unit_price AS DECIMAL(18,2)),
        CAST(lnd.DC_unit_price_discount AS DECIMAL(5,4)),
        CAST(lnd.DC_unit_price * lnd.DC_unit_price_discount * lnd.INT_order_qty AS DECIMAL(18,2)),
        CAST(lnd.DC_unit_price * lnd.INT_order_qty AS DECIMAL(18,2)),
        CAST(lnd.DC_line_total AS DECIMAL(18,2)),
        pd.DC_standard_cost,
        CAST(pd.DC_standard_cost * lnd.INT_order_qty AS DECIMAL(18,2)),
        CAST(lnd.DC_line_total - (pd.DC_standard_cost * lnd.INT_order_qty) AS DECIMAL(18,2)),
        1,
        @DT_load_date,
        @NM_batch_id
    FROM landing.salesorderline_lnd lnd
    LEFT JOIN staging.Product_Dim pd
        ON lnd.INT_product_id = pd.INT_product_id AND pd.BT_is_current = 1
    LEFT JOIN staging.ProductCategory_Dim cat
        ON pd.INT_subcategory_id = cat.INT_subcategory_id AND cat.BT_is_current = 1;

    -- ── inventory_stg: landing.inventory_lnd + staging dims + Production.Location ──
    TRUNCATE TABLE staging.inventory_stg;
    INSERT INTO staging.inventory_stg (
        INT_product_id, INT_product_sk, NM_product_name,
        NM_subcategory_name, NM_category_name, DC_standard_cost,
        INT_location_id, NM_location_name,
        INT_total_quantity, INT_safety_stock_level, INT_reorder_point,
        DC_stock_value, NM_stock_status,
        DT_load_timestamp, NM_batch_id
    )
    SELECT
        lnd.INT_product_id,
        pd.INT_product_sk,
        pd.NM_product_name,
        cat.NM_subcategory_name,
        cat.NM_category_name,
        pd.DC_standard_cost,
        lnd.INT_location_id,
        l.Name,
        SUM(lnd.INT_quantity),
        pd.INT_safety_stock_level,
        pd.INT_reorder_point,
        CAST(SUM(lnd.INT_quantity) * pd.DC_standard_cost AS DECIMAL(18,2)),
        CASE
            WHEN SUM(lnd.INT_quantity) = 0                          THEN 'CRITICAL'
            WHEN SUM(lnd.INT_quantity) < pd.INT_safety_stock_level  THEN 'LOW'
            ELSE 'OK'
        END,
        @DT_load_date,
        @NM_batch_id
    FROM landing.inventory_lnd lnd
    LEFT JOIN staging.Product_Dim pd
        ON lnd.INT_product_id = pd.INT_product_id AND pd.BT_is_current = 1
    LEFT JOIN staging.ProductCategory_Dim cat
        ON pd.INT_subcategory_id = cat.INT_subcategory_id AND cat.BT_is_current = 1
    LEFT JOIN Production.Location l
        ON lnd.INT_location_id = l.LocationID
    GROUP BY
        lnd.INT_product_id, pd.INT_product_sk, pd.NM_product_name,
        cat.NM_subcategory_name, cat.NM_category_name, pd.DC_standard_cost,
        lnd.INT_location_id, l.Name,
        pd.INT_safety_stock_level, pd.INT_reorder_point;

    PRINT 'Staging facts loaded. Batch: ' + @NM_batch_id;
END;
GO
