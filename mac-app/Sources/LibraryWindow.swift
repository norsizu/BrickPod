import AppKit

// 曲库管理窗口：左侧按「全部 / 歌手 / 专辑」浏览，右侧歌曲列表（可排序、可改列宽）。
// - 双击单元格改歌名/歌手/专辑；多选后「编辑信息…」批量改；清空某项 = 恢复文件原标签
// - 删除 = 移到废纸篓（只动曲库里的副本）
// 修改都落在 overrides.json，由 AppDelegate 重建曲库 JSON、刷新 iPod 后回调 reload()

/// 按 Delete / ⌦ 删除选中行
final class LibraryTableView: NSTableView {
    var onDelete: (() -> Void)?
    override func keyDown(with event: NSEvent) {
        let key = event.charactersIgnoringModifiers?.unicodeScalars.first?.value
        if key == UInt32(NSDeleteCharacter) || key == UInt32(NSDeleteFunctionKey) {
            onDelete?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// 侧边栏节点（NSOutlineView 需要引用类型做 item）
final class SidebarNode: NSObject {
    enum Kind: Equatable { case all, group, artist, album }
    let kind: Kind
    let title: String
    var count = 0
    var children: [SidebarNode] = []
    init(_ kind: Kind, _ title: String) {
        self.kind = kind
        self.title = title
    }
}

final class LibraryWindowController: NSWindowController, NSWindowDelegate,
    NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate {

    struct Row {
        let order: Int              // 曲库 JSON 里的原始顺序（专辑内按曲目排好）
        let name, artist, album: String
        let durationMs: Int
        let file: URL?
    }

    private let musicDir: URL
    private let jsonURL: URL
    /// 删除/编辑后调用：AppDelegate 负责重建曲库、刷新 iPod，再回调 reload()
    var onChanged: (() -> Void)?
    var onImport: (() -> Void)?

    private var allRows: [Row] = []
    private var rows: [Row] = []                // 侧边栏筛选 + 排序后的可见行
    private var roots: [SidebarNode] = []
    private var current: SidebarNode?

    private let sidebar = NSOutlineView()
    private let table = LibraryTableView()
    private let status = NSTextField(labelWithString: "")
    private var editButton: NSButton!
    private var deleteButton: NSButton!
    private var revealButton: NSButton!

    private static let fieldTitles = ["name": "歌名", "artistName": "歌手", "albumName": "专辑"]
    private static let columnField = ["name": "name", "artist": "artistName", "album": "albumName"]

    init(musicDir: URL, jsonURL: URL) {
        self.musicDir = musicDir
        self.jsonURL = jsonURL
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 820, height: 500),
                         styleMask: [.titled, .closable, .miniaturizable, .resizable],
                         backing: .buffered, defer: false)
        w.title = "曲库"
        w.minSize = NSSize(width: 560, height: 300)
        w.isReleasedWhenClosed = false
        super.init(window: w)
        w.delegate = self
        buildUI()
        w.setFrameAutosaveName("ipod.library")
        if !w.setFrameUsingName("ipod.library") { w.center() }
        reload()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func buildUI() {
        guard let content = window?.contentView else { return }

        // 左：侧边栏
        let sideCol = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("side"))
        sidebar.addTableColumn(sideCol)
        sidebar.outlineTableColumn = sideCol
        sidebar.headerView = nil
        sidebar.style = .sourceList
        sidebar.dataSource = self
        sidebar.delegate = self
        sidebar.floatsGroupRows = false
        sidebar.menu = sidebarMenu()
        let sideScroll = NSScrollView()
        sideScroll.documentView = sidebar
        sideScroll.hasVerticalScroller = true
        sideScroll.drawsBackground = false

        // 右：歌曲表
        let columns: [(id: String, title: String, width: CGFloat)] = [
            ("name", "歌名", 230), ("artist", "歌手", 130), ("album", "专辑", 170), ("time", "时长", 56),
        ]
        for c in columns {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(c.id))
            col.title = c.title
            col.width = c.width
            col.minWidth = c.id == "time" ? 48 : 70
            // 可手动拖列宽，窗口缩放时也跟着变（上一版漏了 userResizingMask，列宽拖不动）
            col.resizingMask = [.autoresizingMask, .userResizingMask]
            col.sortDescriptorPrototype = NSSortDescriptor(key: c.id, ascending: true)
            if c.id == "time" { col.headerCell.alignment = .right }
            table.addTableColumn(col)
        }
        table.dataSource = self
        table.delegate = self
        table.allowsMultipleSelection = true
        table.usesAlternatingRowBackgroundColors = true
        table.style = .inset
        table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        table.autosaveName = "ipod.library.columns"
        table.autosaveTableColumns = true
        table.target = self
        table.doubleAction = #selector(doubleClicked)
        table.onDelete = { [weak self] in self?.deleteSelected() }
        table.menu = rowMenu()
        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.autosaveName = "ipod.library.split"
        split.addArrangedSubview(sideScroll)
        split.addArrangedSubview(scroll)
        split.setHoldingPriority(.defaultLow + 10, forSubviewAt: 0)   // 拉窗口时侧栏不变宽
        sideScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        scroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 360).isActive = true
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)

        // 底栏
        let importButton = NSButton(title: "导入音乐…", target: self, action: #selector(importClicked))
        editButton = NSButton(title: "编辑信息…", target: self, action: #selector(editSelected))
        revealButton = NSButton(title: "在 Finder 中显示", target: self, action: #selector(revealSelected))
        deleteButton = NSButton(title: "移到废纸篓", target: self, action: #selector(deleteSelected))
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        status.lineBreakMode = .byTruncatingTail
        status.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.setContentHuggingPriority(.defaultLow, for: .horizontal)

        // 导入 + 状态靠左，针对选中项的操作靠右
        let bar = NSStackView()
        bar.orientation = .horizontal
        bar.spacing = 8
        bar.setViews([importButton, status], in: .leading)
        bar.setViews([editButton, revealButton, deleteButton], in: .trailing)
        bar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(bar)

        NSLayoutConstraint.activate([
            split.topAnchor.constraint(equalTo: content.topAnchor),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            split.bottomAnchor.constraint(equalTo: bar.topAnchor, constant: -10),
            bar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            bar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            bar.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12),
        ])
        if split.subviews.first?.frame.width ?? 0 < 150 {
            split.setPosition(190, ofDividerAt: 0)
        }
    }

    private func rowMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "编辑信息…", action: #selector(editSelected), keyEquivalent: "").target = self
        m.addItem(withTitle: "在 Finder 中显示", action: #selector(revealSelected), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "移到废纸篓…", action: #selector(deleteSelected), keyEquivalent: "").target = self
        return m
    }

    private func sidebarMenu() -> NSMenu {
        let m = NSMenu()
        m.addItem(withTitle: "编辑信息…", action: #selector(editSidebarItem), keyEquivalent: "").target = self
        m.addItem(withTitle: "在 Finder 中显示", action: #selector(revealSidebarItem), keyEquivalent: "").target = self
        m.addItem(.separator())
        m.addItem(withTitle: "移到废纸篓…", action: #selector(deleteSidebarItem), keyEquivalent: "").target = self
        return m
    }

    // MARK: - 数据

    /// 重新读曲库 JSON（导入/删除/编辑/启动同步之后调用），尽量保留侧栏选择和排序
    func reload() {
        allRows = []
        if let data = try? Data(contentsOf: jsonURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let songs = obj["songs"] as? [[String: Any]] {
            allRows = songs.enumerated().map { i, s in
                Row(order: i,
                    name: s["name"] as? String ?? "?",
                    artist: s["artistName"] as? String ?? "",
                    album: s["albumName"] as? String ?? "",
                    durationMs: s["durationInMillis"] as? Int ?? 0,
                    file: (s["previewUrl"] as? String).flatMap {
                        LibraryBuilder.fileURL(forPreviewUrl: $0, musicDir: musicDir)
                    })
            }
        }
        rebuildSidebar()
        applyFilter()
    }

    private func rebuildSidebar() {
        let keep = current.map { ($0.kind, $0.title) }
        let all = SidebarNode(.all, "全部歌曲")
        all.count = allRows.count
        let artists = SidebarNode(.group, "歌手")
        let albums = SidebarNode(.group, "专辑")
        artists.children = groupNodes(.artist, key: \.artist)
        albums.children = groupNodes(.album, key: \.album)
        roots = [all, artists, albums]

        sidebar.reloadData()
        sidebar.expandItem(artists)
        sidebar.expandItem(albums)

        // 恢复原来的选择；那一项没了（比如整张专辑删了）就回到「全部歌曲」
        let candidates = [all] + artists.children + albums.children
        let target = keep.flatMap { k in candidates.first { $0.kind == k.0 && $0.title == k.1 } } ?? all
        current = target
        let row = sidebar.row(forItem: target)
        if row >= 0 { sidebar.selectRowIndexes([row], byExtendingSelection: false) }
    }

    private func groupNodes(_ kind: SidebarNode.Kind, key: KeyPath<Row, String>) -> [SidebarNode] {
        var counts: [String: Int] = [:]
        for r in allRows { counts[r[keyPath: key], default: 0] += 1 }
        return counts.keys
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .map { let n = SidebarNode(kind, $0); n.count = counts[$0]!; return n }
    }

    private func rows(for node: SidebarNode?) -> [Row] {
        guard let node else { return allRows }
        switch node.kind {
        case .artist: return allRows.filter { $0.artist == node.title }
        case .album: return allRows.filter { $0.album == node.title }
        default: return allRows
        }
    }

    private func applyFilter() {
        rows = sorted(rows(for: current))
        table.reloadData()
        updateStatus()
    }

    private func sorted(_ input: [Row]) -> [Row] {
        guard let sd = table.sortDescriptors.first, let key = sd.key else {
            return input.sorted { $0.order < $1.order }
        }
        func cmp(_ a: String, _ b: String) -> ComparisonResult { a.localizedStandardCompare(b) }
        return input.sorted { a, b in
            let r: ComparisonResult
            switch key {
            case "name": r = cmp(a.name, b.name)
            case "artist": r = cmp(a.artist, b.artist)
            case "album": r = cmp(a.album, b.album)
            default: r = a.durationMs == b.durationMs ? .orderedSame : (a.durationMs < b.durationMs ? .orderedAscending : .orderedDescending)
            }
            if r == .orderedSame { return a.order < b.order }      // 稳定：同值保持曲目顺序
            return sd.ascending ? r == .orderedAscending : r == .orderedDescending
        }
    }

    private func updateStatus() {
        let sel = table.selectedRowIndexes.count
        var text: String
        if allRows.isEmpty {
            text = "曲库是空的，点「导入音乐…」添加"
        } else {
            let albums = Set(rows.map(\.album)).count
            text = "\(rows.count) 首 · \(albums) 张专辑"
            if sel > 0 { text += " · 已选 \(sel) 首" }
        }
        status.stringValue = text
        editButton.isEnabled = sel > 0
        deleteButton.isEnabled = sel > 0
        revealButton.isEnabled = sel > 0
    }

    private func selectedRows() -> [Row] {
        // 右键点在未选中的行上时，以那一行为准（Finder 的习惯）
        let clicked = table.clickedRow
        if clicked >= 0, clicked < rows.count, !table.selectedRowIndexes.contains(clicked) {
            return [rows[clicked]]
        }
        return table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0] : nil }
    }

    /// 侧栏右键点中的歌手/专辑 → 它名下的全部歌
    private func sidebarTargetRows() -> (title: String, rows: [Row])? {
        let r = sidebar.clickedRow >= 0 ? sidebar.clickedRow : sidebar.selectedRow
        guard r >= 0, let node = sidebar.item(atRow: r) as? SidebarNode,
              node.kind == .artist || node.kind == .album
        else { return nil }
        return (node.title, rows(for: node))
    }

    // MARK: - 操作

    @objc private func importClicked() { onImport?() }

    @objc private func revealSelected() { reveal(selectedRows()) }
    @objc private func revealSidebarItem() { if let t = sidebarTargetRows() { reveal(t.rows) } }
    private func reveal(_ rs: [Row]) {
        let files = rs.compactMap(\.file)
        if !files.isEmpty { NSWorkspace.shared.activateFileViewerSelecting(files) }
    }

    @objc func deleteSelected() { confirmDelete(selectedRows(), label: nil) }
    @objc private func deleteSidebarItem() {
        if let t = sidebarTargetRows() { confirmDelete(t.rows, label: "「\(t.title)」的 \(t.rows.count) 首歌") }
    }

    private func confirmDelete(_ sel: [Row], label: String?) {
        guard !sel.isEmpty, let window else { return }
        let a = NSAlert()
        let what = label ?? (sel.count == 1 ? "「\(sel[0].name)」" : "\(sel.count) 首歌")
        a.messageText = "把\(what)移到废纸篓？"
        a.informativeText = "只删除 BrickPod 曲库里的副本，不影响你导入时选的原文件；需要的话可以从废纸篓恢复。"
        a.addButton(withTitle: "移到废纸篓")
        a.addButton(withTitle: "取消")
        a.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self else { return }
            let n = LibraryBuilder.trash(sel.compactMap(\.file), musicDir: self.musicDir)
            print("[library] 移到废纸篓 \(n)/\(sel.count) 个文件")
            self.table.deselectAll(nil)
            self.onChanged?()
        }
    }

    // MARK: 编辑

    @objc private func doubleClicked() {
        let row = table.clickedRow, col = table.clickedColumn
        guard row >= 0, col >= 0,
              Self.columnField[table.tableColumns[col].identifier.rawValue] != nil
        else { return }
        table.editColumn(col, row: row, with: nil, select: true)
    }

    /// 单元格编辑结束（回车 / 点别处）
    @objc private func cellEdited(_ sender: NSTextField) {
        let row = table.row(for: sender), col = table.column(for: sender)
        guard row >= 0, row < rows.count, col >= 0,
              let field = Self.columnField[table.tableColumns[col].identifier.rawValue],
              let file = rows[row].file
        else { return }
        let old = value(rows[row], field)
        let new = sender.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard new != old else { return }
        LibraryBuilder.setOverride(field: field, value: new, files: [file], musicDir: musicDir)
        print("[library] 修改 \(field): \(old) → \(new.isEmpty ? "(恢复原标签)" : new)")
        onChanged?()
    }

    private func value(_ r: Row, _ field: String) -> String {
        switch field {
        case "name": return r.name
        case "artistName": return r.artist
        default: return r.album
        }
    }

    @objc private func editSelected() { batchEdit(selectedRows(), title: nil) }
    @objc private func editSidebarItem() {
        if let t = sidebarTargetRows() { batchEdit(t.rows, title: "「\(t.title)」的 \(t.rows.count) 首歌") }
    }

    /// 批量编辑：值一致的字段预填；不一致的显示"多个值"，留空 = 不改
    private func batchEdit(_ sel: [Row], title: String?) {
        guard !sel.isEmpty, let window else { return }
        let fields = LibraryBuilder.editableFields
        var common: [String: String?] = [:]
        for f in fields {
            let vals = Set(sel.map { value($0, f) })
            common[f] = vals.count == 1 ? vals.first! : nil
        }

        let grid = NSGridView()
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        var inputs: [String: NSTextField] = [:]
        for f in fields {
            let label = NSTextField(labelWithString: (Self.fieldTitles[f] ?? f) + "：")
            label.alignment = .right
            let tf = NSTextField(string: (common[f] ?? nil) ?? "")
            tf.placeholderString = (common[f] ?? nil) == nil ? "多个值（留空不修改）" : "清空则恢复文件原标签"
            tf.widthAnchor.constraint(equalToConstant: 280).isActive = true
            grid.addRow(with: [label, tf])
            inputs[f] = tf
        }
        // 单首歌时歌名可改；多首歌一起改歌名没有意义
        if sel.count > 1, let tf = inputs["name"] {
            tf.isEnabled = false
            tf.stringValue = ""
            tf.placeholderString = "多首歌不能一起改歌名"
        }
        grid.frame = NSRect(x: 0, y: 0, width: 340, height: 100)

        let a = NSAlert()
        a.messageText = "编辑" + (title ?? (sel.count == 1 ? "「\(sel[0].name)」" : " \(sel.count) 首歌的信息"))
        a.informativeText = "只改 BrickPod 里的显示，不改动音频文件。"
        a.accessoryView = grid
        a.addButton(withTitle: "保存")
        a.addButton(withTitle: "取消")
        a.window.initialFirstResponder = sel.count > 1 ? inputs["artistName"] : inputs["name"]
        a.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self else { return }
            let files = sel.compactMap(\.file)
            var changed = false
            for f in fields {
                guard let tf = inputs[f], tf.isEnabled else { continue }
                let new = tf.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if let c = common[f] ?? nil {
                    guard new != c else { continue }          // 原本一致：改了才写（清空 = 恢复原标签）
                } else {
                    guard !new.isEmpty else { continue }       // 原本不一致：留空 = 不改
                }
                LibraryBuilder.setOverride(field: f, value: new, files: files, musicDir: self.musicDir)
                changed = true
            }
            if changed {
                print("[library] 批量编辑 \(files.count) 首")
                self.onChanged?()
            }
        }
    }

    // MARK: - NSTableViewDataSource / Delegate（歌曲表）

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let id = tableColumn?.identifier else { return nil }
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? makeCell(id)
        let r = rows[row]
        let tf = cell.textField!
        switch id.rawValue {
        case "name": tf.stringValue = r.name
        case "artist": tf.stringValue = r.artist
        case "album": tf.stringValue = r.album
        default:
            let sec = r.durationMs / 1000
            tf.stringValue = String(format: "%d:%02d", sec / 60, sec % 60)
        }
        return cell
    }

    private func makeCell(_ id: NSUserInterfaceItemIdentifier) -> NSTableCellView {
        let c = NSTableCellView()
        c.identifier = id
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        tf.translatesAutoresizingMaskIntoConstraints = false
        if id.rawValue == "time" {
            tf.alignment = .right
            tf.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else {
            tf.isEditable = true            // 双击进入编辑
            tf.target = self
            tf.action = #selector(cellEdited(_:))
        }
        c.addSubview(tf)
        c.textField = tf
        NSLayoutConstraint.activate([
            tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
            tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -2),
            tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
        ])
        return c
    }

    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let keep = Set(table.selectedRowIndexes.compactMap { $0 < rows.count ? rows[$0].order : nil })
        rows = sorted(rows)
        table.reloadData()
        let idx = IndexSet(rows.indices.filter { keep.contains(rows[$0].order) })
        table.selectRowIndexes(idx, byExtendingSelection: false)
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if (notification.object as? NSTableView) === table { updateStatus() }
    }

    func debugResetSort() { table.sortDescriptors = [] }

    /// 调试用：进入第一行歌名的编辑状态
    func debugBeginEdit() -> Bool {
        guard !rows.isEmpty else { return false }
        window?.makeKeyAndOrderFront(nil)
        table.editColumn(0, row: 0, with: nil, select: true)
        return true
    }
    /// 调试用：当前编辑框里的文字
    func debugEditorText() -> String? { (window?.firstResponder as? NSTextView)?.string }
    /// 调试用：放弃编辑（不触发保存）
    func debugAbortEdit() {
        ((window?.firstResponder as? NSTextView)?.delegate as? NSTextField)?.abortEditing()
    }

    /// 调试用：模拟点表头排序，返回前几行
    func debugSort(_ key: String, ascending: Bool, take n: Int = 3) -> [String] {
        table.sortDescriptors = [NSSortDescriptor(key: key, ascending: ascending)]
        return rows.prefix(n).map { "\($0.name) \($0.durationMs / 1000)s" }
    }

    // MARK: - NSOutlineViewDataSource / Delegate（侧栏）

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? SidebarNode)?.children.count ?? roots.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        (item as? SidebarNode)?.children[index] ?? roots[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? SidebarNode)?.kind == .group
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
        (item as? SidebarNode)?.kind == .group
    }

    func outlineView(_ outlineView: NSOutlineView, shouldSelectItem item: Any) -> Bool {
        (item as? SidebarNode)?.kind != .group
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? SidebarNode else { return nil }
        if node.kind == .group {
            let id = NSUserInterfaceItemIdentifier("header")
            let v = (outlineView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
                let c = NSTableCellView()
                c.identifier = id
                let tf = NSTextField(labelWithString: "")
                tf.translatesAutoresizingMaskIntoConstraints = false
                c.addSubview(tf)
                c.textField = tf
                NSLayoutConstraint.activate([
                    tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 2),
                    tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
                ])
                return c
            }()
            v.textField?.stringValue = node.title
            return v
        }
        let id = NSUserInterfaceItemIdentifier("item")
        let v = (outlineView.makeView(withIdentifier: id, owner: self) as? SidebarCell) ?? SidebarCell(id)
        v.configure(node)
        return v
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard let node = sidebar.item(atRow: sidebar.selectedRow) as? SidebarNode, node !== current else { return }
        current = node
        table.deselectAll(nil)
        applyFilter()
    }
}

/// 侧栏条目：图标 + 名字 + 右侧歌曲数
final class SidebarCell: NSTableCellView {
    private let countLabel = NSTextField(labelWithString: "")

    init(_ id: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        identifier = id
        let icon = NSImageView()
        let tf = NSTextField(labelWithString: "")
        tf.lineBreakMode = .byTruncatingTail
        countLabel.textColor = .secondaryLabelColor
        countLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        countLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for v in [icon, tf, countLabel] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            addSubview(v)
        }
        imageView = icon
        textField = tf
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.widthAnchor.constraint(equalToConstant: 16),
            icon.heightAnchor.constraint(equalToConstant: 16),
            tf.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 6),
            tf.centerYAnchor.constraint(equalTo: centerYAnchor),
            countLabel.leadingAnchor.constraint(greaterThanOrEqualTo: tf.trailingAnchor, constant: 6),
            countLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            countLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ node: SidebarNode) {
        textField?.stringValue = node.title
        countLabel.stringValue = "\(node.count)"
        let symbol: String
        switch node.kind {
        case .all: symbol = "music.note.list"
        case .artist: symbol = "music.mic"
        default: symbol = "square.stack"
        }
        imageView?.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
    }
}
