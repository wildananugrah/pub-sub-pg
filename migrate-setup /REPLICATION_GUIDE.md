# PostgreSQL Logical Replication Setup and Management Guide

This guide provides comprehensive instructions for setting up, managing, and troubleshooting PostgreSQL logical replication between source and target databases.

## Table of Contents

1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Initial Setup](#initial-setup)
4. [Managing Replication](#managing-replication)
5. [Monitoring](#monitoring)
6. [Troubleshooting](#troubleshooting)
7. [Comparison and Validation](#comparison-and-validation)
8. [Cleanup and Removal](#cleanup-and-removal)
9. [Common Issues and Solutions](#common-issues-and-solutions)

---

## Overview

### Database Connections

**Source Database (Publisher):**
- Host: `52.74.112.75`
- Port: `6000`
- User: `pg`
- Password: `p@ssw0rd1234`

**Target Database (Subscriber):**
- Host: `100.89.22.125`
- Port: `6000`
- User: `pg`
- Password: `p@ssw0rd1234`

### Available Scripts

| Script | Purpose |
|--------|---------|
| `setup_logical_replication.sh` | Setup and manage replication |
| `monitor_replication.sh` | Monitor replication status |
| `compare_databases.sh` | Compare database structures |
| `fix_replica_identity.sh` | Fix replica identity for DELETE operations |
| `cleanup_replication.sh` | Remove replication components |
| `check_replication_info.sh` | Check detailed replication information |

---

## Prerequisites

1. **PostgreSQL Configuration on Source:**
   - `wal_level = logical`
   - `max_replication_slots = 10`
   - `max_wal_senders = 10`

2. **Docker installed** (for running psql commands)

3. **Network connectivity** between source and target databases

---

## Initial Setup

### 1. Setup Replication for All Tables

```bash
# Setup replication for all tables in a database
./setup_logical_replication.sh --setup-all postgres

# Setup for multiple databases
./setup_logical_replication.sh --batch
```

### 2. Setup Replication for Specific Tables

```bash
# Setup replication for specific tables only
./setup_logical_replication.sh --setup-tables postgres users orders products
```

### 3. Fix Replica Identity (Required for DELETE operations)

```bash
# Fix replica identity for all tables
./fix_replica_identity.sh --fix-all postgres

# Fix specific table
./fix_replica_identity.sh --fix-table postgres public.roles

# Check current replica identity status
./fix_replica_identity.sh --check postgres
```

---

## Managing Replication

### Enable/Disable Subscriptions

```bash
# Enable a paused subscription
./setup_logical_replication.sh --enable postgres

# Disable subscription (pause replication)
./setup_logical_replication.sh --disable postgres

# Completely remove replication
./setup_logical_replication.sh --remove postgres
```

### Interactive Mode

```bash
# Run in interactive mode for menu-driven options
./setup_logical_replication.sh
```

Menu options:
1. Setup replication for all tables
2. Setup replication for specific tables
3. Monitor replication status
4. Enable existing subscription
5. Disable subscription (pause)
6. Remove replication completely
7. Setup for multiple databases
8. Exit

---

## Monitoring

### Quick Status Check

```bash
# One-time status check
./monitor_replication.sh --once postgres

# Continuous monitoring (updates every 5 seconds)
./monitor_replication.sh --monitor postgres
```

### Monitor Output Explanation

```
Source: 52.74.112.75:6000 → Target: 100.89.22.125:6000
Refresh: Every 5s

Database: postgres
Publication: Not configured      ← Publication needs to be created
Subscription: sub_postgres ()     ← Subscription exists but inactive
Synced Tables: 0
Slot: [Active|294|[0|0]         ← Slot status|tables|[lag MB|bytes]
Replication Lag: 0 B
```

Status Indicators:
- ✓ Green: Working correctly
- ✗ Red: Issues detected
- `[Active]`: Replication is running
- `[Inactive]`: Replication is paused

### Detailed Replication Information

```bash
# Check all replication details
./check_replication_info.sh --all postgres

# Check publications only
./check_replication_info.sh --publications postgres

# Check subscriptions only
./check_replication_info.sh --subscriptions postgres
```

---

## Troubleshooting

### Common Issues and Solutions

#### 1. "Publication not configured"

**Problem:** The monitoring shows "Publication: Not configured"

**Solution:**
```bash
# Create publication on source
./setup_logical_replication.sh --setup-all postgres
```

#### 2. "Subscription inactive" (active = f)

**Problem:** Subscription exists but shows `active = f` in monitoring

**Solution:**
```bash
# Enable the subscription
./setup_logical_replication.sh --enable postgres
```

#### 3. "Cannot DELETE from table - no replica identity"

**Problem:** Error when deleting records: `ERROR: cannot delete from table "roles" because it does not have a replica identity`

**Solution:**
```bash
# Fix replica identity for all tables
./fix_replica_identity.sh --fix-all postgres

# Or fix specific table
./fix_replica_identity.sh --fix-table postgres public.roles
```

#### 4. High Replication Lag

**Problem:** Replication lag is growing

**Possible causes:**
- Network issues
- Target database is slower
- Large transactions

**Check status:**
```bash
./monitor_replication.sh --once postgres
```

---

## Comparison and Validation

### Compare Database Structures

```bash
# Quick summary comparison
./compare_databases.sh --quick postgres

# Detailed comparison
./compare_databases.sh --db postgres

# Compare all databases
./compare_databases.sh --all

# Generate detailed report
./compare_databases.sh --detailed postgres report.txt
```

### What's Compared:
1. **Databases** - Which databases exist on each server
2. **Schemas** - Schema structure within databases
3. **Tables** - Table existence in each schema
4. **Columns** - Column names and order
5. **Data Types** - Column types, lengths, precision

### Output Interpretation:
- ✓ Green = Matching
- ✗ Red = Differences found
- Shows items only in SOURCE
- Shows items only in TARGET
- Summary with match percentage

---

## Cleanup and Removal

### Remove Specific Components

```bash
# Remove all subscriptions (target side)
./cleanup_replication.sh --subscriptions

# Remove all publications (source side)
./cleanup_replication.sh --publications

# Remove replication slots
./cleanup_replication.sh --slots
```

### Complete Cleanup

```bash
# Remove everything (subscriptions, publications, slots)
./cleanup_replication.sh --all

# Remove for specific database only
./cleanup_replication.sh --db postgres
```

### Interactive Cleanup

```bash
# Run interactive mode
./cleanup_replication.sh
```

---

## Common Issues and Solutions

### Issue 1: Replication Not Starting

**Symptoms:**
- Subscription shows as inactive
- No data being replicated

**Solutions:**
```bash
# Check subscription status
./monitor_replication.sh --once postgres

# Enable subscription
./setup_logical_replication.sh --enable postgres

# Check for errors in PostgreSQL logs
docker logs [container_name]
```

### Issue 2: DELETE Operations Failing

**Symptoms:**
- Error: "cannot delete from table because it does not have a replica identity"

**Solutions:**
```bash
# Fix replica identity
./fix_replica_identity.sh --fix-all postgres
```

### Issue 3: Tables Not Syncing

**Symptoms:**
- Some tables not appearing in target
- Synced Tables shows 0

**Solutions:**
```bash
# Check table structure matches
./compare_databases.sh --db postgres

# Recreate publication and subscription
./setup_logical_replication.sh --remove postgres
./setup_logical_replication.sh --setup-all postgres
```

### Issue 4: Connection Errors

**Symptoms:**
- Cannot connect to source/target
- Subscription creation fails

**Check:**
1. Network connectivity: `ping [host]`
2. Port accessibility: `telnet [host] [port]`
3. PostgreSQL authentication: Check pg_hba.conf
4. Firewall rules

---

## Best Practices

1. **Always monitor after setup:**
   ```bash
   ./monitor_replication.sh --monitor postgres
   ```

2. **Fix replica identity before production use:**
   ```bash
   ./fix_replica_identity.sh --fix-all postgres
   ```

3. **Verify structure matches:**
   ```bash
   ./compare_databases.sh --quick postgres
   ```

4. **Regular monitoring:**
   - Check replication lag
   - Verify all subscriptions are active
   - Monitor disk space for WAL files

5. **Before major changes:**
   - Disable replication
   - Make changes
   - Re-enable replication

---

## Step-by-Step Setup Example

### Complete setup for a new database:

```bash
# 1. Check initial status
./monitor_replication.sh --once postgres

# 2. Setup replication for all tables
./setup_logical_replication.sh --setup-all postgres

# 3. Fix replica identity to allow DELETEs
./fix_replica_identity.sh --fix-all postgres

# 4. Enable subscription if not active
./setup_logical_replication.sh --enable postgres

# 5. Verify structure matches
./compare_databases.sh --quick postgres

# 6. Monitor replication
./monitor_replication.sh --monitor postgres
```

---

## SQL Commands Reference

### Check Publications (on source):
```sql
SELECT * FROM pg_publication;
SELECT * FROM pg_publication_tables;
```

### Check Subscriptions (on target):
```sql
SELECT * FROM pg_subscription;
SELECT subname, subenabled FROM pg_subscription;
```

### Check Replication Slots (on source):
```sql
SELECT * FROM pg_replication_slots;
```

### Enable/Disable Subscription (on target):
```sql
ALTER SUBSCRIPTION sub_postgres ENABLE;
ALTER SUBSCRIPTION sub_postgres DISABLE;
```

### Set Replica Identity (on source):
```sql
-- For tables with primary key
ALTER TABLE public.roles REPLICA IDENTITY DEFAULT;

-- For tables without primary key
ALTER TABLE public.roles REPLICA IDENTITY FULL;
```

---

## Support and Troubleshooting

For additional help:
1. Check PostgreSQL logs on both source and target
2. Verify network connectivity between servers
3. Ensure proper PostgreSQL configuration (wal_level = logical)
4. Check disk space for WAL files
5. Review pg_hba.conf for authentication issues

---

## Quick Reference Card

| Task | Command |
|------|---------|
| Setup replication | `./setup_logical_replication.sh --setup-all postgres` |
| Monitor status | `./monitor_replication.sh --once postgres` |
| Enable subscription | `./setup_logical_replication.sh --enable postgres` |
| Fix DELETE issues | `./fix_replica_identity.sh --fix-all postgres` |
| Compare structures | `./compare_databases.sh --quick postgres` |
| Remove everything | `./cleanup_replication.sh --all` |

---

*Last updated: 2024*