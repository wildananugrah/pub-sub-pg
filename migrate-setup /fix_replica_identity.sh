#!/bin/bash

# Fix replica identity for tables to allow DELETE operations in logical replication
# This script sets the appropriate replica identity for tables

# Source database configuration
SOURCE_HOST="52.74.112.75"
SOURCE_PORT="6000"
SOURCE_USER="pg"
SOURCE_PASSWORD="p@ssw0rd1234"

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
        postgis/postgis \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$1" -c "$2"
}

# Function to fix replica identity for a single table
fix_table_replica_identity() {
    local dbname=$1
    local schema=$2
    local table=$3

    echo -e "${YELLOW}Checking replica identity for ${schema}.${table}...${NC}"

    # Check if table has a primary key
    PK_EXISTS=$(docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgis/postgis \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$dbname" -tAc "
        SELECT COUNT(*)
        FROM pg_constraint
        WHERE contype = 'p'
        AND conrelid = '${schema}.${table}'::regclass;")

    if [ "$PK_EXISTS" = "1" ]; then
        # Table has primary key, use DEFAULT (which uses PK)
        echo -e "${GREEN}  Table has primary key, setting REPLICA IDENTITY DEFAULT${NC}"
        exec_source_sql "$dbname" "ALTER TABLE ${schema}.${table} REPLICA IDENTITY DEFAULT;"
    else
        # No primary key, check for unique index
        UNIQUE_EXISTS=$(docker run --rm \
            -e PGPASSWORD="$SOURCE_PASSWORD" \
            postgis/postgis \
            psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
            -d "$dbname" -tAc "
            SELECT COUNT(*)
            FROM pg_indexes
            WHERE schemaname = '${schema}'
            AND tablename = '${table}'
            AND indexdef LIKE '%UNIQUE%';")

        if [ "$UNIQUE_EXISTS" -gt "0" ]; then
            # Has unique index, can use USING INDEX
            echo -e "${YELLOW}  Table has unique index, you can set REPLICA IDENTITY USING INDEX${NC}"
            echo "  Run: ALTER TABLE ${schema}.${table} REPLICA IDENTITY USING INDEX <index_name>;"
        else
            # No PK or unique index, use FULL (less efficient but works)
            echo -e "${YELLOW}  No primary key or unique index, setting REPLICA IDENTITY FULL${NC}"
            exec_source_sql "$dbname" "ALTER TABLE ${schema}.${table} REPLICA IDENTITY FULL;"
            echo -e "${YELLOW}  Warning: REPLICA IDENTITY FULL is less efficient for replication${NC}"
        fi
    fi
}

# Function to fix all tables in a database
fix_all_tables() {
    local dbname=$1

    echo -e "${BLUE}=========================================${NC}"
    echo -e "${BLUE}Fixing replica identity for database: $dbname${NC}"
    echo -e "${BLUE}=========================================${NC}"

    # Get all tables that are part of the publication
    TABLES=$(docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgis/postgis \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$dbname" -tAc "
        SELECT DISTINCT schemaname || '.' || tablename
        FROM pg_publication_tables
        WHERE pubname LIKE 'source_publication_%';")

    if [ -z "$TABLES" ]; then
        echo -e "${YELLOW}No tables found in publication${NC}"

        # If no publication, get all user tables
        echo -e "${YELLOW}Getting all user tables instead...${NC}"
        TABLES=$(docker run --rm \
            -e PGPASSWORD="$SOURCE_PASSWORD" \
            postgis/postgis \
            psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
            -d "$dbname" -tAc "
            SELECT schemaname || '.' || tablename
            FROM pg_tables
            WHERE schemaname NOT IN ('pg_catalog', 'information_schema')
            ORDER BY schemaname, tablename;")
    fi

    # Process each table
    for table_full in $TABLES; do
        schema=$(echo $table_full | cut -d'.' -f1)
        table=$(echo $table_full | cut -d'.' -f2)
        fix_table_replica_identity "$dbname" "$schema" "$table"
    done

    echo -e "${GREEN}✓ Replica identity fix completed for $dbname${NC}"
}

# Function to check current replica identity status
check_replica_identity() {
    local dbname=$1

    echo -e "${BLUE}Current replica identity status for $dbname:${NC}"

    docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgis/postgis \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$dbname" -c "
        SELECT
            c.relnamespace::regnamespace AS schema,
            c.relname AS table,
            CASE c.relreplident
                WHEN 'd' THEN 'DEFAULT (primary key)'
                WHEN 'f' THEN 'FULL (all columns)'
                WHEN 'i' THEN 'USING INDEX'
                WHEN 'n' THEN 'NOTHING'
            END AS replica_identity
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE c.relkind = 'r'
        AND n.nspname NOT IN ('pg_catalog', 'information_schema')
        ORDER BY n.nspname, c.relname;"
}

# Main script
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTION] DATABASE [TABLE]"
    echo ""
    echo "Options:"
    echo "  --fix-all DATABASE        Fix replica identity for all tables"
    echo "  --fix-table DATABASE SCHEMA.TABLE   Fix specific table"
    echo "  --check DATABASE          Check current replica identity status"
    echo "  --help                    Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --fix-all postgres"
    echo "  $0 --fix-table postgres public.roles"
    echo "  $0 --check postgres"
    exit 0
fi

case "$1" in
    --fix-all)
        fix_all_tables "$2"
        ;;
    --fix-table)
        if [ -z "$3" ]; then
            echo "Error: Please specify schema.table"
            exit 1
        fi
        schema=$(echo $3 | cut -d'.' -f1)
        table=$(echo $3 | cut -d'.' -f2)
        fix_table_replica_identity "$2" "$schema" "$table"
        ;;
    --check)
        check_replica_identity "$2"
        ;;
    *)
        echo "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac