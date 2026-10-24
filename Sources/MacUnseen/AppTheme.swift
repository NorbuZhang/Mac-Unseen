import SwiftUI

struct SubtlePressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.background {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(configuration.isPressed ? 0.10 : 0))
        }
    }
}

enum DetailStyle: String, CaseIterable, Identifiable {
    case accent
    case standard

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accent: tr("强调色设计")
        case .standard: tr("标准设计")
        }
    }
}

private struct DetailStyleKey: EnvironmentKey {
    static let defaultValue = DetailStyle.standard
}

extension EnvironmentValues {
    var detailStyle: DetailStyle {
        get { self[DetailStyleKey.self] }
        set { self[DetailStyleKey.self] = newValue }
    }
}

enum AppPalette {
    // Text needs more contrast than decorative fills. Keep the brand hue while
    // resolving its foreground separately for light and dark appearances.
    static let accentText = Color(nsColor: NSColor(name: nil) { appearance in
        if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
            return NSColor(srgbRed: 0.40, green: 0.73, blue: 0.78, alpha: 1)
        }
        return NSColor(srgbRed: 0.10, green: 0.43, blue: 0.47, alpha: 1)
    })
    static let accent = Color(
        red: 0.16,
        green: 0.52,
        blue: 0.57
    )
    static let blue = Color(
        red: 0.28,
        green: 0.43,
        blue: 0.68
    )
    static let brandTeal = Color(red: 0.20, green: 0.58, blue: 0.61)
    static let brandAmber = Color(red: 0.88, green: 0.55, blue: 0.22)
    static let brandLavender = Color(red: 0.57, green: 0.43, blue: 0.66)
    static let brandSlate = Color(red: 0.07, green: 0.16, blue: 0.20)
    static let canvas = Color(nsColor: .windowBackgroundColor)
    static let cardBorder = Color.primary.opacity(0.09)
    static let tileFill = Color.primary.opacity(0.045)
    static let tileBorder = Color.primary.opacity(0.07)
    static let hairline = Color.primary.opacity(0.08)
    static let spectral: [Color] = [
        Color(red: 0.43, green: 0.49, blue: 0.61),
        Color(red: 0.38, green: 0.56, blue: 0.64),
        Color(red: 0.39, green: 0.61, blue: 0.57),
        Color(red: 0.57, green: 0.49, blue: 0.62),
    ]
}
