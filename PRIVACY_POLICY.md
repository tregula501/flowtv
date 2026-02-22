# FlowTV Privacy Policy

**Last updated:** February 21, 2026

## Overview

FlowTV is an open-source IPTV media player application. This privacy policy describes how FlowTV handles user data.

## Data Collection

FlowTV does **not** collect, transmit, or share any personal data. All data stays on your device.

### What FlowTV Stores Locally

- **Playlist URLs and credentials:** Stored on-device using encrypted storage (Android Keystore / Windows DPAPI). These are never transmitted to any server other than the IPTV service you configure.
- **App settings:** Theme preference, EPG refresh interval, and other configuration options stored in a local database.
- **EPG data:** Electronic Program Guide data fetched from sources you configure, cached locally for offline access.
- **Favorites and channel ordering:** Stored locally in the app database.

### What FlowTV Does NOT Do

- Does not collect analytics or usage data
- Does not use advertising SDKs or tracking frameworks
- Does not transmit data to the developer or any third party
- Does not access contacts, camera, microphone, or location
- Does not require account creation

## Network Activity

FlowTV connects to the internet solely to:

1. Fetch IPTV playlists and stream content from servers **you** configure
2. Download EPG (TV guide) data from sources **you** configure
3. Load channel logos from URLs provided in your playlists

All network requests go directly to the servers you have configured. FlowTV does not proxy, intercept, or redirect your traffic.

## Third-Party Content

FlowTV is a media player — it does not provide, host, or endorse any streaming content. Users are responsible for ensuring they have the legal right to access the content they configure in the app.

## Data Deletion

All data can be removed by:
- Deleting individual playlists from the Settings screen
- Clearing app data from your device's system settings
- Uninstalling the application

## Children's Privacy

FlowTV does not knowingly collect any information from children under 13. The app does not collect information from any user.

## Changes to This Policy

Updates to this privacy policy will be posted in this file within the project repository. Since FlowTV collects no data, meaningful changes to this policy are unlikely.

## Contact

For questions about this privacy policy, open an issue at:
https://github.com/tregula501/flowtv/issues

## Open Source

FlowTV is open-source software licensed under GPL v3. The complete source code is available at:
https://github.com/tregula501/flowtv
