#!/bin/bash
/usr/sbin/networksetup -setwebproxystate "Wi-Fi" off
/usr/sbin/networksetup -setsecurewebproxystate "Wi-Fi" off
launchctl unload /Library/LaunchDaemons/com.proxylogger.daemon.plist
rm -rf /Applications/ProxyLogger.app
rm -rf /Library/LaunchDaemons/com.proxylogger.daemon.plist
