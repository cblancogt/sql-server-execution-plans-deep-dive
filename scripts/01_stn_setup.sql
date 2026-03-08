-- ============================================================
-- SCRIPT 01: STN LAB SETUP
-- Sistema Tributario Nacional — Simulación de entorno financiero
-- Compatible: SQL Server 2017 / 2022
-- Validación: Carlos Roberto Blanco Osoy
-- ============================================================

USE master;
GO

IF DB_ID('STN_Lab') IS NOT NULL
BEGIN
    ALTER DATABASE STN_Lab SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE STN_Lab;
END
GO

CREATE DATABASE STN_Lab
ON PRIMARY (
    NAME = STN_Lab_Data,
    FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.LAB_DB\MSSQL\DATA\STN_Lab.mdf',
    SIZE = 512MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 128MB
)
LOG ON (
    NAME = STN_Lab_Log,
    FILENAME = 'C:\Program Files\Microsoft SQL Server\MSSQL16.LAB_DB\MSSQL\DATA\STN_Lab.ldf',
    SIZE = 128MB,
    FILEGROWTH = 64MB
);
GO

-- NOTA: Modificar el path C:\SQLData\ acorde al ambiente
-- Como ver Path: SELECT physical_name FROM sys.database_files WHERE file_id = 1

USE STN_Lab;
GO

CREATE TABLE dbo.Contribuyente (
    ContribuyenteID     INT             NOT NULL,
    NIT                 VARCHAR(20)     NOT NULL,
    RazonSocial         VARCHAR(200)    NOT NULL,
    TipoPersona         CHAR(1)         NOT NULL,
    DepartamentoID      SMALLINT        NOT NULL,
    FechaRegistro       DATE            NOT NULL,
    Estado              CHAR(1)         NOT NULL
);
GO

CREATE TABLE dbo.Declaracion (
    DeclaracionID       INT             NOT NULL,
    ContribuyenteID     INT             NOT NULL,
    TipoImpuestoID      SMALLINT        NOT NULL,
    PeriodoFiscal       CHAR(7)         NOT NULL,
    FechaPresentacion   DATETIME2(3)    NOT NULL,
    MontoDeclarado      DECIMAL(18,2)   NOT NULL,
    MontoImpuesto       DECIMAL(18,2)   NOT NULL,
    Estado              CHAR(2)         NOT NULL,
    UsuarioRegistro     VARCHAR(50)     NOT NULL,
    FechaCreacion       DATETIME2(3)    NOT NULL DEFAULT SYSDATETIME()
);
GO

CREATE TABLE dbo.Pago (
    PagoID              BIGINT          NOT NULL,
    DeclaracionID       INT             NOT NULL,
    ContribuyenteID     INT             NOT NULL,
    FechaPago           DATETIME2(3)    NOT NULL,
    MontoPagado         DECIMAL(18,2)   NOT NULL,
    MediosPago          VARCHAR(20)     NOT NULL,
    NumeroReferencia    VARCHAR(50)     NOT NULL,
    BancoID             SMALLINT        NOT NULL
);
GO

CREATE TABLE dbo.AuditoriaFiscal (
    AuditoriaID         INT             NOT NULL,
    ContribuyenteID     INT             NOT NULL,
    DeclaracionID       INT             NOT NULL,
    FechaInicio         DATE            NOT NULL,
    FechaCierre         DATE            NULL,
    AuditorID           INT             NOT NULL,
    DiferenciaDeterminada DECIMAL(18,2) NOT NULL DEFAULT 0,
    Estado              VARCHAR(20)     NOT NULL
);
GO

CREATE TABLE dbo.TipoImpuesto (
    TipoImpuestoID      SMALLINT        NOT NULL,
    Codigo              VARCHAR(10)     NOT NULL,
    Descripcion         VARCHAR(100)    NOT NULL,
    TasaBase            DECIMAL(8,4)    NOT NULL
);
GO

-- ============================================================
-- CARGA DE DATOS
-- ============================================================

INSERT INTO dbo.TipoImpuesto VALUES
(1, 'ISR',   'Impuesto Sobre la Renta',          0.25),
(2, 'IVA',   'Impuesto al Valor Agregado',        0.12),
(3, 'IUSI',  'Impuesto Único Sobre Inmuebles',    0.009),
(4, 'ISO',   'Impuesto de Solidaridad',           0.01),
(5, 'IETAP', 'Impuesto Específico sobre Tabaco',  0.75),
(6, 'IPRIMA','Impuesto sobre Primas de Seguros',  0.03);
GO

-- Contribuyentes: 200,000
;WITH
L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
L1 AS (SELECT 1 AS c FROM L0 a, L0 b),
L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
L4 AS (SELECT 1 AS c FROM L3 a, L3 b),
L5 AS (SELECT 1 AS c FROM L4 a, L4 b),
Nums AS (SELECT TOP 200000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM L5)
INSERT INTO dbo.Contribuyente
SELECT
    n,
    CAST(n * 7 + 1000000 AS VARCHAR(20)),
    'CONTRIBUYENTE ' + CAST(n AS VARCHAR(10)),
    CASE WHEN n % 3 = 0 THEN 'J' ELSE 'I' END,
    CAST((n % 22) + 1 AS SMALLINT),
    DATEADD(DAY, -(n % 3650), '2024-01-01'),
    CASE WHEN n % 20 = 0 THEN 'I'
         WHEN n % 50 = 0 THEN 'S'
         ELSE 'A' END
FROM Nums;
GO

-- Declaraciones: 1,500,000
;WITH
L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
L1 AS (SELECT 1 AS c FROM L0 a, L0 b),
L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
L4 AS (SELECT 1 AS c FROM L3 a, L3 b),
L5 AS (SELECT 1 AS c FROM L4 a, L4 b),
Nums AS (SELECT TOP 1500000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM L5)
INSERT INTO dbo.Declaracion
    (DeclaracionID, ContribuyenteID, TipoImpuestoID, PeriodoFiscal,
     FechaPresentacion, MontoDeclarado, MontoImpuesto, Estado, UsuarioRegistro)
SELECT
    n,
    (n % 200000) + 1,
    CAST((n % 6) + 1 AS SMALLINT),
    CAST(2020 + (n % 4) AS VARCHAR(4)) + '-'
        + RIGHT('0' + CAST((n % 12) + 1 AS VARCHAR(2)), 2),
    DATEADD(SECOND, n, '2020-01-01 08:00:00'),
    CAST((n % 500000) + 1000 AS DECIMAL(18,2)),
    CAST(((n % 500000) + 1000) * 0.12 AS DECIMAL(18,2)),
    CASE WHEN n % 15 = 0 THEN 'OM'
         WHEN n % 8  = 0 THEN 'AU'
         ELSE 'PR' END,
    'SISTEMA'
FROM Nums;
GO

-- Pagos: 1,200,000
;WITH
L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
L1 AS (SELECT 1 AS c FROM L0 a, L0 b),
L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
L4 AS (SELECT 1 AS c FROM L3 a, L3 b),
L5 AS (SELECT 1 AS c FROM L4 a, L4 b),
Nums AS (SELECT TOP 1200000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM L5)
INSERT INTO dbo.Pago
    (PagoID, DeclaracionID, ContribuyenteID, FechaPago,
     MontoPagado, MediosPago, NumeroReferencia, BancoID)
SELECT
    n,
    (n % 1500000) + 1,
    (n % 200000) + 1,
    DATEADD(DAY, n % 1460, '2020-01-15'),
    CAST((n % 100000) + 500 AS DECIMAL(18,2)),
    CASE n % 3
        WHEN 0 THEN 'BANCO'
        WHEN 1 THEN 'ONLINE'
        ELSE 'VENTANILLA' END,
    'REF-' + CAST(n * 13 AS VARCHAR(15)),
    CAST((n % 15) + 1 AS SMALLINT)
FROM Nums;
GO

-- Auditorías: 50,000
;WITH
L0 AS (SELECT 1 AS c UNION ALL SELECT 1),
L1 AS (SELECT 1 AS c FROM L0 a, L0 b),
L2 AS (SELECT 1 AS c FROM L1 a, L1 b),
L3 AS (SELECT 1 AS c FROM L2 a, L2 b),
L4 AS (SELECT 1 AS c FROM L3 a, L3 b),
L5 AS (SELECT 1 AS c FROM L4 a, L4 b),
Nums AS (SELECT TOP 50000 ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS n FROM L5)
INSERT INTO dbo.AuditoriaFiscal
    (AuditoriaID, ContribuyenteID, DeclaracionID, FechaInicio,
     FechaCierre, AuditorID, DiferenciaDeterminada, Estado)
SELECT
    n,
    (n % 200000) + 1,
    (n % 1500000) + 1,
    DATEADD(DAY, n % 1000, '2021-01-01'),
    CASE WHEN n % 5 = 0 THEN NULL
         ELSE DATEADD(DAY, (n % 1000) + 90, '2021-01-01') END,
    (n % 50) + 1,
    CAST((n % 250000) AS DECIMAL(18,2)),
    CASE WHEN n % 5 = 0 THEN 'ABIERTA'
         WHEN n % 7 = 0 THEN 'APELADA'
         ELSE 'CERRADA' END
FROM Nums;
GO

-- ============================================================
-- CONSTRAINTS
-- ============================================================
ALTER TABLE dbo.Contribuyente   ADD CONSTRAINT PK_Contribuyente PRIMARY KEY NONCLUSTERED (ContribuyenteID);
ALTER TABLE dbo.TipoImpuesto    ADD CONSTRAINT PK_TipoImpuesto  PRIMARY KEY NONCLUSTERED (TipoImpuestoID);
ALTER TABLE dbo.Declaracion     ADD CONSTRAINT PK_Declaracion   PRIMARY KEY NONCLUSTERED (DeclaracionID);
ALTER TABLE dbo.Pago            ADD CONSTRAINT PK_Pago          PRIMARY KEY NONCLUSTERED (PagoID);
ALTER TABLE dbo.AuditoriaFiscal ADD CONSTRAINT PK_Auditoria     PRIMARY KEY NONCLUSTERED (AuditoriaID);
GO

PRINT '  STN_Lab creado exitosamente.';
PRINT '  Contribuyentes: 200,000';
PRINT '  Declaraciones:  1,500,000';
PRINT '  Pagos:          1,200,000';
PRINT '  Auditorías:     50,000';
GO