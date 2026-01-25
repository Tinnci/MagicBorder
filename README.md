# MagicBorder

MagicBorder is a native macOS application inspired by "Mouse Without Borders," built with SwiftUI and Swift. It allows you to share your mouse and keyboard across multiple computers seamlessly.

## Features

- **Native macOS Design**: Built with SwiftUI using `NavigationSplitView` and standard macOS components.
- **Easy Arrangement**: Drag and drop machines to match your physical desk layout.
- **Universal Clipboard**: Share text and files between connected machines (Work in Progress).
- **Secure Communication**: Encrypted connection using a shared security key.
- **Localization**: Supports multiple languages (English, Chinese).

## Installation

### Prerequisites
- macOS 14.0 or later.
- Swift 6.0 toolchain.

### Build from Source
```bash
swift build -c release
```
The binaries will be located in `.build/release/`.

## Usage
1. Open MagicBorder on all computers.
2. Grant Accessibility permissions when prompted.
3. Configure the **Security Key** to match on all devices.
4. Arrange your screens in the **Arrangement** tab.

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)** - see the [LICENSE](LICENSE) file for details.
