-- ============================================================
-- C1300S1 | STN Lab — Estimated vs Actual Rows
-- Statistics, Cardinality Estimation & Stale Histograms
-- SQL Server 2017 / 2022
-- ============================================================
-- Demonstrates how stale statistics cause cardinality estimation
-- failures, leading to suboptimal plan choices. Uses a bulk
-- insert of skewed data to simulate a nightly declaration load
-- in STN — a common pattern in tax systems.
-- Run with Actual Execution Plan enabled (Ctrl+M).
-- ============================================================

USE STN_Lab;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- ============================================================
-- 3.1: BASELINE — statistics current, estimation accurate
-- Expected: Estimated Rows ≈ Actual Rows
-- ============================================================

SELECT COUNT(*) FROM dbo.Contribuyente WHERE TipoPersona = 'I';

GO

-- ============================================================
-- 3.2: SKEWED BULK INSERT — simulate nightly IVA load
-- 50,000 declarations, all PeriodoFiscal = '2024-12', TipoImpuestoID = 2
-- Statistics on PeriodoFiscal are now stale for this value
-- ============================================================

INSERT INTO dbo.Declaracion
    (DeclaracionID, ContribuyenteID, TipoImpuestoID, PeriodoFiscal,
     FechaPresentacion, MontoDeclarado, MontoImpuesto, Estado, UsuarioRegistro)
SELECT TOP 50000
    1500001 + ROW_NUMBER() OVER (ORDER BY (SELECT NULL)),
    (ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 200000) + 1,
    2,
    '2024-12',
    DATEADD(HOUR, ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) % 720, '2024-12-01'),
    CAST(RAND(CHECKSUM(NEWID())) * 100000 + 1000 AS DECIMAL(18,2)),
    CAST(RAND(CHECKSUM(NEWID())) * 12000 + 120  AS DECIMAL(18,2)),
    'PR',
    'CARGA_DIC'
FROM sys.all_columns a CROSS JOIN sys.all_columns b;
GO

-- Query with stale statistics — observe Estimated vs Actual rows
-- Optimizer will underestimate based on old histogram
SELECT
    d.DeclaracionID,
    d.MontoImpuesto,
    c.RazonSocial
FROM dbo.Declaracion d
    INNER JOIN dbo.Contribuyente c ON d.ContribuyenteID = c.ContribuyenteID
WHERE d.PeriodoFiscal = '2024-12'
  AND d.TipoImpuestoID = 2;

GO

-- ============================================================
-- 3.3: UPDATE STATISTICS — observe plan change
-- Expected: Estimated Rows converges to Actual Rows
-- ============================================================

UPDATE STATISTICS dbo.Declaracion WITH FULLSCAN;
GO

SELECT
    d.DeclaracionID,
    d.MontoImpuesto,
    c.RazonSocial
FROM dbo.Declaracion d
    INNER JOIN dbo.Contribuyente c ON d.ContribuyenteID = c.ContribuyenteID
WHERE d.PeriodoFiscal = '2024-12'
  AND d.TipoImpuestoID = 2;

GO

-- ============================================================
-- 3.4: STATISTICS HEALTH CHECK — last update and modification counter
-- High modification_counter + old last_updated = stale statistics
-- In STN: nightly bulk loads require statistics update post-load
-- ============================================================

SELECT
    OBJECT_NAME(s.object_id)    AS TableName,
    s.name                      AS StatName,
    sp.last_updated,
    sp.rows,
    sp.rows_sampled,
    CAST(100.0 * sp.rows_sampled / NULLIF(sp.rows,0) AS DECIMAL(5,2)) AS SamplePct,
    sp.modification_counter
FROM sys.stats s
CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
WHERE OBJECT_NAME(s.object_id) IN ('Contribuyente','Declaracion','Pago','AuditoriaFiscal')
ORDER BY sp.modification_counter DESC;

GO

-- ============================================================
-- 3.5: COMPATIBILITY LEVEL AND CARDINALITY ESTIMATOR
-- SQL Server 2017: CE120 default | SQL Server 2022: CE160 default
-- CE160 handles column correlation better — useful for STN queries
-- filtering on multiple correlated columns simultaneously
-- ============================================================

SELECT name, compatibility_level
FROM sys.databases
WHERE name = 'STN_Lab';
GO

-- Force legacy CE for comparison (2017+)
SELECT
    d.PeriodoFiscal,
    COUNT(*)             AS TotalDeclaraciones,
    SUM(d.MontoImpuesto) AS TotalImpuesto
FROM dbo.Declaracion d
    INNER JOIN dbo.Contribuyente c ON d.ContribuyenteID = c.ContribuyenteID
WHERE c.TipoPersona = 'J'
  AND d.Estado = 'PR'
GROUP BY d.PeriodoFiscal
OPTION (USE HINT('FORCE_LEGACY_CARDINALITY_ESTIMATION'));

-- Run without hint and compare estimated rows per operator
SELECT
    d.PeriodoFiscal,
    COUNT(*)             AS TotalDeclaraciones,
    SUM(d.MontoImpuesto) AS TotalImpuesto
FROM dbo.Declaracion d
    INNER JOIN dbo.Contribuyente c ON d.ContribuyenteID = c.ContribuyenteID
WHERE c.TipoPersona = 'J'
  AND d.Estado = 'PR'
GROUP BY d.PeriodoFiscal;

GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
