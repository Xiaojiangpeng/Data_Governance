-- =============================================
-- LANDING LAYER: Raw extract from OLTP
-- Source: OLTP → Landing (fact tables only)
-- No transformation — as-is from source
-- All metadata columns use prefix convention
-- =============================================

-- Landing: Product (raw from Production.Product)
CREATE TABLE [landing].[product_lnd] (
    INT_product_id          INT             NOT NULL,
    NM_product_number       NVARCHAR(25)    NOT NULL,
    NM_product_name         NVARCHAR(50)    NOT NULL,
    DC_standard_cost        MONEY           NOT NULL,
    DC_list_price           MONEY           NOT NULL,
    INT_safety_stock_level  SMALLINT        NOT NULL,
    INT_reorder_point       SMALLINT        NOT NULL,
    BT_finished_goods_flag  BIT             NOT NULL,
    NM_color                NVARCHAR(15),
    NM_size                 NVARCHAR(5),
    DC_weight               DECIMAL(8,2),
    INT_subcategory_id      INT,            -- raw FK, not resolved
    DT_modified_date        DATETIME,
    -- ETL metadata
    NM_source_system        VARCHAR(50),
    DT_load_timestamp       DATETIME,
    NM_batch_id             VARCHAR(50)
);
GO

-- Landing: Sales Order Header (raw from Sales.SalesOrderHeader)
CREATE TABLE [landing].[salesorder_lnd] (
    INT_sales_order_id      INT             NOT NULL,
    INT_revision_number     TINYINT,
    DT_order_date           DATETIME        NOT NULL,
    DT_due_date             DATETIME        NOT NULL,
    DT_ship_date            DATETIME,
    INT_status              TINYINT         NOT NULL,   -- raw code, not decoded
    INT_customer_id         INT             NOT NULL,
    INT_sales_person_id     INT,
    INT_territory_id        SMALLINT,                   -- raw FK, not resolved
    DC_sub_total            MONEY           NOT NULL,
    DC_tax_amt              MONEY           NOT NULL,
    DC_freight              MONEY           NOT NULL,
    DC_total_due            MONEY           NOT NULL,
    DT_modified_date        DATETIME,
    -- ETL metadata
    NM_source_system        VARCHAR(50),
    DT_load_timestamp       DATETIME,
    NM_batch_id             VARCHAR(50)
);
GO

-- Landing: Sales Order Line (raw from Sales.SalesOrderDetail)
CREATE TABLE [landing].[salesorderline_lnd] (
    INT_sales_order_id          INT             NOT NULL,
    INT_sales_order_detail_id   INT             NOT NULL,
    INT_order_qty               SMALLINT        NOT NULL,
    INT_product_id              INT             NOT NULL,   -- raw FK, not resolved
    DC_unit_price               MONEY           NOT NULL,
    DC_unit_price_discount      MONEY           NOT NULL,
    DC_line_total               DECIMAL(38,6)   NOT NULL,
    DT_modified_date            DATETIME,
    -- ETL metadata
    NM_source_system            VARCHAR(50),
    DT_load_timestamp           DATETIME,
    NM_batch_id                 VARCHAR(50)
);
GO

-- Landing: Product Inventory (raw from Production.ProductInventory)
CREATE TABLE [landing].[inventory_lnd] (
    INT_product_id          INT             NOT NULL,   -- raw FK, not resolved
    INT_location_id         SMALLINT        NOT NULL,   -- raw FK, not resolved
    NM_shelf                NCHAR(10),
    INT_bin                 TINYINT,
    INT_quantity            SMALLINT        NOT NULL,
    DT_modified_date        DATETIME,
    -- ETL metadata
    NM_source_system        VARCHAR(50),
    DT_load_timestamp       DATETIME,
    NM_batch_id             VARCHAR(50)
);
GO

-- =============================================
-- SP: Load Landing Layer
-- Source: OLTP → landing (fact tables)
-- =============================================
CREATE PROCEDURE [etl].[sp_Load_Landing]
    @NM_batch_id    VARCHAR(50),
    @DT_load_date   DATETIME = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @DT_load_date IS NULL SET @DT_load_date = GETDATE();

    -- product_lnd: full extract from Production.Product
    TRUNCATE TABLE landing.product_lnd;
    INSERT INTO landing.product_lnd (
        INT_product_id, NM_product_number, NM_product_name,
        DC_standard_cost, DC_list_price,
        INT_safety_stock_level, INT_reorder_point,
        BT_finished_goods_flag, NM_color, NM_size, DC_weight,
        INT_subcategory_id, DT_modified_date,
        NM_source_system, DT_load_timestamp, NM_batch_id
    )
    SELECT
        ProductID, ProductNumber, Name,
        StandardCost, ListPrice,
        SafetyStockLevel, ReorderPoint,
        FinishedGoodsFlag, Color, Size, Weight,
        ProductSubcategoryID, ModifiedDate,
        'AdventureWorks_OLTP', @DT_load_date, @NM_batch_id
    FROM Production.Product;

    -- salesorder_lnd: full extract from Sales.SalesOrderHeader
    TRUNCATE TABLE landing.salesorder_lnd;
    INSERT INTO landing.salesorder_lnd (
        INT_sales_order_id, INT_revision_number,
        DT_order_date, DT_due_date, DT_ship_date,
        INT_status, INT_customer_id, INT_sales_person_id, INT_territory_id,
        DC_sub_total, DC_tax_amt, DC_freight, DC_total_due,
        DT_modified_date, NM_source_system, DT_load_timestamp, NM_batch_id
    )
    SELECT
        SalesOrderID, RevisionNumber,
        OrderDate, DueDate, ShipDate,
        Status, CustomerID, SalesPersonID, TerritoryID,
        SubTotal, TaxAmt, Freight, TotalDue,
        ModifiedDate, 'AdventureWorks_OLTP', @DT_load_date, @NM_batch_id
    FROM Sales.SalesOrderHeader;

    -- salesorderline_lnd: full extract from Sales.SalesOrderDetail
    TRUNCATE TABLE landing.salesorderline_lnd;
    INSERT INTO landing.salesorderline_lnd (
        INT_sales_order_id, INT_sales_order_detail_id, INT_order_qty,
        INT_product_id, DC_unit_price, DC_unit_price_discount, DC_line_total,
        DT_modified_date, NM_source_system, DT_load_timestamp, NM_batch_id
    )
    SELECT
        SalesOrderID, SalesOrderDetailID, OrderQty,
        ProductID, UnitPrice, UnitPriceDiscount, LineTotal,
        ModifiedDate, 'AdventureWorks_OLTP', @DT_load_date, @NM_batch_id
    FROM Sales.SalesOrderDetail;

    -- inventory_lnd: full extract from Production.ProductInventory
    TRUNCATE TABLE landing.inventory_lnd;
    INSERT INTO landing.inventory_lnd (
        INT_product_id, INT_location_id, NM_shelf, INT_bin, INT_quantity,
        DT_modified_date, NM_source_system, DT_load_timestamp, NM_batch_id
    )
    SELECT
        ProductID, LocationID, Shelf, Bin, Quantity,
        ModifiedDate, 'AdventureWorks_OLTP', @DT_load_date, @NM_batch_id
    FROM Production.ProductInventory;

    PRINT 'Landing layer loaded. Batch: ' + @NM_batch_id;
END;
GO
