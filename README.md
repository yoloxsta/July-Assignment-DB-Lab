# PostgreSQL Performance Lab

A hands-on lab environment for DevOps engineers to learn PostgreSQL performance monitoring, tuning, and benchmarking.

## Quick Start

### Prerequisites
- Docker Desktop running
- Ports 5432 and 5050 available

### Start the Lab

```bash
# Start PostgreSQL and pgAdmin
docker-compose up -d

# Wait for containers to be healthy
docker-compose ps

# Check PostgreSQL logs
docker-compose logs postgres
```

### Connection Details

| Service | Host | Port | User | Password |
|---------|------|------|------|----------|
| PostgreSQL | localhost | 5432 | labuser | labpass |
| pgAdmin | localhost:5050 | 5050 | admin@example.com | admin |

## Lab Exercises & Results

### Exercise 1: Query Analysis with EXPLAIN

**Goal**: Learn to read query execution plans and identify bottlenecks.

```sql
-- Connect to database
docker exec -it pg-perf-lab psql -U labuser -d perflab

-- Basic EXPLAIN
EXPLAIN SELECT * FROM users WHERE email = 'user50000@example.com';

-- EXPLAIN ANALYZE (actually runs the query)
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user50000@example.com';

-- Detailed output with buffers
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) 
SELECT * FROM users WHERE email = 'user50000@example.com';
```

**Key EXPLAIN Terms:**
| Term | Meaning |
|------|---------|
| `Seq Scan` | Sequential scan (slow for large tables) |
| `Index Scan` | Using index (fast) |
| `cost` | Estimated cost (first = startup, second = total) |
| `rows` | Estimated rows returned |
| `actual time` | Actual execution time (from ANALYZE) |
| `Buffers` | Pages read from disk vs cache |

---

### Exercise 2: Index Performance Comparison

**Goal**: Compare query performance with and without indexes.

#### Step 1: Test without index

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user75000@example.com';
```

**Result (Before Index):**
```
Seq Scan on users  (cost=0.00..2084.00 rows=1 width=72)
Execution Time: 52.159 ms
```

#### Step 2: Create index

```sql
-- Create B-tree index (default, good for equality and range queries)
CREATE INDEX idx_users_email ON users(email);

-- Analyze to update statistics
ANALYZE users;
```

#### Step 3: Test with index

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user75000@example.com';
```

**Result (After Index):**
```
Index Scan using idx_users_email on users  (cost=0.42..8.44 rows=1 width=72)
Execution Time: 0.104 ms
```

#### Performance Improvement

| Metric | Before Index | After Index | Improvement |
|--------|--------------|-------------|-------------|
| Scan Type | Seq Scan | Index Scan | ✓ |
| Execution Time | 52.159 ms | 0.104 ms | **500x faster** |

---

### Exercise 3: Monitoring with pg_stat_statements

**Goal**: Identify slow queries in your workload.

```sql
-- Check if extension is loaded
SHOW shared_preload_libraries;

-- Query the stats
SELECT 
    queryid,
    calls,
    round(total_exec_time::numeric, 2) as total_time_ms,
    round(mean_exec_time::numeric, 2) as avg_time_ms,
    round((100 * total_exec_time / sum(total_exec_time) over())::numeric, 2) as pct_total,
    rows,
    query
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;
```

---

### Exercise 4: Table Bloat and VACUUM

**Goal**: Understand table bloat and maintenance.

#### Check Table Sizes

```sql
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

**Result:**
| Table | Total Size | Table Size | Index Size |
|-------|------------|------------|------------|
| audit_logs | 136 MB | 115 MB | 21 MB |
| orders | 45 MB | 34 MB | 11 MB |
| users | 24 MB | 14 MB | 10 MB |
| products | 3.2 MB | 864 kB | 2.4 MB |

#### Check Cache Hit Ratio

```sql
SELECT 
    sum(blks_hit) * 100.0 / sum(blks_hit + blks_read) AS cache_hit_ratio
FROM pg_stat_database
WHERE datname = 'perflab';
```

**Result:** Cache hit ratio: **99.45%** (Target: >99%)

#### Simulate Bloat and VACUUM

```sql
-- Create dead tuples
UPDATE orders SET status = 'processing' WHERE id < 10000;

-- Check dead tuples
SELECT schemaname, tablename, n_live_tup, n_dead_tup
FROM pg_stat_user_tables 
WHERE tablename = 'orders';
```

**Result:** 9,999 dead tuples created

```sql
-- Run VACUUM (reclaims space, doesn't reduce file size)
VACUUM orders;
```

Autovacuum automatically cleaned the dead tuples.

#### Autovacuum Settings

```sql
SHOW autovacuum;  -- on
SHOW autovacuum_vacuum_threshold;  -- 50
```

---

### Exercise 5: Connection Pooling

**Goal**: Understand why connection pooling matters.

#### Check Connections

```sql
-- Current connections
SELECT state, count(*) 
FROM pg_stat_activity 
WHERE datname = 'perflab'
GROUP BY state;
```

**Result:** 1 active connection

```sql
-- Max connections setting
SHOW max_connections;
```

**Result:** 100 max connections

#### Database Statistics

```sql
SELECT 
    datname,
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted
FROM pg_stat_database
WHERE datname = 'perflab';
```

**Result:**
| Metric | Value |
|--------|-------|
| Active backends | 1 |
| Transactions committed | 401 |
| Transactions rolled back | 1 |
| Blocks read | 43,842 |
| Blocks hit | 7,967,520 |
| Tuples inserted | 1,610,626 |
| Tuples updated | 10,462 |
| Tuples deleted | 149 |

---

### Exercise 6: Lock Monitoring

**Goal**: Detect and resolve lock issues.

```sql
-- Open two psql sessions to simulate locking

-- Session 1:
BEGIN;
UPDATE orders SET status = 'locked' WHERE id = 1;
-- Don't commit yet!

-- Session 2 (in another terminal):
-- This will wait for the lock
UPDATE orders SET status = 'waiting' WHERE id = 1;

-- Check blocked queries
SELECT 
    l.pid,
    l.locktype,
    l.mode,
    l.granted,
    a.query,
    a.state,
    a.usename
FROM pg_locks l
JOIN pg_stat_activity a ON l.pid = a.pid
WHERE l.granted = false;

-- Kill blocking query if needed
-- SELECT pg_terminate_backend(pid);
```

---

### Exercise 7: Performance Benchmarking with pgbench

**Goal**: Measure database throughput under load.

#### Initialize pgbench

```bash
docker exec -it pg-perf-lab pgbench -U labuser -i perflab
```

**Result:** Created tables with 100,000 accounts

#### Run Benchmark (10 clients, 100 transactions each)

```bash
docker exec -it pg-perf-lab pgbench -U labuser -c 10 -t 100 perflab
```

**Result:**
| Metric | Value |
|--------|-------|
| Clients | 10 |
| Transactions | 1,000 total |
| Latency average | 14.975 ms |
| TPS | **667.77** |

#### Run Benchmark (20 clients, 200 transactions each)

```bash
docker exec -it pg-perf-lab pgbench -U labuser -c 20 -t 200 perflab
```

**Result:**
| Metric | Value |
|--------|-------|
| Clients | 20 |
| Transactions | 4,000 total |
| Latency average | 29.415 ms |
| TPS | **679.92** |

---

### Exercise 8: Monitoring Queries

#### Index Usage Statistics

```sql
SELECT 
    schemaname,
    relname as tablename,
    indexrelname as indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan DESC;
```

**Result:**
| Table | Index | Scans | Size |
|-------|-------|-------|------|
| users | users_pkey | 500,001 | 2208 kB |
| pgbench_accounts | pgbench_accounts_pkey | 10,000 | 2208 kB |
| pgbench_tellers | pgbench_tellers_pkey | 2,066 | 16 kB |
| users | idx_users_email | 1 | 3992 kB |
| products | products_pkey | 1 | 240 kB |
| orders | orders_pkey | 1 | 11 MB |

#### Long-Running Queries

```sql
SELECT 
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query,
    state,
    usename
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
AND state != 'idle';
```

#### Unused Indexes (Candidates for Removal)

```sql
SELECT 
    schemaname || '.' || relname AS table,
    indexrelname AS index,
    pg_size_pretty(pg_relation_size(i.indexrelid)) AS index_size,
    idx_scan as index_scans
FROM pg_stat_user_indexes ui
JOIN pg_index i ON ui.indexrelid = i.indexrelid
WHERE NOT indisunique 
AND idx_scan < 50
ORDER BY pg_relation_size(i.indexrelid) DESC;
```

---

## Key Metrics to Monitor (DevOps Perspective)

### System-Level Metrics
- CPU usage (user vs system vs iowait)
- Memory usage (PostgreSQL shared buffers vs OS cache)
- Disk I/O (reads/writes, iowait)
- Network connections

### PostgreSQL Statistics Views

| View | Purpose |
|------|---------|
| `pg_stat_database` | Database-level statistics |
| `pg_stat_user_tables` | Table-level statistics |
| `pg_stat_user_indexes` | Index usage statistics |
| `pg_stat_activity` | Current activity and connections |
| `pg_stat_statements` | Query performance statistics |

### Important Configuration Settings

```sql
-- Check key settings
SHOW shared_buffers;        -- Should be 25% of RAM
SHOW work_mem;              -- Memory for sorting/hashing
SHOW effective_cache_size;  -- Should be 50-75% of RAM
SHOW max_connections;       -- Connection limit
SHOW checkpoint_completion_target;  -- Checkpoint spreading
SHOW random_page_cost;      -- SSD: 1.1, HDD: 4.0
```

---

## Project Structure

```
dblab/
├── docker-compose.yml      # PostgreSQL + pgAdmin setup
├── README.md               # This file
├── LAB-GUIDE.md            # Step-by-step lab instructions
├── init/
│   ├── 01-schema.sql       # Database schema
│   └── 02-seed-data.sql    # Test data (1M+ records)
└── scripts/
    └── perf-checks.sql     # Monitoring queries
```

## Test Data

The lab includes seeded test data:

| Table | Rows | Purpose |
|-------|------|---------|
| users | 100,000 | User accounts |
| orders | 500,000 | Order records |
| products | 10,000 | Product catalog |
| audit_logs | 1,000,000 | Audit trail |

---

## Cleanup

```bash
# Stop containers
docker-compose down

# Remove data (start fresh)
docker-compose down -v
```

---

## Additional Resources

- [PostgreSQL Performance Optimization](https://www.postgresql.org/docs/current/performance-tips.html)
- [EXPLAIN Documentation](https://www.postgresql.org/docs/current/sql-explain.html)
- [Monitoring Stats](https://www.postgresql.org/docs/current/monitoring-stats.html)
- [pg_stat_statements](https://www.postgresql.org/docs/current/pgstatstatements.html)

---

## License

MIT License
