# PostgreSQL Performance Lab Guide

## DevOps Engineer's Guide to Database Performance

This lab covers essential PostgreSQL performance concepts, tools, and techniques that every DevOps engineer should know.

---

## Lab Setup

### Prerequisites
- Docker Desktop running
- Port 5432 and 5050 available

### Start the Lab Environment

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
| pgAdmin | localhost | 5050 | admin@lab.local | admin |

---

## Lab Exercises

### Exercise 1: Query Analysis with EXPLAIN

**Goal**: Learn to read query execution plans and identify bottlenecks.

```sql
-- Connect to database
docker exec -it pg-perf-lab psql -U labuser -d perflab

-- Basic EXPLAIN
EXPLAIN SELECT * FROM users WHERE email = 'user50000@example.com';

-- EXPLAIN ANALYZE (actually runs the query)
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user50000@example.com';

-- More detailed output
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) 
SELECT * FROM users WHERE email = 'user50000@example.com';
```

**What to look for:**
- `Seq Scan` = Sequential scan (slow for large tables)
- `Index Scan` = Using index (fast)
- `cost` = Estimated cost (first number = startup, second = total)
- `rows` = Estimated rows returned
- `actual time` = Actual execution time (from ANALYZE)
- `Buffers` = Pages read from disk vs cache

---

### Exercise 2: Index Performance Comparison

**Goal**: Compare query performance with and without indexes.

#### Step 1: Test without index

```sql
-- Clear query cache (restart PostgreSQL)
\! docker restart pg-perf-lab

-- Time a search without index
\timing on

EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user75000@example.com';
-- Note the execution time

EXPLAIN ANALYZE SELECT * FROM users WHERE status = 'inactive';
-- Note the execution time
```

#### Step 2: Create indexes

```sql
-- Create B-tree index (default, good for equality and range queries)
CREATE INDEX idx_users_email ON users(email);

-- Create partial index (only indexes subset of data)
CREATE INDEX idx_users_inactive ON users(created_at) 
WHERE status = 'inactive';

-- Analyze to update statistics
ANALYZE users;
```

#### Step 3: Test with index

```sql
-- Clear cache again
\! docker restart pg-perf-lab

EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user75000@example.com';
-- Compare the execution time!

EXPLAIN ANALYZE SELECT * FROM users WHERE status = 'inactive';
-- Compare the execution time!
```

---

### Exercise 3: Monitoring with pg_stat_statements

**Goal**: Identify slow queries in your workload.

```sql
-- Enable pg_stat_statements extension (already done in init)
-- Make sure it's loaded
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

```sql
-- Check table size
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;

-- Check for dead tuples (bloat)
SELECT 
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) as dead_ratio
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;

-- Simulate updates that create bloat
UPDATE orders SET status = 'processing' WHERE id < 10000;

-- Check bloat again
SELECT schemaname, tablename, n_dead_tup 
FROM pg_stat_user_tables 
WHERE tablename = 'orders';

-- Run VACUUM (reclaims space but doesn't reduce file size)
VACUUM orders;

-- Run VACUUM FULL (compacts table, locks it!)
-- WARNING: This locks the table
-- VACUUM FULL orders;

-- Check autovacuum settings
SHOW autovacuum;
SHOW autovacuum_vacuum_threshold;
```

---

### Exercise 5: Connection Pooling

**Goal**: Understand why connection pooling matters.

```sql
-- Check current connections
SELECT 
    state,
    count(*) 
FROM pg_stat_activity 
WHERE datname = 'perflab'
GROUP BY state;

-- Check max connections
SHOW max_connections;

-- View connection stats
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

-- Check locks
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

```bash
# Initialize pgbench tables
docker exec -it pg-perf-lab pgbench -U labuser -i perflab

# Run benchmark (10 clients, 100 transactions each)
docker exec -it pg-perf-lab pgbench -U labuser -c 10 -t 100 perflab

# Run with custom scale
docker exec -it pg-perf-lab pgbench -U labuser -c 20 -t 500 perflab
```

---

### Exercise 8: Monitoring Queries

```sql
-- Long-running queries
SELECT 
    pid,
    now() - pg_stat_activity.query_start AS duration,
    query,
    state,
    usename
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes'
AND state != 'idle';

-- Queries waiting for locks
SELECT 
    pid,
    query,
    state,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;

-- Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC;

-- Unused indexes (potential candidates for removal)
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

### PostgreSQL Metrics
- `pg_stat_database` - Database-level statistics
- `pg_stat_user_tables` - Table-level statistics
- `pg_stat_user_indexes` - Index usage statistics
- `pg_stat_activity` - Current activity and connections
- `pg_stat_statements` - Query performance statistics

### Key Settings to Monitor
```sql
-- Important configuration settings
SHOW shared_buffers;        -- Should be 25% of RAM
SHOW work_mem;              -- Memory for sorting/hashing
SHOW effective_cache_size;  -- Should be 50-75% of RAM
SHOW max_connections;       -- Connection limit
SHOW checkpoint_completion_target;  -- Checkpoint spreading
SHOW random_page_cost;      -- SSD: 1.1, HDD: 4.0
```

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
