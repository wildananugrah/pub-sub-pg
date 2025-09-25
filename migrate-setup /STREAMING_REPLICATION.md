# PostgreSQL Streaming Replication Guide

## Overview

Streaming replication creates a complete, real-time copy of your entire PostgreSQL cluster. Unlike logical replication which works at the table level, streaming replication maintains an exact replica of the master database including all databases, tables, indexes, and even configuration.

## Comparison: Streaming vs Logical Replication

| Feature | Streaming Replication | Logical Replication |
|---------|----------------------|-------------------|
| **Scope** | Entire cluster | Selected tables/databases |
| **Performance** | Lower latency, higher throughput | Slightly higher latency |
| **DDL Replication** | Yes, automatic | No, manual |
| **PostgreSQL Version** | 9.0+ | 10+ |
| **Use Cases** | HA, failover, read scaling | Data distribution, upgrades |
| **Standby Mode** | Read-only | Read-write |
| **Conflict Resolution** | N/A (read-only) | Required for multi-master |
| **Network Bandwidth** | Higher | Lower |
| **Setup Complexity** | Medium | Low-Medium |

## Prerequisites

### Master Server Requirements

1. **PostgreSQL Configuration** (`postgresql.conf`):
```ini
# Replication Settings
wal_level = replica              # or 'logical' which also works
max_wal_senders = 10             # Max number of replication connections
wal_keep_size = 1GB              # Keep WAL files for standby
max_replication_slots = 10       # Max number of replication slots
hot_standby = on                 # Allow queries on standby

# Archive Settings (Optional but recommended)
archive_mode = on
archive_command = 'test ! -f /archive/%f && cp %p /archive/%f'
```

2. **Authentication** (`pg_hba.conf`):
```
# TYPE  DATABASE        USER            ADDRESS                 METHOD
host    replication     replicator      standby_ip/32          md5
host    replication     replicator      0.0.0.0/0              md5
```

3. **Restart PostgreSQL** after configuration changes

### Standby Server Requirements

1. PostgreSQL installed (same major version as master)
2. Empty or ready-to-overwrite data directory
3. Network connectivity to master

## Setup Instructions

### Method 1: Traditional Setup

#### Step 1: Configure Master

```bash
# Run the setup script
./setup_streaming_replication.sh --configure

# Or manually create replication user
psql -h master_host -U postgres -c "
  CREATE USER replicator WITH REPLICATION LOGIN PASSWORD 'your_password';
"
```

#### Step 2: Create Base Backup

```bash
# Using the script
./setup_streaming_replication.sh --backup

# Or manually with pg_basebackup
pg_basebackup \
  -h master_host \
  -p 5432 \
  -U replicator \
  -D /path/to/standby/data \
  -Fp \
  -Xs \
  -R \
  -P
```

#### Step 3: Configure Standby

After base backup, the standby needs:

1. **postgresql.auto.conf** (created automatically with -R flag):
```ini
primary_conninfo = 'host=master_host port=5432 user=replicator password=your_password'
primary_slot_name = 'standby_slot'
```

2. **standby.signal** file in data directory (indicates standby mode)

#### Step 4: Start Standby

```bash
# Start PostgreSQL on standby
systemctl start postgresql

# Verify replication
./monitor_streaming_replication.sh --once
```

### Method 2: Docker Setup

```bash
# Quick Docker-based setup
./setup_streaming_replication.sh --docker

# This creates two containers:
# - pg_master (port 5432)
# - pg_standby (port 6000)
```

## Monitoring

### Real-time Monitoring Dashboard

```bash
# Continuous monitoring
./monitor_streaming_replication.sh

# Single check
./monitor_streaming_replication.sh --once

# Custom refresh interval
./monitor_streaming_replication.sh --interval 5
```

### Manual Monitoring Commands

#### On Master:
```sql
-- Check replication status
SELECT * FROM pg_stat_replication;

-- Check replication lag
SELECT
    client_addr,
    state,
    pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) as lag
FROM pg_stat_replication;

-- Check replication slots
SELECT * FROM pg_replication_slots;
```

#### On Standby:
```sql
-- Verify standby mode
SELECT pg_is_in_recovery();

-- Check last received WAL
SELECT pg_last_wal_receive_lsn();

-- Check last replayed WAL
SELECT pg_last_wal_replay_lsn();

-- Check lag time
SELECT now() - pg_last_xact_replay_timestamp() AS replication_lag;
```

## Failover Procedures

### Manual Failover

1. **Stop master** (if still running):
```bash
systemctl stop postgresql
```

2. **Promote standby to master**:
```bash
# Using script
./setup_streaming_replication.sh --promote

# Or manually
psql -h standby_host -U postgres -c "SELECT pg_promote();"
```

3. **Reconfigure applications** to point to new master

4. **Setup new standby** (optional):
   - Use old master as new standby after fixing issues
   - Create fresh standby from new master

### Automatic Failover Tools

Consider these tools for production:
- **Patroni**: Automatic failover with etcd/Consul
- **repmgr**: Replication management and automatic failover
- **PAF (PostgreSQL Automatic Failover)**: Pacemaker-based
- **pg_auto_failover**: Citusdata's solution

## Troubleshooting

### Common Issues

#### 1. Standby Not Connecting

**Symptoms:**
- No entries in `pg_stat_replication` on master
- Standby logs show connection errors

**Solutions:**
- Check `pg_hba.conf` on master
- Verify firewall rules
- Test connectivity: `psql -h master_host -U replicator -d postgres`

#### 2. High Replication Lag

**Symptoms:**
- Large lag shown in monitoring
- Standby falling behind

**Solutions:**
- Check network bandwidth
- Increase `wal_keep_size` on master
- Check for long-running queries on standby
- Consider using replication slots

#### 3. WAL Files Accumulating

**Symptoms:**
- Disk filling up on master
- Many files in pg_wal directory

**Solutions:**
```sql
-- Check replication slots
SELECT slot_name, active FROM pg_replication_slots;

-- Remove inactive slots
SELECT pg_drop_replication_slot('unused_slot');
```

#### 4. Standby Query Conflicts

**Symptoms:**
- Queries cancelled on standby
- "canceling statement due to conflict with recovery"

**Solutions:**
```ini
# In standby postgresql.conf
max_standby_streaming_delay = 30s  # Delay WAL application
hot_standby_feedback = on          # Prevent vacuum conflicts
```

## Best Practices

### 1. Use Replication Slots
Prevents master from removing WAL files needed by standby:
```sql
SELECT pg_create_physical_replication_slot('standby_slot');
```

### 2. Monitor Regularly
Set up alerts for:
- Replication lag > threshold
- Disconnected standbys
- WAL accumulation

### 3. Test Failover
Regularly practice failover procedures in test environment

### 4. Backup Strategy
- Continue backing up master
- Optionally backup standby for faster recovery

### 5. Network Security
- Use SSL for replication connections
- Restrict replication user permissions
- Use dedicated network for replication traffic

### 6. Resource Planning
- Standby needs same resources as master
- Account for read query load on standby
- Plan network bandwidth (especially for remote standbys)

## Advanced Configurations

### Cascading Replication
Standby servers can have their own standbys:
```
Master -> Standby1 -> Standby2
```

### Synchronous Replication
Ensures data is written to standby before commit:
```ini
# On master postgresql.conf
synchronous_commit = on
synchronous_standby_names = 'standby1'
```

### Delayed Standby
Protection against accidental data loss:
```ini
# On standby postgresql.conf
recovery_min_apply_delay = '1h'
```

## Migration from Logical to Streaming

If you're currently using logical replication and want to switch:

1. **Stop logical replication**:
```bash
./setup_logical_replication.sh --disable dbname
```

2. **Perform full backup/restore**:
```bash
./migrate_with_docker.sh
```

3. **Setup streaming replication**:
```bash
./setup_streaming_replication.sh --configure
./setup_streaming_replication.sh --backup
```

## Performance Tuning

### Master Tuning
```ini
# Increase WAL writer performance
wal_buffers = 16MB
wal_writer_delay = 200ms
wal_writer_flush_after = 1MB

# Checkpoint tuning
checkpoint_segments = 32  # For older versions
max_wal_size = 2GB       # For newer versions
checkpoint_completion_target = 0.9
```

### Standby Tuning
```ini
# Improve recovery performance
wal_receiver_status_interval = 1s
hot_standby_feedback = on
max_standby_streaming_delay = 30s
```

### Network Tuning
```bash
# TCP tuning for replication
sysctl -w net.core.rmem_max=134217728
sysctl -w net.core.wmem_max=134217728
sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728"
sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728"
```

## Comparison with Other Solutions

| Solution | Pros | Cons | Best For |
|----------|------|------|----------|
| **Streaming Replication** | Native, simple, complete copy | All-or-nothing, read-only standbys | HA, disaster recovery |
| **Logical Replication** | Selective, version-independent | No DDL, requires PKs | Upgrades, data distribution |
| **pglogical** | More features than logical | External extension | Complex requirements |
| **Bucardo** | Multi-master, flexible | Complex setup | Multi-master needs |
| **Slony** | Mature, trigger-based | Performance overhead | Legacy systems |

## Summary

Streaming replication is ideal when you need:
- Complete database cluster replication
- High availability and disaster recovery
- Read scaling with identical data
- Automatic DDL replication
- Simple setup and maintenance

Use logical replication instead when you need:
- Selective table replication
- Cross-version replication
- Minimal network bandwidth
- Independent standby schemas
- Write capability on replicas