# cloudflare-ddns


🌐 **Languages**: [English](README.md) | [中文說明](README.zh-TW.md)


A simple Cloudflare DDNS script with multi-service support.


This script updates Cloudflare DNS records automatically when your public IP

changes. It supports IPv4 (A) and optional IPv6 (AAAA), and is designed to be

reusable across multiple services using separate `.env` configuration files.


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


## Quick Start


```bash

cp ddns.env.example ddns.env

nano ddns.env

env -i ./cloudflare-ddns.sh ./ddns.env

