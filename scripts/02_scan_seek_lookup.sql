-- ============================================================
-- C1300S1 | STN Lab — Execution Plan Operators
-- Scan vs Seek vs Key Lookup vs Join Strategies
-- SQL Server 2017 / 2022
-- ============================================================
-- Demonstrates the cost progression from Table Scan to Covered
-- Index Seek, and the three main join operator types.
-- All exercises use the STN contributor and declaration tables.
-- Run with Actual Execution Plan enabled (Ctrl+M) and
-- SET STATISTICS IO / TIME ON for full visibility.
-- ============================================================

USE STN_Lab;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- ============================================================
-- 2.1: TABLE SCAN
-- No useful index on NIT — full table read on 200K rows
-- Expected: Table Scan or Clustered Index Scan, ~1,800 logical reads
-- ============================================================

SELECT ContribuyenteID, NIT, RazonSocial, Estado
FROM dbo.Contribuyente
WHERE NIT = '8000007';

GO

-- ============================================================
-- 2.2: INDEX SEEK + KEY LOOKUP
-- Nonclustered index on NIT exists, but SELECT requests columns
-- not included in the index — forces a Key Lookup per row
-- Expected: Index Seek → Nested Loops → Key Lookup, ~6 logical reads
-- ============================================================

ALTER TABLE dbo.Contribuyente DROP CONSTRAINT PK_Contribuyente;
GO
ALTER TABLE dbo.Contribuyente
    ADD CONSTRAINT PK_Contribuyente PRIMARY KEY CLUSTERED (ContribuyenteID);
GO
CREATE NONCLUSTERED INDEX IX_Contribuyente_NIT
    ON dbo.Contribuyente (NIT);
GO

SELECT ContribuyenteID, NIT, RazonSocial, Estado
FROM dbo.Contribuyente
WHERE NIT = '8000007';

-- Key Lookup occurs because RazonSocial and Estado are not in IX_NIT
-- Output List in the Key Lookup node identifies the offending columns

GO

-- ============================================================
-- 2.3: COVERED INDEX — Key Lookup eliminated
-- Adding required columns to INCLUDE removes the lookup entirely
-- Expected: Index Seek only, ~3 logical reads
-- ============================================================

CREATE NONCLUSTERED INDEX IX_Contribuyente_NIT_Covering
    ON dbo.Contribuyente (NIT)
    INCLUDE (RazonSocial, Estado);
GO

SELECT ContribuyenteID, NIT, RazonSocial, Estado
FROM dbo.Contribuyente
WHERE NIT = '8000007';

-- All requested columns now satisfied within the index
-- No Key Lookup, no additional I/O per row

GO

-- ============================================================
-- 2.4a: NESTED LOOPS — small lookup table
-- Optimal when one side is small and the other has an index
-- TipoImpuesto has 6 rows — Nested Loops is correct here
-- ============================================================

SELECT
    d.DeclaracionID,
    d.PeriodoFiscal,
    d.MontoImpuesto,
    t.Descripcion
FROM dbo.Declaracion d
    INNER JOIN dbo.TipoImpuesto t ON d.TipoImpuestoID = t.TipoImpuestoID
WHERE d.DeclaracionID BETWEEN 1 AND 100;

GO

-- ============================================================
-- 2.4b: HASH MATCH — large tables, no index on join key
-- SQL Server builds an in-memory hash table from one input
-- Watch for Tempdb Spill warning (yellow triangle on Hash node)
-- ============================================================

SELECT
    c.NIT,
    c.RazonSocial,
    COUNT(d.DeclaracionID)      AS TotalDeclaraciones,
    SUM(d.MontoImpuesto)        AS TotalImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE c.DepartamentoID = 5
GROUP BY c.NIT, c.RazonSocial;

GO

-- ============================================================
-- 2.4c: INDEX ON JOIN KEY — observe plan change
-- Adding index on ContribuyenteID may shift Hash Match to Merge Join
-- ============================================================

CREATE NONCLUSTERED INDEX IX_Declaracion_ContribuyenteID
    ON dbo.Declaracion (ContribuyenteID)
    INCLUDE (MontoImpuesto, PeriodoFiscal, Estado);
GO

SELECT
    c.NIT,
    c.RazonSocial,
    COUNT(d.DeclaracionID)      AS TotalDeclaraciones,
    SUM(d.MontoImpuesto)        AS TotalImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE c.DepartamentoID = 5
GROUP BY c.NIT, c.RazonSocial;

GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
