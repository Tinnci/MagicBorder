# Security Policy

## Supported Versions

Only the latest release on `main` receives security fixes and protocol compatibility updates.

| Version | Supported |
| --- | --- |
| `main` / latest `v*` tag | ✅ Yes |
| Older snapshots | ❌ No |

## Reporting a Vulnerability

**Please do not report security vulnerabilities through public GitHub issues.**

If you discover a security vulnerability (for example: authentication bypass, packet parsing crashes, privilege/Accessibility misuse, or clipboard data exposure):

1. Use **GitHub Private Vulnerability Reporting** on the repository's **Security → Advisories** tab, or contact the maintainer privately via GitHub (`@Tinnci`).
2. Include a clear description, affected commit or release tag, reproduction steps, and potential impact.
3. Allow reasonable time for a fix and coordinated disclosure before publishing details.

## Security Architecture & Threat Model

Because MagicBorder operates as a local-network KVM, clipboard bridge, and Accessibility client, please keep these boundaries in mind:

- **Trusted LAN Assumption**: MagicBorder is designed for private local networks. Do not expose TCP ports `15100`, `15101`, or `12345` directly to the public internet.
- **Security Key Strength**: Configure a strong pairing key (at least 16 non-whitespace characters) before enabling network connections.
- **MWB Compatibility Mode**: Uses PBKDF2-HMAC-SHA512 (50,000 iterations) and AES-256-CBC stream framing to maintain wire compatibility with Microsoft PowerToys Mouse Without Borders.
- **Modern Mode (`macOS ↔ macOS`)**: Uses HMAC-SHA256 handshake verification (`SymmetricKey` / constant-time validation, rejecting unsigned or tampered handshakes whenever a security key is configured) and enforces a 32 MB packet frame cap.
- **macOS Permissions**: Global HID capture/synthesis requires explicit user authorization in **System Settings → Privacy & Security → Accessibility**; local peer discovery uses macOS Local Network permissions.
