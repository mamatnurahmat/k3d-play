#!/bin/bash
set -e

# Define the config file
CONFIG_FILE="k3d-config.yaml"

echo "🧹 Cleaning up k3d cluster defined in $CONFIG_FILE..."

# Check if k3d is installed
if ! command -v k3d &> /dev/null; then
    echo "❌ k3d could not be found. Please ensure it is installed."
    exit 1
fi

# Delete the cluster using the config file
k3d cluster delete --config "$CONFIG_FILE"

echo "✅ Cluster deleted successfully."
