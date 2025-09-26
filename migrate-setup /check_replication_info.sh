#!/bin/bash

# PostgreSQL Replication Information Tool
# Shows complete pub/sub relationships and replication status

# Database configuration
SOURCE_HOST="52.74.112.75"
SOURCE_PORT="5432"
SOURCE_USER="pg"
SOURCE_PASSWORD="~nagha2025yasha@~"

TARGET_HOST="52.74.112.75"
TARGET_PORT="6000"
TARGET_USER="pg"
TARGET_PASSWORD="p@ssw0rd1234"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

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

# Function to show header
show_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         PostgreSQL Logical Replication Information                    ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Function to check publications on source
check_publications() {
    local dbname=$1

    echo -e "${BLUE}═══ PUBLICATIONS on $SOURCE_HOST:$SOURCE_PORT (Database: $dbname) ═══${NC}"
    echo ""

    # List all publications
    echo -e "${YELLOW}Publications:${NC}"
    exec_source_sql "$dbname" "
        SELECT
            pubname AS \"Publication\",
            CASE
                WHEN puballtables THEN 'ALL TABLES'
                ELSE (SELECT COUNT(*)::text || ' tables' FROM pg_publication_tables WHERE pubname = p.pubname)
            END AS \"Scope\",
            CASE WHEN pubinsert THEN '✓' ELSE '✗' END AS \"INS\",
            CASE WHEN pubupdate THEN '✓' ELSE '✗' END AS \"UPD\",
            CASE WHEN pubdelete THEN '✓' ELSE '✗' END AS \"DEL\",
            CASE WHEN pubtruncate THEN '✓' ELSE '✗' END AS \"TRUNC\"
        FROM pg_publication p
        ORDER BY pubname;
    "

    # Show publication tables
    echo -e "\n${YELLOW}Publication Tables:${NC}"
    exec_source_sql "$dbname" "
        SELECT
            p.pubname AS \"Publication\",
            pt.schemaname || '.' || pt.tablename AS \"Table\",
            pg_size_pretty(pg_relation_size((pt.schemaname || '.' || pt.tablename)::regclass)) AS \"Size\"
        FROM pg_publication p
        JOIN pg_publication_tables pt ON p.pubname = pt.pubname
        ORDER BY p.pubname, pt.tablename
        LIMIT 20;
    "

    # Show replication slots (who's subscribing)
    echo -e "\n${YELLOW}Replication Slots (Subscribers):${NC}"
    exec_source_sql "$dbname" "
        SELECT
            slot_name AS \"Slot Name\",
            COALESCE(
                (SELECT client_addr::text FROM pg_stat_replication WHERE pid = rs.active_pid),
                'Not Connected'
            ) AS \"Subscriber IP\",
            active AS \"Active\",
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS \"Lag\"
        FROM pg_replication_slots rs
        WHERE slot_type = 'logical' AND database = '$dbname'
        ORDER BY slot_name;
    "
}

# Function to check subscriptions on target
check_subscriptions() {
    local dbname=$1

    echo -e "\n${BLUE}═══ SUBSCRIPTIONS on $TARGET_HOST:$TARGET_PORT (Database: $dbname) ═══${NC}"
    echo ""

    # List all subscriptions
    echo -e "${YELLOW}Subscriptions:${NC}"
    exec_target_sql "$dbname" "
        SELECT
            subname AS \"Subscription\",
            subenabled AS \"Enabled\",
            subpublications[1] AS \"Publication\",
            substring(subconninfo from 'host=([^ ]+)') AS \"Publisher Host\",
            substring(subconninfo from 'port=([0-9]+)') AS \"Port\",
            substring(subconninfo from 'dbname=([^ ]+)') AS \"Source DB\"
        FROM pg_subscription
        ORDER BY subname;
    "

    # Show subscription table status
    echo -e "\n${YELLOW}Subscription Table Status:${NC}"
    exec_target_sql "$dbname" "
        SELECT
            s.subname AS \"Subscription\",
            c.relname AS \"Table\",
            CASE sr.srsubstate
                WHEN 'i' THEN 'initializing'
                WHEN 'd' THEN 'copying data'
                WHEN 'f' THEN 'finished copy'
                WHEN 's' THEN 'synchronized'
                WHEN 'r' THEN 'ready'
                ELSE sr.srsubstate
            END AS \"Sync State\",
            pg_size_pretty(pg_relation_size(c.oid)) AS \"Size\"
        FROM pg_subscription s
        JOIN pg_subscription_rel sr ON s.oid = sr.srsubid
        JOIN pg_class c ON sr.srrelid = c.oid
        ORDER BY s.subname, c.relname
        LIMIT 20;
    "

    # Show subscription workers
    echo -e "\n${YELLOW}Subscription Workers:${NC}"
    exec_target_sql "$dbname" "
        SELECT
            s.subname AS \"Subscription\",
            COALESCE(w.pid::text, 'No worker') AS \"Worker PID\",
            CASE
                WHEN w.pid IS NOT NULL THEN 'Active'
                ELSE 'Inactive'
            END AS \"Status\",
            w.received_lsn AS \"Received LSN\",
            age(now(), w.last_msg_receipt_time) AS \"Last Message Age\"
        FROM pg_subscription s
        LEFT JOIN pg_stat_subscription w ON s.oid = w.subid
        ORDER BY s.subname;
    "
}

# Function to show complete mapping
show_complete_mapping() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    REPLICATION TOPOLOGY MAP                           ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    echo -e "${MAGENTA}Publisher → Subscriber Relationships:${NC}"
    echo ""

    # For each database, show the connections
    local databases=${1:-"devmode serayuopakprogo"}

    for db in $databases; do
        echo -e "${GREEN}Database: $db${NC}"
        echo "├─ ${BLUE}Publisher ($SOURCE_HOST:$SOURCE_PORT)${NC}"

        # Get publications
        local pubs=$(docker run --rm \
            -e PGPASSWORD="$SOURCE_PASSWORD" \
            postgres:16 \
            psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
            -d "$db" -tAc "SELECT pubname FROM pg_publication" 2>/dev/null)

        if [ ! -z "$pubs" ]; then
            echo "$pubs" | while read pub; do
                echo "│  ├─ Publication: ${YELLOW}$pub${NC}"

                # Check for subscribers
                local slots=$(docker run --rm \
                    -e PGPASSWORD="$SOURCE_PASSWORD" \
                    postgres:16 \
                    psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
                    -d "$db" -tAc "
                        SELECT slot_name || ' (' ||
                            COALESCE((SELECT client_addr::text FROM pg_stat_replication WHERE pid = rs.active_pid), 'disconnected') || ')'
                        FROM pg_replication_slots rs
                        WHERE database = '$db' AND slot_type = 'logical' AND slot_name LIKE '%${db}%'
                    " 2>/dev/null)

                if [ ! -z "$slots" ]; then
                    echo "$slots" | while read slot; do
                        echo "│  │  └─ Subscriber slot: ${CYAN}$slot${NC}"
                    done
                fi
            done
        else
            echo "│  └─ No publications"
        fi

        echo "│"
        echo "└─ ${BLUE}Subscriber ($TARGET_HOST:$TARGET_PORT)${NC}"

        # Get subscriptions
        local subs=$(docker run --rm \
            -e PGPASSWORD="$TARGET_PASSWORD" \
            postgres:16 \
            psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
            -d "$db" -tAc "SELECT subname FROM pg_subscription" 2>/dev/null)

        if [ ! -z "$subs" ]; then
            echo "$subs" | while read sub; do
                echo "   ├─ Subscription: ${YELLOW}$sub${NC}"

                # Get publication it subscribes to
                local pub_info=$(docker run --rm \
                    -e PGPASSWORD="$TARGET_PASSWORD" \
                    postgres:16 \
                    psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
                    -d "$db" -tAc "
                        SELECT 'subscribes to: ' || array_to_string(subpublications, ', ') ||
                               ' from ' || substring(subconninfo from 'host=([^ ]+)')
                        FROM pg_subscription WHERE subname = '$sub'
                    " 2>/dev/null)

                if [ ! -z "$pub_info" ]; then
                    echo "   │  └─ ${pub_info}"
                fi
            done
        else
            echo "   └─ No subscriptions"
        fi

        echo ""
    done
}

# Function to check specific database
check_database() {
    local dbname=$1

    show_header
    check_publications "$dbname"
    check_subscriptions "$dbname"
}

# Function to generate summary report
generate_summary() {
    echo -e "\n${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                         SUMMARY REPORT                                ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    local databases=${1:-"devmode serayuopakprogo"}

    echo -e "${YELLOW}Replication Configuration Summary:${NC}"
    echo ""

    for db in $databases; do
        echo -e "${GREEN}Database: $db${NC}"

        # Count publications
        local pub_count=$(docker run --rm \
            -e PGPASSWORD="$SOURCE_PASSWORD" \
            postgres:16 \
            psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
            -d "$db" -tAc "SELECT COUNT(*) FROM pg_publication" 2>/dev/null)

        # Count subscriptions
        local sub_count=$(docker run --rm \
            -e PGPASSWORD="$TARGET_PASSWORD" \
            postgres:16 \
            psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
            -d "$db" -tAc "SELECT COUNT(*) FROM pg_subscription" 2>/dev/null)

        # Count active slots
        local slot_count=$(docker run --rm \
            -e PGPASSWORD="$SOURCE_PASSWORD" \
            postgres:16 \
            psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
            -d "$db" -tAc "SELECT COUNT(*) FROM pg_replication_slots WHERE database = '$db' AND active = true" 2>/dev/null)

        echo "  Publications: ${pub_count:-0}"
        echo "  Subscriptions: ${sub_count:-0}"
        echo "  Active Slots: ${slot_count:-0}"
        echo ""
    done
}

# Main menu
show_menu() {
    echo ""
    echo "Select an option:"
    echo "1. Check specific database"
    echo "2. Show complete replication topology"
    echo "3. Check all publications (source)"
    echo "4. Check all subscriptions (target)"
    echo "5. Generate summary report"
    echo "6. Run SQL query file"
    echo "7. Exit"
    echo ""
}

# Main script
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTIONS] [DATABASE]"
    echo ""
    echo "Show PostgreSQL logical replication pub/sub information"
    echo ""
    echo "Options:"
    echo "  --db DATABASE        Check specific database"
    echo "  --topology          Show complete replication topology"
    echo "  --publications      Check all publications"
    echo "  --subscriptions     Check all subscriptions"
    echo "  --summary           Generate summary report"
    echo "  --sql               Run SQL queries from file"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --db devmode"
    echo "  $0 --topology"
    echo "  $0 --summary"
    exit 0
fi

# Handle command line arguments
if [ ! -z "$1" ]; then
    case "$1" in
        --db)
            check_database "$2"
            ;;
        --topology)
            show_complete_mapping "$2"
            ;;
        --publications)
            dbname=${2:-"postgres"}
            check_publications "$dbname"
            ;;
        --subscriptions)
            dbname=${2:-"postgres"}
            check_subscriptions "$dbname"
            ;;
        --summary)
            generate_summary "$2"
            ;;
        --sql)
            echo "Running SQL queries from check_replication_status.sql..."
            echo "Choose target:"
            echo "1. Source/Publisher ($SOURCE_HOST:$SOURCE_PORT)"
            echo "2. Target/Subscriber ($TARGET_HOST:$TARGET_PORT)"
            read -p "Select (1 or 2): " target
            read -p "Enter database name: " dbname

            if [ "$target" = "1" ]; then
                docker run --rm \
                    -e PGPASSWORD="$SOURCE_PASSWORD" \
                    -v "$(pwd):/scripts" \
                    postgres:16 \
                    psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
                    -d "$dbname" -f /scripts/check_replication_status.sql
            else
                docker run --rm \
                    -e PGPASSWORD="$TARGET_PASSWORD" \
                    -v "$(pwd):/scripts" \
                    postgres:16 \
                    psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
                    -d "$dbname" -f /scripts/check_replication_status.sql
            fi
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
else
    # Interactive mode
    show_header

    while true; do
        show_menu
        read -p "Select option: " option

        case $option in
            1)
                read -p "Enter database name: " dbname
                check_database "$dbname"
                ;;
            2)
                read -p "Enter databases (space-separated, or press Enter for default): " databases
                show_complete_mapping "${databases:-devmode serayuopakprogo}"
                ;;
            3)
                read -p "Enter database name: " dbname
                check_publications "$dbname"
                ;;
            4)
                read -p "Enter database name: " dbname
                check_subscriptions "$dbname"
                ;;
            5)
                read -p "Enter databases (space-separated, or press Enter for default): " databases
                generate_summary "${databases:-devmode serayuopakprogo}"
                ;;
            6)
                echo "Choose target:"
                echo "1. Source/Publisher"
                echo "2. Target/Subscriber"
                read -p "Select (1 or 2): " target
                read -p "Enter database name: " dbname

                if [ "$target" = "1" ]; then
                    docker run --rm \
                        -e PGPASSWORD="$SOURCE_PASSWORD" \
                        -v "$(pwd):/scripts" \
                        postgres:16 \
                        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
                        -d "$dbname" -f /scripts/check_replication_status.sql
                else
                    docker run --rm \
                        -e PGPASSWORD="$TARGET_PASSWORD" \
                        -v "$(pwd):/scripts" \
                        postgres:16 \
                        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
                        -d "$dbname" -f /scripts/check_replication_status.sql
                fi
                ;;
            7)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac

        echo ""
        read -p "Press Enter to continue..."
    done
fi