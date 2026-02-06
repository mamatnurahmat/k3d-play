# WAF Implementation dengan OWASP ModSecurity + CrowdSec

Dokumentasi implementasi Web Application Firewall (WAF) menggunakan ModSecurity dengan OWASP Core Rule Set (CRS) dan CrowdSec untuk IP-based anomaly detection.

## Arsitektur

```
┌─────────────┐     ┌────────────────┐     ┌─────────────────────────────────────────┐     ┌────────────────┐
│   Client    │────▶│  nginx-gateway │────▶│  waf-app001 Pod                         │────▶│  app001        │
│             │     │  (port 30000)  │     │  ┌─────────────┐  ┌──────────────────┐  │     │  (backend)     │
└─────────────┘     └────────────────┘     │  │ ModSecurity │  │ CrowdSec Agent   │  │     └────────────────┘
                                           │  │ (WAF rules) │  │ (log parser)     │  │
                                           │  └──────┬──────┘  └────────┬─────────┘  │
                                           └─────────┼──────────────────┼────────────┘
                                                     │                  │
                                                     ▼                  ▼
                                           ┌─────────────────────────────────────────┐
                                           │  CrowdSec LAPI (Decision Engine)       │
                                           │  - IP blocklist management             │
                                           │  - Threat intelligence                 │
                                           └─────────────────────────────────────────┘
```

## Komponen

| Komponen | Fungsi |
|----------|--------|
| ModSecurity | WAF dengan OWASP CRS rules |
| CrowdSec Agent | Parse logs, detect anomali |
| CrowdSec LAPI | Central decision API |

## Instalasi

### Quick Setup (Recommended)

```bash
chmod +x scripts/setup-crowdsec.sh
./scripts/setup-crowdsec.sh
```

### Manual Setup

#### 1. Deploy CrowdSec LAPI

```bash
kubectl apply -f manifests/waf/crowdsec-config.yaml
kubectl apply -f manifests/waf/crowdsec-lapi.yaml
kubectl wait --for=condition=ready pod -l app=crowdsec-lapi --timeout=120s
```

#### 2. Register Agent & Bouncer

```bash
# Get LAPI pod
LAPI_POD=$(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}')

# Register agent
kubectl exec $LAPI_POD -- cscli machines add waf-app001-agent --password "your-password"

# Create bouncer key
BOUNCER_KEY=$(kubectl exec $LAPI_POD -- cscli bouncers add waf-app001-bouncer -o raw)

# Create secrets
kubectl create secret generic crowdsec-agent-credentials --from-literal=password="your-password"
kubectl create secret generic crowdsec-bouncer-key --from-literal=api-key="$BOUNCER_KEY"
```

#### 3. Deploy WAF

```bash
kubectl apply -f manifests/waf/waf-deployments.yaml
kubectl apply -f manifests/routes/
```

## Verifikasi

```bash
# Check pods (harus ada 2 containers: modsecurity + crowdsec-agent)
kubectl get pods -l app=waf-app001

# Check agent registered
kubectl exec -it $(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}') -- cscli machines list

# Check CrowdSec logs
kubectl logs -l app=waf-app001 -c crowdsec-agent --tail=10
```

## Testing

### Test SQL Injection (ModSecurity block)

```bash
kubectl run test-sqli --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" "http://waf-app001/?id=1'%20OR%20'1'='1"
# Expected: 403
```

### Test Normal Traffic

```bash
kubectl run test-normal --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" "http://waf-app001/"
# Expected: 200
```

### Check CrowdSec Decisions

```bash
kubectl exec -it $(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}') -- cscli decisions list
```

### Manual Ban IP (Testing)

```bash
kubectl exec -it $(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}') -- \
  cscli decisions add --ip 10.42.0.100 --duration 1h --reason "manual test ban"
```

## Skenario Testing - Trigger Auto Block

CrowdSec akan auto-ban IP jika terdeteksi serangan berulang. Berikut skenario testing:

### Skenario 1: SQL Injection Bruteforce

```bash
# Dari terminal lokal - jalankan 20x SQL injection attack
for i in {1..20}; do
  curl -s "http://app001.localhost/?id=1'%20OR%20'1'='1" -o /dev/null
  curl -s "http://app001.localhost/?user=admin'--" -o /dev/null
  echo "Attack attempt $i"
done

# Cek apakah IP sudah di-ban
kubectl exec -it $(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}') -- cscli decisions list
```

### Skenario 2: Path Traversal Attack

```bash
# Jalankan 15x path traversal
for i in {1..15}; do
  curl -s "http://app001.localhost/../../../etc/passwd" -o /dev/null
  curl -s "http://app001.localhost/..%2f..%2f..%2fetc%2fpasswd" -o /dev/null
done
```

### Skenario 3: XSS Attack

```bash
# Jalankan 15x XSS attack
for i in {1..15}; do
  curl -s "http://app001.localhost/?q=<script>alert(1)</script>" -o /dev/null
  curl -s "http://app001.localhost/?name=<img%20src=x%20onerror=alert(1)>" -o /dev/null
done
```

### Skenario 4: Sensitive File Probe

```bash
# Probe file sensitif
for i in {1..10}; do
  curl -s "http://app001.localhost/.env" -o /dev/null
  curl -s "http://app001.localhost/.git/config" -o /dev/null
  curl -s "http://app001.localhost/wp-config.php" -o /dev/null
  curl -s "http://app001.localhost/.htaccess" -o /dev/null
done
```

### Verifikasi IP Terblokir

```bash
# Lihat decisions aktif
LAPI_POD=$(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}')
kubectl exec -it $LAPI_POD -- cscli decisions list

# Output akan menampilkan IP yang di-ban:
# ╭───────┬──────────┬────────────────┬─────────────────┬────────┬─────────┬───────────────────────────────────╮
# │  ID   │  Source  │  IP/Scope      │     Reason      │ Action │ Country │            Expiration             │
# ├───────┼──────────┼────────────────┼─────────────────┼────────┼─────────┼───────────────────────────────────┤
# │ 12345 │ crowdsec │ 192.168.1.100  │ http-sqli-prob..│  ban   │   ID    │ 3h59m45s                          │
# ╰───────┴──────────┴────────────────┴─────────────────┴────────┴─────────┴───────────────────────────────────╯
```

## Unblock IP (Remove Ban)

### Cara 1: Unblock IP Spesifik

```bash
LAPI_POD=$(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}')

# Lihat daftar IP yang di-ban
kubectl exec -it $LAPI_POD -- cscli decisions list

# Unblock berdasarkan IP
kubectl exec -it $LAPI_POD -- cscli decisions delete --ip 192.168.1.100

# Verifikasi
kubectl exec -it $LAPI_POD -- cscli decisions list
```

### Cara 2: Unblock Berdasarkan Decision ID

```bash
# Lihat decision ID dari list
kubectl exec -it $LAPI_POD -- cscli decisions list

# Delete berdasarkan ID
kubectl exec -it $LAPI_POD -- cscli decisions delete --id 12345
```

### Cara 3: Unblock Semua IP

```bash
# HATI-HATI: Ini akan menghapus SEMUA decisions
kubectl exec -it $LAPI_POD -- cscli decisions delete --all
```

### Cara 4: Whitelist IP Permanen

Untuk whitelist IP secara permanen (tidak akan pernah di-ban):

```bash
# Tambah whitelist
kubectl exec -it $LAPI_POD -- cscli parsers install crowdsecurity/whitelists

# Edit whitelist file di dalam container
kubectl exec -it $LAPI_POD -- sh -c 'cat >> /etc/crowdsec/parsers/s02-enrich/mywhitelists.yaml << EOF
name: my-whitelist
description: "Whitelisted IPs"
whitelist:
  reason: "trusted network"
  ip:
    - "192.168.1.100"
    - "10.0.0.0/8"
EOF'

# Reload CrowdSec
kubectl exec -it $LAPI_POD -- kill -HUP 1
```

## Konfigurasi

### ModSecurity

| Variable | Default | Deskripsi |
|----------|---------|-----------|
| PARANOIA | 1 | Level sensitivitas (1-4) |
| ANOMALY_INBOUND | 5 | Threshold inbound |
| ANOMALY_OUTBOUND | 4 | Threshold outbound |

### CrowdSec

| Variable | Deskripsi |
|----------|-----------|
| COLLECTIONS | Collections to install |
| LOCAL_API_URL | LAPI endpoint |
| DISABLE_LOCAL_API | Agent-only mode |

## File Struktur

```
manifests/
├── waf/
│   ├── waf-deployments.yaml    # WAF + CrowdSec agent
│   ├── crowdsec-lapi.yaml      # CrowdSec LAPI
│   └── crowdsec-config.yaml    # ConfigMaps
└── routes/
    └── app001-route.yaml       # Route via WAF

scripts/
└── setup-crowdsec.sh           # Setup automation
```

## Troubleshooting

### Agent tidak connect ke LAPI

```bash
# Check LAPI service
kubectl get svc crowdsec-lapi

# Test connectivity
kubectl exec -it $(kubectl get pod -l app=waf-app001 -o jsonpath='{.items[0].metadata.name}') -c crowdsec-agent -- \
  curl -s http://crowdsec-lapi:8080/health
```

### Decisions tidak muncul

```bash
# Check agent parsing logs
kubectl logs -l app=waf-app001 -c crowdsec-agent --tail=50 | grep -i "parsed"

# Check acquis.yaml
kubectl exec -it $(kubectl get pod -l app=waf-app001 -o jsonpath='{.items[0].metadata.name}') -c crowdsec-agent -- \
  cat /etc/crowdsec/acquis.yaml
```

## Referensi

- [OWASP ModSecurity CRS](https://coreruleset.org/)
- [CrowdSec Documentation](https://docs.crowdsec.net/)
- [CrowdSec Kubernetes](https://docs.crowdsec.net/docs/getting_started/install_crowdsec_kubernetes)
