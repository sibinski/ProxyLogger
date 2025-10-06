#!/bin/bash

exec >> /tmp/proxy_postinstall.log 2>&1
echo "Postinstall started at $(date)"

# Set system proxy to redirect browser traffic to ProxyLogger
/usr/sbin/networksetup -setwebproxy "Wi-Fi" 127.0.0.1 8080
/usr/sbin/networksetup -setsecurewebproxy "Wi-Fi" 127.0.0.1 8080

# Load the LaunchAgent to start ProxyLogger

PLIST="/Library/LaunchDaemons/com.proxylogger.daemon.plist"
BINARY="/Applications/ProxyLogger.app/Contents/MacOS/ProxyLogger"

echo "[*] Validating ProxyLogger LaunchDaemon setup..."

# 1. Check plist exists
if [ ! -f "$PLIST" ]; then
    echo "[!] ERROR: LaunchDaemon plist not found at $PLIST"
    exit 1
fi

# 2. Check plist ownership and permissions
OWNER=$(stat -f "%Su:%Sg" "$PLIST")
PERMS=$(stat -f "%Lp" "$PLIST")
if [ "$OWNER" != "root:wheel" ] || [ "$PERMS" != "644" ]; then
    echo "[!] Fixing plist ownership/permissions..."
    chown root:wheel "$PLIST"
    chmod 644 "$PLIST"
fi

# 3. Validate plist syntax
if ! plutil -lint "$PLIST"; then
    echo "[!] ERROR: Plist is not valid XML"
    exit 1
fi

# 4. Check binary exists and is executable
if [ ! -x "$BINARY" ]; then
    echo "[!] ERROR: ProxyLogger binary missing or not executable at $BINARY"
    exit 1
fi

# 5. Bootstrap cleanly
echo "[*] Bootstrapping LaunchDaemon..."
launchctl bootout system "$PLIST" 2>/dev/null || true
if launchctl bootstrap system "$PLIST"; then
    echo "ProxyLogger LaunchDaemon installed and running."
else
    echo "[!] ERROR: launchctl bootstrap failed"
    exit 1
fi

# Convert mitmproxy certificate (if found) for macOS Keychain compatibility
CERT_SRC="$HOME/.mitmproxy/mitmproxy-ca-cert.pem"
CERT_DST="$HOME/.mitmproxy/mitmproxy-ca-cert.crt"

if [ -f "$CERT_SRC" ]; then
    /usr/bin/openssl x509 -in "$CERT_SRC" -out "$CERT_DST"
    echo "Converted mitmproxy certificate to .crt format for Keychain import."
else
    echo "mitmproxy-ca-cert.pem not found. Please visit https://mitm.it to download it."
fi

# Define source path
README_SRC="/Applications/ProxyLogger.app/Contents/Resources/README.txt"

# Define user who reads Readme file
USER_ID=$(id -u)
USERNAME=$(stat -f "%Su" /dev/console)

# Auto-open README in TextEdit
if [ -f "$README_SRC" ]; then
    launchctl asuser "$USER_ID" sudo -u "$USERNAME" open -a TextEdit "$README_SRC"
    echo "Opened Readme.txt in TextEdit."
    
else
    echo "README not found at $README_SRC or failed to open."
fi

