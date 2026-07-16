# PostgreSQL Performance Lab

A hands-on lab environment for DevOps engineers to learn PostgreSQL performance monitoring, tuning, and benchmarking.
---
## Table of Contents
1. [What is this lab?](#what-is-this-lab)
2. [Why do you need this as a DevOps Engineer?](#why-do-you-need-this-as-a-devops-engineer)
3. [Quick Start](#quick-start)
4. [Lab Exercises Explained](#lab-exercises-explained)
   - [Exercise 1: EXPLAIN - Query Analysis](#exercise-1-explain---query-analysis)
   - [Exercise 2: Index Performance](#exercise-2-index-performance)
   - [Exercise 3: pg_stat_statements - Find Slow Queries](#exercise-3-pg_stat_statements---find-slow-queries)
   - [Exercise 4: VACUUM - Table Bloat](#exercise-4-vacuum---table-bloat)
   - [Exercise 5: Connection Pooling](#exercise-5-connection-pooling)
   - [Exercise 6: Lock Monitoring](#exercise-6-lock-monitoring)
   - [Exercise 7: pgbench - Benchmarking](#exercise-7-pgbench---benchmarking)
   - [Exercise 8: Monitoring Queries](#exercise-8-monitoring-queries)
5. [DevOps Database Checklist](#devops-database-checklist)
6. [Key Takeaways](#key-takeaways)
7. [Cleanup](#cleanup)
8. [Additional Resources](#additional-resources)

---

## What is this lab?

This is a hands-on learning environment for **PostgreSQL database performance tuning** - a critical skill for DevOps engineers. It includes:

| Component | Description |
|-----------|-------------|
| **PostgreSQL 16** | The database server with sample data |
| **pgAdmin 4** | Web-based GUI for database management |
| **Test Data** | 100K users, 500K orders, 1M audit logs |
| **Lab Exercises** | Real-world performance scenarios |

---

## Why do you need this as a DevOps Engineer?

### 1. Database Performance = Application Performance
```
User Request → Application → Database → Response
                              ↓
                         90% of slowness happens here
```
Most application performance issues come from the database. Knowing how to diagnose and fix them is essential.

### 2. Real-World DevOps Scenarios

| Scenario | What You'll Learn |
|----------|-------------------|
| "The app is slow" | Diagnose with EXPLAIN, find missing indexes |
| "Database disk is full" | Check table bloat, run VACUUM |
| "Users can't login" | Monitor connections, detect lock issues |
| "Need to benchmark before release" | Use pgbench for load testing |
| "Which queries are slow?" | Use pg_stat_statements |

### 3. Production Monitoring Skills

You'll learn to monitor these key metrics:
- Cache hit ratio (should be >99%)
- Dead tuples (table bloat)
- Index usage (unused indexes waste space)
- Connection count
- Query performance
---
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

### Using pgAdmin

1. Open http://localhost:5050
2. Login with `admin@example.com` / `admin`
3. Right-click **Servers** → **Register** → **Server**
4. **Connection tab**:
   - Host: `pg-perf-lab`
   - Port: `5432`
   - Database: `perflab`
   - Username: `labuser`
   - Password: `labpass`

---
## Lab Exercises Explained

### Exercise 1: EXPLAIN - Query Analysis

#### What is it?

`EXPLAIN` shows how PostgreSQL executes a query. It's the first step in query optimization.

#### Why is it important?

Before optimizing, you need to understand the execution plan. You can't fix what you don't understand.

#### How it works

```sql
-- Connect to database
docker exec -it pg-perf-lab psql -U labuser -d perflab

-- Basic EXPLAIN (shows estimated plan)
EXPLAIN SELECT * FROM users WHERE email = 'user50000@example.com';

-- EXPLAIN ANALYZE (actually runs the query, shows real times)
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user50000@example.com';

-- Detailed output with buffer information
EXPLAIN (ANALYZE, BUFFERS, FORMAT TEXT) 
SELECT * FROM users WHERE email = 'user50000@example.com';
```

#### Output Breakdown

```
Seq Scan on users  (cost=0.00..2084.00 rows=1 width=72)
                    ↑            ↑         ↑
                 startup cost  total cost  estimated rows

Actual time: 0.055..52.159 ms
             ↑
          execution time
```

#### Key Terms Explained

| Term | Meaning | Good/Bad |
|------|---------|----------|
| Seq Scan | Reads entire table row by row | Bad for large tables |
| Index Scan | Uses index to find rows directly | Good - fast |
| Bitmap Scan | Combination of index + sequential | Middle ground |
| cost | Estimated computational effort | Lower is better |
| rows | Estimated rows returned | Compare with actual |
| actual time | Real execution time (from ANALYZE) | Lower is better |
| Buffers | Pages read from disk vs cache | More hits = better |

#### When to Use EXPLAIN

- Query is slow
- Before adding indexes
- After adding indexes (verify it's used)
- Comparing query variations

---

### Exercise 2: Index Performance

#### What is an Index?

An index speeds up data lookups, similar to a book's index. Instead of reading every page, you jump directly to the information you need.

#### Why Indexes Matter

Without indexes, PostgreSQL reads every row (sequential scan). With indexes, it jumps directly to the matching rows.

#### How It Works

```
Without Index (Seq Scan):
┌─────────────────────────────────────┐
│ Row 1 → Row 2 → Row 3 → ... → Row 100000 │  ← Must read ALL rows
└─────────────────────────────────────┘
Time: 52ms

With Index (Index Scan):
┌─────────┐
│ Index   │  → Direct pointer to row
│ "email" │
└────┬────┘
     ↓
   Row 50000  ← Jump directly
└────────────┘
Time: 0.1ms
```

#### Step 1: Test Without Index

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user75000@example.com';
```

**Result:**
```
Seq Scan on users  (cost=0.00..2084.00 rows=1 width=72)
Execution Time: 52.159 ms
```

#### Step 2: Create Index

```sql
-- B-tree index (default, good for equality and range queries)
CREATE INDEX idx_users_email ON users(email);

-- Partial index (only indexes subset of data - saves space)
CREATE INDEX idx_users_inactive ON users(created_at) 
WHERE status = 'inactive';

-- Update statistics so PostgreSQL knows about the index
ANALYZE users;
```

#### Step 3: Test With Index

```sql
EXPLAIN ANALYZE SELECT * FROM users WHERE email = 'user75000@example.com';
```

**Result:**
```
Index Scan using idx_users_email on users  (cost=0.42..8.44 rows=1 width=72)
Execution Time: 0.104 ms
```

#### Performance Improvement

| Metric | Before Index | After Index | Improvement |
|--------|--------------|-------------|-------------|
| Scan Type | Seq Scan | Index Scan | ✓ |
| Execution Time | 52.159 ms | 0.104 ms | **500x faster** |

#### When to Create Indexes

✅ **Create indexes on:**
- Columns used in WHERE clauses
- Columns used in JOIN conditions
- Columns used in ORDER BY
- Columns with high cardinality (many unique values)

❌ **Don't create indexes on:**
- Small tables (< 1000 rows)
- Columns with low cardinality (e.g., boolean: only 2 values)
- Tables with heavy INSERT/UPDATE (indexes slow down writes)
- Columns that are rarely queried

#### Index Types

| Type | Use Case | Example |
|------|----------|---------|
| B-tree (default) | Equality, range, sorting | `WHERE email = 'x'` |
| Hash | Equality only | `WHERE id = 123` |
| GIN | Array, JSONB, full-text | `WHERE tags @> ARRAY['postgres']` |
| GiST | Geometric, full-text | `WHERE location @ point` |

---

### Exercise 3: pg_stat_statements - Find Slow Queries

#### What is it?

An extension that tracks execution statistics for all queries. It's your dashboard for query performance.

#### Why is it important?

In production, you need to know which queries are slowest. You can't optimize what you don't measure.

#### How to Use

```sql
-- Verify extension is loaded
SHOW shared_preload_libraries;

-- Query the statistics
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

#### Output Explained

| Column | Meaning |
|--------|---------|
| queryid | Unique identifier for the query |
| calls | How many times this query ran |
| total_time_ms | Total time spent on this query |
| avg_time_ms | Average time per call |
| pct_total | Percentage of total database time |
| rows | Total rows returned |

#### DevOps Use Cases

1. **Weekly slow query report** - Run this query weekly to identify optimization targets
2. **After deployment** - Check if new queries are performing poorly
3. **Capacity planning** - Identify queries that will grow with data

---

### Exercise 4: VACUUM - Table Bloat

#### What is Table Bloat?

PostgreSQL uses MVCC (Multi-Version Concurrency Control). When you UPDATE or DELETE, the old version remains on disk until VACUUM cleans it up.

#### Why It Matters

Dead tuples waste disk space and slow down queries. PostgreSQL must read through them even though they're not visible.

#### How MVCC Works

```
UPDATE orders SET status = 'shipped' WHERE id = 1;

Before:  [id=1, status='pending']  ← still on disk (dead tuple)
After:   [id=1, status='shipped']  ← new version

VACUUM:  Removes dead tuple, reclaims space
```

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

**Lab Results:**

| Table | Total Size | Table Size | Index Size |
|-------|------------|------------|------------|
| audit_logs | 136 MB | 115 MB | 21 MB |
| orders | 45 MB | 34 MB | 11 MB |
| users | 24 MB | 14 MB | 10 MB |

#### Check for Dead Tuples

```sql
SELECT 
    schemaname,
    tablename,
    n_live_tup,
    n_dead_tup,
    round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) as dead_ratio
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC;
```

#### Simulate Bloat

```sql
-- Create dead tuples
UPDATE orders SET status = 'processing' WHERE id < 10000;

-- Check dead tuples
SELECT schemaname, tablename, n_dead_tup 
FROM pg_stat_user_tables 
WHERE tablename = 'orders';
```

**Result:** 9,999 dead tuples created

#### Types of VACUUM

| Command | What it does | Locks table? | When to use |
|---------|--------------|--------------|-------------|
| `VACUUM` | Marks dead space as reusable | No | Regular maintenance |
| `VACUUM ANALYZE` | VACUUM + update statistics | No | After bulk changes |
| `VACUUM FULL` | Compacts table, reduces file size | Yes (locks!) | Emergency bloat cleanup |

```sql
-- Regular vacuum (doesn't lock)
VACUUM orders;

-- Full vacuum (locks table - use carefully!)
-- VACUUM FULL orders;
```

#### Autovacuum

PostgreSQL automatically runs VACUUM based on thresholds:

```sql
-- Check autovacuum is enabled
SHOW autovacuum;  -- should be 'on'

-- Check thresholds
SHOW autovacuum_vacuum_threshold;  -- default: 50
SHOW autovacuum_vacuum_scale_factor;  -- default: 0.2
```

**How autovacuum triggers:**
```
Trigger = threshold + scale_factor * n_live_tup
Trigger = 50 + 0.2 * 100000 = 20050 dead tuples
```

#### Lab Result

After the UPDATE, autovacuum automatically cleaned the dead tuples. No manual intervention needed!

---

### Exercise 5: Connection Pooling

#### What is Connection Pooling?

PostgreSQL has a limit on concurrent connections. Each connection uses memory (~10MB). Connection pooling shares connections among multiple clients.

#### Why It Matters

Without pooling:
- You can hit `max_connections` limit
- Users get "too many connections" errors
- High memory usage

#### Check Current Connections

```sql
-- Count connections by state
SELECT state, count(*) 
FROM pg_stat_activity 
WHERE datname = 'perflab'
GROUP BY state;
```

**Lab Result:** 1 active connection

#### Check Max Connections

```sql
SHOW max_connections;
```

**Lab Result:** 100 max connections

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

**Lab Results:**

| Metric | Value |
|--------|-------|
| Active backends | 1 |
| Transactions committed | 401 |
| Transactions rolled back | 1 |
| Blocks read | 43,842 |
| Blocks hit | 7,967,520 |
| Tuples inserted | 1,610,626 |

#### Connection Pooling Solutions

| Tool | Description | When to Use |
|------|-------------|-------------|
| PgBouncer | Lightweight, efficient | Most applications |
| PgPool-II | Load balancing, replication | Complex setups |
| Built-in (PostgreSQL 17+) | Native pooling | New deployments |

#### Connection Flow

```
Without Pooling:
App (100 users) → 100 connections → PostgreSQL (1GB RAM used!)

With Pooling:
App (100 users) → PgBouncer → 10 persistent connections → PostgreSQL (100MB RAM)
                       ↑
              Shares connections among users
```

---

### Exercise 6: Lock Monitoring

#### What are Locks?

When one transaction modifies a row, it locks that row. Other transactions must wait for the lock to be released.

#### Why It Matters

Locks can cause:
- Application hangs
- Timeouts
- Poor user experience

#### Simulate a Lock

Open two terminals:

**Terminal 1 (creates lock):**
```sql
BEGIN;
UPDATE orders SET status = 'locked' WHERE id = 1;
-- Don't commit yet!
```

**Terminal 2 (waits for lock):**
```sql
-- This will hang waiting for the lock
UPDATE orders SET status = 'waiting' WHERE id = 1;
```

#### Detect Locks

```sql
-- Find blocked queries
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
```

#### Kill Blocking Query

```sql
-- Terminate the blocking process
SELECT pg_terminate_backend(pid);
```

#### Common Lock Types

| Lock Type | When it occurs | Duration |
|-----------|----------------|----------|
| Row Share | SELECT | Brief |
| Row Exclusive | INSERT, UPDATE, DELETE | Until commit |
| Share | CREATE INDEX | Until complete |
| Access Exclusive | ALTER TABLE, DROP TABLE | Until complete |

#### Lock Monitoring Query

```sql
-- Find queries waiting for locks
SELECT 
    pid,
    query,
    state,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;
```

---

### Exercise 7: pgbench - Benchmarking

#### What is pgbench?

A built-in tool to measure database throughput and latency under load.

#### Why Benchmark?

- Test if database can handle expected load
- Compare configuration changes
- Validate hardware upgrades
- Pre-deployment testing

#### Initialize pgbench

```bash
docker exec -it pg-perf-lab pgbench -U labuser -i perflab
```

**Output:**
```
creating tables...
generating data (client-side)...
100000 of 100000 tuples (100%) done
vacuuming...
creating primary keys...
done in 0.48 s
```

#### Run Benchmark

```bash
# 10 clients, 100 transactions each
docker exec -it pg-perf-lab pgbench -U labuser -c 10 -t 100 perflab

# More intensive: 20 clients, 200 transactions each
docker exec -it pg-perf-lab pgbench -U labuser -c 20 -t 200 perflab
```

#### Lab Results

**Test 1 (10 clients, 100 transactions):**
| Metric | Value |
|--------|-------|
| Clients | 10 |
| Total transactions | 1,000 |
| Latency average | 14.975 ms |
| TPS | 667.77 |

**Test 2 (20 clients, 200 transactions):**
| Metric | Value |
|--------|-------|
| Clients | 20 |
| Total transactions | 4,000 |
| Latency average | 29.415 ms |
| TPS | 679.92 |

#### Interpreting Results

| TPS Range | Meaning |
|-----------|---------|
| < 100 | Database under heavy load or misconfigured |
| 500-1000 | Normal for development environment |
| > 5000 | Good for optimized production (SSD, tuned config) |

#### Benchmark Options

| Option | Description |
|--------|-------------|
| `-c N` | Number of concurrent clients |
| `-t N` | Transactions per client |
| `-T N` | Run for N seconds instead of transaction count |
| `-j N` | Number of threads |
| `-r` | Report per-statement latencies |

---

### Exercise 8: Monitoring Queries

#### Cache Hit Ratio

Should be >99%. Lower means more disk reads.

```sql
SELECT 
    sum(blks_hit) * 100.0 / sum(blks_hit + blks_read) AS cache_hit_ratio
FROM pg_stat_database
WHERE datname = 'perflab';
```

**Lab Result:** 99.45% ✓

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

**Lab Results:**

| Table | Index | Scans | Size |
|-------|-------|-------|------|
| users | users_pkey | 500,001 | 2208 kB |
| pgbench_accounts | pgbench_accounts_pkey | 10,000 | 2208 kB |
| users | idx_users_email | 1 | 3992 kB |
| orders | orders_pkey | 1 | 11 MB |

#### Find Unused Indexes

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

Indexes with `idx_scan = 0` or very low are candidates for removal (wasting space).

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

#### Queries Waiting for Locks

```sql
SELECT 
    pid,
    query,
    state,
    wait_event_type,
    wait_event
FROM pg_stat_activity
WHERE wait_event IS NOT NULL;
```

---

## DevOps Database Checklist

| Task | Frequency | Command/Tool |
|------|-----------|--------------|
| Check slow queries | Daily | pg_stat_statements |
| Monitor cache hit ratio | Daily | pg_stat_database |
| Check table bloat | Weekly | pg_stat_user_tables |
| Find unused indexes | Weekly | pg_stat_user_indexes |
| Check connections | When issues occur | pg_stat_activity |
| Run VACUUM | Automatic (autovacuum) | VACUUM |
| Benchmark before release | Before deployment | pgbench |
| Monitor locks | When app hangs | pg_locks |

---

## Key Takeaways

1. **Indexes are your best friend** - But don't over-index (slows writes)
2. **VACUUM is automatic** - Monitor that autovacuum is working
3. **Cache hit ratio >99%** - If lower, increase shared_buffers
4. **Connection pooling is essential** - For production apps
5. **Monitor proactively** - Before users complain
6. **EXPLAIN ANALYZE** - Always use before optimizing queries

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
- [PostgreSQL Tuning Guide](https://wiki.postgresql.org/wiki/Tuning_Your_PostgreSQL_Server)

---

## License

MIT License
