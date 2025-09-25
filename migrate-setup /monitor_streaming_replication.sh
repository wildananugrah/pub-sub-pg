#!/bin/bash

# PostgreSQL Streaming Replication Monitor
# Real-time monitoring dashboard for streaming replication

# Master database configuration
MASTER_HOST=""
MASTER_PORT=""
MASTER_USER=""
MASTER_PASSWORD=""

# Standby database configuration
STANDBY_HOST=""
STANDBY_PORT=""
STANDBY_USER=""
STANDBY_PASSWORD=""

# Monitoring configuration
REFRESH_INTERVAL=2  # seconds
ALERT_LAG_MB=10     # Alert if lag > 10MB

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'

# Function to clear screen
clear_screen() {
    printf "\033c"
}

# Function to execute SQL on master
exec_master_sql() {
    docker run --rm \
        -e PGPASSWORD="$MASTER_PASSWORD" \
        postgres:16 \
        psql -h "$MASTER_HOST" -p "$MASTER_PORT" -U "$MASTER_USER" \
        -d postgres -tAc "$1" 2>/dev/null
}

# Function to execute SQL on standby
exec_standby_sql() {
    docker run --rm \
        -e PGPASSWORD="$STANDBY_PASSWORD" \
        postgres:16 \
        psql -h "$STANDBY_HOST" -p "$STANDBY_PORT" -U "$STANDBY_USER" \
        -d postgres -tAc "$1" 2>/dev/null
}

# Function to format bytes
format_bytes() {
    local bytes=$1
    if [ -z "$bytes" ] || [ "$bytes" = "" ]; then
        echo "0 B"
    elif [ $bytes -lt 1024 ]; then
        echo "${bytes} B"
    elif [ $bytes -lt 1048576 ]; then
        printf "%.1f KB" $(echo "scale=1; $bytes/1024" | bc)
    elif [ $bytes -lt 1073741824 ]; then
        printf "%.1f MB" $(echo "scale=1; $bytes/1048576" | bc)
    else
        printf "%.2f GB" $(echo "scale=2; $bytes/1073741824" | bc)
    fi
}

# Function to draw a progress bar
draw_progress_bar() {
    local percent=$1
    local width=30
    local filled=$(echo "scale=0; $percent * $width / 100" | bc)
    local empty=$((width - filled))

    printf "["
    printf "%${filled}s" | tr ' ' '█'
    printf "%${empty}s" | tr ' ' '░'
    printf "] %3d%%" $percent
}

# Function to get master status
get_master_status() {
    # Check if master is in recovery mode
    local in_recovery=$(exec_master_sql "SELECT pg_is_in_recovery()")

    # Get replication statistics
    local repl_stats=$(exec_master_sql "
        SELECT
            client_addr,
            state,
            sent_lsn,
            write_lsn,
            flush_lsn,
            replay_lsn,
            write_lag,
            flush_lag,
            replay_lag,
            sync_state,
            sync_priority
        FROM pg_stat_replication
    ")

    # Get WAL position
    local current_wal=$(exec_master_sql "SELECT pg_current_wal_lsn()")

    # Get database size
    local db_size=$(exec_master_sql "SELECT pg_size_pretty(sum(pg_database_size(datname))) FROM pg_database")

    # Get active connections
    local connections=$(exec_master_sql "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")

    echo "$in_recovery|$repl_stats|$current_wal|$db_size|$connections"
}

# Function to get standby status
get_standby_status() {
    # Check if standby is in recovery mode
    local in_recovery=$(exec_standby_sql "SELECT pg_is_in_recovery()")

    # Get last received WAL
    local last_received=$(exec_standby_sql "SELECT pg_last_wal_receive_lsn()")

    # Get last replayed WAL
    local last_replayed=$(exec_standby_sql "SELECT pg_last_wal_replay_lsn()")

    # Get last replay timestamp
    local last_replay_time=$(exec_standby_sql "SELECT pg_last_xact_replay_timestamp()")

    # Get database size
    local db_size=$(exec_standby_sql "SELECT pg_size_pretty(sum(pg_database_size(datname))) FROM pg_database")

    # Get active connections
    local connections=$(exec_standby_sql "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'")

    echo "$in_recovery|$last_received|$last_replayed|$last_replay_time|$db_size|$connections"
}

# Function to calculate replication lag
calculate_lag() {
    local master_lsn=$1
    local standby_lsn=$2

    if [ -z "$master_lsn" ] || [ -z "$standby_lsn" ]; then
        echo "Unknown"
        return
    fi

    local lag_bytes=$(exec_master_sql "SELECT pg_wal_lsn_diff('$master_lsn', '$standby_lsn')")

    if [ -z "$lag_bytes" ] || [ "$lag_bytes" = "" ]; then
        echo "0 B"
    else
        format_bytes ${lag_bytes#-}  # Remove negative sign if present
    fi
}

# Function to display dashboard header
display_header() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${BOLD}           PostgreSQL Streaming Replication Monitor                        ${NC}${CYAN}║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Master:  ${BLUE}$MASTER_HOST:$MASTER_PORT${NC}                                              "
    echo -e "${CYAN}║${NC} Standby: ${BLUE}$STANDBY_HOST:$STANDBY_PORT${NC}                                              "
    echo -e "${CYAN}║${NC} Updated: ${YELLOW}$timestamp${NC}     Refresh: ${GREEN}${REFRESH_INTERVAL}s${NC}     Press ${RED}Ctrl+C${NC} to exit"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Function to display master section
display_master_section() {
    local master_data=$1
    IFS='|' read -r in_recovery repl_stats current_wal db_size connections <<< "$master_data"

    echo ""
    echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│${BOLD}                          MASTER SERVER                                 ${NC}${MAGENTA}│${NC}"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────────────────────┘${NC}"

    if [ "$in_recovery" = "f" ]; then
        echo -e "  Status: ${GREEN}● Primary (Active)${NC}"
    else
        echo -e "  Status: ${YELLOW}● In Recovery${NC}"
    fi

    echo -e "  Current WAL: ${CYAN}$current_wal${NC}"
    echo -e "  Database Size: ${YELLOW}$db_size${NC}"
    echo -e "  Active Connections: ${BLUE}$connections${NC}"

    if [ ! -z "$repl_stats" ]; then
        echo ""
        echo -e "  ${BOLD}Replication Clients:${NC}"

        IFS=$'\n'
        for line in $repl_stats; do
            IFS=$'\t' read -r client state sent write flush replay write_lag flush_lag replay_lag sync_state sync_priority <<< "$line"

            local state_color=$GREEN
            if [ "$state" != "streaming" ]; then
                state_color=$YELLOW
            fi

            echo -e "  ├─ Client: ${BLUE}$client${NC}"
            echo -e "  │  State: ${state_color}$state${NC} | Sync: ${CYAN}$sync_state${NC}"

            if [ ! -z "$replay_lag" ] && [ "$replay_lag" != "" ]; then
                echo -e "  │  Lag: Write=${write_lag:-0ms} Flush=${flush_lag:-0ms} Replay=${replay_lag:-0ms}"
            fi

            # Calculate byte lag
            local byte_lag=$(exec_master_sql "SELECT pg_wal_lsn_diff('$sent', '$replay')")
            if [ ! -z "$byte_lag" ] && [ "$byte_lag" -gt 0 ]; then
                local formatted_lag=$(format_bytes $byte_lag)
                echo -e "  │  Byte Lag: $formatted_lag"
            fi
        done
        unset IFS
    else
        echo -e "  ${YELLOW}No replication clients connected${NC}"
    fi
}

# Function to display standby section
display_standby_section() {
    local standby_data=$1
    IFS='|' read -r in_recovery last_received last_replayed last_replay_time db_size connections <<< "$standby_data"

    echo ""
    echo -e "${MAGENTA}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${MAGENTA}│${BOLD}                         STANDBY SERVER                                 ${NC}${MAGENTA}│${NC}"
    echo -e "${MAGENTA}└─────────────────────────────────────────────────────────────────────────┘${NC}"

    if [ "$in_recovery" = "t" ]; then
        echo -e "  Status: ${GREEN}● Standby (Receiving)${NC}"
    else
        echo -e "  Status: ${RED}● Standalone (Not receiving)${NC}"
    fi

    echo -e "  Last Received WAL: ${CYAN}$last_received${NC}"
    echo -e "  Last Replayed WAL: ${CYAN}$last_replayed${NC}"
    echo -e "  Last Replay Time: ${YELLOW}${last_replay_time:-Unknown}${NC}"
    echo -e "  Database Size: ${YELLOW}$db_size${NC}"
    echo -e "  Active Connections: ${BLUE}$connections${NC}"

    # Calculate time lag
    if [ ! -z "$last_replay_time" ] && [ "$last_replay_time" != "" ]; then
        local current_time=$(date +%s)
        local replay_time=$(date -d "$last_replay_time" +%s 2>/dev/null)
        if [ $? -eq 0 ]; then
            local time_lag=$((current_time - replay_time))
            if [ $time_lag -lt 60 ]; then
                echo -e "  Time Behind Master: ${GREEN}${time_lag} seconds${NC}"
            elif [ $time_lag -lt 3600 ]; then
                echo -e "  Time Behind Master: ${YELLOW}$((time_lag / 60)) minutes${NC}"
            else
                echo -e "  Time Behind Master: ${RED}$((time_lag / 3600)) hours${NC}"
            fi
        fi
    fi
}

# Function to display lag summary
display_lag_summary() {
    local master_wal=$1
    local standby_received=$2
    local standby_replayed=$3

    echo ""
    echo -e "${CYAN}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${CYAN}│${BOLD}                      REPLICATION LAG SUMMARY                           ${NC}${CYAN}│${NC}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────────────────────┘${NC}"

    # Calculate receive lag
    local receive_lag=$(calculate_lag "$master_wal" "$standby_received")
    local replay_lag=$(calculate_lag "$master_wal" "$standby_replayed")

    # Convert to MB for alert checking
    local replay_lag_mb=$(exec_master_sql "SELECT pg_wal_lsn_diff('$master_wal', '$standby_replayed') / 1048576" 2>/dev/null)

    echo -e "  Receive Lag: $receive_lag"
    echo -e "  Replay Lag:  $replay_lag"

    if [ ! -z "$replay_lag_mb" ] && [ $(echo "$replay_lag_mb > $ALERT_LAG_MB" | bc) -eq 1 ]; then
        echo ""
        echo -e "  ${RED}⚠  WARNING: Replication lag exceeds ${ALERT_LAG_MB}MB threshold!${NC}"
    fi

    # Show visual progress
    echo ""
    echo -e "  Replication Progress:"

    if [ ! -z "$master_wal" ] && [ ! -z "$standby_replayed" ]; then
        local total_wal=$(exec_master_sql "SELECT pg_wal_lsn_diff('$master_wal', '0/0')")
        local replayed_wal=$(exec_master_sql "SELECT pg_wal_lsn_diff('$standby_replayed', '0/0')")

        if [ ! -z "$total_wal" ] && [ ! -z "$replayed_wal" ] && [ "$total_wal" -gt 0 ]; then
            local percent=$(echo "scale=0; $replayed_wal * 100 / $total_wal" | bc)
            echo -n "  "
            draw_progress_bar $percent
            echo ""
        fi
    fi
}

# Function to display system metrics
display_system_metrics() {
    echo ""
    echo -e "${YELLOW}┌─────────────────────────────────────────────────────────────────────────┐${NC}"
    echo -e "${YELLOW}│${BOLD}                         SYSTEM METRICS                                 ${NC}${YELLOW}│${NC}"
    echo -e "${YELLOW}└─────────────────────────────────────────────────────────────────────────┘${NC}"

    # Get replication slots info
    local slots=$(exec_master_sql "
        SELECT count(*),
               count(CASE WHEN active THEN 1 END) as active_count
        FROM pg_replication_slots
    ")

    if [ ! -z "$slots" ]; then
        IFS=$'\t' read -r total_slots active_slots <<< "$slots"
        echo -e "  Replication Slots: ${GREEN}$active_slots${NC} active / $total_slots total"
    fi

    # Get WAL files count
    local wal_count=$(exec_master_sql "SELECT count(*) FROM pg_ls_waldir()")
    echo -e "  WAL Files: $wal_count"

    # Get checkpoint info
    local checkpoint=$(exec_master_sql "
        SELECT checkpoint_lsn,
               redo_lsn,
               checkpoint_time
        FROM pg_control_checkpoint()
    " 2>/dev/null)

    if [ ! -z "$checkpoint" ]; then
        IFS=$'\t' read -r checkpoint_lsn redo_lsn checkpoint_time <<< "$checkpoint"
        echo -e "  Last Checkpoint: ${checkpoint_time:-Unknown}"
    fi
}

# Function for continuous monitoring
continuous_monitor() {
    while true; do
        clear_screen
        display_header

        # Get master status
        local master_status=$(get_master_status)
        display_master_section "$master_status"

        # Get standby status
        local standby_status=$(get_standby_status)
        display_standby_section "$standby_status"

        # Extract WAL positions for lag calculation
        local master_wal=$(echo "$master_status" | cut -d'|' -f3)
        local standby_received=$(echo "$standby_status" | cut -d'|' -f2)
        local standby_replayed=$(echo "$standby_status" | cut -d'|' -f3)

        # Display lag summary
        display_lag_summary "$master_wal" "$standby_received" "$standby_replayed"

        # Display system metrics
        display_system_metrics

        echo ""
        echo -e "${CYAN}════════════════════════════════════════════════════════════════════════════${NC}"

        sleep $REFRESH_INTERVAL
    done
}

# Function for single check
single_check() {
    display_header

    # Get master status
    local master_status=$(get_master_status)
    display_master_section "$master_status"

    # Get standby status
    local standby_status=$(get_standby_status)
    display_standby_section "$standby_status"

    # Extract WAL positions for lag calculation
    local master_wal=$(echo "$master_status" | cut -d'|' -f3)
    local standby_received=$(echo "$standby_status" | cut -d'|' -f2)
    local standby_replayed=$(echo "$standby_status" | cut -d'|' -f3)

    # Display lag summary
    display_lag_summary "$master_wal" "$standby_received" "$standby_replayed"

    # Display system metrics
    display_system_metrics

    echo ""
}

# Main script
if [ "$1" == "--help" ] || [ "$1" == "-h" ]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Monitor PostgreSQL streaming replication status"
    echo ""
    echo "Options:"
    echo "  --continuous, -c    Continuous monitoring mode (default)"
    echo "  --once, -o          Check once and exit"
    echo "  --interval N        Set refresh interval in seconds (default: 2)"
    echo "  --alert-lag N       Set alert threshold in MB (default: 10)"
    echo "  --help, -h          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                   # Continuous monitoring with defaults"
    echo "  $0 --once            # Single check"
    echo "  $0 --interval 5      # 5 second refresh rate"
    exit 0
fi

# Parse command line options
MODE="continuous"

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
        --alert-lag)
            ALERT_LAG_MB="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run monitoring
if [ "$MODE" = "continuous" ]; then
    echo "Starting continuous monitoring..."
    echo "Press Ctrl+C to exit"
    sleep 2
    continuous_monitor
else
    single_check
fi