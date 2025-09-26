#!/bin/bash

# Cleanup script to remove all replication components
# This will remove all subscriptions, publications, and replication slots

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source database configuration
SOURCE_HOST="52.74.112.75"
SOURCE_PORT="6000"
SOURCE_USER="pg"
SOURCE_PASSWORD="p@ssw0rd1234"

# Target database configuration
TARGET_HOST="100.89.22.125"
TARGET_PORT="6000"
TARGET_USER="pg"
TARGET_PASSWORD="p@ssw0rd1234"

# Function to execute SQL on source
exec_source_sql() {
    docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgis/postgis \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "${1:-postgres}" -c "$2"
}

# Function to execute SQL on target
exec_target_sql() {
    docker run --rm \
        -e PGPASSWORD="$TARGET_PASSWORD" \
        postgis/postgis \
        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
        -d "${1:-postgres}" -c "$2"
}

# Function to cleanup all subscriptions on target
cleanup_subscriptions() {
    local dbname=${1:-"all"}

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Removing Subscriptions from Target${NC}"
    echo -e "${BLUE}=========================================${NC}"

    if [ "$dbname" = "all" ]; then
        # Get all databases
        DATABASES=$(docker run --rm \
            -e PGPASSWORD="$TARGET_PASSWORD" \
            postgis/postgis \
            psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
            -d postgres -tAc "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1');" 2>/dev/null)

        for db in $DATABASES; do
            echo -e "${YELLOW}Checking database: $db${NC}"

            # List subscriptions in this database
            SUBS=$(docker run --rm \
                -e PGPASSWORD="$TARGET_PASSWORD" \
                postgis/postgis \
                psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
                -d "$db" -tAc "SELECT subname FROM pg_subscription;" 2>/dev/null)

            if [ -n "$SUBS" ]; then
                echo -e "${YELLOW}Found subscriptions in $db:${NC}"
                echo "$SUBS"

                # Drop all subscriptions
                exec_target_sql "$db" "DO \$\$
                DECLARE
                    r RECORD;
                BEGIN
                    FOR r IN SELECT subname FROM pg_subscription
                    LOOP
                        EXECUTE format('DROP SUBSCRIPTION IF EXISTS %I CASCADE', r.subname);
                        RAISE NOTICE 'Dropped subscription: %', r.subname;
                    END LOOP;
                END \$\$;"

                echo -e "${GREEN}✓ Removed subscriptions from $db${NC}"
            else
                echo -e "${GREEN}  No subscriptions in $db${NC}"
            fi
        done
    else
        # Remove from specific database
        echo -e "${YELLOW}Removing subscriptions from database: $dbname${NC}"

        # List subscriptions
        SUBS=$(exec_target_sql "$dbname" "SELECT subname FROM pg_subscription;" 2>/dev/null | grep -v "subname" | grep -v "row")

        if [ -n "$SUBS" ]; then
            echo "Found subscriptions: $SUBS"

            exec_target_sql "$dbname" "DO \$\$
            DECLARE
                r RECORD;
            BEGIN
                FOR r IN SELECT subname FROM pg_subscription
                LOOP
                    EXECUTE format('DROP SUBSCRIPTION IF EXISTS %I CASCADE', r.subname);
                    RAISE NOTICE 'Dropped subscription: %', r.subname;
                END LOOP;
            END \$\$;"

            echo -e "${GREEN}✓ Removed subscriptions from $dbname${NC}"
        else
            echo -e "${GREEN}No subscriptions found in $dbname${NC}"
        fi
    fi
}

# Function to cleanup all publications on source
cleanup_publications() {
    local dbname=${1:-"all"}

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Removing Publications from Source${NC}"
    echo -e "${BLUE}=========================================${NC}"

    if [ "$dbname" = "all" ]; then
        # Get all databases
        DATABASES=$(docker run --rm \
            -e PGPASSWORD="$SOURCE_PASSWORD" \
            postgis/postgis \
            psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
            -d postgres -tAc "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1');" 2>/dev/null)

        for db in $DATABASES; do
            echo -e "${YELLOW}Checking database: $db${NC}"

            # List publications
            PUBS=$(docker run --rm \
                -e PGPASSWORD="$SOURCE_PASSWORD" \
                postgis/postgis \
                psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
                -d "$db" -tAc "SELECT pubname FROM pg_publication;" 2>/dev/null)

            if [ -n "$PUBS" ]; then
                echo -e "${YELLOW}Found publications in $db:${NC}"
                echo "$PUBS"

                # Drop all publications
                exec_source_sql "$db" "DO \$\$
                DECLARE
                    r RECORD;
                BEGIN
                    FOR r IN SELECT pubname FROM pg_publication
                    LOOP
                        EXECUTE format('DROP PUBLICATION IF EXISTS %I CASCADE', r.pubname);
                        RAISE NOTICE 'Dropped publication: %', r.pubname;
                    END LOOP;
                END \$\$;"

                echo -e "${GREEN}✓ Removed publications from $db${NC}"
            else
                echo -e "${GREEN}  No publications in $db${NC}"
            fi
        done
    else
        # Remove from specific database
        echo -e "${YELLOW}Removing publications from database: $dbname${NC}"

        exec_source_sql "$dbname" "DO \$\$
        DECLARE
            r RECORD;
        BEGIN
            FOR r IN SELECT pubname FROM pg_publication
            LOOP
                EXECUTE format('DROP PUBLICATION IF EXISTS %I CASCADE', r.pubname);
                RAISE NOTICE 'Dropped publication: %', r.pubname;
            END LOOP;
        END \$\$;"

        echo -e "${GREEN}✓ Removed publications from $dbname${NC}"
    fi
}

# Function to cleanup replication slots
cleanup_replication_slots() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Removing Replication Slots from Source${NC}"
    echo -e "${BLUE}=========================================${NC}"

    # List all replication slots
    echo -e "${YELLOW}Current replication slots:${NC}"
    exec_source_sql postgres "SELECT slot_name, active FROM pg_replication_slots;"

    # Drop inactive slots
    exec_source_sql postgres "SELECT pg_drop_replication_slot(slot_name) FROM pg_replication_slots WHERE NOT active;"

    # Try to drop active slots (may fail if still in use)
    exec_source_sql postgres "DO \$\$
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN SELECT slot_name FROM pg_replication_slots WHERE active
        LOOP
            BEGIN
                PERFORM pg_drop_replication_slot(r.slot_name);
                RAISE NOTICE 'Dropped slot: %', r.slot_name;
            EXCEPTION
                WHEN OTHERS THEN
                    RAISE NOTICE 'Could not drop active slot: % (still in use)', r.slot_name;
            END;
        END LOOP;
    END \$\$;"

    echo -e "${GREEN}✓ Cleaned up replication slots${NC}"
}

# Show menu
show_menu() {
    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}PostgreSQL Replication Cleanup${NC}"
    echo -e "${BLUE}=========================================${NC}"
    echo
    echo "What would you like to remove?"
    echo
    echo "1. Remove all subscriptions (target only)"
    echo "2. Remove all publications (source only)"
    echo "3. Remove replication slots (source only)"
    echo "4. Complete cleanup (remove everything)"
    echo "5. Remove for specific database"
    echo "6. Exit"
    echo
}

# Main script
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [OPTION]"
    echo
    echo "Options:"
    echo "  --all                    Remove all replication components"
    echo "  --subscriptions [DB]     Remove all subscriptions (optionally for specific DB)"
    echo "  --publications [DB]      Remove all publications (optionally for specific DB)"
    echo "  --slots                  Remove replication slots"
    echo "  --db DATABASE            Remove all components for specific database"
    echo "  --help                   Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --all                 # Complete cleanup"
    echo "  $0 --subscriptions       # Remove all subscriptions"
    echo "  $0 --subscriptions postgres  # Remove subscriptions from postgres DB"
    echo "  $0 --db postgres         # Remove all components for postgres DB"
    exit 0
fi

# Handle command line arguments
if [ -n "$1" ]; then
    case "$1" in
        --all)
            cleanup_subscriptions "all"
            cleanup_publications "all"
            cleanup_replication_slots
            echo -e "${GREEN}${BOLD}✓ Complete cleanup finished!${NC}"
            ;;
        --subscriptions)
            cleanup_subscriptions "${2:-all}"
            ;;
        --publications)
            cleanup_publications "${2:-all}"
            ;;
        --slots)
            cleanup_replication_slots
            ;;
        --db)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Please specify database name${NC}"
                exit 1
            fi
            cleanup_subscriptions "$2"
            cleanup_publications "$2"
            echo -e "${GREEN}✓ Cleanup completed for database: $2${NC}"
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
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
                cleanup_subscriptions "all"
                ;;
            2)
                cleanup_publications "all"
                ;;
            3)
                cleanup_replication_slots
                ;;
            4)
                cleanup_subscriptions "all"
                cleanup_publications "all"
                cleanup_replication_slots
                echo -e "${GREEN}${BOLD}✓ Complete cleanup finished!${NC}"
                ;;
            5)
                read -p "Enter database name: " dbname
                cleanup_subscriptions "$dbname"
                cleanup_publications "$dbname"
                ;;
            6)
                echo "Exiting..."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac

        echo
        read -p "Press Enter to continue..."
    done
fi