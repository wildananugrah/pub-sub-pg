#!/bin/bash

# PostgreSQL Database Migration using Docker
# This avoids version mismatch issues by using PostgreSQL 16 client tools

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

# Databases to migrate
# DATABASES="devmode serayuopakprogo"
# DATABASES="devmode serayuopakprogo wayseputihsekampung ketahun solo bonebolango batanghari wayseputihwaysekampung kahayan cimanukcitanduy undaanyar bonelimboto agamkuantan citarumciliwung musi tondano asahanbarumun barito pemalijratun postgres_dev brantassampean kapuas karama baturusacerucuk wampuseiular pg sampara akemalamo dodokanmoyosari konaweha memberamo kruengaceh waehapubatumerah jeneberangsaddang benainnoelmina indragirirokan remuransiki mahakamberau  seijangduriangkang paluposo master postgres_new postgres"
DATABASES="postgres"

# Migration configuration
BACKUP_DIR="./db_backups_$(date +%Y%m%d_%H%M%S)"
LOG_FILE="migration_$(date +%Y%m%d_%H%M%S).log"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Create backup directory
mkdir -p "$BACKUP_DIR"
echo "Backup directory: $BACKUP_DIR"

# Function to format elapsed time
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(( (seconds % 3600) / 60 ))
    local secs=$((seconds % 60))

    if [ $hours -gt 0 ]; then
        printf "%dh %dm %ds" $hours $minutes $secs
    elif [ $minutes -gt 0 ]; then
        printf "%dm %ds" $minutes $secs
    else
        printf "%ds" $secs
    fi
}

# Function to backup database using Docker
backup_database() {
    local dbname=$1
    local backup_file="$BACKUP_DIR/${dbname}.sql"
    local start_time=$(date +%s)

    echo -e "${YELLOW}Backing up database: $dbname${NC}"

    # Run pg_dump using Docker with PostgreSQL 16
    docker run --rm \
        -e PGPASSWORD="$SOURCE_PASSWORD" \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        postgres:16 \
        pg_dump -h "$SOURCE_HOST" -p "$SOURCE_PORT" -U "$SOURCE_USER" \
        -d "$dbname" \
        -f "/backup/${dbname}.sql" \
        --verbose \
        --no-owner \
        --no-acl \
        --clean \
        --if-exists \
        --create

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Backup completed for $dbname (Time: $(format_time $elapsed))${NC}"
        return 0
    else
        echo -e "${RED}✗ Backup failed for $dbname (Time: $(format_time $elapsed))${NC}"
        return 1
    fi
}

# Function to restore database using Docker
restore_database() {
    local dbname=$1
    local backup_file="$BACKUP_DIR/${dbname}.sql"
    local start_time=$(date +%s)

    echo -e "${YELLOW}Restoring database: $dbname${NC}"

    # Check if target database exists and drop it
    docker run --rm \
        -e PGPASSWORD="$TARGET_PASSWORD" \
        postgres:16 \
        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
        -d postgres -c "DROP DATABASE IF EXISTS \"$dbname\";"

    # Restore the database
    docker run --rm \
        -e PGPASSWORD="$TARGET_PASSWORD" \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        postgres:16 \
        psql -h "$TARGET_HOST" -p "$TARGET_PORT" -U "$TARGET_USER" \
        -d postgres -f "/backup/${dbname}.sql"

    local end_time=$(date +%s)
    local elapsed=$((end_time - start_time))

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Restore completed for $dbname (Time: $(format_time $elapsed))${NC}"
        return 0
    else
        echo -e "${RED}✗ Restore failed for $dbname (Time: $(format_time $elapsed))${NC}"
        return 1
    fi
}

# Main migration
echo "=========================================="
echo "PostgreSQL Migration using Docker"
echo "=========================================="
echo "Source: $SOURCE_HOST:$SOURCE_PORT"
echo "Target: $TARGET_HOST:$TARGET_PORT"
echo "=========================================="

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed. Please install Docker first.${NC}"
    exit 1
fi

# Pull PostgreSQL 16 image if not available
echo "Ensuring PostgreSQL 16 Docker image is available..."
docker pull postgres:16

# Track overall progress
TOTAL_START=$(date +%s)
SUCCESSFUL_MIGRATIONS=0
FAILED_MIGRATIONS=0
SUCCESSFUL_DBS=""
FAILED_DBS=""

# Migrate each database
for db in $DATABASES; do
    echo ""
    echo "Processing database: $db"
    echo "------------------------------------------"
    DB_START=$(date +%s)

    if backup_database "$db"; then
        if restore_database "$db"; then
            DB_END=$(date +%s)
            DB_ELAPSED=$((DB_END - DB_START))
            echo -e "${GREEN}✅ Migration successful for: $db (Total time: $(format_time $DB_ELAPSED))${NC}"

            # Delete backup file after successful migration
            echo -e "${YELLOW}Deleting backup file for $db...${NC}"
            rm -f "$BACKUP_DIR/${db}.sql"
            if [ $? -eq 0 ]; then
                echo -e "${GREEN}✓ Backup deleted for $db${NC}"
            fi

            SUCCESSFUL_MIGRATIONS=$((SUCCESSFUL_MIGRATIONS + 1))
            SUCCESSFUL_DBS="$SUCCESSFUL_DBS $db"
        else
            DB_END=$(date +%s)
            DB_ELAPSED=$((DB_END - DB_START))
            echo -e "${RED}❌ Migration failed for: $db (restore phase) (Time: $(format_time $DB_ELAPSED))${NC}"
            FAILED_MIGRATIONS=$((FAILED_MIGRATIONS + 1))
            FAILED_DBS="$FAILED_DBS $db"
        fi
    else
        DB_END=$(date +%s)
        DB_ELAPSED=$((DB_END - DB_START))
        echo -e "${RED}❌ Migration failed for: $db (backup phase) (Time: $(format_time $DB_ELAPSED))${NC}"
        FAILED_MIGRATIONS=$((FAILED_MIGRATIONS + 1))
        FAILED_DBS="$FAILED_DBS $db"
    fi
done

TOTAL_END=$(date +%s)
TOTAL_ELAPSED=$((TOTAL_END - TOTAL_START))

echo ""
echo "=========================================="
echo "Migration Summary"
echo "=========================================="
echo -e "${GREEN}Successful migrations: $SUCCESSFUL_MIGRATIONS${NC}"
if [ ! -z "$SUCCESSFUL_DBS" ]; then
    echo -e "${GREEN}  Databases:$SUCCESSFUL_DBS${NC}"
fi
echo -e "${RED}Failed migrations: $FAILED_MIGRATIONS${NC}"
if [ ! -z "$FAILED_DBS" ]; then
    echo -e "${RED}  Databases:$FAILED_DBS${NC}"
fi
echo ""
echo "Total time elapsed: $(format_time $TOTAL_ELAPSED)"
echo "Backup directory: $BACKUP_DIR"

# Clean up backup directory if empty
if [ -z "$(ls -A $BACKUP_DIR 2>/dev/null)" ]; then
    echo "Removing empty backup directory..."
    rmdir "$BACKUP_DIR"
fi

echo "=========================================="