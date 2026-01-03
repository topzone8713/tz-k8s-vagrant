#!/bin/bash

# Script to set up SSH tunnel and copy kubeconfig for Kubernetes API access

KUBE_MASTER_IP="192.168.86.100"
LOCAL_PORT="6443"
KUBECONFIG_HOST_PATH="$HOME/.kube/config"
KUBECONFIG_VM_PATH="/root/.kube/config"
SSH_TUNNEL_PID_FILE="/tmp/k8s-ssh-tunnel.pid"

# Function: Start SSH tunnel
start_tunnel() {
    echo "Starting SSH tunnel..."
    
    # Check if tunnel already exists
    if [ -f "$SSH_TUNNEL_PID_FILE" ]; then
        OLD_PID=$(cat "$SSH_TUNNEL_PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "SSH tunnel is already running. PID: $OLD_PID"
            return 0
        else
            rm -f "$SSH_TUNNEL_PID_FILE"
        fi
    fi
    
    # Check if port is already in use
    if command -v lsof > /dev/null 2>&1; then
        if lsof -i :$LOCAL_PORT > /dev/null 2>&1; then
            echo "Warning: Port $LOCAL_PORT is already in use."
            echo "Please use a different port or stop the existing process."
            return 1
        fi
    fi
    
    # Start SSH tunnel
    vagrant ssh kube-master -- -L $LOCAL_PORT:127.0.0.1:6443 -N -f
    
    if [ $? -eq 0 ]; then
        # Save PID (vagrant ssh doesn't return PID directly, so find it with ps)
        sleep 1
        PID=$(ps aux | grep -E "[s]sh.*${LOCAL_PORT}:127.0.0.1:6443" | awk '{print $2}' | head -1)
        if [ -n "$PID" ]; then
            echo "$PID" > "$SSH_TUNNEL_PID_FILE"
            echo "SSH tunnel started. PID: $PID"
            return 0
        fi
    fi
    
    echo "Error: Failed to start SSH tunnel."
    return 1
}

# Function: Stop SSH tunnel
stop_tunnel() {
    if [ -f "$SSH_TUNNEL_PID_FILE" ]; then
        PID=$(cat "$SSH_TUNNEL_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID"
            echo "SSH tunnel stopped. PID: $PID"
        else
            echo "SSH tunnel is not running."
        fi
        rm -f "$SSH_TUNNEL_PID_FILE"
    else
        # Find and stop process even if PID file doesn't exist
        PID=$(ps aux | grep -E "[s]sh.*${LOCAL_PORT}:127.0.0.1:6443" | awk '{print $2}' | head -1)
        if [ -n "$PID" ]; then
            kill "$PID"
            echo "SSH tunnel stopped. PID: $PID"
        else
            echo "No SSH tunnel is running."
        fi
    fi
}

# Function: Copy kubeconfig
copy_kubeconfig() {
    echo "=========================================="
    echo "Copying kubeconfig..."
    echo "=========================================="
    
    vagrant ssh kube-master -c "sudo cat $KUBECONFIG_VM_PATH" > /tmp/kubeconfig_temp 2>/dev/null
    
    if [ $? -ne 0 ] || [ ! -s /tmp/kubeconfig_temp ]; then
        echo "Error: Unable to read kubeconfig file from VM."
        return 1
    fi
    
    mkdir -p "$HOME/.kube"
    cp /tmp/kubeconfig_temp "$KUBECONFIG_HOST_PATH"
    
    # Change server address
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|server: https://.*:6443|server: https://127.0.0.1:$LOCAL_PORT|g" "$KUBECONFIG_HOST_PATH"
    else
        sed -i "s|server: https://.*:6443|server: https://127.0.0.1:$LOCAL_PORT|g" "$KUBECONFIG_HOST_PATH"
    fi
    
    chmod 600 "$KUBECONFIG_HOST_PATH"
    rm -f /tmp/kubeconfig_temp
    
    echo "kubeconfig copied to: $KUBECONFIG_HOST_PATH"
    return 0
}

# Function: Test connection
test_connection() {
    echo "Testing connection..."
    if command -v kubectl > /dev/null 2>&1; then
        kubectl get nodes 2>&1
        if [ $? -eq 0 ]; then
            echo "Connection successful!"
            return 0
        else
            echo "Connection failed. Please check if SSH tunnel is running."
            return 1
        fi
    else
        echo "Warning: kubectl is not installed."
        echo "Please install kubectl or check the path."
        return 1
    fi
}

# Main logic
ACTION="${1:-start}"

if [ "$ACTION" = "start" ]; then
    copy_kubeconfig
    if [ $? -eq 0 ]; then
        start_tunnel
        if [ $? -eq 0 ]; then
            sleep 2
            test_connection
        fi
    fi
elif [ "$ACTION" = "stop" ]; then
    stop_tunnel
elif [ "$ACTION" = "restart" ]; then
    stop_tunnel
    sleep 1
    start_tunnel
elif [ "$ACTION" = "status" ]; then
    if [ -f "$SSH_TUNNEL_PID_FILE" ]; then
        PID=$(cat "$SSH_TUNNEL_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "SSH tunnel running. PID: $PID"
        else
            echo "SSH tunnel is not running."
        fi
    else
        echo "SSH tunnel is not running."
    fi
elif [ "$ACTION" = "test" ]; then
    test_connection
else
    echo "Usage: $0 {start|stop|restart|status|test}"
    echo ""
    echo "  start   - Copy kubeconfig and start SSH tunnel (default)"
    echo "  stop    - Stop SSH tunnel"
    echo "  restart - Restart SSH tunnel"
    echo "  status  - Check SSH tunnel status"
    echo "  test    - Test kubectl connection"
    exit 1
fi

