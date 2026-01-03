#!/bin/bash

# Script to access Kubernetes from MacBook via my-ubuntu
# Double SSH tunneling: MacBook -> my-ubuntu -> kube-master

MY_UBUNTU_HOST="my-ubuntu"  # SSH hostname or IP
MY_UBUNTU_USER="${USER}"     # my-ubuntu username (modify if needed)
LOCAL_PORT="6443"            # Local port on MacBook
REMOTE_PORT="6443"           # Local port on my-ubuntu (kube-master tunnel port)
KUBECONFIG_HOST_PATH="$HOME/.kube/my-ubuntu.config"
KUBECONFIG_VM_PATH="/root/.kube/config"
TUNNEL_PID_FILE="/tmp/k8s-ssh-tunnel-from-mac.pid"
export KUBECONFIG="$KUBECONFIG_HOST_PATH"

# Function: Start SSH tunnel (MacBook -> my-ubuntu -> kube-master)
start_tunnel() {
    echo "Starting SSH tunnel (MacBook -> my-ubuntu -> kube-master)..."
    
    # Check if tunnel already exists
    if [ -f "$TUNNEL_PID_FILE" ]; then
        OLD_PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "SSH tunnel is already running. PID: $OLD_PID"
            return 0
        else
            rm -f "$TUNNEL_PID_FILE"
        fi
    fi
    
    # Check if port is already in use
    if command -v lsof > /dev/null 2>&1; then
        EXISTING_PID=$(lsof -ti :$LOCAL_PORT 2>/dev/null | head -1)
        if [ -n "$EXISTING_PID" ]; then
            # Check if existing process is our tunnel
            EXISTING_CMD=$(ps -p "$EXISTING_PID" -o command= 2>/dev/null | grep -E "ssh.*${LOCAL_PORT}.*${MY_UBUNTU_HOST}" || echo "")
            if [ -n "$EXISTING_CMD" ]; then
                echo "Existing SSH tunnel is running. PID: $EXISTING_PID (reusing)"
                echo "$EXISTING_PID" > "$TUNNEL_PID_FILE"
                return 0
            else
                echo "Warning: Port $LOCAL_PORT is in use by another process. (PID: $EXISTING_PID)"
                echo "Please use a different port or stop the existing process."
                return 1
            fi
        fi
    fi
    
    # Check if kube-master tunnel is running on my-ubuntu
    echo "Checking kube-master tunnel status on my-ubuntu..."
    TUNNEL_STATUS=$(ssh "$MY_UBUNTU_HOST" "cd ~/workspaces/tz-k8s-vagrant && ./access-k8s-from-host.sh status 2>&1")
    TUNNEL_EXISTS=$(echo "$TUNNEL_STATUS" | grep -i "실행 중\|running" || echo "")
    
    if [ -z "$TUNNEL_EXISTS" ]; then
        echo "Starting kube-master tunnel on my-ubuntu..."
        ssh "$MY_UBUNTU_HOST" "cd ~/workspaces/tz-k8s-vagrant && ./access-k8s-from-host.sh start" 2>&1
        sleep 3
    else
        echo "kube-master tunnel is already running on my-ubuntu."
    fi
    
    # Start MacBook -> my-ubuntu SSH tunnel
    # Forward my-ubuntu's 127.0.0.1:6443 to MacBook's 127.0.0.1:6443
    echo "Starting MacBook -> my-ubuntu SSH tunnel..."
    ssh -f -N -L ${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT} "$MY_UBUNTU_HOST" 2>&1
    
    TUNNEL_EXIT_CODE=$?
    if [ $TUNNEL_EXIT_CODE -eq 0 ]; then
        sleep 2
        PID=$(ps aux | grep -E "[s]sh.*${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}.*${MY_UBUNTU_HOST}" | grep -v grep | awk '{print $2}' | head -1)
        if [ -n "$PID" ]; then
            echo "$PID" > "$TUNNEL_PID_FILE"
            echo "SSH tunnel started. PID: $PID"
            echo "MacBook localhost:${LOCAL_PORT} -> my-ubuntu:${REMOTE_PORT} -> kube-master:6443"
            return 0
        else
            echo "Warning: SSH process started but PID not found."
            echo "Check manually: ps aux | grep ssh | grep ${LOCAL_PORT}"
        fi
    else
        echo "Warning: SSH tunnel command failed. (exit code: $TUNNEL_EXIT_CODE)"
    fi
    
    echo "Error: Failed to start SSH tunnel."
    return 1
}

# Function: Stop SSH tunnel
stop_tunnel() {
    if [ -f "$TUNNEL_PID_FILE" ]; then
        PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID"
            echo "SSH tunnel stopped. PID: $PID"
        else
            echo "SSH tunnel is not running."
        fi
        rm -f "$TUNNEL_PID_FILE"
    else
        PID=$(ps aux | grep -E "[s]sh.*${LOCAL_PORT}:127.0.0.1:${REMOTE_PORT}.*${MY_UBUNTU_HOST}" | grep -v grep | awk '{print $2}' | head -1)
        if [ -n "$PID" ]; then
            kill "$PID"
            echo "SSH tunnel stopped. PID: $PID"
        else
            echo "No SSH tunnel is running."
        fi
    fi
}

# Function: Copy kubeconfig (from my-ubuntu)
copy_kubeconfig() {
    echo "=========================================="
    echo "Copying kubeconfig (from my-ubuntu)..."
    echo "=========================================="
    
    # Get kubeconfig from my-ubuntu (use ~/.kube/config on my-ubuntu)
    ssh "$MY_UBUNTU_HOST" "cat ~/.kube/config" > /tmp/kubeconfig_temp 2>/dev/null
    
    if [ $? -ne 0 ] || [ ! -s /tmp/kubeconfig_temp ]; then
        echo "Error: Unable to read kubeconfig file from my-ubuntu."
        echo "Please run 'access-k8s-from-host.sh start' on my-ubuntu first."
        return 1
    fi
    
    mkdir -p "$HOME/.kube"
    cp /tmp/kubeconfig_temp "$KUBECONFIG_HOST_PATH"
    
    # Change server address to MacBook's localhost:6443
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s|server: https://.*:6443|server: https://127.0.0.1:$LOCAL_PORT|g" "$KUBECONFIG_HOST_PATH"
    else
        sed -i "s|server: https://.*:6443|server: https://127.0.0.1:$LOCAL_PORT|g" "$KUBECONFIG_HOST_PATH"
    fi
    
    chmod 600 "$KUBECONFIG_HOST_PATH"
    rm -f /tmp/kubeconfig_temp
    
    echo "kubeconfig copied to: $KUBECONFIG_HOST_PATH"
    echo ""
    echo "Usage:"
    echo "  export KUBECONFIG=\"$KUBECONFIG_HOST_PATH\""
    echo "  kubectl get nodes"
    return 0
}

# Function: Test connection
test_connection() {
    echo "Testing connection..."
    if command -v kubectl > /dev/null 2>&1; then
        KUBECONFIG="$KUBECONFIG_HOST_PATH" kubectl get nodes 2>&1
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
        echo "macOS: brew install kubectl"
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
    if [ -f "$TUNNEL_PID_FILE" ]; then
        PID=$(cat "$TUNNEL_PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "SSH tunnel running. PID: $PID"
        else
            echo "SSH tunnel is not running."
        fi
    else
        echo "SSH tunnel is not running."
    fi
    echo ""
    echo "Tunnel status on my-ubuntu:"
    ssh "$MY_UBUNTU_HOST" "cd ~/workspaces/tz-k8s-vagrant && ./access-k8s-from-host.sh status" 2>/dev/null || echo "Failed to connect to my-ubuntu"
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
    echo ""
    echo "Requirements:"
    echo "  - SSH access to my-ubuntu must be available ('ssh my-ubuntu' should work)"
    echo "  - access-k8s-from-host.sh must exist on my-ubuntu"
    echo "  - kubectl must be installed on MacBook (brew install kubectl)"
    echo ""
    echo "kubeconfig file location: $KUBECONFIG_HOST_PATH"
    echo "Usage:"
    echo "  export KUBECONFIG=\"$KUBECONFIG_HOST_PATH\""
    echo "  kubectl get nodes"
    exit 1
fi

