#!/bin/bash

# Database Structure Comparison Script
# Compares source and target PostgreSQL databases for structural differences
# Checks: databases, schemas, tables, columns, and data types

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

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# Counters for summary
TOTAL_CHECKS=0
DIFFERENCES=0
MATCHES=0

# Temporary files for comparisons
TEMP_DIR="/tmp/db_compare_$$"
mkdir -p "$TEMP_DIR"

# Cleanup on exit
trap "rm -rf $TEMP_DIR" EXIT

# Function to execute SQL on source
exec_source_sql() {
    local db=${1:-postgres}
    local sql=$2
    docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        postgis/postgis \
        psql -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$db" -tAc "$sql" 2>/dev/null
}

# Function to execute SQL on target
exec_target_sql() {
    local db=${1:-postgres}
    local sql=$2
    docker run --rm \
        -e PGPASSWORD="$TARGET_PASSWORD" \
        postgis/postgis \
        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
        -d "$db" -tAc "$sql" 2>/dev/null
}

# Function to print section header
print_header() {
    echo
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}${BOLD}  $1${NC}"
    echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════════════${NC}"
}

# Function to print subsection
print_subsection() {
    echo
    echo -e "${CYAN}─── $1 ───${NC}"
}

# Function to log difference
log_difference() {
    ((DIFFERENCES++))
    ((TOTAL_CHECKS++))
}

# Function to log match
log_match() {
    ((MATCHES++))
    ((TOTAL_CHECKS++))
}

# 1. Compare Databases
compare_databases() {
    print_header "1. DATABASE COMPARISON"

    echo -e "${YELLOW}Fetching database lists...${NC}"

    # Get databases from source (excluding templates and postgres maintenance db)
    exec_source_sql postgres "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres') ORDER BY datname;" > "$TEMP_DIR/source_dbs.txt"

    # Get databases from target
    exec_target_sql postgres "SELECT datname FROM pg_database WHERE datname NOT IN ('template0', 'template1', 'postgres') ORDER BY datname;" > "$TEMP_DIR/target_dbs.txt"

    # Compare lists
    print_subsection "Databases only in SOURCE"
    comm -23 "$TEMP_DIR/source_dbs.txt" "$TEMP_DIR/target_dbs.txt" > "$TEMP_DIR/only_source_dbs.txt"
    if [ -s "$TEMP_DIR/only_source_dbs.txt" ]; then
        while IFS= read -r db; do
            echo -e "${RED}  ✗ $db${NC}"
            log_difference
        done < "$TEMP_DIR/only_source_dbs.txt"
    else
        echo -e "${GREEN}  ✓ None${NC}"
    fi

    print_subsection "Databases only in TARGET"
    comm -13 "$TEMP_DIR/source_dbs.txt" "$TEMP_DIR/target_dbs.txt" > "$TEMP_DIR/only_target_dbs.txt"
    if [ -s "$TEMP_DIR/only_target_dbs.txt" ]; then
        while IFS= read -r db; do
            echo -e "${RED}  ✗ $db${NC}"
            log_difference
        done < "$TEMP_DIR/only_target_dbs.txt"
    else
        echo -e "${GREEN}  ✓ None${NC}"
    fi

    print_subsection "Common Databases"
    comm -12 "$TEMP_DIR/source_dbs.txt" "$TEMP_DIR/target_dbs.txt" > "$TEMP_DIR/common_dbs.txt"
    if [ -s "$TEMP_DIR/common_dbs.txt" ]; then
        while IFS= read -r db; do
            echo -e "${GREEN}  ✓ $db${NC}"
            log_match
        done < "$TEMP_DIR/common_dbs.txt"
    else
        echo -e "${YELLOW}  No common databases found${NC}"
    fi
}

# 2. Compare Schemas for a database
compare_schemas() {
    local dbname=$1

    print_subsection "Schemas in database: $dbname"

    # Get schemas from source (excluding system schemas)
    exec_source_sql "$dbname" "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast') ORDER BY schema_name;" > "$TEMP_DIR/source_schemas.txt"

    # Get schemas from target
    exec_target_sql "$dbname" "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast') ORDER BY schema_name;" > "$TEMP_DIR/target_schemas.txt"

    # Compare schemas
    local has_diff=false

    # Check for schemas only in source
    comm -23 "$TEMP_DIR/source_schemas.txt" "$TEMP_DIR/target_schemas.txt" > "$TEMP_DIR/only_source_schemas.txt"
    if [ -s "$TEMP_DIR/only_source_schemas.txt" ]; then
        has_diff=true
        echo -e "${RED}    Schemas only in SOURCE:${NC}"
        while IFS= read -r schema; do
            echo -e "${RED}      ✗ $schema${NC}"
            log_difference
        done < "$TEMP_DIR/only_source_schemas.txt"
    fi

    # Check for schemas only in target
    comm -13 "$TEMP_DIR/source_schemas.txt" "$TEMP_DIR/target_schemas.txt" > "$TEMP_DIR/only_target_schemas.txt"
    if [ -s "$TEMP_DIR/only_target_schemas.txt" ]; then
        has_diff=true
        echo -e "${RED}    Schemas only in TARGET:${NC}"
        while IFS= read -r schema; do
            echo -e "${RED}      ✗ $schema${NC}"
            log_difference
        done < "$TEMP_DIR/only_target_schemas.txt"
    fi

    if [ "$has_diff" = false ]; then
        echo -e "${GREEN}    ✓ Schemas match${NC}"
    fi

    # Get common schemas for further comparison
    comm -12 "$TEMP_DIR/source_schemas.txt" "$TEMP_DIR/target_schemas.txt" > "$TEMP_DIR/common_schemas.txt"
}

# 3. Compare Tables for a schema
compare_tables() {
    local dbname=$1
    local schema=$2

    # Get tables from source
    exec_source_sql "$dbname" "SELECT table_name FROM information_schema.tables WHERE table_schema = '$schema' AND table_type = 'BASE TABLE' ORDER BY table_name;" > "$TEMP_DIR/source_tables.txt"

    # Get tables from target
    exec_target_sql "$dbname" "SELECT table_name FROM information_schema.tables WHERE table_schema = '$schema' AND table_type = 'BASE TABLE' ORDER BY table_name;" > "$TEMP_DIR/target_tables.txt"

    local has_diff=false

    # Check for tables only in source
    comm -23 "$TEMP_DIR/source_tables.txt" "$TEMP_DIR/target_tables.txt" > "$TEMP_DIR/only_source_tables.txt"
    if [ -s "$TEMP_DIR/only_source_tables.txt" ]; then
        has_diff=true
        echo -e "${RED}      Tables only in SOURCE.$schema:${NC}"
        while IFS= read -r table; do
            echo -e "${RED}        ✗ $table${NC}"
            log_difference
        done < "$TEMP_DIR/only_source_tables.txt"
    fi

    # Check for tables only in target
    comm -13 "$TEMP_DIR/source_tables.txt" "$TEMP_DIR/target_tables.txt" > "$TEMP_DIR/only_target_tables.txt"
    if [ -s "$TEMP_DIR/only_target_tables.txt" ]; then
        has_diff=true
        echo -e "${RED}      Tables only in TARGET.$schema:${NC}"
        while IFS= read -r table; do
            echo -e "${RED}        ✗ $table${NC}"
            log_difference
        done < "$TEMP_DIR/only_target_tables.txt"
    fi

    if [ "$has_diff" = false ]; then
        local table_count=$(wc -l < "$TEMP_DIR/source_tables.txt")
        echo -e "${GREEN}      ✓ $schema: $table_count tables match${NC}"
        log_match
    fi

    # Get common tables for column comparison
    comm -12 "$TEMP_DIR/source_tables.txt" "$TEMP_DIR/target_tables.txt" > "$TEMP_DIR/common_tables.txt"
}

# 4. Compare Columns and Types for a table
compare_columns() {
    local dbname=$1
    local schema=$2
    local table=$3
    local verbose=$4

    # Get columns with types from source
    exec_source_sql "$dbname" "
        SELECT
            column_name || '|' ||
            data_type || '|' ||
            COALESCE(character_maximum_length::text, '') || '|' ||
            COALESCE(numeric_precision::text, '') || '|' ||
            COALESCE(numeric_scale::text, '') || '|' ||
            is_nullable || '|' ||
            COALESCE(column_default, '')
        FROM information_schema.columns
        WHERE table_schema = '$schema'
        AND table_name = '$table'
        ORDER BY ordinal_position;" > "$TEMP_DIR/source_columns.txt"

    # Get columns with types from target
    exec_target_sql "$dbname" "
        SELECT
            column_name || '|' ||
            data_type || '|' ||
            COALESCE(character_maximum_length::text, '') || '|' ||
            COALESCE(numeric_precision::text, '') || '|' ||
            COALESCE(numeric_scale::text, '') || '|' ||
            is_nullable || '|' ||
            COALESCE(column_default, '')
        FROM information_schema.columns
        WHERE table_schema = '$schema'
        AND table_name = '$table'
        ORDER BY ordinal_position;" > "$TEMP_DIR/target_columns.txt"

    # Compare columns
    local has_diff=false

    # Process differences
    diff "$TEMP_DIR/source_columns.txt" "$TEMP_DIR/target_columns.txt" > "$TEMP_DIR/column_diff.txt" 2>&1

    if [ -s "$TEMP_DIR/column_diff.txt" ]; then
        has_diff=true
        if [ "$verbose" = "true" ]; then
            echo -e "${RED}        Table $schema.$table has column differences:${NC}"

            # Parse and show differences more clearly
            grep "^<" "$TEMP_DIR/column_diff.txt" | while IFS='|' read -r line col type len prec scale null default; do
                col=${line#< }
                echo -e "${RED}          SOURCE only: $col ($type)${NC}"
            done

            grep "^>" "$TEMP_DIR/column_diff.txt" | while IFS='|' read -r line col type len prec scale null default; do
                col=${line#> }
                echo -e "${RED}          TARGET only: $col ($type)${NC}"
            done
        else
            echo -e "${RED}        ✗ $schema.$table${NC}"
        fi
        log_difference
    else
        if [ "$verbose" = "true" ]; then
            echo -e "${GREEN}        ✓ $schema.$table columns match${NC}"
        fi
        log_match
    fi
}

# 5. Main comparison function for a database
compare_database_structure() {
    local dbname=$1
    local verbose=${2:-false}

    print_header "2. SCHEMA COMPARISON FOR DATABASE: $dbname"

    compare_schemas "$dbname"

    print_header "3. TABLE COMPARISON FOR DATABASE: $dbname"

    # Compare tables for each common schema
    if [ -s "$TEMP_DIR/common_schemas.txt" ]; then
        while IFS= read -r schema; do
            echo -e "${CYAN}    Schema: $schema${NC}"
            compare_tables "$dbname" "$schema"
        done < "$TEMP_DIR/common_schemas.txt"
    fi

    print_header "4. COLUMN AND TYPE COMPARISON FOR DATABASE: $dbname"

    # Compare columns for each common table
    if [ -s "$TEMP_DIR/common_schemas.txt" ]; then
        while IFS= read -r schema; do
            compare_tables "$dbname" "$schema" 2>/dev/null

            if [ -s "$TEMP_DIR/common_tables.txt" ]; then
                echo -e "${CYAN}    Schema: $schema${NC}"
                while IFS= read -r table; do
                    compare_columns "$dbname" "$schema" "$table" "$verbose"
                done < "$TEMP_DIR/common_tables.txt"
            fi
        done < "$TEMP_DIR/common_schemas.txt"
    fi
}

# 6. Generate detailed report
generate_detailed_report() {
    local dbname=$1
    local output_file=${2:-"db_comparison_report.txt"}

    {
        echo "DATABASE STRUCTURE COMPARISON REPORT"
        echo "Generated: $(date)"
        echo "=================================================="
        echo
        echo "SOURCE: $SOURCE_HOST:$SOURCE_PORT"
        echo "TARGET: $TARGET_HOST:$TARGET_PORT"
        echo "DATABASE: $dbname"
        echo

        # Get table counts
        echo "SUMMARY STATISTICS"
        echo "------------------"

        for schema in $(cat "$TEMP_DIR/common_schemas.txt" 2>/dev/null); do
            source_count=$(exec_source_sql "$dbname" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$schema' AND table_type = 'BASE TABLE';")
            target_count=$(exec_target_sql "$dbname" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$schema' AND table_type = 'BASE TABLE';")
            echo "Schema $schema: Source tables=$source_count, Target tables=$target_count"
        done

        echo
        echo "DETAILED DIFFERENCES"
        echo "-------------------"

        # Run comparison with output redirection
        compare_database_structure "$dbname" true

    } > "$output_file"

    echo -e "${GREEN}Detailed report saved to: $output_file${NC}"
}

# 7. Quick comparison summary
quick_compare() {
    local dbname=$1

    print_header "QUICK COMPARISON SUMMARY: $dbname"

    # Count schemas
    source_schema_count=$(exec_source_sql "$dbname" "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast');")
    target_schema_count=$(exec_target_sql "$dbname" "SELECT COUNT(*) FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast');")

    # Count tables
    source_table_count=$(exec_source_sql "$dbname" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast') AND table_type = 'BASE TABLE';")
    target_table_count=$(exec_target_sql "$dbname" "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast') AND table_type = 'BASE TABLE';")

    # Count columns
    source_column_count=$(exec_source_sql "$dbname" "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast');")
    target_column_count=$(exec_target_sql "$dbname" "SELECT COUNT(*) FROM information_schema.columns WHERE table_schema NOT IN ('pg_catalog', 'information_schema', 'pg_toast');")

    echo -e "${CYAN}Source Database:${NC}"
    echo -e "  Schemas: $source_schema_count"
    echo -e "  Tables:  $source_table_count"
    echo -e "  Columns: $source_column_count"
    echo
    echo -e "${CYAN}Target Database:${NC}"
    echo -e "  Schemas: $target_schema_count"
    echo -e "  Tables:  $target_table_count"
    echo -e "  Columns: $target_column_count"
    echo

    if [ "$source_schema_count" = "$target_schema_count" ] &&
       [ "$source_table_count" = "$target_table_count" ] &&
       [ "$source_column_count" = "$target_column_count" ]; then
        echo -e "${GREEN}${BOLD}✓ Quick check: Counts match!${NC}"
    else
        echo -e "${RED}${BOLD}✗ Quick check: Counts differ!${NC}"
    fi
}

# Print final summary
print_summary() {
    print_header "COMPARISON SUMMARY"

    echo -e "${CYAN}Total Checks:${NC} $TOTAL_CHECKS"
    echo -e "${GREEN}Matches:${NC} $MATCHES"
    echo -e "${RED}Differences:${NC} $DIFFERENCES"

    if [ $DIFFERENCES -eq 0 ]; then
        echo
        echo -e "${GREEN}${BOLD}✓ DATABASES ARE STRUCTURALLY IDENTICAL!${NC}"
    else
        echo
        echo -e "${YELLOW}${BOLD}⚠ FOUND $DIFFERENCES STRUCTURAL DIFFERENCES${NC}"

        local match_percentage=$((MATCHES * 100 / TOTAL_CHECKS))
        echo -e "${CYAN}Match Rate: ${match_percentage}%${NC}"
    fi
}

# Show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --all                    Compare all common databases"
    echo "  --db DATABASE            Compare specific database"
    echo "  --quick DATABASE         Quick summary comparison"
    echo "  --detailed DATABASE      Generate detailed report"
    echo "  --verbose                Show detailed output"
    echo "  --help                   Show this help message"
    echo
    echo "Examples:"
    echo "  $0 --all                 # Compare all databases"
    echo "  $0 --db postgres         # Compare postgres database"
    echo "  $0 --quick postgres      # Quick summary for postgres"
    echo "  $0 --detailed postgres   # Generate detailed report"
    echo
    echo "Connection Settings:"
    echo "  Source: $SOURCE_HOST:$SOURCE_PORT"
    echo "  Target: $TARGET_HOST:$TARGET_PORT"
}

# Main script
main() {
    if [ $# -eq 0 ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        show_usage
        exit 0
    fi

    case "$1" in
        --all)
            compare_databases

            # Compare structure for each common database
            if [ -s "$TEMP_DIR/common_dbs.txt" ]; then
                while IFS= read -r db; do
                    compare_database_structure "$db"
                done < "$TEMP_DIR/common_dbs.txt"
            fi

            print_summary
            ;;

        --db)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Please specify database name${NC}"
                exit 1
            fi
            compare_database_structure "$2" "${3:-false}"
            print_summary
            ;;

        --quick)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Please specify database name${NC}"
                exit 1
            fi
            quick_compare "$2"
            ;;

        --detailed)
            if [ -z "$2" ]; then
                echo -e "${RED}Error: Please specify database name${NC}"
                exit 1
            fi
            generate_detailed_report "$2" "${3:-db_comparison_report.txt}"
            ;;

        *)
            echo -e "${RED}Unknown option: $1${NC}"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"