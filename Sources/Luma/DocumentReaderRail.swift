import SwiftUI
import AppKit

struct DocumentInformation {
    let format: String
    let characterCount: Int?
    let sourceByteCount: Int?
    let encoding: String

    init(tab: DocumentTab) {
        var source = tab.draft
        if source == nil, case .ready(let content) = tab.state { source = content.source }
        switch tab.kind {
        case .image: format = "\(tab.url.pathExtension.uppercased()) 图片"
        case .table: format = tab.url.pathExtension.uppercased()
        case .unsupported:
            format = tab.url.pathExtension.isEmpty ? tr("未知格式") : tr("\(tab.url.pathExtension.uppercased()) 文件")
        default: format = tab.codeLanguage?.title ?? tab.kind.label
        }
        characterCount = source?.count
        sourceByteCount = source?.utf8.count
        if source != nil { encoding = tab.diskSnapshot?.hasBOM == true ? trKey("UTF-8（BOM）") : "UTF-8" }
        else { encoding = tab.kind.hasSource ? tr("未识别") : tr("不适用") }
    }
}

/// One shared column for file actions and, in Markdown preview, the chapter rail.
struct DocumentReaderRail<Navigation: View>: View {
    let tab: DocumentTab
    let workspace: Workspace
    @Binding var showingInformation: Bool
    var navigationHeight: CGFloat?
    var reveal: (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    @ViewBuilder let navigation: () -> Navigation

    var body: some View {
        GeometryReader { geometry in
            let actionsHeight: CGFloat = 62
            let separation: CGFloat = navigationHeight == nil ? 0 : 20
            let height = navigationHeight.map { min($0, max(0, geometry.size.height - actionsHeight - separation - 32)) }
            let top = height.map { max(16, (geometry.size.height - actionsHeight - separation - $0) / 2) }
                ?? max(8, (geometry.size.height - actionsHeight) / 2)
            VStack(spacing: separation) {
                VStack(spacing: 2) {
                    DocumentRailButton(symbol: "info.circle", label: tr("文件信息"), identifier: "documentInformation",
                                       selected: showingInformation, hover: { showingInformation = $0 }) {
                        showingInformation = true
                    }
                    .frame(width: 30, height: 30)
                    DocumentRailButton(symbol: "folder", label: tr("在 Finder 中显示"),
                                       identifier: "revealDocumentInFinder") { reveal(tab.url) }
                        .frame(width: 30, height: 30)
                }
                .frame(height: actionsHeight)
                if let height {
                    navigation().frame(width: 38, height: height)
                }
            }
            .padding(.top, top)
            .frame(width: 38, height: geometry.size.height, alignment: .top)
            .overlay(alignment: .topLeading) {
                if showingInformation {
                    DocumentInformationCard(tab: tab, workspace: workspace)
                        .frame(width: 248)
                        .fixedSize(horizontal: false, vertical: true)
                        .offset(x: 44, y: min(top, max(8, geometry.size.height - 244)))
                        .allowsHitTesting(false)
                }
            }
        }
        .frame(width: 38)
        .background(LumaTheme.paper)
        .zIndex(1)
        .onExitCommand { showingInformation = false }
    }
}

private struct DocumentInformationCard: View {
    let tab: DocumentTab
    let workspace: Workspace

    var body: some View {
        let information = DocumentInformation(tab: tab)
        VStack(alignment: .leading, spacing: 12) {
            Label(tab.title, systemImage: tab.kind.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(LumaTheme.ink)
                .lineLimit(2).truncationMode(.middle)
            VStack(spacing: 7) {
                row(tr("类型"), information.format)
                row(tr("字符数"), information.characterCount.map { $0.formatted() } ?? tr("不适用"))
                row(tr("编码"), information.encoding)
                if let bytes = information.sourceByteCount { row(tr("源码大小"), tr("\(bytes.formatted()) 字节")) }
            }
            if information.characterCount != nil {
                LumaRule()
                VStack(alignment: .leading, spacing: 5) {
                    Text(tr("按当前源码统计，含空格与换行"))
                        .foregroundStyle(LumaTheme.muted)
                    Text(tab.isSaving ? tr("正在保存…") : tab.externalChange ? tr("磁盘文件已变化") : tab.isDirty ? tr("未保存") : tr("已保存"))
                        .foregroundStyle(tab.isDirty || tab.externalChange ? LumaTheme.warning : LumaTheme.muted)
                    if workspace.autoSaveEnabled {
                        Text(tab.autoSaveError == nil ? tr("自动保存已开启") : tr("自动保存已暂停"))
                            .foregroundStyle(tab.autoSaveError == nil ? LumaTheme.muted : LumaTheme.warning)
                    }
                }.font(.system(size: 11))
            }
        }
        .padding(13)
        .background(LumaTheme.control, in: RoundedRectangle(cornerRadius: LumaTheme.groupRadius))
        .overlay { RoundedRectangle(cornerRadius: LumaTheme.groupRadius).strokeBorder(LumaTheme.controlBorder) }
        .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("documentInformationCard")
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label).foregroundStyle(LumaTheme.muted).frame(width: 52, alignment: .leading)
            Text(value).foregroundStyle(LumaTheme.ink).monospacedDigit()
            Spacer(minLength: 0)
        }.font(.system(size: 12))
    }
}

/// Native tracking keeps hover independent of keyboard focus and the WebKit reader.
struct DocumentRailButton: NSViewRepresentable {
    let symbol: String
    let label: String
    let identifier: String
    var selected = false
    var hover: ((Bool) -> Void)?
    let action: () -> Void

    func makeNSView(context: Context) -> DocumentRailNativeButton {
        let button = DocumentRailNativeButton(frame: .zero)
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.imagePosition = .imageOnly
        button.focusRingType = .default
        button.wantsLayer = true
        button.layer?.cornerRadius = LumaTheme.controlRadius
        button.target = button
        button.action = #selector(DocumentRailNativeButton.invoke)
        updateNSView(button, context: context)
        return button
    }

    func updateNSView(_ button: DocumentRailNativeButton, context: Context) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        if button.symbolName != symbol {
            button.symbolName = symbol
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(.init(pointSize: 14, weight: .regular))
        }
        button.setAccessibilityLabel(label)
        button.setAccessibilityHelp(hover == nil ? label : tr("悬停查看文件信息，移开收起；也可按空格查看。"))
        button.toolTip = hover == nil ? label : nil
        button.onHover = hover
        button.onAction = action
        button.selected = selected
    }
}

final class DocumentRailNativeButton: NSButton {
    var symbolName = ""
    var onHover: ((Bool) -> Void)?
    var onAction: (() -> Void)?
    var selected = false { didSet { updateColors() } }
    private var hovered = false
    private var tracking: NSTrackingArea?

    @objc func invoke() { onAction?() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        tracking = area
    }
    override func mouseEntered(with event: NSEvent) {
        hovered = true; updateColors(); onHover?(true)
    }
    override func mouseExited(with event: NSEvent) {
        hovered = false; updateColors(); onHover?(false)
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }
    private func updateColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            contentTintColor = selected ? LumaTheme.nativeAccent : LumaTheme.nativeInk.withAlphaComponent(0.75)
            layer?.backgroundColor = LumaTheme.nativeAccent.withAlphaComponent(selected ? 0.16 : hovered ? 0.09 : 0).cgColor
        }
    }
}
