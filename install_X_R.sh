#!/usr/bin/env bash
# install_xray_reality.sh
# Fully automated interactive installer for Xray VLESS+XHTTP+REALITY on Linux

set -euo pipefail

# Default parameters (optimized for Iranian users)
default_port=8080
default_path="/"
default_host="www.aparat.com"
default_dest="example.com:443"
default_servers="www.aparat.com,aparat.com,filimo.com,filimo.net"

# Interactive introduction
cat <<EOF

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

# Prompt for user input
read -rp $'\n-- Port --\nThe port on which Xray will listen for incoming client connections.\nEnter Port ['$default_port']: ' port_input
port=${port_input:-$default_port}

read -rp $'\n-- XHTTP Path --\nHTTP path used to disguise proxy traffic (e.g., "/", "/cdn-cgi/login").\nEnter XHTTP Path ['$default_path']: ' path_input
path=${path_input:-$default_path}

read -rp $'\n-- XHTTP Host --\nHost header to use in HTTP requests for obfuscation (e.g., "www.aparat.com").\nEnter XHTTP Host ['$default_host']: ' host_input
host=${host_input:-$default_host}

read -rp $'\n-- Reality Dest --\nExternal Reality server address in "domain:port" form (upstream node).\nEnter Reality Dest ['$default_dest']: ' dest_input
dest=${dest_input:-$default_dest}

read -rp $'\n-- Reality ServerNames --\nComma-separated SNI names used in TLS handshake.\nEnter Reality ServerNames ['$default_servers']: ' srv_input
servers=${srv_input:-$default_servers}

# Check root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

# Install Xray
echo -e "\n=== Installing Xray-core ==="
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# Generate key pair
echo -e "\n=== Generating X25519 Key Pair ==="
read -r private_key public_key < <(xray x25519 | awk -F": " '/Private key/{pk=$2}/Public key/{print pk, $2}')

# Generate short ID
echo -e "\n=== Generating Short ID ==="
short_id=$(head -c16 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')

# Prepare JSON array
IFS=',' read -r -a srv_array <<< "$servers"
json_servers=""
for name in "${srv_array[@]}"; do
  json_servers+="\"$name\"," 
done
json_servers="${json_servers%,}"

# Write config file
echo -e "\n=== Writing Config to /usr/local/etc/xray/config.json ==="
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

# Set permissions and restart
echo -e "\n=== Applying Permissions & Restarting Xray ==="
chown -R nobody:nogroup "$config_dir"
chmod 600 "$config_file"
systemctl enable xray
systemctl restart xray

# Output details
cat <<EOF

=== Setup Complete ===
Private Key       : $private_key
Public Key        : $public_key
Short ID          : $short_id
Port              : $port

=== JSON Snippet for Marzneshin Inbound ===
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

=== Client Connection Details ===
Server Address    : <IRAN_SERVER_IP_OR_DOMAIN>
Port              : $port
Protocol          : VLESS+XHTTP+REALITY
XHTTP Path        : $path
XHTTP Host        : $host
Reality Dest      : $dest
Reality ServerNames: $servers
Private Key       : $private_key
Public Key        : $public_key
Short ID          : $short_id
spiderX           : /
fingerprint       : chrome
EOF
