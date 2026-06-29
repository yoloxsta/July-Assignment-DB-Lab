-- Seed Data for Performance Testing
-- Generates realistic test data using generate_series

-- Insert 100,000 users
INSERT INTO users (email, username, status, metadata, created_at)
SELECT 
    'user' || g.i || '@example.com',
    'username' || g.i,
    CASE (g.i % 5) 
        WHEN 0 THEN 'active' 
        WHEN 1 THEN 'active' 
        WHEN 2 THEN 'active' 
        WHEN 3 THEN 'inactive' 
        ELSE 'suspended' 
    END,
    jsonb_build_object(
        'preferences', jsonb_build_object('theme', CASE WHEN g.i % 2 = 0 THEN 'dark' ELSE 'light' END),
        'login_count', (g.i % 1000),
        'last_ip', '192.168.' || ((g.i % 256)) || '.' || ((g.i / 256) % 256)
    ),
    CURRENT_TIMESTAMP - (random() * 365 || ' days')::interval
FROM generate_series(1, 100000) AS g(i);

-- Insert 500,000 orders (average 5 orders per user)
INSERT INTO orders (user_id, total_amount, status, created_at, updated_at)
SELECT 
    (g.i % 100000) + 1,
    (random() * 1000 + 10)::decimal(10, 2),
    CASE (g.i % 4)
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'processing'
        WHEN 2 THEN 'shipped'
        ELSE 'delivered'
    END,
    CURRENT_TIMESTAMP - make_interval(days => (random() * 180)::int),
    CURRENT_TIMESTAMP - make_interval(days => (random() * 30)::int)
FROM generate_series(1, 500000) AS g(i);

-- Insert 10,000 products
INSERT INTO products (name, description, price, category, tags, created_at)
SELECT 
    'Product ' || g.i,
    'This is a detailed description for product ' || g.i || '. It contains various features and specifications that make this product unique and valuable for customers.',
    (random() * 500 + 5)::decimal(10, 2),
    CASE (g.i % 10)
        WHEN 0 THEN 'Electronics'
        WHEN 1 THEN 'Clothing'
        WHEN 2 THEN 'Books'
        WHEN 3 THEN 'Home & Garden'
        WHEN 4 THEN 'Sports'
        WHEN 5 THEN 'Toys'
        WHEN 6 THEN 'Automotive'
        WHEN 7 THEN 'Health'
        WHEN 8 THEN 'Beauty'
        ELSE 'Food'
    END,
    ARRAY[CASE (g.i % 3) WHEN 0 THEN 'featured' WHEN 1 THEN 'sale' ELSE 'new' END],
    CURRENT_TIMESTAMP - make_interval(days => (random() * 365)::int)
FROM generate_series(1, 10000) AS g(i);

-- Insert 1,000,000 audit logs
INSERT INTO audit_logs (table_name, record_id, action, old_data, new_data, changed_by, changed_at)
SELECT 
    CASE (g.i % 4)
        WHEN 0 THEN 'users'
        WHEN 1 THEN 'orders'
        WHEN 2 THEN 'products'
        ELSE 'sessions'
    END,
    (g.i % 100000) + 1,
    CASE (g.i % 3)
        WHEN 0 THEN 'INSERT'
        WHEN 1 THEN 'UPDATE'
        ELSE 'DELETE'
    END,
    CASE WHEN g.i % 3 != 0 THEN jsonb_build_object('field', 'old_value_' || g.i) ELSE NULL END,
    CASE WHEN g.i % 3 != 2 THEN jsonb_build_object('field', 'new_value_' || g.i) ELSE NULL END,
    (g.i % 100000) + 1,
    CURRENT_TIMESTAMP - make_interval(days => (random() * 90)::int)
FROM generate_series(1, 1000000) AS g(i);

-- Create some indexes AFTER data load (to demonstrate index creation time)
-- These will be created manually during the lab exercises

-- Update statistics
ANALYZE;
