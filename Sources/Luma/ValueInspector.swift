import SwiftUI
import AppKit
import ReaderCore

struct SourceValueSelection {
    let range: NSRange
    let revision: Int
    let source: String
}

struct SourceReader: View {
    let text: String
    @Bindable var tab: DocumentTab
    let fontSize: Double
    @ViewState private var selection: SourceValueSelection?
    @ViewState private var inspecting = false
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(tr("源码")).font(.caption).foregroundStyle(LumaTheme.muted)
                Spacer(minLength: 0)
                Button {
                    selection = tab.sourceEditor().selectedValue()
                    inspecting = selection != nil
                } label: { Label(tr("解释所选值"), systemImage: "slider.horizontal.3") }
                    .disabled(tab.sourceSelection.length == 0 || tab.sourceSelection.length > 4096 || tab.isLoading)
                    .help(tab.sourceSelection.length > 4096 ? tr("选区过长，请缩小到一个值后再解释") : tr("选中颜色、时间戳、字节大小或转义字符串后查看解释与替换"))
                    .popover(isPresented: $inspecting) {
                        if let selection {
                            ValueInspector(selection: selection, tab: tab) { inspecting = false }
                        }
                    }
            }.buttonStyle(LumaButtonStyle()).padding(.horizontal, 12).padding(.vertical, 6).background(LumaTheme.paper)
            LumaRule()
            SourceView(text: text, tab: tab, fontSize: fontSize)
        }
    }
}

struct ValueInspector: View {
    let selection: SourceValueSelection
    let tab: DocumentTab
    let close: () -> Void
    @ViewState private var kind: ReadableValue.Kind
    @ViewState private var replacement: String
    @ViewState private var decoded: String
    @ViewState private var unit: ReadableValue.TimestampUnit
    @ViewState private var localTime = false
    @ViewState private var error: String?

    init(selection: SourceValueSelection, tab: DocumentTab, close: @escaping () -> Void) {
        self.selection = selection; self.tab = tab; self.close = close
        _kind = ViewState(initialValue: ReadableValue.suggestedKind(selection.source))
        _replacement = ViewState(initialValue: selection.source)
        _decoded = ViewState(initialValue: ReadableValue.decodedString(selection.source) ?? "")
        let numeric = Double(ReadableValue.unquoted(selection.source)) ?? 0
        _unit = ViewState(initialValue: abs(numeric) >= 100_000_000_000 ? .milliseconds : .seconds)
    }
    private var valid: Bool {
        switch kind {
        case .color: ReadableValue.color(replacement) != nil
        case .timestamp: ReadableValue.date(replacement, unit: unit) != nil
        case .bytes: ReadableValue.byteCount(replacement) != nil
        case .string: ReadableValue.decodedString(replacement) != nil
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(tr("解释所选值")).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }.accessibilityLabel(tr("关闭值解释"))
            }
            Text(selection.source).font(.system(.caption, design: .monospaced)).lineLimit(3).textSelection(.enabled)
                .foregroundStyle(LumaTheme.muted)
            Picker(tr("解释方式"), selection: $kind) {
                ForEach(ReadableValue.Kind.allCases, id: \.self) { Text(trKey($0.rawValue)).tag($0) }
            }.onChange(of: kind) { _, _ in
                replacement = selection.source; decoded = ReadableValue.decodedString(selection.source) ?? ""; error = nil
            }
            details
            Divider()
            TextField(tr("替换为"), text: $replacement, axis: .vertical).lineLimit(1...4).textFieldStyle(.roundedBorder)
                .onChange(of: replacement) { _, value in
                    if let value = ReadableValue.decodedString(value), kind == .string, decoded != value { decoded = value }
                }
            if !valid { Text(tr("这个值无法按当前方式解释，请修改内容或切换解释方式。")).font(.caption).foregroundStyle(LumaTheme.warning) }
            if let error { Text(error).font(.caption).foregroundStyle(LumaTheme.warning) }
            Text(tr("解释方式与单位可更正。点击替换后更新草稿，可撤销；保存沿用当前设置。"))
                .font(.caption).foregroundStyle(LumaTheme.muted)
            HStack {
                Spacer()
                Button(tr("替换选中内容")) {
                    if tab.sourceEditor().replaceValue(selection, with: replacement) { close() }
                    else { error = tr("源码或选区状态已变化，请关闭面板后重新选择。") }
                }.disabled(!valid || replacement == selection.source || tab.isLoading || tab.isRenaming)
            }
        }.padding(16).frame(width: 340).foregroundStyle(LumaTheme.ink)
        .background(LumaTheme.paper).buttonStyle(LumaButtonStyle())
    }
    @ViewBuilder private var details: some View {
        switch kind {
        case .color:
            if let rgba = ReadableValue.color(replacement) {
                ColorPicker(tr("颜色"), selection: Binding(get: {
                    Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
                }, set: { color in
                    guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                    let value = ReadableValue.RGBA(red: rgb.redComponent, green: rgb.greenComponent, blue: rgb.blueComponent, alpha: rgb.alphaComponent)
                    replacement = ReadableValue.preservingQuotes(value.hex, original: selection.source)
                }), supportsOpacity: true)
                Text(rgba.hex).monospaced().textSelection(.enabled)
            }
        case .timestamp:
            Picker(tr("单位"), selection: $unit) {
                ForEach(ReadableValue.TimestampUnit.allCases, id: \.self) { Text(trKey($0.rawValue)).tag($0) }
            }.pickerStyle(.segmented)
            Toggle(tr("使用本机时区"), isOn: $localTime).toggleStyle(.checkbox)
            if let date = ReadableValue.date(replacement, unit: unit) {
                let formatter = ISO8601DateFormatter()
                let _ = formatter.timeZone = localTime ? .current : TimeZone(secondsFromGMT: 0)
                let _ = formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                Text(formatter.string(from: date)).font(.system(.body, design: .monospaced)).textSelection(.enabled)
                Text(localTime ? TimeZone.current.identifier : "UTC").font(.caption).foregroundStyle(LumaTheme.muted)
            }
        case .bytes:
            if let bytes = ReadableValue.byteCount(replacement) {
                Text(tr("\(bytes.formatted(.number.precision(.fractionLength(0...3)))) 字节")).textSelection(.enabled)
                Text("\((bytes / 1024).formatted(.number.precision(.fractionLength(0...3)))) KiB · \((bytes / 1_048_576).formatted(.number.precision(.fractionLength(0...3)))) MiB")
                    .font(.caption).foregroundStyle(LumaTheme.muted)
                Text(tr("KB / MB 按 1000 换算；KiB / MiB 按 1024 换算。")).font(.caption)
            }
        case .string:
            Text(tr("解码后的文字")).font(.caption).foregroundStyle(LumaTheme.muted)
            TextEditor(text: $decoded).font(.system(.body, design: .monospaced)).frame(height: 110)
                .border(LumaTheme.controlBorder)
                .onChange(of: decoded) { _, value in
                    // A displayed decoder result is not itself an edit.
                    if ReadableValue.decodedString(replacement) != value {
                        let encoded = ReadableValue.encodeString(value)
                        replacement = selection.source.hasPrefix("\"") ? encoded : String(encoded.dropFirst().dropLast())
                    }
                }
        }
    }
}
