-- ============================================================
-- C1300S1 | STN Lab — Statistics IO / TIME & Implicit Conversions
-- Logical Reads Interpretation, Sort Spills, Implicit Conversion
-- SQL Server 2017 / 2022
-- ============================================================
-- Covers correct interpretation of SET STATISTICS IO output,
-- the silent performance killer of implicit type conversions,
-- and Sort operator spills to TempDB.
-- Run with Actual Execution Plan enabled (Ctrl+M).
-- ============================================================

USE STN_Lab;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- ============================================================
-- 5.1: COLD vs WARM CACHE — physical vs logical reads
-- Run twice. Physical reads drop to 0 on second execution.
-- Optimize logical reads, not physical reads.
-- ============================================================

-- WARNING: DBCC DROPCLEANBUFFERS is for lab use only — never in production
DBCC DROPCLEANBUFFERS;
GO

-- First execution — cold cache
SELECT
    c.DepartamentoID,
    COUNT(DISTINCT c.ContribuyenteID)   AS TotalContribuyentes,
    SUM(d.MontoImpuesto)                AS TotalImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE d.PeriodoFiscal = '2022-06'
GROUP BY c.DepartamentoID
ORDER BY TotalImpuesto DESC;

-- Second execution — warm cache (same query)
SELECT
    c.DepartamentoID,
    COUNT(DISTINCT c.ContribuyenteID)   AS TotalContribuyentes,
    SUM(d.MontoImpuesto)                AS TotalImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE d.PeriodoFiscal = '2022-06'
GROUP BY c.DepartamentoID
ORDER BY TotalImpuesto DESC;

GO

-- ============================================================
-- 5.2: IMPLICIT CONVERSION — index bypass on NIT column
-- NIT is VARCHAR(20). Passing an integer forces CONVERT_IMPLICIT
-- on every row, making the index on NIT completely useless.
-- ============================================================

-- Correct: VARCHAR parameter — uses index
SELECT ContribuyenteID, NIT, RazonSocial
FROM dbo.Contribuyente
WHERE NIT = '8000007';

-- Implicit conversion: INT parameter — index bypassed, Table Scan
SELECT ContribuyenteID, NIT, RazonSocial
FROM dbo.Contribuyente
WHERE NIT = 8000007;

GO

-- ============================================================
-- 5.3: DETECT IMPLICIT CONVERSIONS IN CACHE
-- Run against production to find this pattern across all queries
-- ============================================================

SELECT DISTINCT
    OBJECT_NAME(qp.objectid)    AS ObjectName,
    SUBSTRING(st.text, 1, 200)  AS QueryText
FROM sys.dm_exec_cached_plans cp
CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) qp
CROSS APPLY sys.dm_exec_sql_text(cp.plan_handle) st
WHERE CAST(qp.query_plan AS NVARCHAR(MAX)) LIKE '%CONVERT_IMPLICIT%'
  AND qp.dbid = DB_ID();

GO

-- ============================================================
-- 5.4: CORRELATED SUBQUERY vs JOIN — Spool operator
-- Correlated subquery executes once per outer row
-- Rewrite as JOIN to eliminate the Spool
-- ============================================================

-- With correlated subquery — watch for Table Spool in plan
SELECT
    c.ContribuyenteID,
    c.NIT,
    c.RazonSocial,
    (SELECT SUM(d.MontoImpuesto)
     FROM dbo.Declaracion d
     WHERE d.ContribuyenteID = c.ContribuyenteID
       AND d.Estado = 'PR') AS ImpuestoPendiente
FROM dbo.Contribuyente c
WHERE c.DepartamentoID = 3
  AND c.Estado = 'A';

-- Equivalent rewrite with JOIN — no Spool
SELECT
    c.ContribuyenteID,
    c.NIT,
    c.RazonSocial,
    SUM(d.MontoImpuesto)    AS ImpuestoPendiente
FROM dbo.Contribuyente c
    LEFT JOIN dbo.Declaracion d
        ON d.ContribuyenteID = c.ContribuyenteID
       AND d.Estado = 'PR'
WHERE c.DepartamentoID = 3
  AND c.Estado = 'A'
GROUP BY c.ContribuyenteID, c.NIT, c.RazonSocial;

GO

-- ============================================================
-- 5.5: SORT SPILL — ORDER BY on unindexed column
-- Sort materializes all rows before returning the first one
-- If memory grant insufficient: Spill to TempDB (worktable > 0)
-- ============================================================

SELECT
    c.NIT,
    c.RazonSocial,
    d.PeriodoFiscal,
    d.MontoImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE d.Estado = 'PR'
ORDER BY d.MontoImpuesto DESC;

-- If worktable > 0 in Statistics IO output → Sort spilled to TempDB
-- This is a memory grant or design issue

GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
