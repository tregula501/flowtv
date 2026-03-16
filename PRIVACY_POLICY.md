# FlowTV Privacy Policy

**Effective date:** March 15, 2026

This privacy policy explains how FlowTV ("the app", "we", "our") handles your data. FlowTV is a free, open-source IPTV player developed by tregula501. The full source code is publicly available under the GPL v3 license at [github.com/tregula501/flowtv](https://github.com/tregula501/flowtv), so you can verify every claim in this policy yourself.

We wrote this policy in plain language because you deserve to understand it without a law degree.

---

## 1. Data We Collect

**None.** FlowTV does not collect, transmit, or share any personal data with the developer or any third party. There are no analytics, no crash reporting, no telemetry, no advertising, and no tracking of any kind.

The app does store data **locally on your device** to function. That data never leaves your device except when sent to IPTV servers that *you* configure.

## 2. Data Stored on Your Device

The following data is created and stored entirely on your device:

| Data | Storage method | Purpose |
|------|---------------|---------|
| Xtream API usernames and passwords | Encrypted device storage (Android Keystore / iOS Keychain / OS-level secure storage) | Authenticating with your IPTV servers |
| Playlist URLs (M3U) | Local SQLite database | Loading your channel lists |
| Channel lists and EPG data | Local SQLite database | Displaying channels and TV guide |
| Favorites and viewing history | Local SQLite database | Personalizing your experience |
| User profiles | Local SQLite database | Supporting multiple users on one device |
| App settings | Local SQLite database | Remembering your preferences |
| Cached channel logos | Local image cache | Displaying logos without re-downloading |

**We have no access to any of this data.** It exists only on your device.

## 3. Network Connections

FlowTV connects to the internet only when you ask it to, and only to servers you have configured. Specifically:

- **Your IPTV servers** -- to fetch playlists, EPG/guide data, and stream video content.
- **Image URLs from your playlists/EPG** -- to download and cache channel logos.
- **Google Cast (Chromecast)** -- if you choose to cast video to a Chromecast or Cast-compatible device on your local network.

FlowTV **never** connects to any server operated by the developer. There is no "phone home" behavior.

## 4. Third-Party Services

### Google Cast (Chromecast)
If you use the casting feature, the app communicates with Google Cast-compatible devices on your local network. This interaction is governed by [Google's Privacy Policy](https://policies.google.com/privacy). Casting is entirely optional and initiated only by you.

### Your IPTV Providers
When you add an Xtream Codes server or M3U playlist URL, the app connects to that provider's server. The data shared with those servers (such as your credentials) is governed by your agreement with that provider, not by this policy. We have no relationship with your IPTV providers and no control over their data practices.

No other third-party services, SDKs, or libraries in the app transmit data externally.

## 5. Security

We take reasonable steps to protect your data:

- **Credentials are encrypted** using your platform's secure storage (Android Keystore, iOS Keychain, or equivalent OS-level mechanisms).
- **All data stays on your device** and is protected by your device's own security (lock screen, encryption, etc.).

### Important Security Notices

- **HTTP streams:** Some IPTV servers use unencrypted HTTP rather than HTTPS. When connecting to an HTTP server, your stream data and any credentials embedded in the URL are not encrypted in transit. This is a limitation of those servers, not of FlowTV.
- **Xtream Codes API:** The Xtream Codes protocol transmits credentials as part of the URL. This is an inherent design of the protocol. We strongly recommend using HTTPS-enabled servers when possible.

## 6. Data Retention and Deletion

Your data stays on your device for as long as you keep it there. You are in full control.

**To delete your data:**
- Remove individual playlists or profiles from within the app settings.
- Clear the app's data through your device's system settings.
- Uninstall the app.

Once deleted, the data is gone. We have no backups because we never had your data in the first place.

## 7. Your Rights (GDPR, CCPA, and Other Privacy Laws)

Because FlowTV collects **zero** personal data and transmits **nothing** to the developer or any third party, many of the rights granted by privacy laws (such as the EU General Data Protection Regulation or the California Consumer Privacy Act) are satisfied by design:

- **Right to know / access:** All your data is on your device. You already have it.
- **Right to delete:** You can delete all data at any time (see Section 6).
- **Right to data portability:** Your data is stored locally and can be managed through your device.
- **Right to opt out of sale:** We do not sell, rent, or trade any personal information. There is nothing to opt out of.
- **Right to non-discrimination:** There is no data collection to discriminate on.
- **Do Not Track:** The app does not track you, regardless of your browser or device settings.

If you believe you have a privacy concern, please contact us (see Section 10).

## 8. Children's Privacy

FlowTV is not directed at children under 13 (or under 16 in the EU). The app does not collect personal information from any user, including children.

Because FlowTV plays content from user-configured sources, the app has no control over and does not moderate the content accessed through it. Parents and guardians are responsible for supervising the content their children access.

## 9. Changes to This Policy

If we update this privacy policy, we will post the revised version in the project repository and update the effective date at the top. Since FlowTV collects no data, significant changes are unlikely.

You can view the full history of changes to this policy in the [Git commit history](https://github.com/tregula501/flowtv/commits/main/PRIVACY_POLICY.md).

## 10. Contact

If you have questions or concerns about this privacy policy, please open an issue at:

**[github.com/tregula501/flowtv/issues](https://github.com/tregula501/flowtv/issues)**

## 11. Open Source

FlowTV is free and open-source software licensed under the [GNU General Public License v3.0](https://www.gnu.org/licenses/gpl-3.0.html). The complete source code is available at:

**[github.com/tregula501/flowtv](https://github.com/tregula501/flowtv)**

You can audit the code to verify that this privacy policy is accurate.
