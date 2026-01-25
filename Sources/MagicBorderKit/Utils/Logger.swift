import OSLog

public struct MBLogger {
    private static let subsystem = "com.tinnci.MagicBorder"

    public static let method = Logger(subsystem: subsystem, category: "Method")
    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let input = Logger(subsystem: subsystem, category: "Input")
    public static let ui = Logger(subsystem: subsystem, category: "UI")
    public static let security = Logger(subsystem: subsystem, category: "Security")
}
