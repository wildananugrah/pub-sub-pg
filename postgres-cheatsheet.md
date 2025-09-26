# PostgreSQL Cheatsheet

## Connection Commands

### Connect to PostgreSQL
```bash
# Connect as a specific user to a specific database
psql -U username -d database_name

# Connect with host and port
psql -h hostname -p port -U username -d database_name

# Example from Docker
docker exec -it container_name psql -U username -d database_name
```

## Database Commands

### List Databases
```sql
\l                      -- List all databases
\list                   -- Same as \l
\l+                     -- List databases with additional info

-- SQL Query alternative
SELECT datname FROM pg_database;
```

### Connect/Switch Database
```sql
\c database_name        -- Connect to a database
\connect database_name  -- Same as \c
```

### Create/Drop Database
```sql
CREATE DATABASE dbname;
DROP DATABASE dbname;
```

## Schema Commands

### List Schemas
```sql
\dn                     -- List all schemas
\dn+                    -- List schemas with details

-- SQL Query alternatives
SELECT schema_name FROM information_schema.schemata;

-- User schemas only (exclude system schemas)
SELECT schema_name FROM information_schema.schemata
WHERE schema_name NOT LIKE 'pg_%'
AND schema_name != 'information_schema';
```

## Table Commands

### List Tables
```sql
\dt                     -- List tables in current schema
\dt+                    -- List tables with size info
\dt schema.*            -- List tables in specific schema
\d table_name           -- Describe a table structure
\d+ table_name          -- Describe table with more details
```

### Table Operations
```sql
-- Show all tables with details
SELECT * FROM information_schema.tables
WHERE table_schema = 'public';

-- Show columns of a table
\d table_name

-- Or using SQL
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'your_table';
```

## User and Permission Commands

### List Users/Roles
```sql
\du                     -- List users/roles
\du+                    -- List users with details
```

### Grant Permissions
```sql
GRANT ALL PRIVILEGES ON DATABASE dbname TO username;
GRANT SELECT, INSERT, UPDATE ON table_name TO username;
```

## Query Commands

### Execute Commands
```sql
\g                      -- Execute previous command
\s                      -- Command history
\s filename             -- Save command history to file
\i filename             -- Execute commands from file
```

### Output Formatting
```sql
\x                      -- Toggle expanded display
\a                      -- Toggle aligned output
\H                      -- Toggle HTML output
\t                      -- Show rows only (no headers)
```

## Information Commands

### System Information
```sql
\conninfo               -- Current connection info
\! command              -- Execute shell command
\timing                 -- Toggle timing of commands
\encoding               -- Show client encoding
```

### Help Commands
```sql
\?                      -- Show psql commands
\h                      -- List SQL commands
\h command              -- Help on specific SQL command
```

## Common Queries

### Database Size
```sql
-- Current database size
SELECT pg_database_size(current_database());

-- All databases sizes
SELECT datname, pg_size_pretty(pg_database_size(datname))
FROM pg_database;
```

### Table Sizes
```sql
-- All tables in current database
SELECT schemaname, tablename,
       pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS size
FROM pg_tables
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

### Active Connections
```sql
SELECT pid, usename, application_name, client_addr, state
FROM pg_stat_activity;
```

### Running Queries
```sql
SELECT pid, now() - pg_stat_activity.query_start AS duration, query, state
FROM pg_stat_activity
WHERE (now() - pg_stat_activity.query_start) > interval '5 minutes';
```

## Exit Commands

```sql
\q                      -- Quit psql
\quit                   -- Same as \q
```

## Tips

1. **Auto-completion**: Press TAB to auto-complete commands and table/column names
2. **Command history**: Use arrow keys to navigate through previous commands
3. **Clear screen**: Use `\! clear` (Linux/Mac) or `\! cls` (Windows)
4. **Cancel query**: Press Ctrl+C to cancel current query
5. **Transactions**: Use `BEGIN;`, `COMMIT;`, and `ROLLBACK;` for transaction control