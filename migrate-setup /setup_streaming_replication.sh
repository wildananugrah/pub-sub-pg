#!/bin/bash

# PostgreSQL Streaming Replication Setup
# Sets up master-standby streaming replication between two PostgreSQL servers
# This creates a complete read-only replica of the entire database cluster

# Master (Primary) database configuration
MASTER_HOST=""
MASTER_PORT=""
MASTER_USER=""
MASTER_PASSWORD=""
MASTER_DATA_DIR=""  # Adjust based on your setup

# Standby (Replica) database configuration
STANDBY_HOST=""
STANDBY_PORT=""
STANDBY_USER=""
STANDBY_PASSWORD=""
STANDBY_DATA_DIR=""  # Adjust based on your setup

# Replication configuration
REPLICATION_USER=""
REPLICATION_PASSWORD=""
REPLICATION_SLOT="standby_slot"
WAL_KEEP_SIZE="1GB"
ARCHIVE_DIR="" # /var/lib/postgresql/wal_archive

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Function to display header
display_header() {
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║         PostgreSQL Streaming Replication Setup                        ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BLUE}Master:${NC} $MASTER_HOST:$MASTER_PORT"
    echo -e "${BLUE}Standby:${NC} $STANDBY_HOST:$STANDBY_PORT"
    echo ""
}

# Function to execute SQL on master via Docker
exec_master_sql() {
    docker run --rm \
        -e PGPASSWORD="$MASTER_PASSWORD" \
        postgres:16 \
        psql -h "$MASTER_HOST" -p "$MASTER_PORT" -U "$MASTER_USER" \
        -d "$1" -c "$2" 2>/dev/null
}

# Function to execute SQL on standby via Docker
exec_standby_sql() {
    docker run --rm \
        -e PGPASSWORD="$STANDBY_PASSWORD" \
        postgres:16 \
        psql -h "$STANDBY_HOST" -p "$STANDBY_PORT" -U "$STANDBY_USER" \
        -d "$1" -c "$2" 2>/dev/null
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "${YELLOW}Checking prerequisites...${NC}"

    # Check Docker
    if ! command -v docker &> /dev/null; then
        echo -e "${RED}✗ Docker is not installed${NC}"
        return 1
    fi
    echo -e "${GREEN}✓ Docker is available${NC}"

    # Check master connectivity
    if docker run --rm -e PGPASSWORD="$MASTER_PASSWORD" postgres:16 \
        psql -h "$MASTER_HOST" -p "$MASTER_PORT" -U "$MASTER_USER" -d postgres -c "SELECT 1;" &>/dev/null; then
        echo -e "${GREEN}✓ Master server is accessible${NC}"
    else
        echo -e "${RED}✗ Cannot connect to master server${NC}"
        return 1
    fi

    # Check standby connectivity
    if docker run --rm -e PGPASSWORD="$STANDBY_PASSWORD" postgres:16 \
        psql -h "$STANDBY_HOST" -p "$STANDBY_PORT" -U "$STANDBY_USER" -d postgres -c "SELECT 1;" &>/dev/null; then
        echo -e "${GREEN}✓ Standby server is accessible${NC}"
    else
        echo -e "${RED}✗ Cannot connect to standby server${NC}"
        return 1
    fi

    return 0
}

# Function to configure master for streaming replication
configure_master() {
    echo ""
    echo -e "${BLUE}═══ Configuring Master Server ═══${NC}"

    # Step 1: Create replication user
    echo -e "${YELLOW}Creating replication user...${NC}"
    exec_master_sql "postgres" "
        CREATE USER $REPLICATION_USER WITH REPLICATION LOGIN PASSWORD '$REPLICATION_PASSWORD';
    " 2>/dev/null

    exec_master_sql "postgres" "
        ALTER USER $REPLICATION_USER WITH REPLICATION;
    "

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Replication user created${NC}"
    else
        echo -e "${YELLOW}! Replication user may already exist${NC}"
    fi

    # Step 2: Create replication slot
    echo -e "${YELLOW}Creating replication slot...${NC}"
    exec_master_sql "postgres" "
        SELECT * FROM pg_create_physical_replication_slot('$REPLICATION_SLOT', true);
    " 2>/dev/null

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Replication slot created${NC}"
    else
        echo -e "${YELLOW}! Replication slot may already exist${NC}"
    fi

    # Step 3: Check WAL level
    echo -e "${YELLOW}Checking WAL configuration...${NC}"
    WAL_LEVEL=$(exec_master_sql "postgres" "SHOW wal_level;" | grep -o 'replica\|logical\|minimal' | head -1)

    if [ "$WAL_LEVEL" = "replica" ] || [ "$WAL_LEVEL" = "logical" ]; then
        echo -e "${GREEN}✓ WAL level is '$WAL_LEVEL' (OK for streaming replication)${NC}"
    else
        echo -e "${RED}✗ WAL level is '$WAL_LEVEL' (needs to be 'replica' or 'logical')${NC}"
        echo ""
        echo -e "${YELLOW}Required postgresql.conf settings on master:${NC}"
        echo "wal_level = replica"
        echo "max_wal_senders = 10"
        echo "wal_keep_size = 1GB"
        echo "max_replication_slots = 10"
        echo "hot_standby = on"
        echo "archive_mode = on"
        echo "archive_command = 'test ! -f $ARCHIVE_DIR/%f && cp %p $ARCHIVE_DIR/%f'"
        echo ""
        echo -e "${YELLOW}Required pg_hba.conf entry on master:${NC}"
        echo "host    replication     $REPLICATION_USER     $STANDBY_HOST/32     md5"
        return 1
    fi

    # Step 4: Show current replication status
    echo -e "${YELLOW}Current replication slots on master:${NC}"
    exec_master_sql "postgres" "
        SELECT slot_name, slot_type, active, restart_lsn
        FROM pg_replication_slots;
    "

    return 0
}

# Function to perform base backup
perform_base_backup() {
    echo ""
    echo -e "${BLUE}═══ Creating Base Backup ═══${NC}"

    local BACKUP_DIR="./streaming_backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    echo -e "${YELLOW}Creating base backup from master...${NC}"
    echo -e "${YELLOW}This may take several minutes for large databases...${NC}"

    # Use pg_basebackup to create a base backup
    docker run --rm \
        -e PGPASSWORD="$REPLICATION_PASSWORD" \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        postgres:16 \
        pg_basebackup \
            -h "$MASTER_HOST" \
            -p "$MASTER_PORT" \
            -U "$REPLICATION_USER" \
            -D /backup/data \
            -Fp \
            -Xs \
            -R \
            -P \
            -v

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Base backup created successfully${NC}"
        echo -e "${GREEN}  Location: $BACKUP_DIR/data${NC}"

        # Create standby configuration
        echo -e "${YELLOW}Creating standby configuration...${NC}"

        # Create postgresql.auto.conf for standby
        cat > "$BACKUP_DIR/data/postgresql.auto.conf" << EOF
# Standby Server Configuration
primary_conninfo = 'host=$MASTER_HOST port=$MASTER_PORT user=$REPLICATION_USER password=$REPLICATION_PASSWORD'
primary_slot_name = '$REPLICATION_SLOT'
hot_standby = on
EOF

        # Create standby.signal file
        touch "$BACKUP_DIR/data/standby.signal"

        echo -e "${GREEN}✓ Standby configuration created${NC}"
        echo ""
        echo -e "${CYAN}═══ Next Steps ═══${NC}"
        echo -e "${YELLOW}1. Stop the standby PostgreSQL server${NC}"
        echo "   sudo systemctl stop postgresql@16-standby"
        echo ""
        echo -e "${YELLOW}2. Replace standby data directory with backup${NC}"
        echo "   sudo rm -rf $STANDBY_DATA_DIR/*"
        echo "   sudo cp -R $BACKUP_DIR/data/* $STANDBY_DATA_DIR/"
        echo "   sudo chown -R postgres:postgres $STANDBY_DATA_DIR"
        echo ""
        echo -e "${YELLOW}3. Start the standby PostgreSQL server${NC}"
        echo "   sudo systemctl start postgresql@16-standby"
        echo ""
        echo -e "${YELLOW}4. Verify replication status${NC}"
        echo "   ./monitor_streaming_replication.sh"

        return 0
    else
        echo -e "${RED}✗ Base backup failed${NC}"
        return 1
    fi
}

# Function to setup using Docker volumes (alternative method)
setup_docker_streaming() {
    echo ""
    echo -e "${BLUE}═══ Docker-based Streaming Replication ═══${NC}"

    # Create Docker network if not exists
    docker network create pg_replication 2>/dev/null

    # Stop existing containers if running
    docker stop pg_master pg_standby 2>/dev/null
    docker rm pg_master pg_standby 2>/dev/null

    echo -e "${YELLOW}Starting master container...${NC}"

    # Start master with replication configuration
    docker run -d \
        --name pg_master \
        --network pg_replication \
        -e POSTGRES_USER=$MASTER_USER \
        -e POSTGRES_PASSWORD=$MASTER_PASSWORD \
        -e POSTGRES_REPLICATION_MODE=master \
        -e POSTGRES_REPLICATION_USER=$REPLICATION_USER \
        -e POSTGRES_REPLICATION_PASSWORD=$REPLICATION_PASSWORD \
        -p $MASTER_PORT:5432 \
        -v pg_master_data:/var/lib/postgresql/data \
        postgres:16 \
        -c "wal_level=replica" \
        -c "max_wal_senders=10" \
        -c "max_replication_slots=10" \
        -c "hot_standby=on"

    echo -e "${GREEN}✓ Master container started${NC}"

    # Wait for master to be ready
    sleep 5

    echo -e "${YELLOW}Starting standby container...${NC}"

    # Start standby
    docker run -d \
        --name pg_standby \
        --network pg_replication \
        -e POSTGRES_USER=$STANDBY_USER \
        -e POSTGRES_PASSWORD=$STANDBY_PASSWORD \
        -e POSTGRES_REPLICATION_MODE=standby \
        -e POSTGRES_MASTER_HOST=pg_master \
        -e POSTGRES_MASTER_PORT=5432 \
        -e POSTGRES_REPLICATION_USER=$REPLICATION_USER \
        -e POSTGRES_REPLICATION_PASSWORD=$REPLICATION_PASSWORD \
        -p $STANDBY_PORT:5432 \
        -v pg_standby_data:/var/lib/postgresql/data \
        postgres:16

    echo -e "${GREEN}✓ Standby container started${NC}"

    echo ""
    echo -e "${CYAN}═══ Docker Containers Status ═══${NC}"
    docker ps --filter "name=pg_master" --filter "name=pg_standby"

    echo ""
    echo -e "${YELLOW}Monitor with: docker logs -f pg_standby${NC}"
}

# Function to test replication
test_replication() {
    echo ""
    echo -e "${BLUE}═══ Testing Replication ═══${NC}"

    # Create test table on master
    echo -e "${YELLOW}Creating test table on master...${NC}"
    exec_master_sql "postgres" "
        CREATE TABLE IF NOT EXISTS replication_test (
            id SERIAL PRIMARY KEY,
            data TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
    "

    # Insert test data
    echo -e "${YELLOW}Inserting test data on master...${NC}"
    TEST_VALUE="Test_$(date +%Y%m%d_%H%M%S)"
    exec_master_sql "postgres" "
        INSERT INTO replication_test (data) VALUES ('$TEST_VALUE');
    "

    # Wait for replication
    echo -e "${YELLOW}Waiting for replication (3 seconds)...${NC}"
    sleep 3

    # Check on standby
    echo -e "${YELLOW}Checking data on standby...${NC}"
    RESULT=$(exec_standby_sql "postgres" "
        SELECT data FROM replication_test WHERE data = '$TEST_VALUE';
    " | grep "$TEST_VALUE")

    if [ ! -z "$RESULT" ]; then
        echo -e "${GREEN}✓ Replication is working! Data found on standby${NC}"
        return 0
    else
        echo -e "${RED}✗ Data not found on standby. Replication may not be working${NC}"
        return 1
    fi
}

# Function to show replication status
show_replication_status() {
    echo ""
    echo -e "${BLUE}═══ Replication Status ═══${NC}"

    echo -e "${YELLOW}Master replication status:${NC}"
    exec_master_sql "postgres" "
        SELECT
            client_addr,
            state,
            sent_lsn,
            write_lsn,
            flush_lsn,
            replay_lsn,
            sync_state
        FROM pg_stat_replication;
    "

    echo -e "${YELLOW}Standby replication status:${NC}"
    exec_standby_sql "postgres" "
        SELECT
            pg_is_in_recovery() as is_standby,
            pg_last_wal_receive_lsn() as received_lsn,
            pg_last_wal_replay_lsn() as replayed_lsn,
            pg_last_xact_replay_timestamp() as last_replay_time;
    "

    echo -e "${YELLOW}Replication lag:${NC}"
    exec_master_sql "postgres" "
        SELECT
            client_addr,
            pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), replay_lsn)) AS replication_lag
        FROM pg_stat_replication;
    "
}

# Function to promote standby to master
promote_standby() {
    echo ""
    echo -e "${BLUE}═══ Promoting Standby to Master ═══${NC}"
    echo -e "${RED}WARNING: This will make the standby a new master!${NC}"

    read -p "Are you sure you want to promote the standby? (yes/no): " confirm
    if [ "$confirm" != "yes" ]; then
        echo "Promotion cancelled"
        return 1
    fi

    echo -e "${YELLOW}Promoting standby server...${NC}"
    exec_standby_sql "postgres" "SELECT pg_promote();"

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ Standby promoted to master${NC}"
        echo -e "${YELLOW}The standby is now a standalone master server${NC}"
        return 0
    else
        echo -e "${RED}✗ Promotion failed${NC}"
        return 1
    fi
}

# Main menu
show_menu() {
    echo ""
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              PostgreSQL Streaming Replication Manager                 ║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "1. Check Prerequisites"
    echo "2. Configure Master for Replication"
    echo "3. Create Base Backup for Standby"
    echo "4. Setup Docker-based Replication (Alternative)"
    echo "5. Test Replication"
    echo "6. Show Replication Status"
    echo "7. Promote Standby to Master (Failover)"
    echo "8. Exit"
    echo ""
}

# Main script
display_header

if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTION]"
    echo ""
    echo "Setup and manage PostgreSQL streaming replication"
    echo ""
    echo "Options:"
    echo "  --check          Check prerequisites"
    echo "  --configure      Configure master for replication"
    echo "  --backup         Create base backup for standby"
    echo "  --docker         Setup Docker-based replication"
    echo "  --test           Test replication"
    echo "  --status         Show replication status"
    echo "  --promote        Promote standby to master"
    echo "  --help           Show this help message"
    echo ""
    echo "Interactive mode: Run without arguments"
    exit 0
fi

# Handle command line arguments
if [ ! -z "$1" ]; then
    case "$1" in
        --check)
            check_prerequisites
            ;;
        --configure)
            check_prerequisites && configure_master
            ;;
        --backup)
            check_prerequisites && perform_base_backup
            ;;
        --docker)
            setup_docker_streaming
            ;;
        --test)
            test_replication
            ;;
        --status)
            show_replication_status
            ;;
        --promote)
            promote_standby
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
                check_prerequisites
                ;;
            2)
                check_prerequisites && configure_master
                ;;
            3)
                check_prerequisites && perform_base_backup
                ;;
            4)
                setup_docker_streaming
                ;;
            5)
                test_replication
                ;;
            6)
                show_replication_status
                ;;
            7)
                promote_standby
                ;;
            8)
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