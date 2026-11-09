import SwiftUI

struct DocumentModeSwitch: View {
    static let width: CGFloat = 145
    @Binding var showSource: Bool

    var body: some View {
        HStack(spacing: 3) {
            page("预览", symbol: "book", source: false)
            page("源码", symbol: "chevron.left.forwardslash.chevron.right", source: true)
        }
        .padding(3)
        .background(LumaTheme.chrome, in: RoundedRectangle(cornerRadius: LumaTheme.groupRadius))
        .overlay {
            RoundedRectangle(cornerRadius: LumaTheme.groupRadius)
                .strokeBorder(LumaTheme.line)
                .allowsHitTesting(false)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("文档视图")
    }

    private func page(_ title: String, symbol: String, source: Bool) -> some View {
        let selected = showSource == source
        return Button {
            showSource = source
        } label: {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(DocumentPageStyle(selected: selected))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(source ? "打开可编辑的源码" : "阅读排版后的文档")
    }
}

private struct DocumentPageStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isFocused) private var focused
    @ViewState private var hovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: selected ? .semibold : .medium))
            .foregroundStyle(selected ? LumaTheme.accent : LumaTheme.muted)
            .frame(width: 68, height: 28)
            .background {
                if selected {
                    DocumentPageShape().fill(LumaTheme.control)
                        .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                } else if hovered {
                    RoundedRectangle(cornerRadius: LumaTheme.controlRadius).fill(LumaTheme.hover)
                }
            }
            .lumaFocusRing(focused)
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.72 : 1)
            .onHover { hovered = $0 }
    }
}

nonisolated private struct DocumentPageShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let radius: CGFloat = 6
            path.move(to: CGPoint(x: 0, y: radius))
            path.addQuadCurve(to: CGPoint(x: radius, y: 0), control: .zero)
            path.addLine(to: CGPoint(x: rect.maxX - 7, y: 0))
            path.addLine(to: CGPoint(x: rect.maxX, y: 7))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY),
                              control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: radius, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: 0, y: rect.maxY - radius),
                              control: CGPoint(x: 0, y: rect.maxY))
            path.closeSubpath()
        }
    }
}
