import SwiftUI
import MySalahCore

struct PrayerPanel: View {
    let model: AppModel
    private var strings: Localizer { model.strings }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "moon.fill").accessibilityHidden(true)
                Text("MySalah").font(.headline)
                Spacer()
            }
            if let location = model.preferences.location, let zone = model.timeZone {
                Text(strings.text("location.summary",
                                  location.locality.district.displayName(language: strings.language).capitalized(with: strings.locale),
                                  location.locality.country.displayName(language: strings.language).capitalized(with: strings.locale)))
                    .font(.subheadline).fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
                Text(strings.day(model.now, timeZone: zone)).font(.caption).foregroundStyle(.secondary)
                if let snapshot = model.snapshot {
                    if snapshot.active == nil, let boundary = snapshot.nextBoundary, let next = snapshot.nextPrayer {
                        HStack {
                            Text(strings.text("nextPrayer", strings.name(next)))
                            Spacer()
                            Text(TimeDisplay.countdown(until: boundary, now: model.now)).monospacedDigit()
                        }.font(.caption).foregroundStyle(.secondary)
                    }
                    VStack(spacing: 4) {
                        ForEach(snapshot.rows) { row in
                            HStack(alignment: .center, spacing: 8) {
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(strings.name(row.prayer)).font(.body)
                                    if row.isYesterday { Text(strings.text("yesterday")).font(.caption2) }
                                }
                                Spacer(minLength: 8)
                                Text(row.isActive ? model.snapshot?.nextBoundary.map { TimeDisplay.countdown(until: $0, now: model.now) } ?? "" : "")
                                    .font(.caption.weight(.medium)).monospacedDigit()
                                    .foregroundStyle(Color(nsColor: .textColor))
                                    .padding(.horizontal, 8).padding(.vertical, 4)
                                    .background(Color(nsColor: .textBackgroundColor), in: Capsule())
                                    .opacity(row.isActive ? 1 : 0)
                                    .fixedSize()
                                    .frame(width: 72, alignment: .trailing)
                                Text(row.start.map { TimeDisplay.clock($0, format: model.preferences.clockFormat, language: strings.language, timeZone: zone) } ?? "—")
                                    .font(.body).monospacedDigit().fixedSize()
                            }
                            .padding(.horizontal, 8).padding(.vertical, 8)
                            .foregroundStyle(row.isActive ? Color.white : Color.primary)
                            .background(row.isActive ? Color(nsColor: .systemBlue) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(accessibilityLabel(row, zone: zone))
                            .accessibilityAddTraits(row.isActive ? .isSelected : [])
                        }
                    }
                }
            }
            Text(model.statusText).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 368, alignment: .leading)
        .environment(\.locale, strings.locale)
        .environment(\.layoutDirection, strings.isRTL ? .rightToLeft : .leftToRight)
        .preferredColorScheme(model.preferences.theme == .system ? nil : model.preferences.theme == .dark ? .dark : .light)
    }
    private func accessibilityLabel(_ row: PrayerRow, zone: TimeZone) -> String {
        let start = row.start.map { TimeDisplay.clock($0, format: model.preferences.clockFormat, language: strings.language, timeZone: zone) } ?? strings.text("unavailable")
        var text = "\(strings.name(row.prayer)), \(start)"
        if row.isYesterday { text += ", " + strings.text("yesterday") }
        if row.isActive { text += ", " + strings.text("active") }
        return text
    }
}
