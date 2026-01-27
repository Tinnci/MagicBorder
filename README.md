<p align="center">
  <img src="Sources/MagicBorder/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="128" height="128" alt="MagicBorder Icon">
</p>

# MagicBorder

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
[![Swift](https://img.shields.io/badge/Swift-6.1+-orange.svg)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)

MagicBorder is a native macOS application compatible with "Mouse Without Borders," built with SwiftUI and Swift. It enables seamless sharing of mouse and keyboard across multiple computers, enhancing productivity in multi-device setups. Whether you're working with a laptop and desktop or multiple machines in a home office, MagicBorder provides a smooth, secure, and intuitive experience.

## ✨ Features

- **🖥️ Native macOS Design**: Leverages SwiftUI with `NavigationSplitView` and standard macOS components for a polished, integrated user interface.
- **🎯 Easy Arrangement**: Drag and drop machines in a visual matrix to replicate your physical desk layout, ensuring intuitive navigation.
- **📋 Universal Clipboard**: Share text and files between connected machines (currently in development).
- **🔒 Secure Communication**: Utilizes encrypted connections with a shared security key to protect data transmission.
- **🌍 Localization**: Supports multiple languages, including English and Chinese, for a global user base.
- **⚡ Real-time Sync**: Low-latency input sharing with automatic device discovery.

## 📋 Table of Contents

- [Requirements](#-requirements)
- [Installation](#-installation)
- [Usage](#-usage)
- [Architecture](#-architecture)
- [Development](#-development)
- [Contributing](#-contributing)
- [Troubleshooting](#-troubleshooting)
- [Support](#-support)
- [Changelog](#-changelog)
- [License](#-license)

## 🔧 Requirements

- **macOS**: 14.0 or later
- **Swift Toolchain**: 6.1 or later
- **Xcode**: 15.0 or later (for development)
- **Network**: All devices must be on the same local network

## 🚀 Installation

### Build from Source

1. **Clone the repository**:
   ```bash
   git clone https://github.com/tinnci/MagicBorder.git
   cd MagicBorder
   ```

2. **Build the project**:
   ```bash
   swift build -c release
   ```

3. **Run the application**:
   ```bash
   ./.build/release/MagicBorder
   ```

### Alternative: Using Xcode

1. Open `MagicBorder.xcodeproj` in Xcode.
2. Select the `MagicBorder` scheme.
3. Build and run (`Cmd + R`).

## 📖 Usage

1. **Launch MagicBorder** on all computers you want to connect.
2. **Grant Permissions**: When prompted, grant Accessibility permissions in System Settings > Privacy & Security > Accessibility.
3. **Configure Security**: Set a matching **Security Key** in the Settings tab on all devices.
4. **Arrange Machines**: In the **Arrangement** tab, drag and drop machine icons to match your physical setup.
5. **Connect**: Machines should automatically discover and connect, allowing seamless input sharing.

### Keyboard Shortcuts

- **Switch to next machine**: `Ctrl + Alt + F12` (configurable)
- **Toggle input capture**: `Ctrl + Alt + F11`

## 🏗️ Architecture

MagicBorder is built with a modular architecture:

- **App Layer** (`Sources/MagicBorder/`): SwiftUI views and application logic
- **Core Library** (`Sources/MagicBorderKit/`): Reusable components including:
  - **Network**: Bonjour discovery, TCP connections, protocol handling
  - **Input**: Event interception, mouse/keyboard simulation
  - **Security**: Encryption, authentication
  - **Utils**: Logging, accessibility services, clipboard monitoring

### Key Components

- `NetworkManager`: Handles peer discovery and communication
- `InputManager`: Manages input event capture and forwarding
- `MWBProtocol`: Defines packet formats compatible with Mouse Without Borders

## 💻 Development

### Setup Development Environment

1. Ensure you have Xcode 15+ installed.
2. Clone and navigate to the project directory.
3. Open in Xcode or use command line tools.

### Building

```bash
# Debug build
swift build

# Release build
swift build -c release

# Clean build
swift build --clean
```

### Testing

```bash
swift test
```

### Code Style

- Follow Swift standard conventions
- Use meaningful variable names
- Add documentation for public APIs
- Run `swift format` for consistent formatting

## 🤝 Contributing

We welcome contributions! Here's how you can help:

### Development Workflow

1. **Fork** the repository on GitHub.
2. **Create a feature branch**: `git checkout -b feature/your-feature-name`
3. **Make your changes** with clear commit messages.
4. **Test thoroughly** - ensure all existing tests pass.
5. **Submit a Pull Request** with a detailed description.

### Guidelines

- **Issues First**: For major changes, open an issue first to discuss.
- **Code Quality**: Ensure code is well-documented and tested.
- **Compatibility**: Maintain compatibility with Mouse Without Borders protocol.
- **Security**: Be mindful of security implications in network and input handling code.

### Areas for Contribution

- 🐛 Bug fixes and stability improvements
- ✨ New features (clipboard file sharing, advanced settings)
- 🌍 Additional language support
- 📚 Documentation improvements
- 🧪 Test coverage expansion

## 🔍 Troubleshooting

### Common Issues

**Connection Problems**
- Ensure all devices are on the same Wi-Fi network
- Check firewall settings (allow incoming connections on port 12345)
- Verify security keys match exactly

**Permission Issues**
- Go to System Settings > Privacy & Security > Accessibility
- Ensure MagicBorder is checked and enabled
- Restart the application after granting permissions

**Input Not Working**
- Confirm Accessibility permissions are granted
- Check if another application is capturing input
- Try toggling input capture in the app settings

**Performance Issues**
- Close unnecessary applications
- Ensure stable network connection
- Check system resources (CPU, memory)

### Debug Mode

Enable debug logging by setting the environment variable:
```bash
export MAGICBORDER_DEBUG=1
```

### Getting Help

- Check existing [Issues](https://github.com/tinnci/MagicBorder/issues)
- Search the [Discussions](https://github.com/tinnci/MagicBorder/discussions) forum
- Create a new issue with detailed information about your setup and the problem

## 📞 Support

- **Issues**: [GitHub Issues](https://github.com/tinnci/MagicBorder/issues)
- **Discussions**: [GitHub Discussions](https://github.com/tinnci/MagicBorder/discussions)
- **Email**: For security issues, contact maintainers privately

## 📝 Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and updates.

## 📄 License

This project is licensed under the **GNU General Public License v3.0 (GPL-3.0)** - see the [LICENSE](LICENSE) file for details.

---

**Made with ❤️ for the macOS community**
