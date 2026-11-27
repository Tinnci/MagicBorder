public import CoreGraphics

/// Pure bidirectional mapping between Windows Virtual-Key codes and macOS `CGKeyCode`s.
public enum MBKeyCodeMapper: Sendable {
    public static func macKeyCode(forWindowsKeyCode winCode: Int32) -> CGKeyCode? {
        self.windowsToMacMap[Int(winCode)]
    }

    public static func windowsKeyCode(for macKeyCode: CGKeyCode) -> Int32? {
        self.macToWindowsMap[macKeyCode]
    }

    public static func isModifierDown(macKeyCode: CGKeyCode, flags: CGEventFlags) -> Bool {
        switch macKeyCode {
        case 56, 60:
            flags.contains(.maskShift)
        case 59, 62:
            flags.contains(.maskControl)
        case 58, 61:
            flags.contains(.maskAlternate)
        case 55, 54:
            flags.contains(.maskCommand)
        case 57:
            flags.contains(.maskAlphaShift)
        default:
            flags.contains(.maskNonCoalesced)
        }
    }

    private static let windowsToMacMap: [Int: CGKeyCode] = [
        // Letters
        0x41: 0,  // A
        0x42: 11,  // B
        0x43: 8,  // C
        0x44: 2,  // D
        0x45: 14,  // E
        0x46: 3,  // F
        0x47: 5,  // G
        0x48: 4,  // H
        0x49: 34,  // I
        0x4A: 38,  // J
        0x4B: 40,  // K
        0x4C: 37,  // L
        0x4D: 46,  // M
        0x4E: 45,  // N
        0x4F: 31,  // O
        0x50: 35,  // P
        0x51: 12,  // Q
        0x52: 15,  // R
        0x53: 1,  // S
        0x54: 17,  // T
        0x55: 32,  // U
        0x56: 9,  // V
        0x57: 13,  // W
        0x58: 7,  // X
        0x59: 16,  // Y
        0x5A: 6,  // Z

        // Numbers
        0x30: 29,  // 0
        0x31: 18,  // 1
        0x32: 19,  // 2
        0x33: 20,  // 3
        0x34: 21,  // 4
        0x35: 23,  // 5
        0x36: 22,  // 6
        0x37: 26,  // 7
        0x38: 28,  // 8
        0x39: 25,  // 9

        // Function Keys
        0x70: 122,  // F1
        0x71: 120,  // F2
        0x72: 99,  // F3
        0x73: 118,  // F4
        0x74: 96,  // F5
        0x75: 97,  // F6
        0x76: 98,  // F7
        0x77: 100,  // F8
        0x78: 101,  // F9
        0x79: 109,  // F10
        0x7A: 103,  // F11
        0x7B: 111,  // F12

        // Special Keys
        0x0D: 36,  // Enter
        0x20: 49,  // Space
        0x1B: 53,  // Esc
        0x08: 51,  // Backspace
        0x09: 48,  // Tab
        0x14: 57,  // Caps Lock
        0x10: 56,  // Shift (Left)
        0x11: 59,  // Ctrl (Left)
        0x12: 58,  // Alt (Left) / Option
        0x5B: 55,  // Windows Key (Left) / Command
        0x5C: 54,  // Windows Key (Right) / Command

        // Punctuation
        0xBA: 41,  // ;
        0xDE: 39,  // '
        0xDB: 33,  // [
        0xDD: 30,  // ]
        0xDC: 42,  // \
        0xBC: 43,  // ,
        0xBE: 47,  // .
        0xBF: 44,  // /
        0xC0: 50,  // `
        0xBD: 27,  // -
        0xBB: 24,  // =

        // Navigation
        0x25: 123,  // Left Arrow
        0x26: 126,  // Up Arrow
        0x27: 124,  // Right Arrow
        0x28: 125,  // Down Arrow
        0x21: 116,  // Page Up
        0x22: 121,  // Page Down
        0x24: 115,  // Home
        0x23: 119,  // End
        0x2D: 114,  // Insert
        0x2E: 117,  // Delete
    ]

    private static let macToWindowsMap: [CGKeyCode: Int32] = {
        var map: [CGKeyCode: Int32] = [:]
        for (win, mac) in Self.windowsToMacMap {
            map[mac] = Int32(win)
        }
        return map
    }()
}
