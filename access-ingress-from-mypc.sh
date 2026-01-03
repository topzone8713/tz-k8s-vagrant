#!/bin/bash

# Script to access Kubernetes Service/Ingress from MacBook using kubectl port-forward
# Usage: ./access-ingress-from-mypc.sh [command] [service-name] [namespace]
#
# Important:
#   - Default service is ingress-nginx-controller, which allows access to ALL ingresses
#   - Once ingress-nginx-controller is forwarded, all ingress domains are accessible via the same port (8080/8443)
#   - Individual service port-forwarding is usually not necessary
#   - Just add desired domains to /etc/hosts and access them via the forwarded port

KUBECONFIG_PATH="$HOME/.kube/my-ubuntu.config"
DEFAULT_NAMESPACE="default"
DEFAULT_SERVICE_NAME="ingress-nginx-controller"
HTTP_LOCAL_PORT="8080"
HTTPS_LOCAL_PORT="8443"

# Parse arguments
ACTION="${1:-start}"
SERVICE_NAME="${2:-$DEFAULT_SERVICE_NAME}"
NAMESPACE="${3:-$DEFAULT_NAMESPACE}"

# Generate PID file based on service and namespace
PID_FILE="/tmp/k8s-port-forward-${NAMESPACE}-${SERVICE_NAME}.pid"

# Function: Start port-forward
start_portforward() {
    echo "Starting kubectl port-forward for service: $SERVICE_NAME (namespace: $NAMESPACE)..."
    
    # Check if port-forward already exists
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if ps -p "$OLD_PID" > /dev/null 2>&1; then
            echo "Port-forward is already running. PID: $OLD_PID"
            echo ""
            echo "Service: $SERVICE_NAME (namespace: $NAMESPACE)"
            echo "Ports: localhost:$HTTP_LOCAL_PORT, localhost:$HTTPS_LOCAL_PORT"
            echo ""
            # Get ingress host if available
            export KUBECONFIG="$KUBECONFIG_PATH"
            INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.rules[0].http.paths[0].backend.service.name=="'$SERVICE_NAME'")].spec.rules[0].host}' 2>/dev/null | awk '{print $1}')
            if [ -n "$INGRESS_HOST" ]; then
                echo "Access URL (add to /etc/hosts: 127.0.0.1 $INGRESS_HOST):"
                echo "  http://$INGRESS_HOST:$HTTP_LOCAL_PORT"
                if [ -n "$HTTPS_LOCAL_PORT" ]; then
                    echo "  https://$INGRESS_HOST:$HTTPS_LOCAL_PORT"
                fi
            else
                echo "Access URL:"
                echo "  http://localhost:$HTTP_LOCAL_PORT"
                if [ -n "$HTTPS_LOCAL_PORT" ]; then
                    echo "  https://localhost:$HTTPS_LOCAL_PORT"
                fi
            fi
            return 0
        else
            rm -f "$PID_FILE"
        fi
    fi
    
    # Check if ports are already in use and stop existing port-forwards
    if command -v lsof > /dev/null 2>&1; then
        HTTP_PID=$(lsof -ti :$HTTP_LOCAL_PORT 2>/dev/null | head -1)
        HTTPS_PID=$(lsof -ti :$HTTPS_LOCAL_PORT 2>/dev/null | head -1)
        
        if [ -n "$HTTP_PID" ]; then
            # Check if it's a kubectl port-forward process
            if ps -p "$HTTP_PID" > /dev/null 2>&1; then
                CMD=$(ps -p "$HTTP_PID" -o command= 2>/dev/null)
                if echo "$CMD" | grep -q "kubectl.*port-forward"; then
                    echo "Stopping existing port-forward on port $HTTP_LOCAL_PORT (PID: $HTTP_PID)..."
                    kill "$HTTP_PID" 2>/dev/null
                    sleep 1
                fi
            fi
        fi
        
        if [ -n "$HTTPS_PID" ] && [ "$HTTPS_PID" != "$HTTP_PID" ]; then
            # Check if it's a kubectl port-forward process
            if ps -p "$HTTPS_PID" > /dev/null 2>&1; then
                CMD=$(ps -p "$HTTPS_PID" -o command= 2>/dev/null)
                if echo "$CMD" | grep -q "kubectl.*port-forward"; then
                    echo "Stopping existing port-forward on port $HTTPS_LOCAL_PORT (PID: $HTTPS_PID)..."
                    kill "$HTTPS_PID" 2>/dev/null
                    sleep 1
                fi
            fi
        fi
        
        # Also stop any existing kubectl port-forward processes
        EXISTING_PF_PIDS=$(ps aux | grep -E "[k]ubectl.*port-forward" | awk '{print $2}')
        if [ -n "$EXISTING_PF_PIDS" ]; then
            echo "Stopping all existing kubectl port-forward processes..."
            echo "$EXISTING_PF_PIDS" | xargs kill 2>/dev/null
            sleep 1
        fi
        
        # Clean up any PID files
        rm -f /tmp/k8s-port-forward-*.pid 2>/dev/null
    fi
    
    # Check if kubectl is available
    if ! command -v kubectl > /dev/null 2>&1; then
        echo "Error: kubectl is not installed."
        echo "Please install kubectl: brew install kubectl"
        return 1
    fi
    
    # Check if kubeconfig exists
    if [ ! -f "$KUBECONFIG_PATH" ]; then
        echo "Error: kubeconfig file not found: $KUBECONFIG_PATH"
        echo "Please run access-k8s-from-mypc.sh start first."
        return 1
    fi
    
    # Verify service exists
    export KUBECONFIG="$KUBECONFIG_PATH"
    if ! kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" > /dev/null 2>&1; then
        echo "Error: Service '$SERVICE_NAME' not found in namespace '$NAMESPACE'."
        echo "Available services in namespace '$NAMESPACE':"
        kubectl get svc -n "$NAMESPACE" 2>&1 | head -10
        return 1
    fi
    
    # Get service ports (try to detect HTTP/HTTPS ports)
    SERVICE_PORTS=$(kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" -o jsonpath='{.spec.ports[*].port}' 2>/dev/null)
    HTTP_PORT=$(echo "$SERVICE_PORTS" | awk '{print $1}')
    HTTPS_PORT=$(echo "$SERVICE_PORTS" | awk '{print $2}')
    
    # Use default ports if service has standard HTTP/HTTPS ports
    if [ -n "$HTTPS_PORT" ]; then
        REMOTE_HTTP_PORT="${HTTP_PORT:-80}"
        REMOTE_HTTPS_PORT="${HTTPS_PORT:-443}"
        echo "Starting port-forward: $HTTP_LOCAL_PORT:$REMOTE_HTTP_PORT, $HTTPS_LOCAL_PORT:$REMOTE_HTTPS_PORT"
        kubectl port-forward -n "$NAMESPACE" svc/$SERVICE_NAME ${HTTP_LOCAL_PORT}:${REMOTE_HTTP_PORT} ${HTTPS_LOCAL_PORT}:${REMOTE_HTTPS_PORT} > /dev/null 2>&1 &
    else
        # Single port (HTTP only)
        REMOTE_HTTP_PORT="${HTTP_PORT:-80}"
        echo "Starting port-forward: $HTTP_LOCAL_PORT:$REMOTE_HTTP_PORT"
        kubectl port-forward -n "$NAMESPACE" svc/$SERVICE_NAME ${HTTP_LOCAL_PORT}:${REMOTE_HTTP_PORT} > /dev/null 2>&1 &
    fi
    
    PF_PID=$!
    sleep 2
    
    if ps -p "$PF_PID" > /dev/null 2>&1; then
        echo "$PF_PID" > "$PID_FILE"
        echo "Port-forward started. PID: $PF_PID"
        echo ""
        echo "Service: $SERVICE_NAME (namespace: $NAMESPACE)"
        echo "Ports: localhost:$HTTP_LOCAL_PORT -> $SERVICE_NAME:$REMOTE_HTTP_PORT"
        if [ -n "$REMOTE_HTTPS_PORT" ]; then
            echo "        localhost:$HTTPS_LOCAL_PORT -> $SERVICE_NAME:$REMOTE_HTTPS_PORT"
        fi
        echo ""
        # Get ingress host if available
        INGRESS_HOST=$(kubectl get ingress -n "$NAMESPACE" -o jsonpath='{.items[?(@.spec.rules[0].http.paths[0].backend.service.name=="'$SERVICE_NAME'")].spec.rules[0].host}' 2>/dev/null | awk '{print $1}')
        if [ -n "$INGRESS_HOST" ]; then
            echo "Access URL (add to /etc/hosts: 127.0.0.1 $INGRESS_HOST):"
            echo "  http://$INGRESS_HOST:$HTTP_LOCAL_PORT"
            if [ -n "$REMOTE_HTTPS_PORT" ]; then
                echo "  https://$INGRESS_HOST:$HTTPS_LOCAL_PORT"
            fi
        else
            echo "Access URL:"
            echo "  http://localhost:$HTTP_LOCAL_PORT"
            if [ -n "$REMOTE_HTTPS_PORT" ]; then
                echo "  https://localhost:$HTTPS_LOCAL_PORT"
            fi
        fi
        return 0
    else
        echo "Error: Failed to start port-forward."
        return 1
    fi
}

# Function: Stop port-forward
stop_portforward() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            kill "$PID"
            echo "Port-forward stopped. PID: $PID (service: $SERVICE_NAME, namespace: $NAMESPACE)"
        else
            echo "Port-forward is not running."
        fi
        rm -f "$PID_FILE"
    else
        PID=$(ps aux | grep -E "[k]ubectl.*port-forward.*-n.*${NAMESPACE}.*${SERVICE_NAME}" | awk '{print $2}' | head -1)
        if [ -n "$PID" ]; then
            kill "$PID"
            echo "Port-forward stopped. PID: $PID (service: $SERVICE_NAME, namespace: $NAMESPACE)"
        else
            echo "No port-forward is running for service: $SERVICE_NAME (namespace: $NAMESPACE)"
        fi
    fi
}

# Function: Show status
show_status() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        if ps -p "$PID" > /dev/null 2>&1; then
            echo "Port-forward running. PID: $PID"
            echo "Service: $SERVICE_NAME (namespace: $NAMESPACE)"
            echo "Ports: localhost:$HTTP_LOCAL_PORT, localhost:$HTTPS_LOCAL_PORT"
        else
            echo "Port-forward is not running for service: $SERVICE_NAME (namespace: $NAMESPACE)"
        fi
    else
        echo "Port-forward is not running for service: $SERVICE_NAME (namespace: $NAMESPACE)"
    fi
}

# Function: List available services and ingresses
list_resources() {
    # Check if kubectl is available
    if ! command -v kubectl > /dev/null 2>&1; then
        echo "Error: kubectl is not installed."
        echo "Please install kubectl: brew install kubectl"
        return 1
    fi
    
    # Check if kubeconfig exists
    if [ ! -f "$KUBECONFIG_PATH" ]; then
        echo "Error: kubeconfig file not found: $KUBECONFIG_PATH"
        echo "Please run access-k8s-from-mypc.sh start first."
        return 1
    fi
    
    export KUBECONFIG="$KUBECONFIG_PATH"
    
    # Get namespace from argument (if provided)
    LIST_NAMESPACE="$1"
    
    if [ -z "$LIST_NAMESPACE" ]; then
        # List all ingresses from all namespaces
        kubectl get ingress -A --no-headers 2>/dev/null | while read -r namespace name class hosts address ports age; do
            # Try to get service name from ingress
            service_name=$(kubectl get ingress "$name" -n "$namespace" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)
            if [ -n "$service_name" ]; then
                echo "access-ingress-from-mypc.sh start $service_name $namespace"
            else
                # If service name not found, use ingress name as fallback
                echo "access-ingress-from-mypc.sh start $name $namespace"
            fi
        done
    else
        # List ingresses from specific namespace
        kubectl get ingress -n "$LIST_NAMESPACE" --no-headers 2>/dev/null | while read -r name class hosts address ports age; do
            # Try to get service name from ingress
            service_name=$(kubectl get ingress "$name" -n "$LIST_NAMESPACE" -o jsonpath='{.spec.rules[0].http.paths[0].backend.service.name}' 2>/dev/null)
            if [ -n "$service_name" ]; then
                echo "access-ingress-from-mypc.sh start $service_name $LIST_NAMESPACE"
            else
                # If service name not found, use ingress name as fallback
                echo "access-ingress-from-mypc.sh start $name $LIST_NAMESPACE"
            fi
        done
    fi
}

# Main logic
if [ "$ACTION" = "start" ]; then
    start_portforward
elif [ "$ACTION" = "stop" ]; then
    stop_portforward
elif [ "$ACTION" = "status" ]; then
    show_status
elif [ "$ACTION" = "restart" ]; then
    stop_portforward
    sleep 1
    start_portforward
elif [ "$ACTION" = "list" ]; then
    list_resources "$2"
elif [ "$ACTION" = "help" ] || [ "$ACTION" = "-h" ] || [ "$ACTION" = "--help" ]; then
    echo "Usage: $0 [command] [service-name] [namespace]"
    echo ""
    echo "Commands:"
    echo "  start    - Start kubectl port-forward (default)"
    echo "  stop     - Stop port-forward"
    echo "  restart  - Restart port-forward"
    echo "  status   - Show port-forward status"
    echo "  list     - List available services and ingresses"
    echo "  help     - Show this help message"
    echo ""
    echo "Arguments:"
    echo "  service-name  - Kubernetes service name (default: $DEFAULT_SERVICE_NAME)"
    echo "  namespace     - Kubernetes namespace (default: $DEFAULT_NAMESPACE)"
    echo ""
    echo "Examples:"
    echo "  $0 list                                            # List services/ingresses in default namespace"
    echo "  $0 list kube-system                               # List services/ingresses in kube-system namespace"
    echo "  $0 start                                           # Use default service (ingress-nginx-controller)"
    echo "  $0 start my-service                               # Forward my-service in default namespace"
    echo "  $0 start my-service production                    # Forward my-service in production namespace"
    echo "  $0 stop my-service production                     # Stop port-forward for my-service"
    echo "  $0 status                                         # Check status of default service"
    echo ""
    echo "Requirements:"
    echo "  - kubectl must be installed"
    echo "  - KUBECONFIG must be set (run access-k8s-from-mypc.sh start first)"
    exit 0
else
    echo "Error: Unknown command '$ACTION'"
    echo "Run '$0 help' for usage information"
    exit 1
fi
