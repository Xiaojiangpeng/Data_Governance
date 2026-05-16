-- =============================================
-- OLTP SOURCE TABLES (AdventureWorks)
-- Reference only — no prefix convention
-- These are source system tables we do not own
-- =============================================

-- Source: Product master
CREATE TABLE [Production].[Product] (
    ProductID               INT             NOT NULL,
    Name                    NVARCHAR(50)    NOT NULL,
    ProductNumber           NVARCHAR(25)    NOT NULL,
    StandardCost            MONEY           NOT NULL,
    ListPrice               MONEY           NOT NULL,
    SafetyStockLevel        SMALLINT        NOT NULL,
    ReorderPoint            SMALLINT        NOT NULL,
    FinishedGoodsFlag       BIT             NOT NULL,
    Color                   NVARCHAR(15),
    Size                    NVARCHAR(5),
    Weight                  DECIMAL(8,2),
    ProductSubcategoryID    INT,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Product subcategory
CREATE TABLE [Production].[ProductSubcategory] (
    ProductSubcategoryID    INT             NOT NULL,
    ProductCategoryID       INT             NOT NULL,
    Name                    NVARCHAR(50)    NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Product category
CREATE TABLE [Production].[ProductCategory] (
    ProductCategoryID       INT             NOT NULL,
    Name                    NVARCHAR(50)    NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Sales territory
CREATE TABLE [Sales].[SalesTerritory] (
    TerritoryID             INT             NOT NULL,
    Name                    NVARCHAR(50)    NOT NULL,
    CountryRegionCode       NVARCHAR(3)     NOT NULL,
    [Group]                 NVARCHAR(50)    NOT NULL,
    SalesYTD                MONEY           NOT NULL,
    SalesLastYear           MONEY           NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Sales order header
CREATE TABLE [Sales].[SalesOrderHeader] (
    SalesOrderID            INT             NOT NULL,
    RevisionNumber          TINYINT         NOT NULL,
    OrderDate               DATETIME        NOT NULL,
    DueDate                 DATETIME        NOT NULL,
    ShipDate                DATETIME,
    Status                  TINYINT         NOT NULL,
    CustomerID              INT             NOT NULL,
    SalesPersonID           INT,
    TerritoryID             INT,
    SubTotal                MONEY           NOT NULL,
    TaxAmt                  MONEY           NOT NULL,
    Freight                 MONEY           NOT NULL,
    TotalDue                MONEY           NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Sales order detail
CREATE TABLE [Sales].[SalesOrderDetail] (
    SalesOrderID            INT             NOT NULL,
    SalesOrderDetailID      INT             NOT NULL,
    OrderQty                SMALLINT        NOT NULL,
    ProductID               INT             NOT NULL,
    UnitPrice               MONEY           NOT NULL,
    UnitPriceDiscount       MONEY           NOT NULL,
    LineTotal               DECIMAL(38,6)   NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Product inventory
CREATE TABLE [Production].[ProductInventory] (
    ProductID               INT             NOT NULL,
    LocationID              SMALLINT        NOT NULL,
    Shelf                   NCHAR(10)       NOT NULL,
    Bin                     TINYINT         NOT NULL,
    Quantity                SMALLINT        NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO

-- Source: Location
CREATE TABLE [Production].[Location] (
    LocationID              SMALLINT        NOT NULL,
    Name                    NVARCHAR(50)    NOT NULL,
    ModifiedDate            DATETIME        NOT NULL
);
GO
