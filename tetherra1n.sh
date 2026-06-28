#!/usr/bin/env bash

# ========================================================================
# TetherRa1n Automation Utility
# Backend Engines: edwin170/downr1n & Gaster pwnDFU
# Target Environment: Bash 4.0+ (macOS / Linux)
# Status: Production Release Candidate
# ========================================================================

# STRICT SHELL STATE: Exit on error (-e), unset variables (-u), pipe failure, 
# and ensure that ERR traps are properly inherited by shell functions (-E).
set -Eeuo pipefail

# Establish the exact directory path where the script is physically saved
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Global Configuration Constants & Binary Allocations
readonly GASTER="${SCRIPT_DIR}/gaster"
readonly DOWNR1N="${SCRIPT_DIR}/downr1n.sh"
readonly DEFAULT_PROMPT="Press [Enter] to return to menu... "

# Data-driven platform dependency array
readonly SYSTEM_DEPENDENCIES=(
    "unzip"
    "curl"
    "python3"
)

# Shared environment state cache bits
DOWNR1N_READY=0

# Enable ANSI colors only if output is an interactive terminal and not "dumb"
if [[ -t 1 && "${TERM:-}" != "dumb" ]]; then
    readonly GREEN='\033[0;32m'
    readonly RED='\033[0;31m'
    readonly YELLOW='\033[0;33m'
    readonly NC='\033[0m'
else
    readonly GREEN=''
    readonly RED=''
    readonly YELLOW=''
    readonly NC=''
fi

# ------------------------------------------------------------------------
# Termination, Signals, and Housekeeping
# ------------------------------------------------------------------------

cleanup() {
    # Unbind operational traps to prevent feedback loops on final exit
    trap - INT ERR EXIT
}

# Register lifecycle management traps
trap 'printf "\nOperation cancelled by user.\n"; exit 130' INT
trap 'error "Unexpected execution failure on line $LINENO"' ERR
trap cleanup EXIT

# ------------------------------------------------------------------------
# Centralized Logging & UI Layer
# ------------------------------------------------------------------------

info() {
    printf "%b[*] %s%b\n" "${YELLOW}" "$1" "${NC}"
}

success() {
    printf "%b[+] %s%b\n" "${GREEN}" "$1" "${NC}"
}

warn() {
    printf "%b[!] %s%b\n" "${YELLOW}" "$1" "${NC}"
}

error() {
    printf "%b[-] %s%b\n" "${RED}" "$1" "${NC}" >&2
}

# Standardized fatal error termination function
die() {
    trap - ERR # Isolate trap propagation before handling critical termination
    error "$1"
    exit 1
}

# Unified user prompt pause function
pause() {
    local prompt_msg="${1:-$DEFAULT_PROMPT}"
    printf "%s" "$prompt_msg"
    read -r
}

# Safely clear the screen only if supported on an active terminal interface
safe_clear() {
    if [[ -t 1 ]] && command -v clear >/dev/null 2>&1; then
        clear
    fi
}

# ------------------------------------------------------------------------
# Infrastructure Verification Helpers
# ------------------------------------------------------------------------

# Print standardized usage guidelines to the terminal dynamically
usage() {
    local script_name
    script_name=$(basename "$0")

    cat <<EOF
TetherRa1n Automation CLI Wrapper
Usage: 
    ./$script_name [OPTION]

Options:
    -h, --help    Show this documentation menu

Compatibility:
    • Target Environment: Bash 4.0+
    • Platforms: macOS / Linux

Local Requirements (Must sit in script directory):
    $GASTER (Executable)
    $DOWNR1N (Executable script)

System Dependencies:
    irecovery, curl, unzip, python3
EOF
}

# Verify required dependency script/binary exists and is executable
require_executable() {
    local target="$1"
    [[ -x "$target" ]] || die "Required executable missing or permissions invalid: $target"
}

# Verify secondary system dependencies required by downstream engines
require_system_tool() {
    local tool="$1"
    command -v "$tool" >/dev/null 2>&1 || die "Missing critical system dependency: $tool. Please install it first."
}

# Consolidated, cached preflight verification check for the downr1n restoration subsystem
prepare_downr1n_environment() {
    # If package check state has already run successfully this session, return instantly
    ((DOWNR1N_READY)) && return

    require_executable "$DOWNR1N"

    for dep in "${SYSTEM_DEPENDENCIES[@]}"; do
        require_system_tool "$dep"
    done

    # Cache validation result to optimize subshell runtime
    DOWNR1N_READY=1
}

# Validate that the user inputted a proper decimal version scheme (e.g., 14.3)
validate_ios_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
        die "Invalid version format '$version'. Use numeric standard format (e.g., 14.3)."
    fi
}

# ------------------------------------------------------------------------
# Hardware State Verification Engines
# ------------------------------------------------------------------------

# STRICT CHECK: Gaster requires clean, absolute black-screen DFU mode
verify_dfu_state() {
    info "Scanning for clean DFU connection..."
    
    if ! command -v irecovery &> /dev/null; then
        warn "irecovery missing from system PATH. Verify DFU state manually."
        return 0
    fi

    local device_mode
    device_mode=$(irecovery -m 2>/dev/null) || true

    case "$device_mode" in
        *DFU*)
            success "Verified: Device is in DFU mode."
            ;;
        *Normal*|*Recovery*)
            die "Device is currently in $device_mode mode. Gaster strictly requires clean, manual DFU mode."
            ;;
        "")
            die "No connected iOS device detected. Check your USB connection."
            ;;
        *)
            die "Device reported an unsupported hardware state: '$device_mode'."
            ;;
    esac
}

# FLEXIBLE CHECK: Downr1n can accept variations of DFU, pwnDFU, or Recovery handoffs
verify_any_exploit_state() {
    info "Scanning hardware state for script handoff..."
    
    if ! command -v irecovery &> /dev/null; then
        return 0
    fi

    local device_mode
    device_mode=$(irecovery -m 2>/dev/null) || true

    case "$device_mode" in
        *DFU*|*Recovery*)
            success "Device state ready for downr1n engine handoff ($device_mode)."
            ;;
        *Normal*)
            die "Device is in Normal iOS mode. Enter DFU or Recovery to use downr1n paths."
            ;;
        "")
            die "No connected iOS device detected. Check your USB connection."
            ;;
        *)
            die "Device reported an unstable state: '$device_mode'."
            ;;
    esac
}

# ------------------------------------------------------------------------
# Core Operations
# ------------------------------------------------------------------------

run_pwndfu() {
    verify_dfu_state
    require_executable "$GASTER"

    printf '%s\n' \
        "1. Connect your target device via USB." \
        "2. Manually trigger standard DFU mode (screen should remain black)."
    pause "Press [Enter] once your device is in DFU mode to execute exploit... "

    info "Executing pwnDFU sequences via Gaster..."
    "$GASTER" pwn

    success "Exploit layer applied successfully."
    verify_any_exploit_state
}

execute_downgrade() {
    verify_any_exploit_state
    prepare_downr1n_environment

    printf "\nPrerequisite: Place target firmware inside the 'ipsw/' subdirectory.\n"
    printf "Enter target iOS version for downgrade (e.g., 14.3): "
    
    local ios_version
    if ! read -r ios_version; then
        return
    fi

    validate_ios_version "$ios_version"

    info "Initiating Downr1n restore engine..."
    "$DOWNR1N" --downgrade "$ios_version"
}

execute_tether_boot() {
    verify_any_exploit_state
    prepare_downr1n_environment

    printf "\nEnter the exact iOS version you are booting (e.g., 14.3): "
    
    local boot_version
    if ! read -r boot_version; then
        return
    fi

    validate_ios_version "$boot_version"

    info "Launching tethered boot routine for iOS $boot_version..."
    "$DOWNR1N" --boot "$boot_version"
}

# ------------------------------------------------------------------------
# Main Application Entry Point
# ------------------------------------------------------------------------
main() {
    # Check for documentation arguments passed directly on execution
    if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
        usage
        exit 0
    fi

    while true; do
        safe_clear
        printf '%s\n' \
            "==========================================================" \
            "                 TetherRa1n Deployment CLI                " \
            "==========================================================" \
            "1) Step 1: Inject Exploitation Layer (Gaster pwnDFU)" \
            "2) Step 2: Trigger Tethered Downgrade (Downr1n Restore)" \
            "3) Step 3: Launch Safe Tethered Boot (Downr1n Boot)" \
            "4) Exit Utility" \
            "==========================================================" \
            ""
        
        printf "Select an action [1-4]: "
        local option
        if ! read -r option; then
            printf "\nExiting utility due to input stream termination.\n"
            exit 0
        fi

        case "$option" in
            1) 
                run_pwndfu 
                pause
                ;;
            2) 
                execute_downgrade 
                pause
                ;;
            3) 
                execute_tether_boot 
                pause
                ;;
            4) 
                printf "\nExiting TetherRa1n utility.\n"
                exit 0 
                ;;
            *) 
                error "Invalid choice. Please select 1, 2, 3, or 4."
                sleep 2
                ;;
        esac
    done
}

# Pass all script arguments directly into the main runtime execution context
main "$@"
