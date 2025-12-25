# cloudflare-ddns

🌐 **Languages**: [English](README.md) | [中文說明](README.zh-TW.md)

A simple Cloudflare DDNS script with multi-service support.

This script automatically updates Cloudflare DNS records when your public IP
address changes. It supports IPv4 (A) and optional IPv6 (AAAA), and is designed
to be reusable across multiple services using separate `.env` configuration
files.

---

## Features
- IPv4 (A) and IPv6 (AAAA) support
- Multi-service support (one script, multiple configs)
- Safe for cron (works in clean environments)
- Automatic dependency check (curl, jq)
- Uses Cloudflare API Token (recommended over Global API Key)

---

## Requirements
- Ubuntu / Debian
- bash
- root privileges (for cron and optional dependency installation)

---

## Files
- `cloudflare-ddns.sh` : Main script
- `ddns.env.example`   : Example configuration file
- `.gitignore`         : Prevents committing secrets
- `README.md`          : English documentation
- `README.zh-TW.md`    : Traditional Chinese documentation

---

## Quick Start

### 1. Copy example config
```bash
cp ddns.env.example ddns.env
```

### 2. Edit config
```bash
nano ddns.env
```

---

### 3. Manual test (recommended)
Run in a clean environment to simulate cron:
```bash
env -i ./cloudflare-ddns.sh ./ddns.env
```

Possible outputs:
- No change: IP has not changed, no update required
- Updated: DNS record updated successfully

---

## Cloudflare API Token Setup
Recommended API Token permissions:
- Permissions: `Zone → DNS → Edit`
- Zone Resources: Limit to the specific Zone (domain)

---

## Cron Example (Optional)
Run every 5 minutes and write logs to `/var/log`:
```bash
*/5 * * * * /root/cloudflare-ddns.sh /path/to/ddns.env >> /var/log/cloudflare-ddns.log 2>&1
```

---

## View Logs
```bash
tail -n 50 /var/log/cloudflare-ddns.log
tail -f /var/log/cloudflare-ddns.log
```

---

## Notes
- Do NOT commit real `.env` files to GitHub
- Use a separate `.env` file for each service
- `DEFAULT_PROXIED=true/false` only affects newly created DNS records;
  existing records will keep their current Cloudflare settings

---

## License
MIT License

