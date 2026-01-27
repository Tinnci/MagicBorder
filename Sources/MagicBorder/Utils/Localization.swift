import Foundation

func MBLocalized(_ key: String) -> String {
    // Use Bundle.module so SwiftPM resources are resolved at runtime
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

func MBLocalized(_ key: String, arguments: [CVarArg]) -> String {
    let format = Bundle.module.localizedString(forKey: key, value: key, table: nil)
    return String(format: format, locale: Locale.current, arguments: arguments)
}
