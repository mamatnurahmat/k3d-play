# Longhorn Setup on k3d

This guide details how to set up Longhorn distributed storage on a k3d cluster.

## Prerequisites

Longhorn requires `open-iscsi` and `nfs-common` (or `nfs-utils`) to be installed on the host nodes. Since k3d runs nodes as containers, these must be installed *inside* the node containers.

We have provided a script to automate this:
`scripts/setup-longhorn-nodes.sh`

## Installation Steps

1.  **Prepare Nodes**
    Run the setup script to install necessary dependencies on all k3d agents.
    ```bash
    chmod +x scripts/setup-longhorn-nodes.sh
    ./scripts/setup-longhorn-nodes.sh
    ```
    *Note: This must be re-run if you delete and recreate the cluster.*

2.  **Deploy via ArgoCD**
    Apply the Longhorn ArgoCD Application.
    ```bash
    kubectl apply -f gitops/core/longhorn-app.yaml
    ```
    
    This installs:
    - Longhorn from `https://charts.longhorn.io`
    - Configures components to run on nodes with `nodetype: front` or `nodetype: back`.
    - Enables `createDefaultDiskLabeledNodes: true`.

3.  **Verify Installation**
    Check if pods are running in `longhorn-system` namespace.
    ```bash
    kubectl get pods -n longhorn-system -w
    ```
    
    Access the UI by port-forwarding (or via Gateway if configured later):
    ```bash
    kubectl port-forward svc/longhorn-frontend -n longhorn-system 8080:80
    ```
    Access at `http://localhost:8080`.

## Troubleshooting

- **MountPropagation**: If pods fail with mount propagation errors, ensure your k3d cluster was created with proper mount propagation (default in recent k3d).
- **iSCSI missing**: If volumes fail to attach, verify `iscsid` is running on the node where the pod is scheduled.
  ```bash
  docker exec k3d-gateway-demo-agent-X service iscsid status
  ```
