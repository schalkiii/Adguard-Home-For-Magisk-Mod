# Adguard Home For Android
<a href="https://deepwiki.com/liuzq2002/Adguard-Home-For-Magisk-Mod"><img src="https://deepwiki.com/badge.svg" alt="Ask DeepWiki"></a>

[简体中文](README.md) | **English** 
- Ad blocking via DNS request redirection/filtering is universal across modular Root managers
- This project is permanently open-source and free without donations or its variants, and does not differentiate versions based on whether a donation is made
- It achieves out-of-the-box ease of use; after flashing the module, you can use it by just following the tutorial for minor troubleshooting (no need to configure rules)
- Built-in GOODBYEADS blocking rules and adds custom rules on top of them
- This project aims to replace traditional Hosts and deliver a better modern experience — with 'zero' ad leakage, high performance, and strong stealth
- Please read the tutorial before requesting support. Click the link below to jump directly to the tutorial section: [Jump to Tutorial](https://github.com/liuzq2002/Adguard-Home-For-Magisk-Mod/blob/main/README.en.md#-tutorial--read-before-use)
## ⚠️ Risk Notice – Please Read
- Users who have updated to version 2026.03.01 must not downgrade to an earlier version, as doing so may leave residual files when uninstalling modules.
- May interfere with coupon redemption functionality in some apps (not a false positive)
- May prevent reward systems based on watching ads (not a false positive)
- Do **not** use with other similar ad-blocking modules
- Cannot block ads served from the same domain as content (e.g., Twitch, YouTube, Instagram)
## 💡 Advantages Over Other Solutions
### What are the advantages compared to non-AdguardHome DNS implementation solutions?
1. AdguardHome despite years of maintenance still has high-risk CVE vulnerabilities; other competing solutions would only be worse (as their technical strength is not as profound as that of Adguard company)
2. In terms of performance and power consumption they may not be better than AdguardHome which is written in Go language; the smaller the project, the fewer people monitor it and the less likely it is to discover deep-seated vulnerabilities (especially since AdguardHome is a globally renowned open-source large project)
### vs. Private DNS
1. No server dependency → no downtime or overload issues
2. Lower latency – processing happens locally
3. Better privacy – no data sent to third-party servers
### vs. Hosts File
1. Encrypted DNS (DoH) support
2. Prevents DNS hijacking
3. Harder to detect and block, Because the loopback address returned by Hosts is itself a detectable signature
4. No need to flash the meta module, achieving even better concealment
### vs. Accessibility-based Ad Skippers (e.g., Li Tiao Tiao)
1. No background process killing issues
2. No UI lag or performance drain
3. Lightweight and battery-efficient
4. No package name detection risks
### vs. LSPosed Modules
1. Less detectable – no app hooking or injection
2. Broader coverage – blocks ads system-wide, not per-app
### Compared to a VPN, what are the advantages of ad blocking?
1. No need to worry about apps detecting that a VPN is active
2. No need to worry about disconnections in the background
## 📖 Tutorial – Read Before Use
- Disable or uninstall other ad-blocking modules, proxy tools, accessibility services, VPN ad blockers, browser ad blockers etc
- If the ad cannot be blocked, clear all data for the app and try again.
- Magisk users: click the action button next to the module to **toggle bypass mode** (it does not open the Web UI); to open the Web UI just visit `http://127.0.0.1:3000`
- The Web UI address is fixed at `http://127.0.0.1:3000` (the DNS redirection port is randomized, no need to care about it)
- If using Clash Meta, disable system proxy in Network settings (tested and working)
- Upstream DNS: by default the module forwards queries to a local smartdns instance (`127.0.0.1:1451`), so you need to deploy smartdns listening on that port; without it the built-in `fallback_dns` is used automatically (still DoH, but you lose smartdns routing and acceleration)
- USTC Speedtest: [Jump to Tutorial](https://test.ustc.edu.cn)
- Test if ad blocking is working properly (aim for ≥96%): [Jump to Tutorial](https://paileactivist.github.io/toolz/adblock.html)
## 📶 Bypass Mode (for WiFi networks that require a specific DNS)
Some public WiFi networks (captive portals, campus networks, corporate intranets) broadcast a designated DNS via DHCP, or require the device DNS to point at a specific server to complete authentication. The module's DNS redirection conflicts with them, causing broken resolution or an unreachable authentication page.
- Enable (either way):
  - Click the action button next to the module — it toggles bypass mode and prints the current state
  - Or edit `/data/adb/agh/scripts/config.prop` and change `bypass=0` to `bypass=1`
  - Both take effect within 5 seconds, no reboot needed
- Scope: removes all port 53 redirections and 853 (DoT) blocks, and stops forcing Private DNS off; the system then uses the DNS broadcast by the network
- The AGH process stays alive and the Web UI remains reachable at `http://127.0.0.1:3000`, but no DNS traffic is hijacked
- When a proxy module is used, the DNS modifications made in its config are reverted during bypass so the proxy keeps an upstream
- Disable: click the action button again, or change back to `bypass=0`; the daemon rebuilds the rules and refreshes the network (WiFi briefly disconnects)
- Note: turning off "Protection" in the Web UI does NOT stop the DNS hijack. Switch `bypass` instead when changing networks
- Every mode switch is recorded in `/data/adb/agh/agh.log`
- After uninstalling the module, Private DNS is not restored automatically; adjust it in system settings if needed
- If the action button prints "Daemon is not running", the daemon has exited and the switch will not apply automatically — reboot the device
## 🙏 Credits
- [AdguardHome_magisk](https://github.com/410154425/AdGuardHome_magisk)
- [akashaProxy](https://github.com/ModuleList/akashaProxy)
- [box_for_magisk](https://github.com/taamarin/box_for_magisk)
- [AdGuardHomeForMagisk](https://github.com/twoone-3/AdGuardHomeForMagisk)
