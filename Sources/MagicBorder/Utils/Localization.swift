import Foundation

/// Internal helper to get the effective locale for localization.
/// This is needed because during `swift run`, Locale.current and Bundle.main might revert to English.
private var effectiveLocale: Locale {
    if let languageCode = Locale.preferredLanguages.first {
        return Locale(identifier: languageCode)
    }
    return .current
}

/// Resolve a localization bundle in a case-insensitive way to handle SwiftPM lowercasing.
private func resolvedLocalizationBundle() -> Bundle {
    let moduleBundle = Bundle.module
    let preferred = Locale.preferredLanguages

    for language in preferred {
        let normalized = language.replacingOccurrences(of: "_", with: "-")
        let parts = normalized.split(separator: "-")
        var candidates: [String] = [
            language,
            normalized,
            language.lowercased(),
            normalized.lowercased(),
        ]

        if parts.count >= 2 {
            let baseScript = "\(parts[0])-\(parts[1])"
            candidates.append(baseScript)
            candidates.append(baseScript.lowercased())
        }

        if let base = parts.first {
            candidates.append(String(base))
            candidates.append(String(base).lowercased())
        }

        for candidate in candidates {
            if let path = moduleBundle.path(forResource: candidate, ofType: "lproj"),
               let bundle = Bundle(path: path)
            {
                return bundle
            }
        }
    }

    return moduleBundle
}

func MBLocalized(_ key: String) -> String {
    let bundle = resolvedLocalizationBundle()
    return bundle.localizedString(forKey: key, value: key, table: nil)
}

func MBLocalized(_ key: String, arguments: [CVarArg]) -> String {
    let format = MBLocalized(key)
    return String(format: format, locale: effectiveLocale, arguments: arguments)
}
