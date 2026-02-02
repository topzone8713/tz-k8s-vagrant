#!/bin/bash

# Script to check if base.sh was executed and what tools are installed
# This helps debug why base.sh might not have run

echo "=========================================="
echo "Provision Check Script"
echo "=========================================="
echo ""

# Check if base.sh exists
if [ -f /vagrant/scripts/local/base.sh ]; then
    echo "✓ base.sh exists at /vagrant/scripts/local/base.sh"
else
    echo "✗ base.sh NOT FOUND at /vagrant/scripts/local/base.sh"
fi
echo ""

# Check if master.sh or node.sh exists
if [ -f /vagrant/scripts/local/master.sh ]; then
    echo "✓ master.sh exists"
    if grep -q "base.sh" /vagrant/scripts/local/master.sh; then
        echo "  → master.sh calls base.sh (line $(grep -n "base.sh" /vagrant/scripts/local/master.sh | cut -d: -f1))"
    else
        echo "  ✗ master.sh does NOT call base.sh"
    fi
fi

if [ -f /vagrant/scripts/local/node.sh ]; then
    echo "✓ node.sh exists"
    if grep -q "base.sh" /vagrant/scripts/local/node.sh; then
        echo "  → node.sh calls base.sh (line $(grep -n "base.sh" /vagrant/scripts/local/node.sh | cut -d: -f1))"
    else
        echo "  ✗ node.sh does NOT call base.sh"
    fi
fi
echo ""

# Check installed tools
echo "=========================================="
echo "Installed Tools Check"
echo "=========================================="

# Source common vagrant utilities for check_tool function
if [ -f /vagrant/scripts/local/common-vagrant.sh ]; then
    source /vagrant/scripts/local/common-vagrant.sh
fi

TOOLS=("kubectl" "helm" "docker" "ansible" "jq" "curl" "wget")
for tool in "${TOOLS[@]}"; do
    if [ -f /vagrant/scripts/local/common-vagrant.sh ]; then
        # Use common function if available
        TOOL_STATUS=$(check_tool "$tool")
        if [ $? -eq 0 ]; then
            VERSION=$(echo "$TOOL_STATUS" | cut -d':' -f2-)
            echo "✓ $tool: installed ($VERSION)"
        else
            echo "✗ $tool: NOT INSTALLED"
        fi
    else
        # Fallback to inline check
        if command -v "$tool" > /dev/null 2>&1; then
            VERSION=$($tool --version 2>/dev/null | head -1 || echo "version check failed")
            echo "✓ $tool: installed ($VERSION)"
        else
            echo "✗ $tool: NOT INSTALLED"
        fi
    fi
done
echo ""

# Check if base.sh was executed (look for markers)
echo "=========================================="
echo "base.sh Execution Markers"
echo "=========================================="

# Check for markers that base.sh should create
MARKERS=(
    "/home/topzone/.ssh"  # topzone user created
    "/srv/nfs"            # NFS directory created
    "/etc/exports"        # NFS exports file
)

for marker in "${MARKERS[@]}"; do
    if [ -e "$marker" ]; then
        echo "✓ Marker found: $marker"
    else
        echo "✗ Marker NOT found: $marker (base.sh may not have run)"
    fi
done
echo ""

# Check /etc/hosts for kube-master entry (base.sh adds this)
if grep -q "kube-master" /etc/hosts 2>/dev/null; then
    echo "✓ /etc/hosts contains kube-master entry (base.sh likely ran)"
else
    echo "✗ /etc/hosts does NOT contain kube-master entry (base.sh may not have run)"
fi
echo ""

# Check swap file (base.sh creates this)
if [ -f /swapfile ]; then
    echo "✓ /swapfile exists (base.sh likely ran)"
else
    echo "✗ /swapfile does NOT exist (base.sh may not have run)"
fi
echo ""

# Check if this is master or node
HOSTNAME=$(hostname)
echo "Current hostname: $HOSTNAME"
echo ""

# Check provision logs if available
if [ -f /var/log/vagrant-provision.log ]; then
    echo "=========================================="
    echo "Vagrant Provision Log (last 20 lines)"
    echo "=========================================="
    tail -20 /var/log/vagrant-provision.log
    echo ""
fi

echo "=========================================="
echo "Check Complete"
echo "=========================================="
