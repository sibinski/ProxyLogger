ProxyLogger
===========

ProxyLogger is a lightweight Swift-based system proxy daemon that intercepts browser traffic using macOS proxy settings and mitmdump. It logs URLs with timestamps to /tmp/proxy_log.txt and prints them to the terminal.

ProxyLogger runs as a background service via com.proxylogger.daemon.plist, making it suitable for system-wide traffic inspection and logging.

------------------------------------------------------------
Important Modules
------------------------------------------------------------

1. Logging System
- Captures timestamped proxy activity to both terminal and /tmp/proxy_log.txt.
- Ensures traceability of startup, shutdown, and traffic inspection.

2. System Proxy Configuration
- Redirects browser traffic to ProxyLogger via macOS proxy settings.
- Uses networksetup to set HTTP and HTTPS proxies to 127.0.0.1:8080.

3. Signal and Termination Handling
- Enables graceful shutdown via Ctrl+C or /tmp/proxylogger.stop flag.
- Prevents orphaned proxy settings and ensures clean exit.

4. mitmdump Integration
- Launches mitmdump to inspect and log HTTP/HTTPS traffic.
- Parses mitmdump output for visible URLs.

5. TCP Listener and Connection Handler
- Accepts incoming browser connections on port 8080.
- Parses requests, logs URLs/domains, and relays traffic to mitmdump.

6. Traffic Relay
- Creates bidirectional tunnel between browser and mitmdump.
- Enables full duplex communication for page loading and response.

------------------------------------------------------------
Traffic Flow Summary
------------------------------------------------------------

Browser → ProxyLogger (port 8080)
         → Logs request
         → Forwards to mitmdump (port 8081)
         → mitmdump inspects and logs
         → Response relayed back to browser

------------------------------------------------------------
Installation
------------------------------------------------------------

1. Run the Installer
- Double-click ProxyLogger.pkg and follow the prompts.
- Installs ProxyLogger binary to /Applications/ProxyLogger.app/Contents/MacOS
- Installs com.proxylogger.daemon.plist to /Library/LaunchDaemons/
- Adds uninstall.sh and manual to the app bundle.

2. Install mitmdump
- Required for HTTPS inspection.
- Run in Terminal:
  brew install mitmproxy

3. Verify Proxy Activation
- After installation, ProxyLogger runs automatically via launchd.
- Check proxy status:
  networksetup -getwebproxy Wi-Fi
  networksetup -getsecurewebproxy Wi-Fi

------------------------------------------------------------
HTTPS Certificate Setup
------------------------------------------------------------

If mitmproxy-ca-cert.crt exists in ~/.mitmproxy:

1. Open Keychain Access and drag the certificate into System keychain.
2. Double-click the certificate -> Trust -> Always Trust for SSL.
3. Restart your browser.

If no certificate is present:

1. Visit https://mitm.it in Safari or Chrome.
2. Download mitmproxy-ca-cert.pem for macOS.
3. Convert it:
   openssl x509 -in mitmproxy-ca-cert.pem -out mitmproxy-ca-cert.crt
4. Import into System keychain and set trust.
5. Restart your browser.

WARNING: Only use this certificate in trusted environments. It enables HTTPS decryption.

------------------------------------------------------------
Usage
------------------------------------------------------------

After installation, ProxyLogger will:
- Start automatically via com.proxylogger.daemon.plist
- Set system proxy to 127.0.0.1:8080
- Log traffic to /tmp/proxy_log.txt and print to terminal (if run interactively)

------------------------------------------------------------
View Logs
------------------------------------------------------------

To view logs:
cat /tmp/proxy_log.txt

------------------------------------------------------------
Script Details
------------------------------------------------------------

- postinstall.sh: executed automatically by the installer
- uninstall.sh: disables proxy and removes ProxyLogger components

------------------------------------------------------------
Uninstallation
------------------------------------------------------------

1. Stop the daemon:
   touch /tmp/proxylogger.stop
   (or press Ctrl+C if running interactively after running command `sudo launchctl bootout system /Library/LaunchDaemons/com.proxylogger.daemon.plist`)

2. Run the uninstall script:
   sudo /Applications/ProxyLogger.app/Contents/MacOS/uninstall.sh

Manual cleanup:
   sudo launchctl bootout system /Library/LaunchDaemons/com.proxylogger.daemon.plist
   rm -rf /Applications/ProxyLogger.app
   rm -f /tmp/proxy_log.txt

------------------------------------------------------------
Log Format
------------------------------------------------------------

Each entry in /tmp/proxy_log.txt is timestamped in ISO 8601 format.

Example:
[2025-10-06T00:14:23Z] URL: https://example.com

------------------------------------------------------------
Notes
------------------------------------------------------------

- Only browser-originated traffic is logged (based on User-Agent filtering)
- HTTPS domains are captured via CONNECT method
- Works best with Chrome, Firefox, Safari (after certificate setup)
- ProxyLogger runs as a system daemon, not a GUI app

------------------------------------------------------------
Disclaimer
------------------------------------------------------------

ProxyLogger is intended for educational and debugging use.
Do not intercept traffic without consent.
Respect privacy and legal boundaries.