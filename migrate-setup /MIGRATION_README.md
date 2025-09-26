# PostgreSQL Database Migration Scripts

This directory contains scripts to migrate all databases from one PostgreSQL server to another.

## Configuration

**Source Database:**
- Host: 52.74.112.75
- Port: 5432
- User: pg
- Password: ~nagha2025yasha@~

**Target Database:**
- Host: 52.74.112.75
- Port: 6000
- User: pg
- Password: p@ssw0rd1234

## Available Scripts

### 1. Bash Script (migrate_postgres_databases.sh)

**Features:**
- Automatic backup of all databases
- Parallel migration support
- Comprehensive logging
- Progress tracking
- Verification after migration
- Color-coded output

**Usage:**
```bash
# Make script executable
chmod +x migrate_postgres_databases.sh

# Run migration
./migrate_postgres_databases.sh
```

### 2. Python Script (migrate_postgres_databases.py)

**Features:**
- Object-oriented design
- Parallel migration with thread pool
- Progress bars with tqdm
- Detailed logging
- Database verification
- Command-line arguments support

**Installation:**
```bash
# Install dependencies
pip install -r requirements.txt
```

**Usage:**
```bash
# Run sequential migration
python3 migrate_postgres_databases.py

# Run parallel migration
python3 migrate_postgres_databases.py --parallel

# Migrate specific databases only
python3 migrate_postgres_databases.py --databases db1 db2 db3
```

## Migration Process

Both scripts follow the same process:

1. **Connection Test**: Verify connectivity to both source and target servers
2. **Database Discovery**: List all user databases (excluding system databases)
3. **User Confirmation**: Ask for confirmation before proceeding
4. **For each database:**
   - Create backup using `pg_dump`
   - Drop existing database on target (if exists)
   - Restore backup using `psql` or `pg_restore`
   - Verify table count matches source
5. **Summary Report**: Display successful and failed migrations

## Output Files

- **Backup Directory**: `db_backups_YYYYMMDD_HHMMSS/`
  - Contains `.sql` files for each database
- **Log File**: `migration_YYYYMMDD_HHMMSS.log`
  - Detailed migration logs

## Prerequisites

- PostgreSQL client tools (`pg_dump`, `psql`)
- Network connectivity to both database servers
- Sufficient disk space for backups
- For Python script: Python 3.6+ and dependencies in requirements.txt

## Important Notes

1. **Data Safety**: Backups are created before any restore operations
2. **Existing Databases**: Target databases with the same name will be dropped and recreated
3. **System Databases**: postgres, template0, and template1 are excluded from migration
4. **Verification**: Table counts are compared after each migration
5. **Atomicity**: Each database is migrated independently

## Troubleshooting

### Connection Issues
- Verify network connectivity: `ping 52.74.112.75`
- Test PostgreSQL connection: `psql -h HOST -p PORT -U USER -d postgres`

### Permission Issues
- Ensure the user has sufficient privileges on both servers
- Check `pg_hba.conf` configuration on both servers

### Backup/Restore Failures
- Check available disk space
- Verify PostgreSQL client version compatibility
- Review detailed logs in the log file

### Performance
- Use `--parallel` flag with Python script for faster migration
- Adjust `PARALLEL_JOBS` variable to control concurrency

## Recovery

If migration fails:
1. Check the log file for specific errors
2. Failed databases remain unchanged on target
3. Successful migrations are preserved
4. Re-run script to retry failed databases only

## Security Considerations

- Passwords are stored in script (consider using environment variables or .pgpass file)
- Backup files contain full database dumps
- Secure or delete backup files after successful migration

## Real-time Database Synchronization

After initial migration, you can set up real-time synchronization to keep databases in sync.

### Available Synchronization Methods

#### 1. PostgreSQL Logical Replication (Recommended)

**Pros:**
- Native PostgreSQL feature
- Selective table replication
- Minimal performance impact
- DDL changes not replicated (safer)

**Cons:**
- Requires PostgreSQL 10+
- Needs `wal_level = logical` on source
- Primary keys required on all replicated tables

### Prerequisites for Logical Replication

1. **Source PostgreSQL Configuration** (postgresql.conf):
```
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10
```

2. **Restart PostgreSQL after configuration changes**

3. **All replicated tables must have primary keys**

### Setup Scripts

#### setup_logical_replication.sh

Sets up logical replication between source and target databases.

**Usage:**
```bash
# Make script executable
chmod +x setup_logical_replication.sh

# Interactive mode
./setup_logical_replication.sh

# Setup replication for all tables in a database
./setup_logical_replication.sh --setup-all devmode

# Setup replication for specific tables
./setup_logical_replication.sh --setup-tables devmode "users, orders, products"

# Setup for multiple databases
./setup_logical_replication.sh --batch

# Disable replication
./setup_logical_replication.sh --disable devmode
```

#### monitor_replication.sh

Monitors replication status and lag in real-time.

**Usage:**
```bash
# Make script executable
chmod +x monitor_replication.sh

# Monitor all replicated databases continuously
./monitor_replication.sh

# Monitor specific databases
./monitor_replication.sh devmode serayuopakprogo

# Check once and exit
./monitor_replication.sh --once devmode

# Custom refresh interval
./monitor_replication.sh --interval 10 devmode

# Show table statistics
./monitor_replication.sh --stats devmode
```

### Step-by-Step Setup Guide

1. **Initial Migration** (one-time):
```bash
./migrate_with_docker.sh
```

2. **Configure Source PostgreSQL**:
```bash
# SSH to source server
# Edit postgresql.conf
sudo nano /etc/postgresql/16/main/postgresql.conf

# Add/modify these lines:
wal_level = logical
max_replication_slots = 10
max_wal_senders = 10

# Restart PostgreSQL
sudo systemctl restart postgresql
```

3. **Setup Logical Replication**:
```bash
# For all databases
./setup_logical_replication.sh --batch
nohup ./setup_logical_replication.sh --batch > replication.log 2>&1 &

# Or for specific database
./setup_logical_replication.sh --setup-all devmode
./setup_logical_replication.sh --setup-all postgres
```

4. **Monitor Replication**:
```bash
# Start monitoring dashboard
./monitor_replication.sh
```

### Alternative Synchronization Methods

#### 2. Streaming Replication
- Full database cluster replication
- Read-only replicas
- Automatic failover support
- Use when: Need complete mirror, read scaling

#### 3. pglogical Extension
- More flexible than native logical replication
- Supports older PostgreSQL versions
- Bidirectional replication possible
- Use when: Need advanced features, older PostgreSQL

#### 4. SymmetricDS
- Multi-master replication
- Cross-database platform support
- Conflict resolution
- Use when: Need bidirectional sync, heterogeneous databases

#### 5. Debezium + Kafka
- Event streaming platform
- Complex transformations
- Multiple consumers
- Use when: Need event-driven architecture, multiple targets

### Troubleshooting Replication

#### Check Replication Status
```bash
# On source - check publications
psql -h source_host -U pg -d dbname -c "SELECT * FROM pg_publication;"

# On target - check subscriptions
psql -h target_host -U pg -d dbname -c "SELECT * FROM pg_subscription;"

# Check replication lag
./monitor_replication.sh --once dbname
./monitor_replication.sh --once postgres
```

#### Common Issues

1. **"wal_level is not logical"**
   - Solution: Set `wal_level = logical` in postgresql.conf and restart

2. **"relation does not exist"**
   - Solution: Ensure table exists on both source and target

3. **"could not create replication slot"**
   - Solution: Increase `max_replication_slots` on source

4. **High replication lag**
   - Check network bandwidth
   - Verify no long-running transactions
   - Consider increasing `wal_sender_timeout`

#### Emergency Procedures

**Stop all replication:**
```bash
for db in devmode serayuopakprogo; do
    ./setup_logical_replication.sh --disable $db
done
```

**Reset and restart replication:**
```bash
# 1. Disable replication
./setup_logical_replication.sh --disable dbname

# 2. Re-run initial migration if needed
./migrate_with_docker.sh

# 3. Re-enable replication
./setup_logical_replication.sh --setup-all dbname
```

### Best Practices

1. **Monitor regularly** - Set up alerts for high replication lag
2. **Test failover procedures** - Practice switching to target database
3. **Backup both databases** - Replication is not a backup solution
4. **Document table dependencies** - Know which tables must stay in sync
5. **Plan maintenance windows** - Some operations require replication pause

```sh
 Yes! I've created comprehensive queries and tools to get complete pub/sub
  information in PostgreSQL. Here's what I've provided:

  1. SQL Queries File (check_replication_status.sql)

  Contains 16 different query types:

  Publication Queries (Run on Publisher):

  -- See all publications
  SELECT pubname, puballtables, pubinsert, pubupdate FROM pg_publication;

  -- See which tables are published
  SELECT p.pubname, pt.schemaname, pt.tablename FROM pg_publication p
  JOIN pg_publication_tables pt ON p.pubname = pt.pubname;

  -- See who's subscribing (replication slots)
  SELECT slot_name, active, client_addr FROM pg_replication_slots rs
  LEFT JOIN pg_stat_replication sr ON sr.pid = rs.active_pid;

  Subscription Queries (Run on Subscriber):

  -- See all subscriptions
  SELECT subname, subenabled, subconninfo, subpublications FROM pg_subscription;

  -- See table sync status
  SELECT s.subname, sr.tablename, sr.srsubstate FROM pg_subscription s
  JOIN pg_subscription_rel sr ON s.oid = sr.srsubid;

  2. Interactive Script (check_replication_info.sh)

  Features:
  - Complete topology mapping - Shows publisher → subscriber relationships
  - Detailed status for each database
  - Summary reports
  - Interactive and command-line modes

  Usage Examples:

  Quick Check:

  # Check specific database
  ./check_replication_info.sh --db devmode

  # Show complete replication topology
  ./check_replication_info.sh --topology

  # Generate summary report
  ./check_replication_info.sh --summary

  Key Information You'll Get:

  1. Publications - What's being published from source
  2. Subscriptions - What target is subscribing to
  3. Replication Slots - Active connections between pub/sub
  4. Table Sync Status - Which tables are synchronized
  5. Lag Information - How far behind subscriber is
  6. Connection Details - IP addresses, connection strings

  Most Useful Queries:

  To see complete pub→sub mapping:
  -- Run on publisher
  SELECT
      pubname as "Publication",
      slot_name as "Used by Slot",
      client_addr as "Subscriber IP",
      active as "Active"
  FROM pg_publication p
  LEFT JOIN pg_replication_slots rs ON rs.database = current_database()
  LEFT JOIN pg_stat_replication sr ON sr.pid = rs.active_pid;

  To see what's subscribed where:
  -- Run on subscriber
  SELECT
      subname as "Subscription",
      subpublications[1] as "Publication",
      substring(subconninfo from 'host=([^ ]+)') as "Publisher Host",
      subenabled
  FROM pg_subscription;

  The script provides a complete view of your logical replication topology!
```