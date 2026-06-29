-- PostgreSQL Performance Quick Checks
-- Run these commands for quick performance diagnostics

-- ============================================
-- 1. DATABASE SIZE OVERVIEW
-- ============================================
\echo '=== DATABASE SIZES ==='
SELECT 
    datname,
    pg_size_pretty(pg_database_size(datname)) as size
FROM pg_database
WHERE datname NOT IN ('postgres', 'template0', 'template1');

-- ============================================
-- 2. TABLE SIZES
-- ============================================
\echo '=== TABLE SIZES ==='
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC
LIMIT 10;

-- ============================================
-- 3. CACHE HIT RATIO (should be > 99%)
-- ============================================
\echo '=== CACHE HIT RATIO ==='
SELECT 
    round(100.0 * sum(blks_hit) / (sum(blks_hit) + sum(blks_read)), 2) as cache_hit_ratio_pct
FROM pg_stat_database
WHERE datname = 'perflab';

-- ============================================
-- 4. INDEX USAGE
-- ============================================
\echo '=== INDEX USAGE ==='
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_scan,
    pg_size_pretty(pg_relation_size(indexrelid)) as index_size
FROM pg_stat_user_indexes
ORDER BY idx_scan ASC
LIMIT 10;

-- ============================================
-- 5. UNUSED INDEXES
-- ============================================
\echo '=== UNUSED INDEXES (candidates for removal) ==='
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

-- ============================================
-- 6. DEAD TUPLES (BLOAT)
-- ============================================
\echo '=== TABLE BLOAT ==='
SELECT 
    tablename,
    n_live_tup as live_rows,
    n_dead_tup as dead_rows,
    round(100.0 * n_dead_tup / nullif(n_live_tup + n_dead_tup, 0), 2) as dead_ratio_pct,
    last_vacuum,
    last_autovacuum
FROM pg_stat_user_tables
WHERE n_dead_tup > 0
ORDER BY n_dead_tup DESC;

-- ============================================
-- 7. ACTIVE CONNECTIONS
-- ============================================
\echo '=== ACTIVE CONNECTIONS ==='
SELECT 
    state,
    count(*) as count
FROM pg_stat_activity
WHERE datname = 'perflab'
GROUP BY state;

-- ============================================
-- 8. LONG-RUNNING QUERIES
-- ============================================
\echo '=== LONG-RUNNING QUERIES ==='
SELECT 
    pid,
    now() - query_start AS duration,
    left(query, 100) || '...' as query_preview,
    state,
    usename
FROM pg_stat_activity
WHERE state != 'idle'
AND now() - query_start > interval '5 seconds'
ORDER BY duration DESC;

-- ============================================
-- 9. SLOW QUERIES (from pg_stat_statements)
-- ============================================
\echo '=== TOP 10 SLOWEST QUERIES ==='
SELECT 
    round(total_exec_time::numeric, 2) as total_time_ms,
    calls,
    round(mean_exec_time::numeric, 2) as avg_time_ms,
    rows,
    left(query, 80) || '...' as query_preview
FROM pg_stat_statements
ORDER BY total_exec_time DESC
LIMIT 10;

-- ============================================
-- 10. TABLE AND INDEX SCANS
-- ============================================
\echo '=== SEQ VS INDEX SCANS ==='
SELECT 
    tablename,
    seq_scan,
    idx_scan,
    round(100.0 * idx_scan / nullif(seq_scan + idx_scan, 0), 2) as idx_scan_ratio_pct
FROM pg_stat_user_tables
ORDER BY seq_scan DESC
LIMIT 10;

-- ============================================
-- 11. CURRENT LOCKS
-- ============================================
\echo '=== BLOCKED QUERIES ==='
SELECT 
    blocked.pid AS blocked_pid,
    blocked.query AS blocked_query,
    blocking.pid AS blocking_pid,
    blocking.query AS blocking_query
FROM pg_stat_activity blocked
JOIN pg_locks blocked_locks ON blocked.pid = blocked_locks.pid
JOIN pg_locks blocking_locks ON blocked_locks.locktype = blocking_locks.locktype
    AND blocked_locks.database IS NOT DISTINCT FROM blocking_locks.database
    AND blocked_locks.relation IS NOT DISTINCT FROM blocking_locks.relation
    AND blocked_locks.page IS NOT DISTINCT FROM blocking_locks.page
    AND blocked_locks.tuple IS NOT DISTINCT FROM blocking_locks.tuple
    AND blocked_locks.pid != blocking_locks.pid
JOIN pg_stat_activity blocking ON blocking_locks.pid = blocking.pid
WHERE NOT blocked_locks.granted;

-- ============================================
-- 12. INDEX RECOMMENDATIONS
-- ============================================
\echo '=== MISSING INDEXES (tables with many seq scans) ==='
SELECT 
    tablename,
    seq_scan,
    seq_tup_read,
    idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > idx_scan
AND seq_scan > 100
ORDER BY seq_scan DESC;
