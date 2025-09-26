#!/bin/bash

# PostgreSQL Replication Monitoring Script
# Continuously monitors replication status and lag

# Source database configuration
SOURCE_HOST="52.74.112.75"
SOURCE_PORT="5432"
SOURCE_USER="pg"
SOURCE_PASSWORD="~nagha2025yasha@~"

# Target database configuration
TARGET_HOST="52.74.112.75"
TARGET_PORT="6000"
TARGET_USER="pg"
TARGET_PASSWORD="p@ssw0rd1234"

# Monitoring configuration
REFRESH_INTERVAL=5  # seconds
ALERT_LAG_BYTES=10485760  # Alert if lag > 10MB

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to clear screen
clear_screen() {
    printf "\033c"
}

# Function to execute SQL on source
exec_source_sql() {
    docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgres:16 \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$1" -tAc "$2" 2>/dev/null
}

# Function to execute SQL on target
exec_target_sql() {
    docker run --rm \
        -e PGPASSWORD="$TARGET_PASSWORD" \
        postgres:16 \
        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
        -d "$1" -tAc "$2" 2>/dev/null
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" = "0" ]; then
        echo "0 B"
    elif [ $bytes -lt 1024 ]; then
        echo "$bytes B"
    elif [ $bytes -lt 1048576 ]; then
        echo "$(( bytes / 1024 )) KB"
    elif [ $bytes -lt 1073741824 ]; then
        echo "$(( bytes / 1048576 )) MB"
    else
        echo "$(( bytes / 1073741824 )) GB"
    fi
}

# Function to get replication status
get_replication_status() {
    local dbname=$1

    # Get publication info
    local pub_info=$(exec_source_sql "$dbname" "
        SELECT
            pubname,
            puballtables,
            (SELECT count(*) FROM pg_publication_tables WHERE pubname = p.pubname) as table_count
        FROM pg_publication p
        WHERE pubname LIKE 'source_publication_%'
    ")

    # Get subscription info
    local sub_info=$(exec_target_sql "$dbname" "
        SELECT
            s.subname,
            s.subenabled,
            CASE
                WHEN s.subenabled THEN 'Active'
                ELSE 'Inactive'
            END as status,
            (SELECT count(*) FROM pg_subscription_rel WHERE srsubid = s.oid) as table_count,
            (SELECT count(*) FROM pg_subscription_rel WHERE srsubid = s.oid AND srsubstate = 'r') as synced_tables
        FROM pg_subscription s
        WHERE s.subname LIKE 'sub_%'
    ")

    # Get replication slot info
    local slot_info=$(exec_source_sql "postgres" "
        SELECT
            slot_name,
            active,
            COALESCE(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn), 0) AS lag_bytes
        FROM pg_replication_slots
        WHERE slot_name LIKE 'sub_${dbname}%'
    ")

    echo "$pub_info|$sub_info|$slot_info"
}

# Function to display dashboard header
display_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║           PostgreSQL Logical Replication Monitor                      ║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Source: ${BLUE}$SOURCE_HOST:$SOURCE_PORT${NC}  →  Target: ${BLUE}$TARGET_HOST:$TARGET_PORT${NC}"
    echo -e "${CYAN}║${NC} Refresh: Every ${YELLOW}${REFRESH_INTERVAL}s${NC}     Press ${RED}Ctrl+C${NC} to exit"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to display database replication status
display_database_status() {
    local dbname=$1
    local status_data=$2

    IFS='|' read -r pub_info sub_info slot_info <<< "$status_data"

    echo -e "${YELLOW}┌─ Database: ${BLUE}$dbname${NC}"

    # Parse publication info
    if [ ! -z "$pub_info" ]; then
        IFS=$'\t' read -r pubname puballtables table_count <<< "$pub_info"
        echo -e "${YELLOW}├─${NC} Publication: ${GREEN}$pubname${NC}"
        echo -e "${YELLOW}│ ${NC} Tables: $table_count $([ "$puballtables" = "t" ] && echo "(All Tables)" || echo "(Selected Tables)")"
    else
        echo -e "${YELLOW}├─${NC} Publication: ${RED}Not configured${NC}"
    fi

    # Parse subscription info
    if [ ! -z "$sub_info" ]; then
        IFS=$'\t' read -r subname subenabled status table_count synced_tables <<< "$sub_info"
        if [ "$status" = "Active" ]; then
            echo -e "${YELLOW}├─${NC} Subscription: ${GREEN}$subname ($status)${NC}"
        else
            echo -e "${YELLOW}├─${NC} Subscription: ${RED}$subname ($status)${NC}"
        fi
        echo -e "${YELLOW}│ ${NC} Synced Tables: $synced_tables / $table_count"
    else
        echo -e "${YELLOW}├─${NC} Subscription: ${RED}Not configured${NC}"
    fi

    # Parse slot info
    if [ ! -z "$slot_info" ]; then
        IFS=$'\t' read -r slot_name active lag_bytes <<< "$slot_info"
        local formatted_lag=$(format_bytes ${lag_bytes:-0})

        if [ "$active" = "t" ]; then
            echo -e "${YELLOW}├─${NC} Slot: ${GREEN}$slot_name (Active)${NC}"
        else
            echo -e "${YELLOW}├─${NC} Slot: ${YELLOW}$slot_name (Inactive)${NC}"
        fi

        if [ "${lag_bytes:-0}" -gt "$ALERT_LAG_BYTES" ]; then
            echo -e "${YELLOW}└─${NC} Replication Lag: ${RED}$formatted_lag ⚠${NC}"
        else
            echo -e "${YELLOW}└─${NC} Replication Lag: ${GREEN}$formatted_lag ✓${NC}"
        fi
    else
        echo -e "${YELLOW}└─${NC} Slot: ${RED}Not configured${NC}"
    fi

    echo ""
}

# Function to get table-level statistics
get_table_stats() {
    local dbname=$1

    # Get row counts from source
    local source_counts=$(exec_source_sql "$dbname" "
        SELECT
            schemaname || '.' || tablename as table_name,
            n_live_tup as row_count
        FROM pg_stat_user_tables
        ORDER BY n_live_tup DESC
        LIMIT 10
    ")

    # Get row counts from target
    local target_counts=$(exec_target_sql "$dbname" "
        SELECT
            schemaname || '.' || tablename as table_name,
            n_live_tup as row_count
        FROM pg_stat_user_tables
        ORDER BY n_live_tup DESC
        LIMIT 10
    ")

    echo -e "${CYAN}Top Tables by Row Count:${NC}"
    echo -e "${YELLOW}Source Database:${NC}"
    if [ ! -z "$source_counts" ]; then
        echo "$source_counts" | while IFS=$'\t' read -r table_name row_count; do
            printf "  %-40s %10s rows\n" "$table_name" "$row_count"
        done
    else
        echo "  No tables found"
    fi

    echo -e "${YELLOW}Target Database:${NC}"
    if [ ! -z "$target_counts" ]; then
        echo "$target_counts" | while IFS=$'\t' read -r table_name row_count; do
            printf "  %-40s %10s rows\n" "$table_name" "$row_count"
        done
    else
        echo "  No tables found"
    fi
}

# Function for continuous monitoring
continuous_monitor() {
    local databases=$@

    while true; do
        clear_screen
        display_header

        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo -e "${CYAN}Last Update: $timestamp${NC}"
        echo ""

        for db in $databases; do
            local status=$(get_replication_status "$db")
            display_database_status "$db" "$status"
        done

        # Show overall statistics
        echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${CYAN}║                        System Statistics                             ║${NC}"
        echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"

        # Get total replication slots
        local total_slots=$(exec_source_sql "postgres" "SELECT count(*) FROM pg_replication_slots")
        local active_slots=$(exec_source_sql "postgres" "SELECT count(*) FROM pg_replication_slots WHERE active = true")

        echo -e "Replication Slots: ${GREEN}$active_slots${NC} active / $total_slots total"

        # Get WAL statistics
        local wal_size=$(exec_source_sql "postgres" "SELECT pg_size_pretty(sum(size)) FROM pg_ls_waldir()")
        echo -e "WAL Size: $wal_size"

        sleep $REFRESH_INTERVAL
    done
}

# Function for single check
single_check() {
    local databases=$@

    display_header

    for db in $databases; do
        local status=$(get_replication_status "$db")
        display_database_status "$db" "$status"
    done
}

# Main script
echo -e "${CYAN}PostgreSQL Replication Monitor${NC}"
echo ""

# Parse arguments
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTIONS] [DATABASES]"
    echo ""
    echo "Monitor PostgreSQL logical replication status"
    echo ""
    echo "Options:"
    echo "  --continuous, -c    Continuous monitoring mode (default)"
    echo "  --once, -o          Check once and exit"
    echo "  --interval N        Set refresh interval in seconds (default: 5)"
    echo "  --stats DB          Show detailed table statistics for database"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Monitor all databases continuously"
    echo "  $0 -o devmode serayuopakprogo  # Check specific databases once"
    echo "  $0 --interval 10 devmode    # Monitor with 10 second refresh"
    echo "  $0 --stats devmode           # Show table statistics"
    exit 0
fi

# Handle command line options
MODE="continuous"
DATABASES=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --continuous|-c)
            MODE="continuous"
            shift
            ;;
        --once|-o)
            MODE="once"
            shift
            ;;
        --interval)
            REFRESH_INTERVAL="$2"
            shift 2
            ;;
        --stats)
            get_table_stats "$2"
            exit 0
            ;;
        *)
            DATABASES="$DATABASES $1"
            shift
            ;;
    esac
done

# If no databases specified, get all subscribed databases
if [ -z "$DATABASES" ]; then
    DATABASES=$(exec_target_sql "postgres" "SELECT datname FROM pg_database WHERE datname NOT IN ('postgres', 'template0', 'template1') ORDER BY datname")
    if [ -z "$DATABASES" ]; then
        echo -e "${YELLOW}No databases found with subscriptions${NC}"
        echo "Use setup_logical_replication.sh to configure replication first"
        exit 1
    fi
fi

# Run monitoring
if [ "$MODE" = "continuous" ]; then
    echo "Starting continuous monitoring..."
    echo "Monitoring databases: $DATABASES"
    echo ""
    sleep 2
    continuous_monitor $DATABASES
else
    single_check $DATABASES
fi