import Foundation

func MBLocalized(_ key: String) -> String {
    String(localized: key, bundle: .module)
}

func MBLocalized(_ key: String, arguments: [CVarArg]) -> String {
    let format = String(localized: key, bundle: .module)
    return String(format: format, locale: Locale.current, arguments: arguments)
}
