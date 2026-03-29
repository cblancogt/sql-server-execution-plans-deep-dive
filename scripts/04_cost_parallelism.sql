-- ============================================================
-- C1300S1 | STN Lab — Cost Thresholds & Parallelism
-- Serial vs Parallel Plans, MAXDOP, DOP Feedback (2022)
-- SQL Server 2017 / 2022
-- ============================================================
-- Demonstrates how the cost threshold for parallelism controls
-- plan selection, and the performance trade-offs between serial
-- and parallel execution in an OLTP financial system.
-- Run with Actual Execution Plan enabled (Ctrl+M).
-- ============================================================

USE STN_Lab;
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

-- ============================================================
-- 4.1: CURRENT PARALLELISM CONFIGURATION
-- cost threshold for parallelism default = 5 (too low for OLTP)
-- Recommended for financial OLTP: 25–50
-- ============================================================

SELECT name, value_in_use, description
FROM sys.configurations
WHERE name IN (
    'cost threshold for parallelism',
    'max degree of parallelism',
    'max server memory (MB)'
)
ORDER BY name;

GO

-- ============================================================
-- 4.2: SERIAL PLAN — low cost, below threshold
-- Expected: single-thread execution, no parallelism operators
-- ============================================================

SELECT ContribuyenteID, NIT, RazonSocial, Estado
FROM dbo.Contribuyente
WHERE ContribuyenteID BETWEEN 1 AND 100;

GO

-- ============================================================
-- 4.3: PARALLEL PLAN — high cost aggregation
-- Expected: Parallelism (Gather Streams / Distribute Streams)
-- Watch for uneven thread distribution — indicates data skew
-- ============================================================

SELECT
    c.TipoPersona,
    c.DepartamentoID,
    t.Descripcion                       AS TipoImpuesto,
    d.Estado                            AS EstadoDeclaracion,
    COUNT(DISTINCT c.ContribuyenteID)   AS TotalContribuyentes,
    COUNT(d.DeclaracionID)              AS TotalDeclaraciones,
    SUM(d.MontoImpuesto)                AS TotalImpuesto,
    AVG(d.MontoDeclarado)               AS PromedioDeclarado,
    MAX(d.FechaPresentacion)            AS UltimaPresentacion
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d    ON c.ContribuyenteID = d.ContribuyenteID
    INNER JOIN dbo.TipoImpuesto t   ON d.TipoImpuestoID  = t.TipoImpuestoID
WHERE d.FechaPresentacion >= '2022-01-01'
GROUP BY c.TipoPersona, c.DepartamentoID, t.Descripcion, d.Estado
ORDER BY TotalImpuesto DESC;

GO

-- ============================================================
-- 4.4: FORCE SERIAL — MAXDOP 1 vs default for comparison
-- If MAXDOP 1 is faster: coordination overhead exceeds benefit
-- This justifies raising cost threshold for parallelism in STN
-- ============================================================

-- Serial
SELECT
    c.TipoPersona,
    c.DepartamentoID,
    COUNT(d.DeclaracionID)  AS TotalDeclaraciones,
    SUM(d.MontoImpuesto)    AS TotalImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE d.FechaPresentacion >= '2022-01-01'
GROUP BY c.TipoPersona, c.DepartamentoID
OPTION (MAXDOP 1);

-- Parallel (default DOP)
SELECT
    c.TipoPersona,
    c.DepartamentoID,
    COUNT(d.DeclaracionID)  AS TotalDeclaraciones,
    SUM(d.MontoImpuesto)    AS TotalImpuesto
FROM dbo.Contribuyente c
    INNER JOIN dbo.Declaracion d ON c.ContribuyenteID = d.ContribuyenteID
WHERE d.FechaPresentacion >= '2022-01-01'
GROUP BY c.TipoPersona, c.DepartamentoID
OPTION (MAXDOP 0);

GO

-- ============================================================
-- 4.5: TOP QUERIES BY COST IN CACHE
-- Useful for identifying parallelism candidates in production
-- ============================================================

SELECT TOP 10
    qs.total_elapsed_time / qs.execution_count / 1000.0  AS AvgElapsed_ms,
    qs.total_logical_reads / qs.execution_count          AS AvgLogicalReads,
    qs.execution_count,
    SUBSTRING(st.text, (qs.statement_start_offset/2)+1,
        ((CASE qs.statement_end_offset
            WHEN -1 THEN DATALENGTH(st.text)
            ELSE qs.statement_end_offset
          END - qs.statement_start_offset)/2)+1)         AS QueryText
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.dbid = DB_ID('STN_Lab')
ORDER BY qs.total_elapsed_time DESC;

GO

-- ============================================================
-- 4.6: DOP FEEDBACK — SQL Server 2022 only
-- Run the heavy query 3 times and observe if DOP adjusts
-- Look for "DegreeOfParallelismFeedback" in plan XML
-- ============================================================

SELECT
    qs.execution_count,
    qs.total_logical_reads / qs.execution_count AS AvgLogicalReads,
    qs.min_grant_kb,
    qs.max_grant_kb,
    qs.last_grant_kb,
    SUBSTRING(st.text, 1, 100) AS QuerySnippet
FROM sys.dm_exec_query_stats qs
CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) st
WHERE st.dbid = DB_ID('STN_Lab')
  AND st.text LIKE '%TotalImpuesto%'
ORDER BY qs.last_execution_time DESC;

GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO
