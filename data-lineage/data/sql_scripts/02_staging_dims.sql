-- =============================================
-- STAGING LAYER: DIMENSION TABLES (SCD Type 2)
-- Source: OLTP → Staging direct (no landing)
-- Loaded monthly via sp_Load_Dims
-- =============================================

-- Staging Dim: Product (SCD Type 2)
CREATE TABLE [staging].[Product_Dim] (
    INT_product_sk          INT IDENTITY(1,1)   NOT NULL,   -- surrogate key
    INT_product_id          INT                 NOT NULL,   -- natural key from OLTP
    NM_product_name         NVARCHAR(100)       NOT NULL,
    NM_product_number       NVARCHAR(25)        NOT NULL,
    DC_standard_cost        DECIMAL(18,2)       NOT NULL,
    DC_list_price           DECIMAL(18,2)       NOT NULL,
    INT_safety_stock_level  SMALLINT            NOT NULL,
    INT_reorder_point       SMALLINT            NOT NULL,
    BT_finished_goods_flag  BIT                 NOT NULL,
    NM_color                NVARCHAR(15),
    NM_size                 NVARCHAR(5),
    DC_weight               DECIMAL(8,2),
    INT_subcategory_id      INT,
    -- SCD Type 2 tracking
    DT_effective_date       DATE                NOT NULL,
    DT_expiry_date          DATE                NOT NULL    DEFAULT '9999-12-31',
    BT_is_current           BIT                 NOT NULL    DEFAULT 1,
    NM_checksum_val         VARBINARY(32),
    -- ETL metadata
    DT_load_timestamp       DATETIME,
    NM_batch_id             VARCHAR(50)
);
GO

-- Staging Dim: Product Category (SCD Type 2)
CREATE TABLE [staging].[ProductCategory_Dim] (
    INT_category_sk         INT IDENTITY(1,1)   NOT NULL,   -- surrogate key
    INT_subcategory_id      INT                 NOT NULL,   -- natural key from OLTP
    NM_subcategory_name     NVARCHAR(50)        NOT NULL,
    INT_category_id         INT                 NOT NULL,
    NM_category_name        NVARCHAR(50)        NOT NULL,
    -- SCD Type 2 tracking
    DT_effective_date       DATE                NOT NULL,
    DT_expiry_date          DATE                NOT NULL    DEFAULT '9999-12-31',
    BT_is_current           BIT                 NOT NULL    DEFAULT 1,
    NM_checksum_val         VARBINARY(32),
    -- ETL metadata
    DT_load_timestamp       DATETIME,
    NM_batch_id             VARCHAR(50)
);
GO

-- Staging Dim: Territory (SCD Type 2)
CREATE TABLE [staging].[Territory_Dim] (
    INT_territory_sk        INT IDENTITY(1,1)   NOT NULL,   -- surrogate key
    INT_territory_id        SMALLINT            NOT NULL,   -- natural key from OLTP
    NM_territory_name       NVARCHAR(50)        NOT NULL,
    NM_country_region_code  NVARCHAR(3)         NOT NULL,
    NM_territory_group      NVARCHAR(50),
    DC_sales_ytd            DECIMAL(18,2),
    DC_sales_last_year      DECIMAL(18,2),
    -- SCD Type 2 tracking
    DT_effective_date       DATE                NOT NULL,
    DT_expiry_date          DATE                NOT NULL    DEFAULT '9999-12-31',
    BT_is_current           BIT                 NOT NULL    DEFAULT 1,
    NM_checksum_val         VARBINARY(32),
    -- ETL metadata
    DT_load_timestamp       DATETIME,
    NM_batch_id             VARCHAR(50)
);
GO

-- =============================================
-- SP: Load Product_Dim (SCD Type 2)
-- Source: OLTP Production.Product → staging.Product_Dim
-- =============================================
CREATE PROCEDURE [etl].[sp_Load_Product_Dim]
    @NM_batch_id    VARCHAR(50),
    @DT_load_date   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @DT_load_date IS NULL SET @DT_load_date = CAST(GETDATE() AS DATE);

    -- Step 1: Expire rows where attributes have changed
    UPDATE d
    SET d.DT_expiry_date        = DATEADD(DAY, -1, @DT_load_date),
        d.BT_is_current         = 0,
        d.DT_load_timestamp     = GETDATE()
    FROM staging.Product_Dim d
    INNER JOIN (
        SELECT
            ProductID,
            CHECKSUM(
                Name, ProductNumber, StandardCost, ListPrice,
                SafetyStockLevel, ReorderPoint, FinishedGoodsFlag,
                Color, Size, Weight, ProductSubcategoryID
            ) AS new_checksum
        FROM Production.Product
    ) src ON d.INT_product_id = src.ProductID
          AND d.BT_is_current = 1
          AND d.NM_checksum_val <> CONVERT(VARBINARY(32), src.new_checksum);

    -- Step 2: Insert new or changed rows
    INSERT INTO staging.Product_Dim (
        INT_product_id, NM_product_name, NM_product_number,
        DC_standard_cost, DC_list_price,
        INT_safety_stock_level, INT_reorder_point,
        BT_finished_goods_flag, NM_color, NM_size, DC_weight,
        INT_subcategory_id,
        DT_effective_date, DT_expiry_date, BT_is_current,
        NM_checksum_val, DT_load_timestamp, NM_batch_id
    )
    SELECT
        p.ProductID,
        p.Name,
        p.ProductNumber,
        CAST(p.StandardCost AS DECIMAL(18,2)),
        CAST(p.ListPrice AS DECIMAL(18,2)),
        p.SafetyStockLevel,
        p.ReorderPoint,
        p.FinishedGoodsFlag,
        p.Color,
        p.Size,
        CAST(p.Weight AS DECIMAL(8,2)),
        p.ProductSubcategoryID,
        @DT_load_date,
        '9999-12-31',
        1,
        CONVERT(VARBINARY(32), CHECKSUM(
            p.Name, p.ProductNumber, p.StandardCost, p.ListPrice,
            p.SafetyStockLevel, p.ReorderPoint, p.FinishedGoodsFlag,
            p.Color, p.Size, p.Weight, p.ProductSubcategoryID
        )),
        GETDATE(),
        @NM_batch_id
    FROM Production.Product p
    WHERE NOT EXISTS (
        SELECT 1 FROM staging.Product_Dim d
        WHERE d.INT_product_id = p.ProductID
          AND d.BT_is_current = 1
          AND d.NM_checksum_val = CONVERT(VARBINARY(32), CHECKSUM(
              p.Name, p.ProductNumber, p.StandardCost, p.ListPrice,
              p.SafetyStockLevel, p.ReorderPoint, p.FinishedGoodsFlag,
              p.Color, p.Size, p.Weight, p.ProductSubcategoryID
          ))
    );

    PRINT 'Product_Dim loaded. Batch: ' + @NM_batch_id;
END;
GO

-- =============================================
-- SP: Load ProductCategory_Dim (SCD Type 2)
-- Source: OLTP ProductSubcategory + ProductCategory → staging.ProductCategory_Dim
-- =============================================
CREATE PROCEDURE [etl].[sp_Load_ProductCategory_Dim]
    @NM_batch_id    VARCHAR(50),
    @DT_load_date   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @DT_load_date IS NULL SET @DT_load_date = CAST(GETDATE() AS DATE);

    -- Step 1: Expire changed rows
    UPDATE d
    SET d.DT_expiry_date        = DATEADD(DAY, -1, @DT_load_date),
        d.BT_is_current         = 0,
        d.DT_load_timestamp     = GETDATE()
    FROM staging.ProductCategory_Dim d
    INNER JOIN (
        SELECT
            ps.ProductSubcategoryID,
            CHECKSUM(ps.Name, pc.ProductCategoryID, pc.Name) AS new_checksum
        FROM Production.ProductSubcategory ps
        INNER JOIN Production.ProductCategory pc
            ON ps.ProductCategoryID = pc.ProductCategoryID
    ) src ON d.INT_subcategory_id = src.ProductSubcategoryID
          AND d.BT_is_current = 1
          AND d.NM_checksum_val <> CONVERT(VARBINARY(32), src.new_checksum);

    -- Step 2: Insert new or changed rows
    INSERT INTO staging.ProductCategory_Dim (
        INT_subcategory_id, NM_subcategory_name,
        INT_category_id, NM_category_name,
        DT_effective_date, DT_expiry_date, BT_is_current,
        NM_checksum_val, DT_load_timestamp, NM_batch_id
    )
    SELECT
        ps.ProductSubcategoryID,
        ps.Name,
        pc.ProductCategoryID,
        pc.Name,
        @DT_load_date,
        '9999-12-31',
        1,
        CONVERT(VARBINARY(32), CHECKSUM(ps.Name, pc.ProductCategoryID, pc.Name)),
        GETDATE(),
        @NM_batch_id
    FROM Production.ProductSubcategory ps
    INNER JOIN Production.ProductCategory pc
        ON ps.ProductCategoryID = pc.ProductCategoryID
    WHERE NOT EXISTS (
        SELECT 1 FROM staging.ProductCategory_Dim d
        WHERE d.INT_subcategory_id = ps.ProductSubcategoryID
          AND d.BT_is_current = 1
          AND d.NM_checksum_val = CONVERT(VARBINARY(32),
              CHECKSUM(ps.Name, pc.ProductCategoryID, pc.Name))
    );

    PRINT 'ProductCategory_Dim loaded. Batch: ' + @NM_batch_id;
END;
GO

-- =============================================
-- SP: Load Territory_Dim (SCD Type 2)
-- Source: OLTP Sales.SalesTerritory → staging.Territory_Dim
-- =============================================
CREATE PROCEDURE [etl].[sp_Load_Territory_Dim]
    @NM_batch_id    VARCHAR(50),
    @DT_load_date   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @DT_load_date IS NULL SET @DT_load_date = CAST(GETDATE() AS DATE);

    -- Step 1: Expire changed rows
    UPDATE d
    SET d.DT_expiry_date        = DATEADD(DAY, -1, @DT_load_date),
        d.BT_is_current         = 0,
        d.DT_load_timestamp     = GETDATE()
    FROM staging.Territory_Dim d
    INNER JOIN (
        SELECT
            TerritoryID,
            CHECKSUM(Name, CountryRegionCode, [Group], SalesYTD, SalesLastYear) AS new_checksum
        FROM Sales.SalesTerritory
    ) src ON d.INT_territory_id = src.TerritoryID
          AND d.BT_is_current = 1
          AND d.NM_checksum_val <> CONVERT(VARBINARY(32), src.new_checksum);

    -- Step 2: Insert new or changed rows
    INSERT INTO staging.Territory_Dim (
        INT_territory_id, NM_territory_name, NM_country_region_code,
        NM_territory_group, DC_sales_ytd, DC_sales_last_year,
        DT_effective_date, DT_expiry_date, BT_is_current,
        NM_checksum_val, DT_load_timestamp, NM_batch_id
    )
    SELECT
        st.TerritoryID,
        st.Name,
        st.CountryRegionCode,
        st.[Group],
        CAST(st.SalesYTD AS DECIMAL(18,2)),
        CAST(st.SalesLastYear AS DECIMAL(18,2)),
        @DT_load_date,
        '9999-12-31',
        1,
        CONVERT(VARBINARY(32), CHECKSUM(
            st.Name, st.CountryRegionCode, st.[Group], st.SalesYTD, st.SalesLastYear
        )),
        GETDATE(),
        @NM_batch_id
    FROM Sales.SalesTerritory st
    WHERE NOT EXISTS (
        SELECT 1 FROM staging.Territory_Dim d
        WHERE d.INT_territory_id = st.TerritoryID
          AND d.BT_is_current = 1
          AND d.NM_checksum_val = CONVERT(VARBINARY(32), CHECKSUM(
              st.Name, st.CountryRegionCode, st.[Group], st.SalesYTD, st.SalesLastYear
          ))
    );

    PRINT 'Territory_Dim loaded. Batch: ' + @NM_batch_id;
END;
GO

-- =============================================
-- SP: Master dim loader
-- =============================================
CREATE PROCEDURE [etl].[sp_Load_Dims]
    @NM_batch_id    VARCHAR(50) = NULL,
    @DT_load_date   DATE = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @NM_batch_id IS NULL SET @NM_batch_id = 'DIM_' + CONVERT(VARCHAR, GETDATE(), 112);
    IF @DT_load_date IS NULL SET @DT_load_date = CAST(GETDATE() AS DATE);

    PRINT '=== Loading Staging Dimensions. Batch: ' + @NM_batch_id + ' ===';
    EXEC etl.sp_Load_ProductCategory_Dim    @NM_batch_id = @NM_batch_id, @DT_load_date = @DT_load_date;
    EXEC etl.sp_Load_Product_Dim            @NM_batch_id = @NM_batch_id, @DT_load_date = @DT_load_date;
    EXEC etl.sp_Load_Territory_Dim          @NM_batch_id = @NM_batch_id, @DT_load_date = @DT_load_date;
    PRINT '=== Dimensions loaded successfully ===';
END;
GO
