import Foundation

public struct Localizer: Sendable {
    public let language: AppLanguage
    public init(language: AppLanguage) { self.language = language.resolved() }
    public var isRTL: Bool { language == .ar }
    public var locale: Locale { Locale(identifier: language.rawValue) }
    public func text(_ key: String, _ arguments: CVarArg...) -> String {
        let bundle = Bundle.module.path(forResource: language.rawValue, ofType: "lproj").flatMap(Bundle.init(path:)) ?? .module
        let fallback = Bundle.module.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))?.localizedString(forKey: key, value: key, table: nil) ?? key
        let format = bundle.localizedString(forKey: key, value: fallback, table: nil)
        return arguments.isEmpty ? format : String(format: format, locale: locale, arguments: arguments)
    }
    public func name(_ prayer: Prayer) -> String { text("prayer.\(prayer.rawValue)") }
    public func day(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter(); formatter.locale = locale; formatter.timeZone = timeZone
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}
