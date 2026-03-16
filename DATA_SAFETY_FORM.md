# FlowTV -- Google Play Data Safety Form

> Step-by-step answers for the Data Safety section in Google Play Console.
> Follow along in **Play Console > App content > Data safety** and enter the
> answers below.

---

## Step 1: Data Collection and Security Overview

| Question | Answer |
|----------|--------|
| Does your app collect or share any of the required user data types? | **No** |
| Is all of the user data collected by your app encrypted in transit? | **Yes** |
| Do you provide a way for users to request that their data is deleted? | **Yes** |

### Why "encrypted in transit" is Yes
- Xtream Codes credentials are stored via Android Keystore (encrypted at rest).
- Network requests use the system HTTP stack; HTTPS is supported and recommended.
- Some user-configured IPTV servers may use plain HTTP -- this is the server operator's choice, not the app's. Because the app itself does not transmit data to the developer or any third party, the transit-encryption question refers to developer-controlled transmissions, of which there are none.

### Why "deletion" is Yes
Users can delete all stored data via:
1. **In-app:** Remove individual playlists, profiles, or favorites from Settings.
2. **System settings:** Android Settings > Apps > FlowTV > Clear Data.
3. **Uninstall:** Removes all app data from the device.

No server-side data exists because the app never transmits data to the developer.

---

## Step 2: Data Types

For every data type below, answer **"Not collected"** and **"Not shared"**.

### Location

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Approximate location | No | No |
| Precise location | No | No |

### Personal info

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Name | No | No |
| Email address | No | No |
| User IDs | No | No |
| Address | No | No |
| Phone number | No | No |
| Race and ethnicity | No | No |
| Political or religious beliefs | No | No |
| Sexual orientation | No | No |
| Other personal info | No | No |

### Financial info

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| User payment info | No | No |
| Purchase history | No | No |
| Credit score | No | No |
| Other financial info | No | No |

### Health and fitness

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Health info | No | No |
| Fitness info | No | No |

### Messages

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Emails | No | No |
| SMS or MMS | No | No |
| Other in-app messages | No | No |

### Photos and videos

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Photos | No | No |
| Videos | No | No |

### Audio files

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Voice or sound recordings | No | No |
| Music files | No | No |
| Other audio files | No | No |

### Files and docs

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Files and docs | No | No |

### Calendar

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Calendar events | No | No |

### Contacts

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Contacts | No | No |

### App activity

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| App interactions | No | No |
| In-app search history | No | No |
| Installed apps | No | No |
| Other user-generated content | No | No |
| Other actions | No | No |

### Web browsing

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Web browsing history | No | No |

### App info and performance

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Crash logs | No | No |
| Diagnostics | No | No |
| Other app performance data | No | No |

### Device or other IDs

| Sub-type | Collected | Shared |
|----------|-----------|--------|
| Device or other IDs | No | No |

---

## Step 3: Data Handling Practices

Because all data types are marked as "Not collected" and "Not shared", the
console will skip the detailed data-handling questions (purpose, optional vs.
required, etc.). No further input is needed.

---

## Step 4: Privacy Policy

| Field | Value |
|-------|-------|
| Privacy policy URL | `https://github.com/tregula501/flowtv/blob/main/PRIVACY_POLICY.md` |

---

## Notes for Google Play Review

### Why the app accesses the network but collects no data
FlowTV is a media player. It connects to IPTV servers that the user manually
configures (similar to VLC or MX Player). All network traffic goes directly
between the user's device and their chosen servers. The developer operates no
backend, API, or analytics service. No data is routed through or collected by
the developer.

### Third-party SDKs included in the app

| SDK / Library | Transmits data externally? | Purpose |
|---------------|---------------------------|---------|
| media_kit (libmpv/FFmpeg) | No | Local video playback |
| flutter_chrome_cast | Local network only (mDNS/Cast) | Chromecast discovery and casting |
| dio | To user-configured servers only | HTTP client for fetching playlists and EPG |
| flutter_secure_storage | No (Android Keystore only) | Encrypting Xtream credentials locally |
| drift (SQLite) | No (local database) | Local data storage |
| xml | No | Parsing XMLTV EPG data locally |
| flutter_riverpod | No | State management |
| wakelock_plus | No | Keeping screen on during playback |

No analytics, advertising, crash-reporting, or telemetry SDKs are included.

### If Google requests clarification
Suggested response template:

> FlowTV is a media player utility. It does not provide, host, or link to any
> streaming content. Users must supply their own IPTV server credentials or
> M3U playlist URLs. The app connects only to servers the user has manually
> configured -- no data is sent to the developer or any third party. All
> credentials are encrypted locally using Android Keystore. The app contains
> no analytics, advertising, or tracking SDKs. The complete source code is
> publicly auditable at https://github.com/tregula501/flowtv.
