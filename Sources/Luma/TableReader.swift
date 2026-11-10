import SwiftUI
import AppKit
import ReaderCore

struct TableCellSelection: Identifiable {
    let row: Int
    let column: Int
    var id: String { "\(row):\(column)" }
}

@Observable final class TableReadingState {
    enum WidthMode: String, CaseIterable { case comfortable = "舒适列宽", fit = "适合窗口" }
    struct Filter {
        var query = ""
        var values: Set<String>?
        var isActive: Bool { !query.isEmpty || values != nil }
    }
    private(set) var rows: [[String]] = []
    private(set) var columnCount = 0
    private(set) var sourceLines: [Int] = []
    private(set) var revision = 0
    private(set) var visibleRows: [Int] = []
    private(set) var filters: [Int: Filter] = [:]
    private(set) var sortColumn: Int?
    private(set) var ascending = true
    var widthMode = WidthMode.comfortable { didSet { if widthMode != oldValue { columnWidths = [:] } } }
    var expandedCell: TableCellSelection?
    @ObservationIgnored var columnWidths: [Int: CGFloat] = [:]

    var dataCount: Int { max(0, rows.count - 1) }
    var hasConditions: Bool { !filters.isEmpty || sortColumn != nil }
    func title(_ column: Int) -> String {
        let label = rows.first.flatMap { column < $0.count ? $0[column] : nil } ?? ""
        return label.isEmpty ? tr("第 \(column + 1) 列") : label
    }
    func value(row: Int, column: Int) -> String {
        guard rows.indices.contains(row), rows[row].indices.contains(column) else { return "" }
        return rows[row][column]
    }
    func update(_ table: CSVDocument) {
        rows = table.rows; columnCount = table.columnCount; sourceLines = table.sourceLines
        filters = filters.filter { $0.key < columnCount }
        if let sortColumn, sortColumn >= columnCount { self.sortColumn = nil }
        if let cell = expandedCell, !rows.indices.contains(cell.row) || cell.column >= columnCount { expandedCell = nil }
        refresh()
    }
    func setFilter(_ filter: Filter, column: Int) {
        if filter.isActive { filters[column] = filter } else { filters[column] = nil }
        refresh()
    }
    func sort(column: Int, ascending: Bool) {
        sortColumn = column; self.ascending = ascending; refresh()
    }
    func reset() { filters = [:]; sortColumn = nil; refresh() }
    func facets(column: Int) -> [(value: String, count: Int)] {
        let counts = matchingRows(excluding: column).reduce(into: [String: Int]()) { result, row in
            result[value(row: row, column: column), default: 0] += 1
        }
        return counts.map { (value: $0.key, count: $0.value) }.sorted { $0.value.localizedStandardCompare($1.value) == .orderedAscending }
    }
    private func matchingRows(excluding: Int? = nil) -> [Int] {
        guard rows.count > 1 else { return [] }
        return (1..<rows.count).filter { row in
            filters.allSatisfy { column, filter in
                if column == excluding { return true }
                let cell = value(row: row, column: column)
                return (filter.query.isEmpty || cell.localizedCaseInsensitiveContains(filter.query)) &&
                    (filter.values?.contains(cell) ?? true)
            }
        }
    }
    static func number(_ value: String) -> Decimal? {
        guard value.range(of: #"^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$"#, options: .regularExpression) != nil else { return nil }
        return Decimal(string: value, locale: Locale(identifier: "en_US_POSIX"))
    }
    func sourceLine(_ row: Int) -> Int { sourceLines.indices.contains(row) ? sourceLines[row] : row + 1 }
    private func refresh() {
        revision += 1
        var result = matchingRows()
        if let column = sortColumn {
            let numbers = Dictionary(uniqueKeysWithValues: result.compactMap { row in Self.number(value(row: row, column: column)).map { (row, $0) } })
            result.sort { left, right in
                let a = value(row: left, column: column), b = value(row: right, column: column)
                let order: ComparisonResult
                if let x = numbers[left], let y = numbers[right] {
                    order = x == y ? .orderedSame : x < y ? .orderedAscending : .orderedDescending
                } else if numbers[left] != nil { order = .orderedAscending }
                else if numbers[right] != nil { order = .orderedDescending }
                else { order = a.localizedStandardCompare(b) }
                if order == .orderedSame { return left < right }
                return order == (ascending ? .orderedAscending : .orderedDescending)
            }
        }
        visibleRows = result
    }
}

struct TableReader: View {
    @Bindable var state: TableReadingState
    @ViewState private var filterColumn = 0
    @ViewState private var showingFilter = false
    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { recordCount; Spacer(minLength: 0); controls }
                VStack(alignment: .leading, spacing: 4) { recordCount; HStack { controls; Spacer(minLength: 0) } }
            }.buttonStyle(LumaButtonStyle()).padding(.horizontal, 12).padding(.vertical, 7).background(LumaTheme.paper)
            if state.hasConditions {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(state.filters.keys.sorted(), id: \.self) { column in
                            Button { state.setFilter(.init(), column: column) } label: {
                                Label(tr("\(state.title(column)) · 已筛选"), systemImage: "xmark.circle")
                            }.help(tr("移除这一列的筛选"))
                        }
                        if let column = state.sortColumn {
                            Text("\(state.title(column)) · \(state.ascending ? tr("升序") : tr("降序"))").foregroundStyle(LumaTheme.muted)
                        }
                    }.font(.caption).buttonStyle(LumaButtonStyle()).padding(.horizontal, 12).padding(.vertical, 4)
                }
            }
            LumaRule()
            if state.rows.isEmpty {
                ContentUnavailableView(tr("空表格"), systemImage: "tablecells", description: Text(tr("这个文件没有可显示的数据。")))
            } else {
                NativeTableReader(state: state, revision: state.revision, widthMode: state.widthMode, language: AppLocalization.shared.language)
                    .clipped()
                    .overlay {
                        if state.visibleRows.isEmpty && state.dataCount > 0 {
                            ContentUnavailableView(tr("没有匹配的记录"), systemImage: "line.3.horizontal.decrease.circle", description: Text(tr("调整表头筛选，或重置全部条件。")))
                                .allowsHitTesting(false)
                        }
                    }
            }
            LumaRule()
            Text(tr("点击表头筛选或排序 · 拖动表头分隔线调整列宽 · 双击单元格查看全文 · 行号对应源文件起始行"))
                .font(.system(size: 11)).foregroundStyle(LumaTheme.muted).lineLimit(2).padding(7)
        }
        .sheet(item: $state.expandedCell) { cell in
            VStack(alignment: .leading, spacing: 12) {
                Text(tr("源码第 \(state.sourceLine(cell.row)) 行 · \(state.title(cell.column))")).font(.headline).lineLimit(2)
                ScrollView {
                    Text(state.value(row: cell.row, column: cell.column)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }.background(LumaTheme.paper).frame(minHeight: 180)
                HStack {
                    Button(tr("复制完整内容")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(state.value(row: cell.row, column: cell.column), forType: .string)
                    }
                    Spacer()
                    Button(tr("完成")) { state.expandedCell = nil }.keyboardShortcut(.defaultAction)
                }
            }.padding(20).frame(width: 540, height: 380).onExitCommand { state.expandedCell = nil }
        }
    }
    private var recordCount: some View {
        Text(tr("\(state.visibleRows.count.formatted()) / \(state.dataCount.formatted()) 条 · \(state.columnCount) 列"))
            .font(.caption.monospacedDigit()).foregroundStyle(LumaTheme.muted)
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Picker(tr("列宽"), selection: $state.widthMode) {
                ForEach(TableReadingState.WidthMode.allCases, id: \.self) { Text(trKey($0.rawValue)).tag($0) }
            }.labelsHidden().fixedSize().controlSize(.small)
            Menu(tr("列操作")) {
                ForEach(0..<state.columnCount, id: \.self) { column in
                    Button(state.title(column)) { filterColumn = column; showingFilter = true }
                }
            }.fixedSize().disabled(state.columnCount == 0)
            .popover(isPresented: $showingFilter) {
                TableColumnFilterView(state: state, column: filterColumn)
            }
            Button(tr("重置")) { state.reset() }.disabled(!state.hasConditions).help(tr("重置全部筛选与排序"))
        }
    }
}

struct TableColumnFilterView: View {
    let state: TableReadingState
    let column: Int
    @ViewState private var valueQuery = ""
    private var filter: TableReadingState.Filter { state.filters[column] ?? .init() }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(state.title(column)).font(.headline).lineLimit(2)
            HStack {
                Button(tr("升序")) { state.sort(column: column, ascending: true) }
                Button(tr("降序")) { state.sort(column: column, ascending: false) }
                Spacer()
                Button(tr("清除此列")) { state.setFilter(.init(), column: column) }
            }.controlSize(.small)
            TextField(tr("包含文字"), text: Binding(get: { filter.query }, set: { value in
                var next = filter; next.query = value; state.setFilter(next, column: column)
            })).textFieldStyle(.roundedBorder)
            let summaryValues = state.facets(column: column)
            let numbers = summaryValues.compactMap { TableReadingState.number($0.value) }
            Text(tr("空值 \(summaryValues.first(where: { $0.value.isEmpty })?.count ?? 0) · \(summaryValues.count) 种值"))
                .font(.caption).foregroundStyle(.secondary)
            if let low = numbers.min(), let high = numbers.max() {
                Text(tr("数值范围 \(NSDecimalNumber(decimal: low).stringValue) – \(NSDecimalNumber(decimal: high).stringValue)"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Divider()
            HStack {
                Button(tr("全选")) { var next = filter; next.values = nil; state.setFilter(next, column: column) }
                Button(tr("全不选")) { var next = filter; next.values = []; state.setFilter(next, column: column) }
                Spacer()
                Text(tr("值 · 条数")).foregroundStyle(.secondary)
            }.font(.caption)
            TextField(tr("搜索列值"), text: $valueQuery).textFieldStyle(.roundedBorder)
            let values = state.facets(column: column).filter { valueQuery.isEmpty || $0.value.localizedCaseInsensitiveContains(valueQuery) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(values.prefix(200)), id: \.value) { item in
                        Toggle(isOn: Binding(get: { filter.values?.contains(item.value) ?? true }, set: { selected in
                            var next = filter
                            var values = next.values ?? Set(state.facets(column: column).map(\.value))
                            if selected { values.insert(item.value) } else { values.remove(item.value) }
                            next.values = values; state.setFilter(next, column: column)
                        })) {
                            HStack {
                                Text(item.value.isEmpty ? tr("（空值）") : item.value).lineLimit(2)
                                Spacer()
                                Text(item.count.formatted()).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }.toggleStyle(.checkbox)
                    }
                }.padding(.vertical, 4)
            }.frame(height: 200)
            if values.count > 200 { Text(tr("显示前 200 个值，请搜索缩小范围。")).font(.caption).foregroundStyle(.secondary) }
        }.padding(14).frame(width: 310)
    }
}

struct NativeTableReader: NSViewRepresentable {
    let state: TableReadingState
    let revision: Int
    let widthMode: TableReadingState.WidthMode
    var language: AppLanguage = .simplifiedChinese
    func makeCoordinator() -> Coordinator { Coordinator(state: state) }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = TableReadingScrollView()
        let table = NSTableView()
        // The table is already below its own controls, not underneath the window toolbar.
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = .init()
        scroll.drawsBackground = true
        scroll.backgroundColor = LumaTheme.nativePaper
        scroll.focusRingType = .none
        table.focusRingType = .none
        table.delegate = context.coordinator; table.dataSource = context.coordinator
        table.headerView = NSTableHeaderView(); table.rowHeight = 34
        table.intercellSpacing = .zero
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .noColumnAutoresizing
        table.allowsColumnReordering = false
        table.target = context.coordinator; table.doubleAction = #selector(Coordinator.expandCell)
        table.setAccessibilityLabel(tr("数据表格，点击表头筛选，双击单元格查看完整内容"))
        scroll.hasHorizontalScroller = true; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true
        scroll.documentView = table
        context.coordinator.table = table
        scroll.onResize = { [weak coordinator = context.coordinator] width in coordinator?.resize(width: width) }
        context.coordinator.refresh(width: scroll.contentSize.width)
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        scroll.backgroundColor = LumaTheme.nativePaper
        context.coordinator.refresh(width: scroll.contentSize.width)
    }
    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) {
        coordinator.popover?.close(); coordinator.table?.delegate = nil; coordinator.table?.dataSource = nil
    }
    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        let state: TableReadingState
        weak var table: NSTableView?
        var popover: NSPopover?
        private var resizing = false
        func resize(width: CGFloat) {
            guard state.widthMode == .fit else { return }
            refresh(width: width)
        }
        init(state: TableReadingState) { self.state = state }
        func refresh(width: CGFloat) {
            guard let table else { return }
            resizing = true
            defer { resizing = false }
            if table.tableColumns.count != state.columnCount + 1 {
                for column in table.tableColumns { table.removeTableColumn(column) }
                for index in -1..<state.columnCount {
                    let column = NSTableColumn(identifier: .init("\(index)"))
                    column.isEditable = false
                    column.minWidth = index == -1 ? 44 : 72
                    column.maxWidth = index == -1 ? 44 : 1600
                    table.addTableColumn(column)
                }
            }
            for (index, column) in table.tableColumns.enumerated() {
                let dataColumn = index - 1
                if dataColumn < 0 { column.title = "#"; column.width = 44; continue }
                let suffix = state.sortColumn == dataColumn ? (state.ascending ? " ↑" : " ↓") : ""
                column.title = state.title(dataColumn) + (state.filters[dataColumn] == nil ? "" : " •") + suffix
                column.width = state.columnWidths[dataColumn] ?? (state.widthMode == .fit ? max(72, (width - 44) / CGFloat(max(1, state.columnCount))) : 194)
            }
            table.backgroundColor = LumaTheme.nativePaper
            table.reloadData()
        }
        func numberOfRows(in tableView: NSTableView) -> Int { state.visibleRows.count }
        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            guard let raw = tableColumn?.identifier.rawValue, let column = Int(raw), state.visibleRows.indices.contains(row) else { return nil }
            let original = state.visibleRows[row]
            let cell = NSTextField(labelWithString: column < 0 ? "\(state.sourceLine(original))" : state.value(row: original, column: column).replacingOccurrences(of: "\n", with: " ↵ "))
            cell.font = .systemFont(ofSize: 12)
            cell.textColor = column < 0 ? .secondaryLabelColor : LumaTheme.nativeInk
            cell.lineBreakMode = .byTruncatingTail
            cell.toolTip = column < 0 ? tr("源码第 \(state.sourceLine(original)) 行") : state.value(row: original, column: column)
            cell.setAccessibilityLabel(column < 0 ? tr("源码第 \(state.sourceLine(original)) 行") : "\(state.title(column))：\(state.value(row: original, column: column))")
            return cell
        }
        func tableView(_ tableView: NSTableView, didClick tableColumn: NSTableColumn) {
            guard let column = Int(tableColumn.identifier.rawValue), column >= 0, let header = tableView.headerView else { return }
            popover?.close()
            let popover = NSPopover(); popover.behavior = .semitransient
            popover.contentViewController = NSHostingController(rootView: TableColumnFilterView(state: state, column: column))
            self.popover = popover
            let position = tableView.column(withIdentifier: tableColumn.identifier)
            popover.show(relativeTo: header.headerRect(ofColumn: position), of: header, preferredEdge: .maxY)
        }
        func tableViewColumnDidResize(_ notification: Notification) {
            guard !resizing, let table else { return }
            for column in table.tableColumns {
                if let index = Int(column.identifier.rawValue), index >= 0 { state.columnWidths[index] = column.width }
            }
        }
        @objc func expandCell() {
            guard let table, state.visibleRows.indices.contains(table.clickedRow), table.clickedColumn > 0 else { return }
            state.expandedCell = .init(row: state.visibleRows[table.clickedRow], column: table.clickedColumn - 1)
        }
    }
}

private final class TableReadingScrollView: NSScrollView {
    var onResize: ((CGFloat) -> Void)?
    override func setFrameSize(_ newSize: NSSize) {
        let previous = frame.width
        super.setFrameSize(newSize)
        tile()
        if abs(previous - newSize.width) > 0.5 { onResize?(contentSize.width) }
    }
}
