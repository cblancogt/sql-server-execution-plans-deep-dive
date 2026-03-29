# Observations Document - C1300S1
### Architecture Master Plan 2026–2027 | DBA - Data & Solutions Architect

**Date:** 29 March 2026
**System:** STN - Sistema Tributario Nacional (Government)
**Environment:** SQL Server 2022 · STN_Lab
**Block:** DATA ARCHITECTURE

---

## 1. Context

STN is a high-volume government tax system simulation running on SQL Server 2022 lab environment.
This week's focus - Execution Plans Deep Dive - was motivated by undiagnosed performance degradation in reporting queries running against the OLTP database.
In systems where data integrity and availability are legal requirements, understanding the optimizer's decisions is the difference between guesswork and structured diagnosis.

**Lab volumes:**

| Table | Records |
|-------|---------|
| Contribuyente | 200,000 |
| Declaracion | 1,550,000 (1,500,000 base + 50,000 bulk insert) |
| Pago | 1,200,000 |
| AuditoriaFiscal | 50,000 |

---

## 2. What to Learn

- Understand execution plan operators and their cost hierarchy in STN context
- Identify stale statistics and their impact on cardinality estimation
- Compare execution plan behavior across SQL Server features
- Document architectural decisions applicable to STN

---

## 3. Applications & Results

### 3.1 Scan vs Seek vs Covered Index

**Setup:** STN_Lab · dbo.Contribuyente · 200,000 rows · no useful index on NIT initially

**Executed:** Script 02 - three progressions on the same query

**Observed:**

| Metric | Table Scan | Seek + Key Lookup | Covered Index |
|--------|-----------|-------------------|---------------|
| Logical reads | 1,302 | 6 | 3 |
| Elapsed time (ms) | 77 | 38 | 1 |
| Dominant operator | Table Scan | Key Lookup (50%) | Index Seek |

**I/O reduction (Table Scan to Covered Index):** 434x fewer logical reads · 77x faster

**Key finding:**
The same query against 200,000 rows returned in 1ms with a covered index vs 77ms with a full table scan. The difference is not hardware - it is index design. Adding an INCLUDE clause to an existing index eliminated the Key Lookup entirely and reduced logical reads from 1,302 to 3 without any schema or application changes.

---

### 3.2 Join Operators - Nested Loops, Hash Match, Merge Join

**Setup:** STN_Lab · dbo.Declaracion (1.5M rows) · dbo.Contribuyente (200K rows) · dbo.TipoImpuesto (6 rows)

**Executed:** Script 02 - three join operator scenarios

**Observed:**

| Operator | Scenario | Cost | Decision |
|----------|----------|------|----------|
| Nested Loops | Declaracion (100 rows) JOIN TipoImpuesto (6 rows) | 0% | Correct - small inner table |
| Hash Match | Contribuyente JOIN Declaracion without index on join key | 90% Table Scan dominant | Necessary given missing index |
| Merge Join | Forced via hint - both sources ordered by ContribuyenteID | Index Scan 53% obligatory | Requires full index read to satisfy order requirement |

**Key finding:**
The optimizer chose correctly in all three cases given available structures. Hash Match dominated at 90% only because no index existed on ContribuyenteID in Declaracion. After creating IX_Declaracion_ContribuyenteID the plan shifted to Index Scan at 52% - same operator but reading the narrower index structure instead of full data pages, cutting elapsed time by half.

---

### 3.3 Estimated vs Actual Rows - Stale Statistics

**Setup:** STN_Lab · dbo.Declaracion · bulk insert of 50,000 skewed records simulating nightly IVA load (PeriodoFiscal = '2024-12', TipoImpuestoID = 2)

**Executed:** Script 03 - baseline, post-insert, post UPDATE STATISTICS

**Observed:**

| Scenario | Estimated Rows | Actual Rows | Error |
|----------|---------------|-------------|-------|
| Statistics current (baseline) | 133,333 | 133,334 | ~0% |
| Post bulk insert (stale) | 50,000 | 21,037 | 237% |
| Post UPDATE STATISTICS | 50,000 | 21,997 | 227% |

| Metric | Value |
|--------|-------|
| Elapsed time before UPDATE STATISTICS | 93ms |
| Elapsed time after UPDATE STATISTICS | 40ms |
| Table Scan persisted after UPDATE STATISTICS | YES |
| Spill warning observed | NO |

**Key finding:**
UPDATE STATISTICS reduced cardinality error from 237% to 227% and elapsed time from 93ms to 40ms. The Table Scan at 83% persisted because statistics improve optimizer estimates - they do not compensate for a missing index. Without an index on PeriodoFiscal and TipoImpuestoID, reading 1,550,000 rows is inevitable regardless of statistics accuracy.

---

### 3.4 Statistics Health Diagnostics

**Executed:** Script 03 - sys.dm_db_stats_properties diagnostic

**Observed:**

| Column | Result |
|--------|--------|
| modification_counter | 0 across all tables - statistics current |
| SamplePct Declaracion / Pago / AuditoriaFiscal | 100% |
| SamplePct Contribuyente (_WA_Sys entries) | 84–86% - partial sample |
| last_updated Declaracion | 2026-03-22 - reflects UPDATE STATISTICS from exercise 3.3 |

**Interpretation:**
modification_counter at 0 across all tables - no stale statistics at the time of diagnosis. Three automatic statistics entries on Contribuyente show partial sampling (84–86%). In a lab with static data this is not a problem, but in production with high daily transaction volume these entries would be candidates for UPDATE STATISTICS WITH FULLSCAN.

---

### 3.5 Cardinality Estimator - CE Legacy vs CE160

**Executed:** Script 03 - same query with and without FORCE_LEGACY_CARDINALITY_ESTIMATION hint

**Observed:** No observable difference between CE legacy and CE160 in this scenario. Both plans produced identical operators, costs, and row estimates.

**Conclusion:**
CE160 improvements in column correlation handling require non-uniform data distribution to manifest. With synthetic lab data generated through uniform formulas, the correlation between TipoPersona and Estado is artificial and CE160 cannot distinguish it from the legacy estimator.

---

### 3.6 Cost Threshold and Parallelism

**Setup:** STN_Lab configuration - cost threshold for parallelism: 5 · MAXDOP: 8

**Executed:** Script 04 - serial vs parallel plan comparison

**Observed:**

| Configuration | CPU time | Elapsed time | Behavior |
|---------------|----------|--------------|----------|
| MAXDOP 1 (serial) | 16ms | 15ms | CPU ≈ Elapsed - single thread |
| MAXDOP 0 (parallel) | 16ms | 35ms | CPU < Elapsed - coordination overhead visible |

**Key finding:**
MAXDOP 1 was faster on elapsed time. With warm cache and this data volume, the overhead of distributing and reuniting threads (35ms) exceeded the benefit of parallelism (15ms). In production with cold cache and high concurrent load the result inverts - parallelism becomes advantageous when the dataset is large enough to justify thread coordination cost.

**Plan 4.3 - Heavy aggregation operators observed:**

Table Scan Declaracion 89% - no index on FechaPresentacion, read 1,550,000 rows to filter those after 2022-01-01. Table Scan TipoImpuesto 0% - 6 rows, insignificant. Clustered Index Scan Contribuyente 9% - read all 200,000 records. Adaptive Join - SQL Server 2022 decided join strategy at runtime due to 250% estimation error on Contribuyente. Hash Match Aggregate - executed GROUP BY with COUNT, SUM, AVG, MAX. Sort - ordered by TotalImpuesto DESC before returning result. Parallelism Gather Streams - confirmed parallelism activation due to high Table Scan cost. Missing Index on FechaPresentacion - impact 71.87%, would eliminate the dominant Table Scan.

---

### 3.7 Implicit Conversion

**Setup:** dbo.Contribuyente · NIT column is VARCHAR(20)

**Executed:** Script 05 - same query with VARCHAR parameter vs INT parameter

**Observed:**

| Query | Operator | Logical reads |
|-------|----------|---------------|
| WHERE NIT = '8000007' (VARCHAR) | Index Seek | 3 |
| WHERE NIT = 8000007 (INT) | Table Scan | 1,087 |

**Key finding:**
Passing NIT as an integer forces CONVERT_IMPLICIT on every row, bypassing the index completely. The same lookup went from 3 logical reads to 1,087 - a 362x increase - with no code change other than removing the quotes. In STN this pattern is a risk wherever .NET form fields pass NIT as a numeric type to stored procedures.

---

### 3.8 Sort Spill

**Setup:** dbo.Contribuyente JOIN dbo.Declaracion · 1,275,000 rows · ORDER BY MontoImpuesto DESC

**Executed:** Script 05 - ORDER BY on unindexed column at scale

**Observed:**

| Metric | Value |
|--------|-------|
| Sort cost | 58% of total plan |
| Spill Level | 8 - severe |
| Pages written to TempDB | 8,781 |
| Pages read from TempDB | 8,781 |
| Memory granted | 53,504KB |
| Memory used | 53,632KB |
| Grant exceeded by | 128KB |
| Rows sorted | 1,275,000 |

**Key finding:**
ORDER BY on 1,275,000 rows without an ordered index forces the Sort operator to materialize all rows before returning the first one. The memory grant of 53,504KB fell short by 128KB - triggering a Spill Level 8, one of the most severe classifications. 8,781 pages were written to and read from TempDB, adding significant I/O. In production under concurrent load, multiple queries spilling simultaneously compress TempDB and compound the degradation.

---

## 4. SQL Server 2022 - Feature Observations

| Feature | Behavior | Observed |
|---------|----------|----------|
| Batch Mode on Rowstore | Available (compat 150+) - Execution Mode: Batch on aggregation query | YES |
| Adaptive Join | Runtime decision between Nested Loops and Hash Match | YES |
| Memory Grant Feedback | Persistent adjustment between executions | Not tested |
| Parameter Sensitive Plan | Multiple plans per parameter range | Not tested |

---

## 5. Architectural Conclusions

### Problem this topic solves

Without a structured methodology to read execution plans, performance diagnosis in STN relies on guesswork. Table Scans, Key Lookups, implicit conversions, and Sort spills are silent - they produce no errors. They degrade gradually until the system becomes unusable under load. A single INCLUDE clause eliminated 434x of unnecessary I/O. A single quote removed from a parameter eliminated 362x of unnecessary I/O. These are design decisions, not hardware problems.

### Architectural decision taken

**Decision:** Establish execution plan analysis as the mandatory first step in any STN performance investigation, before tuning queries, adding indexes, or increasing resources.

**Context:** STN processes high-volume tax declarations where reporting queries compete with transactional workloads on the same database. Performance degradation affects legal compliance deadlines.

**Rationale:** Every operator in the plan has a measurable cost. Reading the plan reveals the root cause in minutes. Without it, the same symptoms can be misattributed to hardware, network, or application layers indefinitely.

**Consequences:** Requires SSMS with Actual Execution Plan enabled and SET STATISTICS IO ON as standard practice. Introduces a structured diagnosis methodology applicable to all future performance incidents in STN.

### How I would explain this in an interview

"In high-volume financial systems like STN, execution plan analysis directly impacts the ability to diagnose performance under load. The key insight is that the optimizer makes all decisions based on what it knows - statistics, available indexes, data types - not on what the data actually contains. I validated this in the STN lab, where a 434x reduction in I/O was achieved on the same query simply by adding an INCLUDE clause, and a 362x reduction by correcting a parameter data type mismatch."

---

## 6. What's Next

**This feeds into:**
- C1300S2: Index Strategy - covered indexes built this week are the starting point
- C1300S11: Columnstore / HTAP - permanent solution to analytical queries on OLTP

---

## 7. References & Resources

- **GitHub repo:** https://github.com/cblancogt/sql-server-execution-plans-deep-dive
- **Evidence:** docs/evidence/ - detailed per-exercise technical documentation
- **Scripts used:** 01_stn_setup.sql · 02_scan_seek_lookup.sql · 03_estimated_vs_actual.sql · 04_cost_parallelism.sql · 05_statistics_io_time.sql

---