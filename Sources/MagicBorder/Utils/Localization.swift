import Foundation

private let effectiveLocale: Locale = {
    if let languageCode = Locale.preferredLanguages.first {
        return Locale(identifier: languageCode)
    }
    return .current
}()

private let cachedLocalizationBundle: Bundle = {
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
}()

func localizedString(_ key: String) -> String {
    cachedLocalizationBundle.localizedString(forKey: key, value: key, table: nil)
}

func localizedString(_ key: String, arguments: [any CVarArg]) -> String {
    let format = localizedString(key)
    return String(format: format, locale: effectiveLocale, arguments: arguments)
}
