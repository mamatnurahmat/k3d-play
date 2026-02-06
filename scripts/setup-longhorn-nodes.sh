#!/bin/bash

# Get list of k3d node containers for the current cluster
CLUSTER_NAME="k3d-gateway-demo" # Derived from config
NODES=$(docker ps --format '{{.Names}}' | grep "$CLUSTER_NAME-*")

if [ -z "$NODES" ]; then
  echo "No nodes found for cluster $CLUSTER_NAME"
  exit 1
fi

echo "Found nodes: $NODES"

for NODE in $NODES; do
  echo "------------------------------------------------"
  echo "Configuring node: $NODE"
  
  # Check for apk (Alpine/K3s default)
  if docker exec "$NODE" which apk > /dev/null 2>&1; then
    echo "Detected APK package manager"
    docker exec "$NODE" apk update
    docker exec "$NODE" apk add open-iscsi nfs-common multipath-tools
    docker exec "$NODE" rc-update add iscsid
    docker exec "$NODE" service iscsid start
    continue
  fi

  # Check for apt-get (Debian/Ubuntu)
  if docker exec "$NODE" which apt-get > /dev/null 2>&1; then
    echo "Detected APT package manager"
    docker exec "$NODE" apt-get update
    docker exec "$NODE" apt-get install -y open-iscsi nfs-common
    docker exec "$NODE" systemctl enable iscsid
    docker exec "$NODE" systemctl start iscsid
    continue
  fi
  
  # Check for microdnf/yum (RHEL/CentOS/Fedora)
  if docker exec "$NODE" which microdnf > /dev/null 2>&1; then
    echo "Detected MicroDNF package manager"
    docker exec "$NODE" microdnf install -y iscsi-initiator-utils nfs-utils
    docker exec "$NODE" systemctl enable iscsid
    docker exec "$NODE" systemctl start iscsid
    continue
  elif docker exec "$NODE" which yum > /dev/null 2>&1; then
    echo "Detected YUM package manager"
    docker exec "$NODE" yum install -y iscsi-initiator-utils nfs-utils
    docker exec "$NODE" systemctl enable iscsid
    docker exec "$NODE" systemctl start iscsid
    continue
  fi

  echo "ERROR: Could not detect package manager (apk, apt, yum, microdnf) on node $NODE"
  echo "Manual installation of open-iscsi and nfs-common is required."
done

echo "------------------------------------------------"
echo "Node setup checks completed."
