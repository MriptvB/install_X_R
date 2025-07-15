#!/usr/bin/env bash
# install_xray_reality.sh
# Fully automated installer and configurator for Xray VLESS+XHTTP+REALITY on Linux (Debian/Ubuntu/CentOS)
# Usage: sudo bash install_xray_reality.sh -p <PORT> -P <PATH> -H <HOST> -d <DEST> -s <SERVER_NAMES>

set -euo pipefail

# Default parameters
default_port=8080
default_path="/cdn-cgi/login"
default_host="www.google.com"
default_dest="example.com:443"
default_servers="example.com,www.example.com"

env_help() {
  cat <<EOF
Usage: sudo bash install_xray_reality.sh [options]

Options:
  -p PORT             Listening port on this server (default: $default_port)
  -P PATH             XHTTP path (default: $default_path)
  -H HOST             XHTTP Host header (default: $default_host)
  -d DEST             Reality dest (domain:port, default: $default_dest)
  -s SERVERS          Comma-separated Reality serverNames (default: $default_servers)
  -h                  Show this help message

Example:
  sudo bash install_xray_reality.sh \
    -p 8080 \
    -P /cdn-cgi/login \
    -H www.google.com \
    -d node.example.com:443 \
    -s node.example.com,www.node.example.com
EOF
}

# Parse flags
port="$default_port"
path="$default_path"
host="$default_host"
dest="$default_dest"
servers="$default_servers"
while getopts ":p:P:H:d:s:h" opt; do
  case $opt in
    p) port="$OPTARG" ;; 
    P) path="$OPTARG" ;; 
    H) host="$OPTARG" ;; 
    d) dest="$OPTARG" ;; 
    s) servers="$OPTARG" ;; 
    h) env_help; exit 0 ;; 
    *) env_help; exit 1 ;; 
  esac
done

# Ensure running as root
if [[ $EUID -ne 0 ]]; then
  echo "Error: This script must be run as root." >&2
  exit 1
fi

echo "\n=== Installing Xray-core ==="
# 1. Install Xray using official installer
bash <(curl -Ls https://github.com/XTLS/Xray-install/raw/main/install-release.sh)

# 2. Generate Reality keys
echo "\n=== Generating X25519 key pair ==="
read -r private_key public_key < <(xray x25519 | awk -F": " '/Private key/{pk=$2}/Public key/{print pk, $2}')

# 3. Generate valid shortId (16 random bytes → base64-url without padding)
echo "Generating short ID..."
short_id=$(head -c16 /dev/urandom | base64 | tr '+/' '-_' | tr -d '=')

# 4. Build configuration JSON
echo "\n=== Writing config to /usr/local/etc/xray/config.json ==="
config_dir="/usr/local/etc/xray"
config_file="$config_dir/config.json"
mkdir -p "$config_dir"

# Prepare serverNames array
IFS=',' read -r -a srv_array <<< "$servers"
json_servers=""
for name in "${srv_array[@]}"; do
  json_servers+="\"$name\"," 
  done
# strip trailing comma and space
json_servers="${json_servers%, }"

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

# 5. Configure permissions and restart service
echo "Setting permissions and restarting Xray..."
chown -R nobody:nogroup "$config_dir"
chmod 600 "$config_file"
systemctl enable xray
systemctl restart xray

# 6. Output summary, JSON snippet and text summary
echo "\n=== Setup Complete ==="
echo "Private Key: $private_key"
echo "Public Key : $public_key"
echo "Short ID    : $short_id"
echo "Port        : $port"

# Print JSON snippet for Marzneshin panel
echo "\n=== JSON Snippet for Marzneshin Inbound (copy-paste) ==="
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

# Detailed text summary
cat <<EOF

=== Connection Details ===
- Connect to Server: <IRAN_SERVER_IP_OR_DOMAIN>
- Port    : $port
- Protocol: VLESS+XHTTP+REALITY

Stream Settings:
- XHTTP Path   : $path
- XHTTP Host   : $host

Reality Settings:
- dest           : $dest
- serverNames    : ${servers//,/ , }
- privateKey     : $private_key
- publicKey      : $public_key
- shortIds       : $short_id
- spiderX        : /
- fingerprint    : chrome

In Marzneshin panel, add a new inbound with these values and add your UUID clients under "clients" array. After saving, restart the node.
EOF
