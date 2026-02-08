#!/usr/bin/env bash

# Common Vagrant utility functions
# This script provides reusable functions for Vagrant operations across all scripts

# Detect host type (my-ubuntu, my-mac, my-mac2, my-windows, etc.)
# Usage: detect_host
detect_host() {
    local hostname=$(hostname 2>/dev/null || echo "")
    local username=$(whoami 2>/dev/null || echo "")
    local project_path=$(pwd)
    
    # Check for macOS
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # Check for my-mac2 (dooheehong user)
        if [[ "$username" == "dooheehong" ]] || [[ "$project_path" == *"dooheehong"* ]]; then
            echo "my-mac2"
            return
        fi
        # Check for my-mac (doogee323 user)
        if [[ "$username" == "doogee323" ]] || [[ "$project_path" == *"doogee323"* ]]; then
            echo "my-mac"
            return
        fi
        # Default macOS
        echo "my-mac"
        return
    fi
    
    # Check for Linux (my-ubuntu)
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "my-ubuntu"
        return
    fi
    
    # Check for Windows (Git Bash, MSYS2, Cygwin)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys2" ]]; then
        echo "my-windows"
        return
    fi
    
    # Default
    echo "unknown"
}

# Find vagrant command
# Usage: find_vagrant_cmd
find_vagrant_cmd() {
    # Set PATH to include VirtualBox (for macOS)
    if [[ "$OSTYPE" == "darwin"* ]]; then
        export PATH="/Applications/VirtualBox.app/Contents/MacOS:$PATH:/usr/local/bin"
    fi
    # Set PATH to include VirtualBox (for Windows)
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys2" ]]; then
        export PATH="/c/Program Files/Oracle/VirtualBox:$PATH:${PATH}"
    fi
    
    local VAGRANT_CMD=$(which vagrant 2>/dev/null || find /usr/local -name vagrant 2>/dev/null | head -1 || echo "vagrant")
    
    # Quote-friendly check: path may contain spaces (e.g. "C:\Program Files (x86)\Vagrant\bin\vagrant" on Windows)
    if [ ! -f "$VAGRANT_CMD" ] && ! command -v vagrant >/dev/null 2>&1; then
        echo "Error: vagrant command not found. Please install Vagrant or set PATH." >&2
        return 1
    fi
    
    echo "$VAGRANT_CMD"
}

# Execute command on VM via SSH
# On Windows (Git Bash), use PowerShell + Windows cwd so vagrant ssh finds project (avoids "path specified")
# Usage: ssh_vm <vm_name> <command> [suppress_warnings]
ssh_vm() {
    local VM_NAME="$1"
    local COMMAND="$2"
    local SUPPRESS_WARNINGS="${3:-true}"
    local VAGRANT_CMD="${4:-$(find_vagrant_cmd)}"
    
    if [ -z "$VM_NAME" ] || [ -z "$COMMAND" ]; then
        echo "Error: ssh_vm requires vm_name and command" >&2
        return 1
    fi
    
    if [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys2" ]]; then
        local win_path
        win_path=$(cygpath -w "$(pwd)" 2>/dev/null) || win_path=$(echo "$(pwd)" | sed 's|^/\([a-zA-Z]\)/|\1:\\|' | sed 's|/|\\|g')
        local vagrant_dir; vagrant_dir=$(dirname "$VAGRANT_CMD" 2>/dev/null)
        local win_vagrant_dir
        win_vagrant_dir=$(cygpath -w "$vagrant_dir" 2>/dev/null) || win_vagrant_dir=$(echo "$vagrant_dir" | sed 's|^/\([a-zA-Z]\)/|\1:\\|' | sed 's|/|\\|g')
        local win_path_ps="${win_path//\'/\'\'}"; local win_vagrant_ps="${win_vagrant_dir//\'/\'\'}"
        local cmd_esc_ps="${COMMAND//\'/\'\'}"
        if [ "$SUPPRESS_WARNINGS" = "true" ]; then
            powershell -NoProfile -NonInteractive -Command "\$env:PATH = '$win_vagrant_ps' + ';' + \$env:PATH; Set-Location -LiteralPath '$win_path_ps'; vagrant ssh '$VM_NAME' -- -t '$cmd_esc_ps'" 2>&1 | grep -v "Warning: Permanently added" || return ${PIPESTATUS[0]}
        else
            powershell -NoProfile -NonInteractive -Command "\$env:PATH = '$win_vagrant_ps' + ';' + \$env:PATH; Set-Location -LiteralPath '$win_path_ps'; vagrant ssh '$VM_NAME' -- -t '$cmd_esc_ps'"
        fi
        return $?
    fi
    
    if [ "$SUPPRESS_WARNINGS" = "true" ]; then
        "$VAGRANT_CMD" ssh "$VM_NAME" -- -t "$COMMAND" 2>&1 | grep -v "Warning: Permanently added" || return ${PIPESTATUS[0]}
    else
        "$VAGRANT_CMD" ssh "$VM_NAME" -- -t "$COMMAND"
    fi
}

# Get VM status
# Usage: get_vm_status <vm_name>
get_vm_status() {
    local VM_NAME="$1"
    local VAGRANT_CMD="${2:-$(find_vagrant_cmd)}"
    
    if [ -z "$VM_NAME" ]; then
        echo "Error: get_vm_status requires vm_name" >&2
        return 1
    fi
    
    "$VAGRANT_CMD" status "$VM_NAME" 2>/dev/null | grep "$VM_NAME" | awk '{print $2}' || echo "unknown"
}

# Get list of running VMs
# Usage: get_running_vms
get_running_vms() {
    local VAGRANT_CMD="${1:-$(find_vagrant_cmd)}"
    local list=""
    
    # Try machine-readable first (timestamp,target,type,data -> field 2 = target)
    list=$("$VAGRANT_CMD" status --machine-readable 2>&1 | tr -d '\r' | grep ",state,running" | cut -d',' -f2 | sort -u)
    
    # Fallback: parse human-readable output (e.g. "kube-master   running (virtualbox)")
    # Needed on Windows where machine-readable format can differ or go to stderr
    if [ -z "$list" ]; then
        list=$("$VAGRANT_CMD" status 2>&1 | tr -d '\r' | awk '/running\s*\(/ {print $1}' | sort -u)
    fi
    
    echo "$list"
}

# Check if tool is installed
# Usage: check_tool <tool_name> [version_command]
check_tool() {
    local TOOL_NAME="$1"
    local VERSION_CMD="${2:-"--version"}"
    
    if [ -z "$TOOL_NAME" ]; then
        echo "Error: check_tool requires tool_name" >&2
        return 1
    fi
    
    if command -v "$TOOL_NAME" > /dev/null 2>&1; then
        local VERSION=""
        case "$TOOL_NAME" in
            kubectl)
                VERSION=$(kubectl version --client --short 2>/dev/null | head -1 || echo "version check failed")
                ;;
            helm)
                VERSION=$(helm version --short 2>/dev/null || echo "version check failed")
                ;;
            docker)
                VERSION=$(docker --version 2>/dev/null || echo "version check failed")
                ;;
            ansible)
                VERSION=$(ansible --version 2>/dev/null | head -1 || echo "version check failed")
                ;;
            jq)
                VERSION=$(jq --version 2>/dev/null || echo "version check failed")
                ;;
            curl)
                VERSION=$(curl --version 2>/dev/null | head -1 || echo "version check failed")
                ;;
            wget)
                VERSION=$(wget --version 2>/dev/null | head -1 || echo "version check failed")
                ;;
            *)
                VERSION=$($TOOL_NAME $VERSION_CMD 2>/dev/null | head -1 || echo "version check failed")
                ;;
        esac
        echo "installed:$VERSION"
        return 0
    else
        echo "not_installed"
        return 1
    fi
}

# Configure static IP on VM interface
# Usage: configure_static_ip <vm_name> <interface> <ip> <netmask> <gateway> <dns_servers>
configure_static_ip() {
    local VM_NAME="$1"
    local INTERFACE="$2"
    local IP="$3"
    local NETMASK="${4:-255.255.255.0}"
    local GATEWAY="$5"
    local DNS_SERVERS="${6:-8.8.8.8 8.8.4.4}"
    local VAGRANT_CMD="${7:-$(find_vagrant_cmd)}"
    
    if [ -z "$VM_NAME" ] || [ -z "$INTERFACE" ] || [ -z "$IP" ]; then
        echo "Error: configure_static_ip requires vm_name, interface, and ip" >&2
        return 1
    fi
    
    # Use unified vm-network.sh script
    ssh_vm "$VM_NAME" "sudo bash /vagrant/scripts/local/vm-network.sh configure-interface $INTERFACE $IP $NETMASK $GATEWAY '$DNS_SERVERS'" "true" "$VAGRANT_CMD"
}

# Test connectivity from VM
# Usage: test_vm_connectivity <vm_name> <target_ip> [description]
test_vm_connectivity() {
    local VM_NAME="$1"
    local TARGET_IP="$2"
    local DESCRIPTION="${3:-$TARGET_IP}"
    local VAGRANT_CMD="${4:-$(find_vagrant_cmd)}"
    
    if [ -z "$VM_NAME" ] || [ -z "$TARGET_IP" ]; then
        echo "Error: test_vm_connectivity requires vm_name and target_ip" >&2
        return 1
    fi
    
    ssh_vm "$VM_NAME" "ping -c 2 -W 2 $TARGET_IP > /dev/null 2>&1 && echo '✓ $DESCRIPTION reachable' || echo '✗ $DESCRIPTION unreachable'" "true" "$VAGRANT_CMD"
}

# If script is executed directly, show usage
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    echo "Common Vagrant utility functions"
    echo "This script should be sourced, not executed directly"
    echo ""
    echo "Usage: source common-vagrant.sh"
    echo ""
    echo "Available functions:"
    echo "  - detect_host"
    echo "  - find_vagrant_cmd"
    echo "  - ssh_vm <vm_name> <command>"
    echo "  - get_vm_status <vm_name>"
    echo "  - get_running_vms"
    echo "  - check_tool <tool_name>"
    echo "  - configure_static_ip <vm_name> <interface> <ip> [netmask] [gateway] [dns]"
    echo "  - test_vm_connectivity <vm_name> <target_ip> [description]"
fi
