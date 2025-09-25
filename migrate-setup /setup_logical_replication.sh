#!/bin/bash

# PostgreSQL Logical Replication Setup
# This script sets up logical replication between source (publisher) and target (subscriber) databases
# Logical replication allows selective table replication and real-time sync

# Source database configuration (Publisher)
SOURCE_HOST="52.74.112.75"
SOURCE_PORT="5432"
SOURCE_USER="pg"
SOURCE_PASSWORD="~nagha2025yasha@~"

# Target database configuration (Subscriber)
TARGET_HOST="52.74.112.75"
TARGET_PORT="6000"
TARGET_USER="pg"
TARGET_PASSWORD="p@ssw0rd1234"

# Replication configuration
REPLICATION_USER="replicator"
REPLICATION_PASSWORD="repl@1234"
PUBLICATION_NAME="source_publication"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Function to execute SQL on source
exec_source_sql() {
    docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgres:16 \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$1" -c "$2"
}

# Function to execute SQL on target
exec_target_sql() {
    docker run --rm \
        -e PGPASSWORD="$TARGET_PASSWORD" \
        postgres:16 \
        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
        -d "$1" -c "$2"
}

# Function to setup replication for a database
setup_database_replication() {
    local dbname=$1
    local tables=${2:-"ALL TABLES"}  # Default to all tables if not specified

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Setting up replication for: $dbname${NC}"
    echo -e "${BLUE}=========================================${NC}"

    # Step 1: Configure source database (Publisher)
    echo -e "${YELLOW}Step 1: Configuring publisher on source...${NC}"

    # Check if wal_level is set to logical
    WAL_LEVEL=$(exec_source_sql "postgres" "SHOW wal_level;" | grep -o 'logical\|replica\|minimal' | head -1)
    if [ "$WAL_LEVEL" != "logical" ]; then
        echo -e "${RED}WARNING: wal_level is '$WAL_LEVEL', not 'logical'${NC}"
        echo "You need to set wal_level = logical in postgresql.conf and restart PostgreSQL"
        echo "Add these settings to postgresql.conf on source server:"
        echo "  wal_level = logical"
        echo "  max_replication_slots = 10"
        echo "  max_wal_senders = 10"
        return 1
    fi

    # Create publication
    echo -e "${YELLOW}Creating publication '${PUBLICATION_NAME}_${dbname}'...${NC}"
    if [ "$tables" = "ALL TABLES" ]; then
        exec_source_sql "$dbname" "DROP PUBLICATION IF EXISTS ${PUBLICATION_NAME}_${dbname};"
        exec_source_sql "$dbname" "CREATE PUBLICATION ${PUBLICATION_NAME}_${dbname} FOR ALL TABLES;"
    else
        exec_source_sql "$dbname" "DROP PUBLICATION IF EXISTS ${PUBLICATION_NAME}_${dbname};"
        exec_source_sql "$dbname" "CREATE PUBLICATION ${PUBLICATION_NAME}_${dbname} FOR TABLE $tables;"
    fi

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Publication created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create publication${NC}"
        return 1
    fi

    # Step 2: Configure target database (Subscriber)
    echo -e "${YELLOW}Step 2: Configuring subscriber on target...${NC}"

    # Create subscription
    echo -e "${YELLOW}Creating subscription to '${PUBLICATION_NAME}_${dbname}'...${NC}"

    # Drop existing subscription if it exists
    exec_target_sql "$dbname" "DROP SUBSCRIPTION IF EXISTS sub_${dbname};"

    # Create new subscription
    SUBSCRIPTION_SQL="CREATE SUBSCRIPTION sub_${dbname}
        CONNECTION 'host=$SOURCE_HOST port=$SOURCE_PORT dbname=$dbname user=$SOURCE_USER password=$SOURCE_PASSWORD'
        PUBLICATION ${PUBLICATION_NAME}_${dbname}
        WITH (copy_data = false, create_slot = true, slot_name = 'sub_${dbname}_slot');"

    exec_target_sql "$dbname" "$SUBSCRIPTION_SQL"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Subscription created successfully${NC}"
    else
        echo -e "${RED}✗ Failed to create subscription${NC}"
        return 1
    fi

    # Step 3: Verify replication status
    echo -e "${YELLOW}Step 3: Verifying replication status...${NC}"

    # Check publication
    echo -e "${YELLOW}Publications on source:${NC}"
    exec_source_sql "$dbname" "SELECT pubname, puballtables FROM pg_publication WHERE pubname LIKE '${PUBLICATION_NAME}%';"

    # Check subscription
    echo -e "${YELLOW}Subscriptions on target:${NC}"
    exec_target_sql "$dbname" "SELECT subname, subenabled, subconninfo FROM pg_subscription WHERE subname LIKE 'sub_%';"

    # Check replication slots
    echo -e "${YELLOW}Replication slots on source:${NC}"
    exec_source_sql "$dbname" "SELECT slot_name, active, restart_lsn FROM pg_replication_slots;"

    echo -e "${GREEN}✓ Replication setup completed for $dbname${NC}"
    return 0
}

# Function to monitor replication lag
monitor_replication() {
    local dbname=$1

    echo -e "${YELLOW}Monitoring replication for $dbname...${NC}"

    # Check replication lag
    exec_source_sql "$dbname" "SELECT
        slot_name,
        active,
        pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS replication_lag,
        restart_lsn
    FROM pg_replication_slots
    WHERE slot_name LIKE 'sub_${dbname}%';"

    # Check subscription status
    exec_target_sql "$dbname" "SELECT
        subname,
        subenabled,
        CASE
            WHEN subenabled THEN 'Active'
            ELSE 'Inactive'
        END as status
    FROM pg_subscription
    WHERE subname = 'sub_${dbname}';"
}

# Function to sync specific tables
sync_tables() {
    local dbname=$1
    shift
    local tables="$@"

    echo -e "${YELLOW}Setting up replication for specific tables in $dbname${NC}"
    echo -e "${YELLOW}Tables: $tables${NC}"

    setup_database_replication "$dbname" "$tables"
}

# Function to disable replication
disable_replication() {
    local dbname=$1

    echo -e "${YELLOW}Disabling replication for $dbname...${NC}"

    # Drop subscription on target
    exec_target_sql "$dbname" "DROP SUBSCRIPTION IF EXISTS sub_${dbname};"

    # Drop publication on source
    exec_source_sql "$dbname" "DROP PUBLICATION IF EXISTS ${PUBLICATION_NAME}_${dbname};"

    # Drop replication slot
    exec_source_sql "$dbname" "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE slot_name LIKE 'sub_${dbname}%' AND NOT active;"

    echo -e "${GREEN}✓ Replication disabled for $dbname${NC}"
}

# Main menu
show_menu() {
    echo ""
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}PostgreSQL Logical Replication Manager${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo "1. Setup replication for all tables in a database"
    echo "2. Setup replication for specific tables"
    echo "3. Monitor replication status"
    echo "4. Disable replication"
    echo "5. Setup replication for multiple databases"
    echo "6. Exit"
    echo ""
}

# Main script
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Options:"
    echo "  --setup-all DB_NAME       Setup replication for all tables in database"
    echo "  --setup-tables DB_NAME TABLES   Setup replication for specific tables"
    echo "  --monitor DB_NAME         Monitor replication status"
    echo "  --disable DB_NAME         Disable replication"
    echo "  --batch                   Setup for multiple databases (interactive)"
    echo "  --help                    Show this help message"
    exit 0
fi

# Command line arguments
if [ ! -z "$1" ]; then
    case "$1" in
        --setup-all)
            setup_database_replication "$2"
            ;;
        --setup-tables)
            dbname=$2
            shift 2
            sync_tables "$dbname" "$@"
            ;;
        --monitor)
            monitor_replication "$2"
            ;;
        --disable)
            disable_replication "$2"
            ;;
        --batch)
            # Setup for multiple databases
            DATABASES="devmode serayuopakprogo wayseputihsekampung"
            for db in $DATABASES; do
                setup_database_replication "$db"
                echo ""
            done
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
else
    # Interactive mode
    while true; do
        show_menu
        read -p "Select option: " option

        case $option in
            1)
                read -p "Enter database name: " dbname
                setup_database_replication "$dbname"
                ;;
            2)
                read -p "Enter database name: " dbname
                read -p "Enter table names (space-separated): " tables
                sync_tables "$dbname" $tables
                ;;
            3)
                read -p "Enter database name: " dbname
                monitor_replication "$dbname"
                ;;
            4)
                read -p "Enter database name: " dbname
                disable_replication "$dbname"
                ;;
            5)
                read -p "Enter database names (space-separated): " databases
                for db in $databases; do
                    setup_database_replication "$db"
                    echo ""
                done
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
fi