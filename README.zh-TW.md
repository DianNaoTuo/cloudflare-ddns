# cloudflare-ddns（中文說明）


🌐 **語言**：[English](README.md) | [中文說明](README.zh-TW.md)


這是一支 Cloudflare 動態 DNS（DDNS）腳本，用來在你的對外 IP 位址變動時，

自動更新 Cloudflare DNS 紀錄。


此腳本支援多服務（同一支腳本搭配多份設定檔），

可選擇使用 IPv4（A）與 IPv6（AAAA）紀錄。


---


## 檔案說明

- `cloudflare-ddns.sh`：主腳本

- `ddns.env.example`：設定檔範例（請複製成自己的 `ddns.env`）

- `.gitignore`：避免把 `.env`（含 Token）推到 GitHub

- `README.md`：英文說明

- `README.zh-TW.md`：中文說明


---


## 快速開始


### 1️⃣ 複製設定檔範例

```bash

cp ddns.env.example ddns.env

```


### 2️⃣ 編輯設定檔

```bash

nano ddns.env

```


---


### 3️⃣ 手動測試（模擬 cron 的乾淨環境）

```bash

env -i ./cloudflare-ddns.sh ./ddns.env

```


可能看到的結果：

- IP 沒變：IP 沒有變化，無需更新

- IP 有變：正在更新 DNS 紀錄… 成功更新


---


## Cloudflare API Token 設定建議

建立 API Token 時建議設定：

- 權限：`Zone → DNS → Edit`

- Zone 資源：限制到指定的網域（Zone）


---


## cron 排程範例

```bash

*/5 * * * * /root/cloudflare-ddns.sh /path/to/ddns.env >> /var/log/cloudflare-ddns.log 2>&1

```


---


## 查看 log

```bash

tail -n 50 /var/log/cloudflare-ddns.log

tail -f /var/log/cloudflare-ddns.log

```


---


## 注意事項

- **請勿把真的 `.env` 檔案推上 GitHub**

- 建議每個服務使用獨立的 `.env`

- `DEFAULT_PROXIED` 只影響「新增紀錄」的橘雲預設值


---


## 授權

MIT License


