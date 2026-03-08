# SQL Server Execution Plans — Deep Dive

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
| `02_scan_seek_lookup.sql` | Table Scan, Index Seek, Covered Index progression |

---

## Key Concepts Demonstrated

### Operator Hierarchy (Cost to Benefit)
```
Index Seek           : Cheapest. 1-3 logical reads for any selectivity.
Index Scan           : Reads the entire index. Acceptable if index is narrow.
Table/Clustered Scan : Reads every data page. Avoid for selective filters.
Key Lookup           : 1 random I/O per row. Deadly at scale. Eliminate with INCLUDE.
Hash Match           : Memory-intensive. Watch for tempdb spills.
Sort                 : Materializes all rows before returning first. Blocks streaming.
Spool                : Optimizer saved an intermediate result. Often a design signal.
```

### Operators That Killed STN's Monday Report

The original reporting query used **4 correlated subqueries**, each executing once per active contributor (~160,000 active records):
```
Execution model (original):
  For each of 160,000 contributors:
    Table Scan on Declaracion (1.5M rows) x 2
    Table Scan on Pago (1.2M rows) x 1
    Table Scan on AuditoriaFiscal (50K rows) x 1

Total logical reads: ~1.2 billion pages
Execution time: 12-18 minutes
```

After rewrite + targeted indexes:
```
Execution model (optimized):
  1x aggregation pass on Declaracion (filtered index, 150K rows)
  1x aggregation pass on Pago (covered index)
  1x aggregation pass on AuditoriaFiscal (filtered index, 8K rows)
  Hash Join on aggregated results

Total logical reads: ~45,000 pages
Execution time: 4-8 seconds
Improvement: ~27,000x reduction in I/O
```

---

## How to Use This Repository
```bash
# 1. Create the lab database
sqlcmd -S your-server -E -i scripts/01_stn_setup.sql

# 2. Run each script in order with Actual Execution Plan enabled (Ctrl+M in SSMS)
```

---

## About This Repository

This repository is part of a structured architecture practice program focused on SQL Server internals, performance diagnosis, and cloud migration patterns. All systems used (STN, GOVCORE, ENERGRID, TRANSTRACK, LEXNOVA) are simulated legacy environments designed to practice real-world architecture, diagnosis, and modernization decisions at scale.

---

*One step at a time*