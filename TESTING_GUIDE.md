# CrowdSec WAF - Testing Guide

Dokumentasi ini berisi panduan langkah-demi-langkah untuk memverifikasi proteksi WAF dan CrowdSec.

## 1. Persiapan

Pastikan semua pod berjalan normal:
```bash
kubectl get pods -l app=waf-app001
# Expected: 2/2 Running

kubectl get pods -l app=crowdsec-lapi
# Expected: 1/1 Running
```

> **Catatan:** CrowdSec agent di cluster ini sudah dikonfigurasi untuk **MENONAKTIFKAN** whitelist private IP agar bisa ditest dari dalam cluster.

## 2. Skenario Attack

Kita akan mensimulasikan serangan dari pod lain di dalam cluster.

### Jalankan Serangan

Copy-paste perintah berikut ke terminal:

```bash
# Membuat pod attacker sementara yang melakukan 40x SQL Injection
kubectl run attack-simulation --image=curlimages/curl --rm -it --restart=Never -- sh -c '
  echo "🚀 Starting 40x SQL Injection Attack on waf-app001..."
  for i in $(seq 1 40); do
    # Kirim payload malicious
    curl -s "http://waf-app001/?id=$i%27%20UNION%20SELECT%20user,pass%20FROM%20users" -o /dev/null -w "."
  done
  echo "\n✅ Attack complete!"
'
```

**Hasil yang diharapkan:**
- 20-30 request pertama mungkin mendapat response `403 Forbidden` (diblock oleh ModSecurity WAF).
- Setelah threshold tercapai, IP attacker akan diban oleh CrowdSec.

### Skenario Attack via Domain (Local Host)

Jika Anda ingin melakukan testing langsung dari komputer host (bukan dari dalam pod) menggunakan domain `app001.localhost`.

**Prasyarat:**
- Domain `app001.localhost` harus sudah resolve ke IP ingress/gateway (biasanya `127.0.0.1` jika menggunakan k3d/Docker Desktop).
- Port ingress harus terbuka (contoh: port 80 atau 30000).

**Perintah Attack:**
```bash
# Lakukan attack loop
for i in $(seq 1 40); do
  curl -s "http://app001.localhost/?id=$i%27%20UNION%20SELECT%20user,pass%20FROM%20users" -o /dev/null -w "."
done
```

**Hasil:**
- Jika IP Host Anda (Gateway Gateway) belum di-whitelist, IP tersebut akan terkena ban.
- Akses normal via browser ke `http://app001.localhost` juga akan terblokir (Error 403 atau Connection Refused) setelah IP di-ban.

## 3. Verifikasi Ban

### Cek Active Decisions (Ban List)

```bash
# Dapatkan nama pod LAPI
LAPI_POD=$(kubectl get pod -l app=crowdsec-lapi -o jsonpath='{.items[0].metadata.name}')

# List decisions
kubectl exec -it $LAPI_POD -- cscli decisions list
```

**Contoh Output Berhasil:**
```
╭────┬──────────┬───────────────┬────────────────────────────┬────────┬─────────┬────┬────────┬────────────┬──────────╮
│ ID │  Source  │  Scope:Value  │           Reason           │ Action │ Country │ AS │ Events │ expiration │ Alert ID │
├────┼──────────┼───────────────┼────────────────────────────┼────────┼─────────┼────┼────────┼────────────┼──────────┤
│ 2  │ crowdsec │ Ip:10.42.1.12 │ crowdsecurity/http-probing │ ban    │         │    │ 11     │ 3h59m50s   │ 2        │
╰────┴──────────┴───────────────┴────────────────────────────┴────────┴─────────┴────┴────────┴────────────┴──────────╯
```
*Terlihat IP 10.42.1.12 diban selama 4 jam karena `http-probing`.*

## 4. Cara Unblock (PENTING)

Jika IP anda atau IP testing terblokir, gunakan cara ini untuk membuka blokir:

### Unblock IP Tertentu

```bash
# Ganti 10.42.1.12 dengan IP yang ingin di-unblock
kubectl exec -it $LAPI_POD -- cscli decisions delete --ip 10.42.1.12
```

### Unblock Semua (Reset)

```bash
kubectl exec -it $LAPI_POD -- cscli decisions delete --all
```

## 5. Troubleshooting

Jika testing tidak men-trigger ban:
1.  **Cek Logs Agent:**
    ```bash
    kubectl logs -l app=waf-app001 -c crowdsec-agent --tail=50
    ```
    *Pastikan "Lines parsed" bertambah saat attack terjadi.*

2.  **Verify Whitelist Disabled:**
    Pastikan parser whitelist tidak ada:
    ```bash
    kubectl exec -it $(kubectl get pod -l app=waf-app001 -o jsonpath='{.items[0].metadata.name}') -c crowdsec-agent -- cscli parsers list | grep whitelist
    ```
    *Jika `crowdsecurity/whitelists` masih ada, CrowdSec akan mengabaikan serangan dari private IP (local).*
