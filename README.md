# SQL Server Execution Plans - architecture
> **Architecture Master Plan · Week C1300S1**  
> From SQL Server DBA to Data Architect | STN Government System Case Study

---

## Overview

This repository documents a hands-on deep dive into SQL Server execution plans using a simulated **STN (Sistema Tributario Nacional)** — a high-volume government system processing 1.5M+ tax declarations. The goal is not just to understand execution plans theoretically, but to apply them in the context of a real legacy system and draw architectural conclusions.

**System context:** STN is simulated on SQL Server 2022 lab environment. The lab replicates the scale and structure of a real high-volume tax system to practice architecture, diagnosis, and optimization decisions.

---

## Problem Statement

In high-volume transactional systems like STN, poorly optimized queries can cascade into:

- 15+ minute reporting windows that degrade OLTP performance
- Undetected table scans reading millions of pages on every execution
- Parameter sniffing issues causing unpredictable performance under load
- Implicit conversion bugs that silently bypass indexes

Without a structured methodology to read and act on execution plans, these problems are diagnosed by luck — not by design.

---

## What's Covered

| Script | Topic |
|--------|-------|
| `01_stn_setup.sql` | Lab setup: 200K contributors, 1.5M declarations, 1.2M payments |
| `02_scan_seek_lookup.sql` | Table Scan, Index Seek, Covered Index, Join Operators |
| `03_estimated_vs_actual.sql` | Stale statistics, cardinality estimation failures, statistics health |
| `04_cost_parallelism.sql` | Cost threshold for parallelism, MAXDOP, serial vs parallel plans |
| `05_statistics_io_time.sql` | Implicit conversions, Sort spills, IO interpretation |

---

## Key Concepts Demonstrated

### Operator Hierarchy (Cost to Benefit)
```
Index Seek           : Cheapest. 1-3 logical reads for any selectivity.
Index Scan           : Reads the entire index. Acceptable if index is narrow.
Table/Clustered Scan : Reads every data page. Avoid for selective filters.
Key Lookup           : 1 random I/O per row. Deadly at scale. Eliminate with INCLUDE.
RID Lookup           : Same as Key Lookup on heap tables — no clustered index.
Hash Match           : Memory-intensive. Watch for tempdb spills.
Merge Join           : Efficient when both sources arrive ordered by join key.
Nested Loops         : Optimal when one table is small with an index on the inner.
Adaptive Join        : SQL Server 2019+ decides join strategy at runtime.
Sort                 : Materializes all rows before returning first. Blocks streaming.
```

### Validated Results — STN Lab

**Scan vs Seek vs Covered Index (dbo.Contribuyente, 200K rows):**
```
Table Scan (no index)    : 1,302 logical reads  77ms
Index Seek + Key Lookup  :     6 logical reads  38ms
Covered Index Seek       :     3 logical reads   1ms

Improvement: 434x fewer logical reads
```

**MAXDOP 1 vs MAXDOP 0 (warm cache):**
```
MAXDOP 1 (serial)    : CPU 16ms  Elapsed 15ms
MAXDOP 0 (parallel)  : CPU 16ms  Elapsed 35ms

Serial was faster — parallelism coordination overhead exceeded the benefit.
```

**Sort Spill — ORDER BY on 1,275,000 rows:**
```
Spill Level    : 8 (severe)
Pages to TempDB: 8,781
Memory granted : 53,504KB
Memory used    : 53,632KB (exceeded grant by 128KB)
```

**Statistics — UPDATE STATISTICS impact:**
```
Cardinality error before : 237%
Cardinality error after  : 227%
Elapsed time before      : 93ms
Elapsed time after       : 40ms
Table Scan persisted — statistics improve estimates, not missing indexes.
```

---

## How to Use This Repository
```bash
# 1. Adjust the file path in 01_stn_setup.sql to match the local SQL Server data directory
# 2. Execute 01_stn_setup.sql to create the lab database
# 3. Run each script in order with Actual Execution Plan enabled (Ctrl+M in SSMS)
```

**Requirements:**
- SQL Server 2022
- SSMS 19+ with Sentry Plan for plan visualization
- ~2GB disk space for the lab database

---

## About This Repository

This repository is part of a structured architecture practice program focused on SQL Server internals, performance diagnosis, and cloud migration patterns. All systems used (STN, GOVCORE, ENERGRID, TRANSTRACK, LEXNOVA) are simulated legacy environments designed to practice real-world architecture, diagnosis, and modernization decisions at scale.

---

*One step at a time*