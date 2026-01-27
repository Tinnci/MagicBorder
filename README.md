# MagicBorder

MagicBorder is a native macOS application compatible with "Mouse Without Borders," built with SwiftUI and Swift. It enables seamless sharing of mouse and keyboard across multiple computers, enhancing productivity in multi-device setups. Whether you're working with a laptop and desktop or multiple machines in a home office, MagicBorder provides a smooth, secure, and intuitive experience.

## Features

- **Native macOS Design**: Leverages SwiftUI with `NavigationSplitView` and standard macOS components for a polished, integrated user interface.
- **Easy Arrangement**: Drag and drop machines in a visual matrix to replicate your physical desk layout, ensuring intuitive navigation.
- **Universal Clipboard**: Share text and files between connected machines (currently in development).
- **Secure Communication**: Utilizes encrypted connections with a shared security key to protect data transmission.
- **Localization**: Supports multiple languages, including English and Chinese, for a global user base.

## Requirements

- macOS 14.0 or later
- Swift 6.1 toolchain or later
- Xcode 15.0 or later (for development)

## Installation

### Build from Source
1. Clone the repository:
   ```bash
   git clone https://github.com/tinnci/MagicBorder.git
   cd MagicBorder
   ```
2. Build the project:
   ```bash
   swift build -c release
   ```
3. The binaries will be located in `.build/release/`.

### Running the Application
After building, run the application:
```bash
./.build/release/MagicBorder
```

## Usage

1. **Launch MagicBorder**: Open the application on all computers you want to connect.
2. **Grant Permissions**: When prompted, grant Accessibility permissions to allow mouse and keyboard control.
3. **Configure Security**: Set a matching **Security Key** on all devices for secure communication.
4. **Arrange Machines**: In the **Arrangement** tab, drag and drop machine icons to match your physical setup.
5. **Connect**: Machines should automatically connect and allow seamless input sharing.

### Tips
- Ensure all machines are on the same network for optimal performance.
- If connection issues occur, verify firewall settings and security key consistency.

## Contributing

We welcome contributions! Please follow these steps:
1. Fork the repository.
2. Create a feature branch: `git checkout -b feature/your-feature`.
3. Commit your changes: `git commit -m 'Add some feature'`.
4. Push to the branch: `git push origin feature/your-feature`.
5. Open a Pull Request.

For major changes, please open an issue first to discuss what you would like to change.

## Support

If you encounter issues or have questions:
- Check the [Issues](https://github.com/tinnci/MagicBorder/issues) page.

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and updates.

## License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)** - see the [LICENSE](LICENSE) file for details.
