#!/usr/bin/env bash
# install_xray_reality.sh
# اسکریپت تعاملی خودکار برای نصب Xray VLESS+XHTTP+REALITY روی لینوکس

set -euo pipefail

# پارامترهای پیش‌فرض (بهینه‌سازی شده برای کاربران ایرانی)
default_port=8080          # پورتی که کاربران به آن متصل می‌شوند
default_path="/"          # مسیر HTTP برای مخفی‌سازی ترافیک (مسیر ریشه عمومی است)
default_host="www.aparat.com"   # هدر Host برای XHTTP، با استفاده از سایت محبوب ایرانی

default_dest="example.com:443"  # آدرس نود خارجی Reality (مقصد ارسال ترافیک)
default_servers="www.aparat.com,aparat.com,filimo.com,filimo.net"  # نام‌های SNI برای TLS handshake

# مقدمه تعامل
cat << 'EOF'

=== راه‌اندازی پل Xray Reality ===
این اسکریپت یک پل Xray Reality با تنظیمات استتار برای سرور ایران پیکربندی می‌کند.

مقادیر پیش‌فرض:
  Port         : $default_port    # پورتی که Xray روی آن گوش می‌دهد
  XHTTP Path   : $default_path    # مسیر HTTP که کلاینت‌ها درخواست می‌کنند
  XHTTP Host   : $default_host    # هدر Host در درخواست‌های HTTP برای مخفی‌سازی
  Reality Dest : $default_dest    # آدرس نود خارجی که ترافیک به آن هدایت می‌شود
  ServerNames  : $default_servers # نام‌های SNI در TLS handshake

برای قبول مقدار پیش‌فرض هر مرحله، دکمه Enter را بزنید.

EOF

# دریافت ورودی‌ها
# پرسش برای پورت
echo "-- پورت --"
echo "پورت ورودی برای اتصال کلاینت‌ها (مثلاً 8080)"
read -rp "وارد کنید [${default_port}]: " port_input
port=${port_input:-$default_port}

# پرسش برای مسیر XHTTP
echo -e "\n-- مسیر XHTTP (Path) --"
echo "این مسیر در URL برای مخفی‌سازی ترافیک استفاده می‌شود (مثلاً '/' یا '/cdn-cgi/login')"
read -rp "وارد کنید [${default_path}]: " path_input
path=${path_input:-$default_path}

# پرسش برای هدر Host
echo -e "\n-- هدر Host --"
echo "مقدار هدر Host برای درخواست‌های HTTP (مثلاً 'www.aparat.com')"
read -rp "وارد کنید [${default_host}]: " host_input
host=${host_input:-$default_host}

# پرسش برای Reality Dest
echo -e "\n-- آدرس نود خارجی (Reality Dest) --"
echo "آدرس نود خارجی به صورت domain:port که ترافیک به آن ارسال می‌شود"
read -rp "وارد کنید [${default_dest}]: " dest_input
dest=${dest_input:-$default_dest}

# پرسش برای ServerNames
echo -e "\n-- نام‌های SNI (ServerNames) --"
echo "فهرست دامنه‌های رایج برای handshake در TLS (مثلاً aparat.com, filimo.com)"
read -rp "وارد کنید [${default_servers}]: " srv_input
servers=${srv_input:-$default_servers}

# بررسی روت بودن کاربر
if [[ $EUID -ne 0 ]]; then
  echo "خطا: برای اجرا باید کاربر root باشید." >&2
  exit 1
fi

# نصب Xray
echo -e "\n=== نصب Xray-core ==="
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# تولید کلیدها
echo -e "\n=== تولید جفت کلید X25519 ==="
read -r private_key public_key < <(xray x25519 | awk -F": " '/Private key/{pk=$2}/Public key/{print pk, $2}')

# تولید shortId
echo -e "\n=== تولید Short ID ==="
short_id=$(head -c16 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')

# آماده‌سازی آرایه JSON برای ServerNames
IFS=',' read -r -a srv_array <<< "$servers"
json_servers=""
for name in "${srv_array[@]}"; do
  json_servers+="\"$name\"," 
done
json_servers="${json_servers%, }"

# نوشتن فایل کانفیگ
echo -e "\n=== نوشتن config.json ==="
config_dir="/usr/local/etc/xray"
config_file="$config_dir/config.json"
mkdir -p "$config_dir"
cat > "$config_file" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "VLESS+XHTTP+REALITY+$port",
      "listen": "0.0.0.0",
      "port": $port,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "$path",
          "host": "$host",
          "headers": {},
          "noSSEHeader": false,
          "xPaddingBytes": "100-1000",
          "mode": "auto"
        },
        "realitySettings": {
          "show": false,
          "dest": "$dest",
          "xver": 0,
          "serverNames": [ $json_servers ],
          "privateKey": "$private_key",
          "publicKey": "$public_key",
          "shortIds": ["$short_id"],
          "spiderX": "/",
          "fingerprint": "chrome"
        }
      }
    }
  ],
  "outbounds": [
    { "protocol": "freedom", "tag": "direct" },
    { "protocol": "blackhole", "tag": "block" }
  ]
}
EOF

# تنظیم مجوزها و راه‌اندازی مجدد
echo -e "\n=== اعمال مجوزها و راه‌اندازی Xray ==="
chown -R nobody:nogroup "$config_dir"
chmod 600 "$config_file"
systemctl enable xray
systemctl restart xray

# نمایش نتایج
echo -e "\n=== تنظیمات انجام شد ==="
echo "کلید خصوصی   : $private_key"
echo "کلید عمومی   : $public_key"
echo "Short ID      : $short_id"
echo "پورت          : $port"

echo -e "\n=== JSON برای پنل مرزنشین (کپی کنید) ==="
cat <<EOF
{
  "tag": "VLESS+XHTTP+REALITY+$port",
  "listen": "0.0.0.0",
  "port": $port,
  "protocol": "vless",
  "settings": { "clients": [], "decryption": "none" },
  "streamSettings": {
    "network": "xhttp", "security": "reality",
    "xhttpSettings": { "path": "$path", "host": "$host", "headers": {}, "noSSEHeader": false, "xPaddingBytes": "100-1000", "mode": "auto" },
    "realitySettings": {
      "dest": "$dest",
      "serverNames": [ $json_servers ],
      "privateKey": "$private_key",
      "publicKey": "$public_key",
      "shortIds": ["$short_id"],
      "spiderX": "/",
      "fingerprint": "chrome"
    }
  }
}
EOF

# خلاصه متنی برای مدیر
echo -e "\n=== جزئیات اتصال برای کلاینت ==="
echo "آدرس سرور     : <آی‌پی یا دامنه سرور ایران>"
echo "پورت          : $port"
echo "پروتکل        : VLESS+XHTTP+REALITY"
echo "مسیر          : $path"
echo "هدر Host      : $host"
echo "مقصد خارجی   : $dest"
echo "SNI Names     : $servers"
echo "کلید خصوصی    : $private_key"
echo "کلید عمومی    : $public_key"
echo "Short ID       : $short_id"
echo "Fingerprint    : chrome"
echo "SpiderX        : /"

echo -e "\nدر پنل مرزنشین، JSON بالا را در یک inbound جدید قرار دهید و UUIDهای کاربران را در قسمت \"clients\" اضافه کنید."
