#!/usr/bin/env bash

# Common network routing fix and connectivity check functions
# This script provides reusable functions for fixing network routing
# and verifying internet connectivity across all provisioning scripts.

# Fix network routing to use NAT interface (eth0) for internet access
# This is needed because bridged interface (eth1) may take precedence
# but doesn't provide internet access in some network configurations
fix_network_routing() {
  local LOG_FILE="${1:-/dev/null}"
  local VERBOSE="${2:-false}"
  
  if [ "$VERBOSE" = "true" ]; then
    echo "=========================================="
    echo "Checking and fixing network routing for internet access..."
    echo "=========================================="
  fi
  
  # Check if there are conflicting default routes via eth1
  DEFAULT_ROUTES=$(ip route | grep "^default" | wc -l)
  ETH1_DEFAULT=$(ip route | grep "^default.*eth1" | wc -l)
  
  if [ "$ETH1_DEFAULT" -gt 0 ] || ! ping -c 1 8.8.8.8 > /dev/null 2>&1; then
    if [ "$VERBOSE" = "true" ]; then
      echo "Fixing network routing for internet access..." | tee -a "$LOG_FILE"
    else
      echo "[$(date)] Fixing network routing for internet access..." | tee -a "$LOG_FILE" > /dev/null 2>&1 || true
    fi
    
    # Remove default route via eth1 (bridged interface) if it exists
    sudo ip route del default via 192.168.0.1 dev eth1 2>/dev/null || true
    # Ensure default route via eth0 (NAT gateway) exists
    sudo ip route del default via 10.0.2.2 dev eth0 2>/dev/null || true
    sudo ip route add default via 10.0.2.2 dev eth0 2>/dev/null || true
    sleep 2
  fi
}

# Verify internet connectivity after routing fix
# Returns 0 if successful, 1 if failed
verify_internet_connectivity() {
  local LOG_FILE="${1:-/dev/null}"
  local EXIT_ON_FAILURE="${2:-true}"
  local PING_COUNT="${3:-3}"
  
  if ! ping -c "$PING_COUNT" 8.8.8.8 > /dev/null 2>&1; then
    if [ -f "$LOG_FILE" ] && [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] ERROR: Internet connectivity check failed!" | tee -a "$LOG_FILE"
      echo "ERROR: Internet connectivity check failed!" >&2
      echo "Current routing table:" >&2
      ip route >&2
      echo "Cannot proceed without internet access." >&2
    else
      echo "ERROR: Internet connectivity check failed!"
      echo "Current routing table:"
      ip route
      echo "Cannot proceed without internet access."
    fi
    
    if [ "$EXIT_ON_FAILURE" = "true" ]; then
      exit 1
    else
      return 1
    fi
  fi
  
  if [ -f "$LOG_FILE" ] && [ "$LOG_FILE" != "/dev/null" ]; then
    echo "[$(date)] Internet connectivity verified" | tee -a "$LOG_FILE"
  else
    echo "✓ Internet connectivity verified"
  fi
  
  return 0
}

# Verify DNS resolution
# Returns 0 if successful, 1 if failed
verify_dns_resolution() {
  local DOMAIN="${1:-github.com}"
  local EXIT_ON_FAILURE="${2:-true}"
  
  if ! nslookup "$DOMAIN" > /dev/null 2>&1; then
    echo "ERROR: DNS resolution failed!"
    echo "Cannot resolve $DOMAIN. Please check DNS configuration."
    
    if [ "$EXIT_ON_FAILURE" = "true" ]; then
      exit 1
    else
      return 1
    fi
  fi
  
  return 0
}

# Main function: Fix routing and verify connectivity
# Usage: fix_and_verify_network [LOG_FILE] [VERBOSE] [EXIT_ON_FAILURE]
fix_and_verify_network() {
  local LOG_FILE="${1:-/dev/null}"
  local VERBOSE="${2:-false}"
  local EXIT_ON_FAILURE="${3:-true}"
  
  fix_network_routing "$LOG_FILE" "$VERBOSE"
  verify_internet_connectivity "$LOG_FILE" "$EXIT_ON_FAILURE"
}

# Download file with retry logic
# Usage: download_with_retry <url> <output_file> [max_timeout] [max_retries] [log_file]
download_with_retry() {
  local URL="$1"
  local OUTPUT_FILE="$2"
  local MAX_TIMEOUT="${3:-600}"
  local MAX_RETRIES="${4:-3}"
  local LOG_FILE="${5:-/dev/null}"
  local RETRY_COUNT=0
  local DOWNLOAD_SUCCESS=false
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] Attempting to download $(basename "$OUTPUT_FILE") (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..." | tee -a "$LOG_FILE"
    else
      echo "Downloading $(basename "$OUTPUT_FILE") (attempt $((RETRY_COUNT + 1))/$MAX_RETRIES)..."
    fi
    
    # Use curl with progress bar
    if curl -L --connect-timeout 30 --max-time "$MAX_TIMEOUT" -# -o "$OUTPUT_FILE" "$URL" 2>&1 | { if [ "$LOG_FILE" != "/dev/null" ]; then tee -a "$LOG_FILE"; else cat; fi; }; then
      if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
        DOWNLOAD_SUCCESS=true
        if [ "$LOG_FILE" != "/dev/null" ]; then
          echo "[$(date)] $(basename "$OUTPUT_FILE") downloaded successfully ($(du -h "$OUTPUT_FILE" | cut -f1))" | tee -a "$LOG_FILE"
        fi
        break
      fi
    fi
    
    RETRY_COUNT=$((RETRY_COUNT + 1))
    rm -f "$OUTPUT_FILE"
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      if [ "$LOG_FILE" != "/dev/null" ]; then
        echo "[$(date)] Waiting 5 seconds before retry..." | tee -a "$LOG_FILE"
      else
        echo "Waiting 5 seconds before retry..."
      fi
      sleep 5
    fi
  done
  
  if [ "$DOWNLOAD_SUCCESS" != true ]; then
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] ERROR: Failed to download $(basename "$OUTPUT_FILE") after $MAX_RETRIES attempts" | tee -a "$LOG_FILE"
      echo "ERROR: Failed to download $(basename "$OUTPUT_FILE") after $MAX_RETRIES attempts" >&2
    else
      echo "ERROR: Failed to download $(basename "$OUTPUT_FILE") after $MAX_RETRIES attempts" >&2
    fi
    return 1
  fi
  
  return 0
}

# Get kubectl version with retry
# Usage: get_kubectl_version [log_file]
get_kubectl_version() {
  local LOG_FILE="${1:-/dev/null}"
  local MAX_RETRIES=3
  local RETRY_COUNT=0
  local KUBECTL_VERSION=""
  
  while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    KUBECTL_VERSION=$(curl -L -s --connect-timeout 30 --max-time 60 https://dl.k8s.io/release/stable.txt)
    if [ -n "$KUBECTL_VERSION" ]; then
      echo "$KUBECTL_VERSION"
      return 0
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] Retrying to get kubectl version (attempt $RETRY_COUNT/$MAX_RETRIES)..." | tee -a "$LOG_FILE"
    else
      echo "Retrying to get kubectl version (attempt $RETRY_COUNT/$MAX_RETRIES)..."
    fi
    sleep 5
  done
  
  if [ "$LOG_FILE" != "/dev/null" ]; then
    echo "[$(date)] ERROR: Failed to get kubectl version" | tee -a "$LOG_FILE"
    echo "ERROR: Failed to get kubectl version" >&2
  else
    echo "ERROR: Failed to get kubectl version" >&2
  fi
  return 1
}

# Install kubectl
# Usage: install_kubectl [log_file] [verbose]
install_kubectl() {
  local LOG_FILE="${1:-/dev/null}"
  local VERBOSE="${2:-false}"
  
  if command -v kubectl > /dev/null 2>&1; then
    # Already installed, just verify
    local VERSION_OUTPUT
    if kubectl version --client --short > /dev/null 2>&1; then
      VERSION_OUTPUT=$(kubectl version --client --short 2>/dev/null || echo "version check failed")
    else
      VERSION_OUTPUT=$(kubectl version --client 2>/dev/null | head -1 || echo "version check failed")
    fi
    if [ "$VERBOSE" = "true" ]; then
      echo "kubectl is already installed: $VERSION_OUTPUT"
    fi
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] kubectl already installed" | tee -a "$LOG_FILE"
    fi
    return 0
  fi
  
  if [ "$VERBOSE" = "true" ]; then
    echo "kubectl not found. Installing kubectl..."
    echo "Note: With slow network (~100KB/s), this may take ~8 minutes..."
  fi
  if [ "$LOG_FILE" != "/dev/null" ]; then
    echo "[$(date)] kubectl not found, installing..." | tee -a "$LOG_FILE"
  fi
  
  # Get kubectl version
  local KUBECTL_VERSION
  if ! KUBECTL_VERSION=$(get_kubectl_version "$LOG_FILE"); then
    return 1
  fi
  
  # Detect architecture
  local ARCH
  ARCH=$(uname -m)
  case "$ARCH" in
    aarch64|arm64)
      ARCH="arm64"
      ;;
    x86_64|amd64)
      ARCH="amd64"
      ;;
    *)
      if [ "$LOG_FILE" != "/dev/null" ]; then
        echo "[$(date)] WARNING: Unknown architecture $ARCH, defaulting to amd64" | tee -a "$LOG_FILE"
      fi
      ARCH="amd64"
      ;;
  esac

  # Download kubectl
  if ! download_with_retry "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/${ARCH}/kubectl" "kubectl" "600" "3" "$LOG_FILE"; then
    return 1
  fi
  
  # Install kubectl
  if ! sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl; then
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] ERROR: Failed to install kubectl" | tee -a "$LOG_FILE"
      echo "ERROR: Failed to install kubectl" >&2
    else
      echo "ERROR: Failed to install kubectl" >&2
    fi
    rm -f kubectl
    return 1
  fi
  
  rm -f kubectl
  
  # Verify installation
  local VERSION_OUTPUT
  if kubectl version --client --short > /dev/null 2>&1; then
    VERSION_OUTPUT=$(kubectl version --client --short 2>/dev/null || echo "version check failed")
  elif kubectl version --client > /dev/null 2>&1; then
    VERSION_OUTPUT=$(kubectl version --client 2>/dev/null | head -1 || echo "version check failed")
  else
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] ERROR: kubectl installation verification failed" | tee -a "$LOG_FILE"
      echo "ERROR: kubectl installation verification failed" >&2
    else
      echo "ERROR: kubectl installation verification failed" >&2
    fi
    return 1
  fi
  
  if [ "$VERBOSE" = "true" ]; then
    echo "kubectl installed: $VERSION_OUTPUT"
  fi
  if [ "$LOG_FILE" != "/dev/null" ]; then
    echo "[$(date)] kubectl installed successfully" | tee -a "$LOG_FILE"
  fi
  
  return 0
}

# Install helm
# Usage: install_helm [log_file] [verbose]
install_helm() {
  local LOG_FILE="${1:-/dev/null}"
  local VERBOSE="${2:-false}"
  
  if command -v helm > /dev/null 2>&1; then
    # Already installed, just verify
    local VERSION_OUTPUT
    if helm version --short > /dev/null 2>&1; then
      VERSION_OUTPUT=$(helm version --short 2>/dev/null || echo "version check failed")
    else
      VERSION_OUTPUT=$(helm version 2>/dev/null | head -1 || echo "version check failed")
    fi
    if [ "$VERBOSE" = "true" ]; then
      echo "helm is already installed: $VERSION_OUTPUT"
    fi
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] helm already installed" | tee -a "$LOG_FILE"
    fi
    return 0
  fi
  
  if [ "$VERBOSE" = "true" ]; then
    echo "helm not found. Installing helm..."
  fi
  if [ "$LOG_FILE" != "/dev/null" ]; then
    echo "[$(date)] helm not found, installing..." | tee -a "$LOG_FILE"
  fi
  
  # Download helm install script
  if ! download_with_retry "https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3" "get_helm.sh" "180" "3" "$LOG_FILE"; then
    return 1
  fi
  
  # Run helm install script
  if ! sudo bash get_helm.sh; then
    if [ "$LOG_FILE" != "/dev/null" ]; then
      echo "[$(date)] ERROR: helm installation script failed (exit code: $?)" | tee -a "$LOG_FILE"
      echo "ERROR: helm installation script failed" >&2
    else
      echo "ERROR: helm installation script failed" >&2
    fi
    sudo rm -f get_helm.sh
    return 1
  fi
  
  sudo rm -f get_helm.sh
  
  # Verify installation
  local VERSION_OUTPUT
  if helm version --short > /dev/null 2>&1; then
    VERSION_OUTPUT=$(helm version --short 2>/dev/null || echo "version check failed")
  else
    VERSION_OUTPUT=$(helm version 2>/dev/null | head -1 || echo "version check failed")
  fi
  
  if [ "$VERBOSE" = "true" ]; then
    echo "helm installed: $VERSION_OUTPUT"
  fi
  if [ "$LOG_FILE" != "/dev/null" ]; then
    echo "[$(date)] helm installed successfully" | tee -a "$LOG_FILE"
  fi
  
  return 0
}

# If script is executed directly, run the fix
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  fix_and_verify_network "/dev/null" "true" "true"
fi
