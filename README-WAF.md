# WAF Implementation dengan OWASP ModSecurity

Dokumentasi implementasi Web Application Firewall (WAF) menggunakan ModSecurity dengan OWASP Core Rule Set (CRS) untuk k3d-demo cluster.

## Arsitektur

```
┌─────────────┐      ┌────────────────────┐      ┌─────────────────┐      ┌─────────────────┐
│   Client    │─────▶│  nginx-gateway     │─────▶│  WAF Proxy      │─────▶│  Backend App    │
│             │      │  (port 30000)      │      │  (ModSecurity)  │      │                 │
└─────────────┘      └────────────────────┘      └─────────────────┘      └─────────────────┘
```

## Domain yang Dilindungi

| Domain | WAF Service | Backend |
|--------|-------------|---------|
| app001.localhost | waf-app001 | app001:80 |
| argocd.localhost | waf-argocd | argocd-server:80 |
| rancher.localhost | waf-rancher | rancher:80 |

## Instalasi

### 1. Deploy WAF

```bash
kubectl apply -f manifests/waf/
```

### 2. Deploy Aplikasi (jika belum)

```bash
kubectl apply -f manifests/workloads/app001.yaml
```

### 3. Update Routes

```bash
kubectl apply -f manifests/routes/
```

### 4. Verifikasi

```bash
# Cek pods
kubectl get pods -l app=waf-app001
kubectl get pods -l app=waf-argocd

# Cek logs - harus ada "844 rules loaded"
kubectl logs -l app=waf-app001 --tail=5
```

## Testing

### Test SQL Injection (harus di-block)

```bash
kubectl run test-sqli --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" "http://waf-app001/?id=1'%20OR%20'1'='1"
# Expected: 403
```

### Test Normal Traffic (harus pass)

```bash
kubectl run test-normal --image=curlimages/curl --rm -it --restart=Never -- \
  curl -s -o /dev/null -w "%{http_code}" "http://waf-app001/"
# Expected: 200
```

## OWASP Rules yang Aktif

| Rule ID Range | Kategori |
|---------------|----------|
| 913xxx | Scanner Detection |
| 921xxx | Protocol Enforcement |
| 930xxx | Local File Inclusion (LFI) |
| 931xxx | Remote File Inclusion (RFI) |
| 932xxx | Remote Code Execution (RCE) |
| 941xxx | Cross-Site Scripting (XSS) |
| 942xxx | SQL Injection |
| 943xxx | Session Fixation |

## Konfigurasi

Environment variables di deployment:

| Variable | Default | Deskripsi |
|----------|---------|-----------|
| PARANOIA | 1 | Level sensitivitas (1-4) |
| ANOMALY_INBOUND | 5 | Threshold inbound |
| ANOMALY_OUTBOUND | 4 | Threshold outbound |
| MODSEC_RULE_ENGINE | On | Enable/disable rules |

## Rollback

Untuk menonaktifkan WAF, kembalikan routes ke backend asli:

```bash
# Edit route
kubectl edit httproute app001-route

# Ubah:
#   backendRefs:
#   - name: waf-app001
#     port: 80
# Menjadi:
#   backendRefs:
#   - name: app001
#     port: 80
```

## File Struktur

```
manifests/
├── waf/
│   └── waf-deployments.yaml    # WAF deployments & services
└── routes/
    ├── app001-route.yaml       # Updated untuk WAF
    ├── argocd-route.yaml       # Updated untuk WAF
    └── rancher-route.yaml      # Updated untuk WAF
```

## Referensi

- [OWASP ModSecurity CRS](https://coreruleset.org/)
- [ModSecurity GitHub](https://github.com/SpiderLabs/ModSecurity)
