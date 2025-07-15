#!/usr/bin/env bash
# install_xray_reality.sh
# Fully automated interactive installer for Xray VLESS+XHTTP+REALITY on Linux

set -euo pipefail

# Default parameters (optimized for Iranian users)
default_port=8080          # Port clients connect to on the Iran bridge server
default_path="/"          # HTTP path to mimic typical web requests (root path is generic)
default_host="www.aparat.com"   # Host header for XHTTP, using a popular local site for obfuscation

default_dest="example.com:443"  # Upstream Reality server address (external node)
default_servers="www.aparat.com,aparat.com,filimo.com,filimo.net"  # SNI names for TLS handshake

# Interactive introduction
cat << 'EOF'

====================================================
    Xray Reality Bridge Setup (Interactive Mode)
====================================================
This script will configure an Xray VLESS+XHTTP+REALITY bridge on this server.

Default settings:
  Port         : $default_port    # Listening port
  XHTTP Path   : $default_path    # HTTP path for obfuscation
  XHTTP Host   : $default_host    # Host header for HTTP disguise
  Reality Dest : $default_dest    # External Reality node address
  ServerNames  : $default_servers # SNI domains for TLS handshake

Press Enter to accept a default value at each prompt.
EOF

# Prompt for Port
echo -e "\n-- Port --"
echo "The port on which Xray will listen for incoming client connections."
read -rp "Enter Port [${default_port}]: " port_input
port=${port_input:-$default_port}

# Prompt for XHTTP Path
echo -e "\n-- XHTTP Path --"
echo "HTTP path used to disguise proxy traffic (e.g., '/', '/cdn-cgi/login')."
read -rp "Enter XHTTP Path [${default_path}]: " path_input
path=${path_input:-$default_path}

# Prompt for XHTTP Host
echo -e "\n-- XHTTP Host --"
echo "Host header to use in HTTP requests for obfuscation (e.g., 'www.aparat.com')."
read -rp "Enter XHTTP Host [${default_host}]: " host_input
host=${host_input:-$default_host}

# Prompt for Reality Dest
echo -e "\n-- Reality Dest --"
echo "External Reality server address in 'domain:port' form (upstream node)."
read -rp "Enter Reality Dest [${default_dest}]: " dest_input
dest=${dest_input:-$default_dest}

# Prompt for ServerNames
echo -e "\n-- Reality ServerNames --"
echo "Comma-separated SNI names used in TLS handshake (e.g., popular domains)."
read -rp "Enter Reality ServerNames [${default_servers}]: " srv_input
servers=${srv_input:-$default_servers}

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

# 1. Install Xray
echo -e "\n=== Installing Xray-core ==="
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# 2. Generate X25519 key pair
echo -e "\n=== Generating X25519 Key Pair ==="
read -r private_key public_key < <(xray x25519 | awk -F": " '/Private key/{pk=$2}/Public key/{print pk, $2}')

# 3. Generate shortId
echo -e "\n=== Generating Short ID ==="
short_id=$(head -c16 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')

# Prepare JSON array for ServerNames
IFS=',' read -r -a srv_array <<< "$servers"
json_servers=""
for name in "${srv_array[@]}"; do
  json_servers+="\"$name\"," 
  done
json_servers="${json_servers%, }"

# 4. Build Xray config
echo -e "\n=== Writing Config to /usr/local/etc/xray/config.json ==="
config_dir="/usr/local/etc/xray"
config_file="$config_dir/config.json"
mkdir -p "$config_dir"
cat > "$config_file" <<EOF
{
  "log": { "loglevel": "warning" },
  "inbounds": [
    {
      "tag": "VLESS+XHTTP+REALITY+\$port",
      "listen": "0.0.0.0",
      "port": \$port,
      "protocol": "vless",
      "settings": { "clients": [], "decryption": "none" },
      "streamSettings": {
        "network": "xhttp",
        "security": "reality",
        "xhttpSettings": {
          "path": "\$path",
          "host": "\$host",
          "headers": {},
          "noSSEHeader": false,
          "xPaddingBytes": "100-1000",
          "mode": "auto"
        },
        "realitySettings": {
          "show": false,
          "dest": "\$dest",
          "xver": 0,
          "serverNames": [ \$json_servers ],
          "privateKey": "\$private_key",
          "publicKey": "\$public_key",
          "shortIds": ["\$short_id"],
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

# 5. Set permissions and restart
echo -e "\n=== Applying Permissions & Restarting Xray ==="
chown -R nobody:nogroup "$config_dir"
chmod 600 "$config_file"
systemctl enable xray
systemctl restart xray

# 6. Output results and snippets
echo -e "\n=== Setup Complete ==="
echo "Private Key: \$private_key"
echo "Public Key : \$public_key"
echo "Short ID    : \$short_id"
echo "Port        : \$port"

echo -e "\n=== JSON Snippet for Marzneshin Inbound ==="
cat <<EOF
{
  "tag": "VLESS+XHTTP+REALITY+\$port",
  "listen": "0.0.0.0",
  "port": \$port,
  "protocol": "vless",
  "settings": { "clients": [], "decryption": "none" },
  "streamSettings": {
    "network": "xhttp", "security": "reality",
    "xhttpSettings": { "path": "\$path", "host": "\$host", "headers": {}, "noSSEHeader": false, "xPaddingBytes": "100-1000", "mode": "auto" },
    "realitySettings": {
      "dest": "\$dest",
      "serverNames": [ \$json_servers ],
      "privateKey": "\$private_key",
      "publicKey": "\$public_key",
      "shortIds": ["\$short_id"],
      "spiderX": "/",
      "fingerprint": "chrome"
    }
  }
}
EOF

# Detailed connection summary
echo -e "\n=== Client Connection Details ==="
echo "Server Address    : <IRAN_SERVER_IP_OR_DOMAIN>"
echo "Port              : \$port"
echo "Protocol          : VLESS+XHTTP+REALITY"
echo "XHTTP Path        : \$path"
echo "XHTTP Host        : \$host"
echo "Reality Dest      : \$dest"
echo "Reality ServerNames: \$servers"
echo "Private Key       : \$private_key"
echo "Public Key        : \$public_key"
echo "Short ID          : \$short_id"
echo "spiderX           : /"
echo "fingerprint       : chrome"
