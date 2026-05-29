# Security Policy

## Supported Versions

FlowTV is an actively developed desktop/mobile IPTV player. Only the latest
released version receives security fixes. Please update to the most recent
release before reporting an issue.

## Reporting a Vulnerability

Please **do not** open a public GitHub issue for security vulnerabilities.

Instead, report privately using GitHub's
[private vulnerability reporting](https://github.com/tregula501/flowtv/security/advisories/new)
(Security tab → "Report a vulnerability"), or email **tregula501@gmail.com**.

Please include:

- A description of the issue and its impact
- Steps to reproduce (or a proof of concept)
- Affected version / platform (Windows, Android, etc.)

You can expect an initial response within a few days. Once a fix is available,
it will be published in a new release and the reporter credited (unless you
prefer to remain anonymous).

## Scope & Notes

FlowTV stores user-supplied IPTV credentials in the OS-provided secure store
(Windows DPAPI, Android EncryptedSharedPreferences, iOS/macOS Keychain) via
`flutter_secure_storage`. Stream URLs are redacted from logs.

When casting, FlowTV runs a short-lived local HLS proxy bound to the LAN so a
Chromecast can fetch segments. It serves only the currently buffered segments
of the active stream and exposes no credentials; it is active only during a
cast session.
