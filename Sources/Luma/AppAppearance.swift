import SwiftUI

nonisolated enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: Self { self }
    var title: String {
        switch self {
        case .system: "跟随系统"
        case .light: "浅色"
        case .dark: "深色"
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
        Picker("外观", selection: $selection) {
            ForEach(AppAppearance.allCases) { appearance in
                Label(appearance.title, systemImage: appearance.symbol).tag(appearance)
            }
        }
    }
}
