#!/usr/bin/env bash
# This script requires bash 4+ for associative arrays
# If default bash is < 4, use: /opt/homebrew/bin/bash or /usr/local/bin/bash

# Unified VM Network Management Script
# This script handles all VM network operations:
# - Static IP configuration (host-side orchestration + VM-side configuration)
# - my-mac2 network fixes and restoration
# Usage:
#   Host-side: bash vm-network.sh apply-static-ip [vm_name]
#   VM-side:   bash vm-network.sh configure-interface <interface> <ip> [netmask] [gateway] [dns]
#   my-mac2:   bash vm-network.sh fix-mac2-network [vm_name]
#   my-mac2:   bash vm-network.sh restore-mac2-node [vm_name]

set +e  # Don't exit on error for host-side operations

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

# Source common utilities
if [ -f "$SCRIPT_DIR/common-vagrant.sh" ]; then
    source "$SCRIPT_DIR/common-vagrant.sh"
fi

# ============================================================================
# VM-SIDE: Configure static IP on a network interface (runs inside VM)
# ============================================================================
configure_interface() {
    local INTERFACE_NAME="${1:-eth1}"
    local IP_ADDRESS="$2"
    local NETMASK="${3:-255.255.255.0}"
    local GATEWAY="$4"
    local DNS_SERVERS="${5:-8.8.8.8 8.8.4.4}"
    
    if [ -z "$IP_ADDRESS" ]; then
        echo "Error: IP address is required"
        echo "Usage: $0 configure-interface <interface_name> <ip_address> [netmask] [gateway] [dns_servers]"
        exit 1
    fi
    
    # Detect network interface
    DETECTED_INTERFACE=$(ip -4 addr show | grep -B 2 "$IP_ADDRESS" | grep -oP '^\d+: \K[^:]+' | head -1 || echo "$INTERFACE_NAME")
    if [ -n "$DETECTED_INTERFACE" ] && [ "$DETECTED_INTERFACE" != "$INTERFACE_NAME" ]; then
        INTERFACE_NAME=$DETECTED_INTERFACE
        echo "Detected interface: $INTERFACE_NAME"
    fi
    
    # Calculate CIDR notation from netmask
    if [[ "$NETMASK" == "255.255.255.0" ]]; then
        CIDR="/24"
    elif [[ "$NETMASK" == "255.255.0.0" ]]; then
        CIDR="/16"
    elif [[ "$NETMASK" == "255.0.0.0" ]]; then
        CIDR="/8"
    else
        CIDR="/24"
    fi
    
    # Extract gateway from IP if not provided
    if [ -z "$GATEWAY" ]; then
        IFS='.' read -r -a IP_PARTS <<< "$IP_ADDRESS"
        GATEWAY="${IP_PARTS[0]}.${IP_PARTS[1]}.${IP_PARTS[2]}.1"
    fi
    
    echo "Configuring static IP for interface: $INTERFACE_NAME"
    echo "  IP Address: $IP_ADDRESS$CIDR"
    echo "  Gateway: $GATEWAY"
    echo "  DNS: $DNS_SERVERS"
    
    # Backup existing netplan configuration
    NETPLAN_DIR="/etc/netplan"
    if [ -d "$NETPLAN_DIR" ]; then
        EXISTING_FILE=$(ls $NETPLAN_DIR/*.yaml 2>/dev/null | head -1)
        if [ -n "$EXISTING_FILE" ]; then
            cp "$EXISTING_FILE" "${EXISTING_FILE}.backup.$(date +%Y%m%d-%H%M%S)"
        fi
    fi
    
    # Create netplan configuration
    NETPLAN_FILE="$NETPLAN_DIR/50-static-${INTERFACE_NAME}.yaml"
    
    cat > "$NETPLAN_FILE" <<EOF
network:
  version: 2
  renderer: networkd
  ethernets:
    $INTERFACE_NAME:
      dhcp4: false
      addresses:
        - $IP_ADDRESS$CIDR
      routes:
        - to: default
          via: $GATEWAY
      nameservers:
        addresses:
EOF
    
    # Add DNS servers
    for DNS in $DNS_SERVERS; do
        echo "          - $DNS" >> "$NETPLAN_FILE"
    done
    
    # Apply netplan configuration
    netplan apply
    
    # Verify configuration
    echo ""
    echo "Static IP configuration applied. Current network configuration:"
    ip addr show "$INTERFACE_NAME" | grep -E "inet |inet6 " || echo "Interface $INTERFACE_NAME not found or not configured"
    
    echo ""
    echo "Testing connectivity..."
    if ping -c 1 -W 2 "$GATEWAY" > /dev/null 2>&1; then
        echo "✓ Gateway $GATEWAY is reachable"
    else
        echo "⚠ Warning: Gateway $GATEWAY is not reachable"
    fi
    
    if ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
        echo "✓ Internet connectivity is working"
    else
        echo "⚠ Warning: Internet connectivity test failed"
    fi
    
    echo ""
    echo "Static IP configuration completed for $INTERFACE_NAME: $IP_ADDRESS"
}

# ============================================================================
# HOST-SIDE: Apply static IP to all VMs
# ============================================================================
apply_static_ip() {
    local TARGET_VM="${1:-}"  # Optional: specific VM name
    
    # VM configuration mapping
    declare -A VM_CONFIGS
    VM_CONFIGS["my-ubuntu:kube-master"]="192.168.0.100:192.168.0.100"
    VM_CONFIGS["my-ubuntu:kube-node-1"]="192.168.0.101:192.168.0.101"
    VM_CONFIGS["my-ubuntu:kube-node-2"]="192.168.0.102:192.168.0.102"
    # Windows (Git Bash/MSYS2) - same as my-ubuntu for default master setup
    VM_CONFIGS["my-windows:kube-master"]="192.168.0.100:192.168.0.100"
    VM_CONFIGS["my-windows:kube-node-1"]="192.168.0.101:192.168.0.101"
    VM_CONFIGS["my-windows:kube-node-2"]="192.168.0.102:192.168.0.102"
    VM_CONFIGS["my-mac:kube-master2"]="192.168.0.103:192.168.0.103"
    VM_CONFIGS["my-mac:kube-node2-1"]="192.168.0.104:192.168.0.104"
    VM_CONFIGS["my-mac:kube-node2-2"]="192.168.0.105:192.168.0.105"
    VM_CONFIGS["my-mac2:kube-master3"]="192.168.0.106:192.168.0.106"
    VM_CONFIGS["my-mac2:kube-node3-1"]="192.168.0.107:192.168.0.107"
    # Slave VMs (A_ENV=S)
    VM_CONFIGS["my-mac:kube-slave-1"]="192.168.0.110:192.168.0.110"
    VM_CONFIGS["my-mac:kube-slave-2"]="192.168.0.112:192.168.0.112"
    VM_CONFIGS["my-mac:kube-slave-3"]="192.168.0.113:192.168.0.113"
    # Slave VMs (A_ENV=S2)
    VM_CONFIGS["my-mac2:kube-slave-4"]="192.168.0.210:192.168.0.210"
    VM_CONFIGS["my-mac2:kube-slave-5"]="192.168.0.212:192.168.0.212"
    VM_CONFIGS["my-mac2:kube-slave-6"]="192.168.0.213:192.168.0.213"
    
    # Find vagrant command
    VAGRANT_CMD=$(find_vagrant_cmd)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    # Detect host
    DETECTED_HOST=$(detect_host)
    if [ "$DETECTED_HOST" == "unknown" ]; then
        echo "Warning: Could not detect host type. Attempting to proceed..."
        DETECTED_HOST="my-ubuntu"
    fi
    
    echo "=========================================="
    echo "Static IP Configuration Script"
    echo "=========================================="
    echo "Detected host: $DETECTED_HOST"
    echo "Using vagrant: $VAGRANT_CMD"
    echo ""
    
    # Get list of running VMs
    echo "Checking running VMs..."
    if [ -n "$TARGET_VM" ]; then
        VM_LIST="$TARGET_VM"
    else
        VM_LIST=$(get_running_vms "$VAGRANT_CMD")
    fi
    
    if [ -z "$VM_LIST" ]; then
        echo "Error: No running VMs found. Please start VMs first with 'vagrant up'"
        exit 1
    fi
    
    echo "Found VMs: $(echo $VM_LIST | tr '\n' ' ')"
    echo ""
    
    # Function to configure static IP for a VM
    configure_vm() {
        local vm_name=$1
        local k8s_ip=$2
        local host_ip=$3
        
        echo "Configuring $vm_name..."
        
        # Configure Kubernetes network (eth1)
        echo "  -> Setting Kubernetes network (eth1) to $k8s_ip"
        if [ -f "$SCRIPT_DIR/vm-network.sh" ]; then
            ssh_vm "$vm_name" "sudo bash /vagrant/scripts/local/vm-network.sh configure-interface eth1 $k8s_ip 255.255.255.0 192.168.0.1 '8.8.8.8 8.8.4.4'" "true" "$VAGRANT_CMD" || {
                echo "    ⚠ Warning: Failed to configure Kubernetes network for $vm_name"
            }
        else
            # Fallback: use configure_static_ip function if available
            configure_static_ip "$vm_name" "eth1" "$k8s_ip" "255.255.255.0" "192.168.0.1" "8.8.8.8 8.8.4.4" "$VAGRANT_CMD" || {
                echo "    ⚠ Warning: Failed to configure Kubernetes network for $vm_name"
            }
        fi
        
        # Configure host access network (eth2) - if exists
        echo "  -> Setting host access network (eth2) to $host_ip"
        if [ -f "$SCRIPT_DIR/vm-network.sh" ]; then
            ssh_vm "$vm_name" "sudo bash /vagrant/scripts/local/vm-network.sh configure-interface eth2 $host_ip 255.255.255.0 192.168.0.1 '8.8.8.8 8.8.4.4'" "true" "$VAGRANT_CMD" || {
                echo "    ℹ Info: Host access network interface may not exist or already configured for $vm_name"
            }
        else
            # Fallback: use configure_static_ip function if available
            configure_static_ip "$vm_name" "eth2" "$host_ip" "255.255.255.0" "192.168.0.1" "8.8.8.8 8.8.4.4" "$VAGRANT_CMD" || {
                echo "    ℹ Info: Host access network interface may not exist or already configured for $vm_name"
            }
        fi
    }
    
    # Configure each VM
    for vm_name in $VM_LIST; do
        config_key="$DETECTED_HOST:$vm_name"
        
        if [ -n "${VM_CONFIGS[$config_key]}" ]; then
            IFS=':' read -r k8s_ip host_ip <<< "${VM_CONFIGS[$config_key]}"
            configure_vm "$vm_name" "$k8s_ip" "$host_ip"
            echo ""
        else
            echo "⚠ Warning: No configuration found for $vm_name on $DETECTED_HOST"
            echo ""
        fi
    done
    
    echo "=========================================="
    echo "Static IP configuration completed!"
    echo "=========================================="
}

# ============================================================================
# my-mac2: Fix network configuration
# ============================================================================
fix_mac2_network() {
    local TARGET_VM="${1:-}"  # Optional: specific VM name
    
    VAGRANT_CMD=$(find_vagrant_cmd)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    echo "=========================================="
    echo "Fixing my-mac2 Kubernetes Nodes Network"
    echo "=========================================="
    echo ""
    
    # VM list
    if [ -n "$TARGET_VM" ]; then
        VM_LIST="$TARGET_VM"
    else
        VM_LIST="kube-master3 kube-node3-1"
    fi
    
    # Function to fix network on a VM
    fix_vm_network() {
        local vm_name=$1
        local k8s_ip=$2
        
        echo "Fixing network for $vm_name ($k8s_ip)..."
        
        # Fix default route to use eth2 (192.168.0.1)
        echo "  -> Setting default route to 192.168.0.1 via eth2"
        ssh_vm "$vm_name" "sudo ip route del default 2>/dev/null; sudo ip route add default via 192.168.0.1 dev eth2" "true" "$VAGRANT_CMD" || {
            echo "    ⚠ Warning: Failed to set default route"
        }
        
        # Restart kubelet to reconnect to API server
        echo "  -> Restarting kubelet"
        ssh_vm "$vm_name" "sudo systemctl restart kubelet" "true" "$VAGRANT_CMD" || {
            echo "    ⚠ Warning: Failed to restart kubelet"
        }
        
        # Verify network connectivity
        echo "  -> Testing connectivity to API server (192.168.0.100)"
        test_vm_connectivity "$vm_name" "192.168.0.100" "API server" "$VAGRANT_CMD" || true
        
        echo ""
    }
    
    # IP mapping for my-mac2
    declare -A MAC2_IPS
    MAC2_IPS["kube-master3"]="192.168.0.106"
    MAC2_IPS["kube-node3-1"]="192.168.0.107"
    
    for vm_name in $VM_LIST; do
        if [ -n "${MAC2_IPS[$vm_name]}" ]; then
            fix_vm_network "$vm_name" "${MAC2_IPS[$vm_name]}"
        fi
    done
    
    echo "=========================================="
    echo "Network fix completed!"
    echo "=========================================="
}

# ============================================================================
# my-mac2: Restore nodes to Ready state
# ============================================================================
restore_mac2_node() {
    local TARGET_VM="${1:-}"  # Optional: specific VM name
    
    VAGRANT_CMD=$(find_vagrant_cmd)
    if [ $? -ne 0 ]; then
        exit 1
    fi
    
    echo "=========================================="
    echo "Restoring my-mac2 Kubernetes Nodes"
    echo "=========================================="
    echo ""
    
    # VM list
    if [ -n "$TARGET_VM" ]; then
        VM_LIST="$TARGET_VM"
    else
        VM_LIST="kube-master3 kube-node3-1"
    fi
    
    # IP mapping for my-mac2
    declare -A MAC2_CONFIGS
    MAC2_CONFIGS["kube-master3"]="192.168.0.106:192.168.0.106"
    MAC2_CONFIGS["kube-node3-1"]="192.168.0.107:192.168.0.107"
    
    # Function to restore a VM
    restore_vm() {
        local vm_name=$1
        local k8s_ip=$2
        local host_ip=$3
        
        echo "Restoring $vm_name..."
        echo "  Kubernetes IP: $k8s_ip"
        echo "  Host IP: $host_ip"
        
        # Check if VM is running
        VM_STATUS=$(get_vm_status "$vm_name" "$VAGRANT_CMD")
        
        if [ "$VM_STATUS" != "running" ]; then
            echo "  ⚠ Warning: VM is not running. Status: $VM_STATUS"
            echo "  -> Starting VM..."
            $VAGRANT_CMD up "$vm_name" 2>&1 | grep -v "Warning: Permanently added" || {
                echo "    ✗ Failed to start VM"
                return 1
            }
            sleep 10
        fi
        
        # Fix default route to use eth2 (192.168.0.1) for external access
        echo "  -> Setting default route to 192.168.0.1 via eth2"
        ssh_vm "$vm_name" "sudo ip route del default 2>/dev/null; sudo ip route add default via 192.168.0.1 dev eth2" "true" "$VAGRANT_CMD" || {
            echo "    ⚠ Warning: Failed to set default route"
        }
        
        # Add route to Kubernetes API server network (192.168.0.0/24) via eth1
        echo "  -> Adding route to Kubernetes network (192.168.0.0/24) via eth1"
        ssh_vm "$vm_name" "sudo ip route add 192.168.0.0/24 via 192.168.0.1 dev eth1 2>/dev/null || sudo ip route replace 192.168.0.0/24 via 192.168.0.1 dev eth1" "true" "$VAGRANT_CMD" || {
            echo "    ℹ Info: Route may already exist"
        }
        
        # Restart kubelet to reconnect to API server
        echo "  -> Restarting kubelet"
        ssh_vm "$vm_name" "sudo systemctl restart kubelet" "true" "$VAGRANT_CMD" || {
            echo "    ⚠ Warning: Failed to restart kubelet"
        }
        
        # Verify network connectivity
        echo "  -> Testing connectivity..."
        test_vm_connectivity "$vm_name" "192.168.0.100" "API server (192.168.0.100)" "$VAGRANT_CMD" || true
        test_vm_connectivity "$vm_name" "8.8.8.8" "Internet" "$VAGRANT_CMD" || true
        
        echo ""
    }
    
    for vm_name in $VM_LIST; do
        if [ -n "${MAC2_CONFIGS[$vm_name]}" ]; then
            IFS=':' read -r k8s_ip host_ip <<< "${MAC2_CONFIGS[$vm_name]}"
            restore_vm "$vm_name" "$k8s_ip" "$host_ip"
        fi
    done
    
    echo "=========================================="
    echo "Restoration completed!"
    echo "=========================================="
}

# ============================================================================
# Main dispatcher
# ============================================================================
ACTION="${1:-help}"

case "$ACTION" in
    configure-interface)
        # VM-side: Configure interface (runs inside VM)
        shift
        configure_interface "$@"
        ;;
    apply-static-ip)
        # Host-side: Apply static IP to all VMs
        shift
        apply_static_ip "$@"
        ;;
    fix-mac2-network)
        # my-mac2: Fix network
        shift
        fix_mac2_network "$@"
        ;;
    restore-mac2-node)
        # my-mac2: Restore node
        shift
        restore_mac2_node "$@"
        ;;
    help|*)
        echo "Usage: $0 <action> [arguments]"
        echo ""
        echo "Actions:"
        echo "  configure-interface <interface> <ip> [netmask] [gateway] [dns]"
        echo "    - Configure static IP on a network interface (runs inside VM)"
        echo ""
        echo "  apply-static-ip [vm_name]"
        echo "    - Apply static IP configuration to all VMs or specific VM (runs on host)"
        echo ""
        echo "  fix-mac2-network [vm_name]"
        echo "    - Fix network configuration for my-mac2 nodes (runs on host)"
        echo ""
        echo "  restore-mac2-node [vm_name]"
        echo "    - Restore my-mac2 Kubernetes nodes to Ready state (runs on host)"
        echo ""
        exit 1
        ;;
esac
