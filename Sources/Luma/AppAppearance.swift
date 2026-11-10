import SwiftUI

nonisolated enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }
    @MainActor var title: String {
        switch self {
        case .system: tr("跟随系统")
        case .light: tr("浅色")
        case .dark: tr("深色")
        }
    }
    var symbol: String {
        switch self {
        case .system: "desktopcomputer"
        case .light: "sun.max"
        case .dark: "moon"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

struct AppearancePicker: View {
    @Binding var selection: AppAppearance

    var body: some View {
        Picker(tr("外观"), selection: $selection) {
            ForEach(AppAppearance.allCases) { appearance in
                Label(appearance.title, systemImage: appearance.symbol).tag(appearance)
            }
        }
    }
}
