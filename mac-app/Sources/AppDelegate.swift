import AppKit
import WebKit

// 无边框透明窗口：窗口本身就是 iPod（桌面配件风）
final class PanelWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

// 右键菜单替换成 App 自己的（默认是 WebKit 的"重新载入/检查元素"）
final class IPodWebView: WKWebView {
    var contextMenuProvider: (() -> NSMenu)?

    // 整机拖动：按下时先照常交给页面；app.html 判定按在机身（滚轮圆外）上，
    // 会发 drag 消息过来，这时用记下的按下事件拖窗口
    private var lastMouseDown: NSEvent?
    override func mouseDown(with event: NSEvent) {
        lastMouseDown = event
        super.mouseDown(with: event)
    }
    override func mouseUp(with event: NSEvent) {
        lastMouseDown = nil
        super.mouseUp(with: event)
    }
    func beginWindowDrag() {
        // 消息是异步到的：鼠标已经松开（快速点击）就不拖了
        guard let down = lastMouseDown, let window, NSEvent.pressedMouseButtons & 1 != 0 else { return }
        lastMouseDown = nil
        window.performDrag(with: down)
        // performDrag 自己吃掉了松开事件，补一个给页面，免得它以为鼠标还按着
        let loc = window.mouseLocationOutsideOfEventStream
        if let up = NSEvent.mouseEvent(with: .leftMouseUp, location: loc, modifierFlags: [],
                                       timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil,
                                       eventNumber: 0, clickCount: 1, pressure: 0) {
            super.mouseUp(with: up)
        }
    }

    // WKWebView 自己注册了文件拖放类型，最深层的注册视图会拿到事件，
    // 外层 DropView 永远收不到 —— 这里整套转交给它
    private var dropTarget: DropView? { superview as? DropView }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.draggingEntered(sender) ?? []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        dropTarget?.draggingUpdated(sender) ?? []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        dropTarget?.draggingExited(sender)
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.prepareForDragOperation(sender) ?? false
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        dropTarget?.performDragOperation(sender) ?? false
    }
    override func concludeDragOperation(_ sender: NSDraggingInfo?) {}
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        guard let custom = contextMenuProvider?() else { return }
        menu.removeAllItems()
        for item in custom.items {
            custom.removeItem(item)
            menu.addItem(item)
        }
    }
}

// 关闭按钮：Dashboard 小部件风格（黑圆底 + 白 ✕ + 白描边），自绘不靠 layer 属性，
// 鼠标进入窗口时浮现，悬停加深
final class CloseButton: NSButton {
    private var hovering = false { didSet { needsDisplay = true } }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        title = ""
        isBordered = false
        setButtonType(.momentaryChange)
        toolTip = "关闭 BrickPod"
    }
    required init?(coder: NSCoder) { fatalError() }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1.5, dy: 1.5)
        let circle = NSBezierPath(ovalIn: r)
        NSColor.black.withAlphaComponent(hovering || isHighlighted ? 0.92 : 0.72).setFill()
        circle.fill()
        NSColor.white.setStroke()
        circle.lineWidth = 1.5
        circle.stroke()

        let k = r.width * 0.21
        let x = NSBezierPath()
        x.move(to: NSPoint(x: r.midX - k, y: r.midY - k))
        x.line(to: NSPoint(x: r.midX + k, y: r.midY + k))
        x.move(to: NSPoint(x: r.midX - k, y: r.midY + k))
        x.line(to: NSPoint(x: r.midX + k, y: r.midY - k))
        x.lineWidth = 1.8
        x.lineCapStyle = .round
        x.stroke()
    }
}

// 内容宿主：接管整窗的文件拖放（WKWebView 默认会把拖进来的文件当导航目标，
// 那是灾难），并承载关闭按钮/遮罩提示/拖拽条的布局
final class DropView: NSView {
    var onImport: (([URL]) -> Void)?
    private var importing = false
    private let overlay = NSTextField(labelWithString: "")
    let closeBtn = CloseButton()
    private var hover = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])

        overlay.font = .systemFont(ofSize: 13, weight: .medium)
        overlay.textColor = .white
        overlay.alignment = .center
        overlay.wantsLayer = true
        overlay.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.72).cgColor
        overlay.layer?.cornerRadius = 9
        overlay.layer?.masksToBounds = true
        overlay.isHidden = true
        addSubview(overlay)

        closeBtn.target = self
        closeBtn.action = #selector(closeClicked)
        closeBtn.alphaValue = 0
        addSubview(closeBtn)
    }
    required init?(coder: NSCoder) { fatalError() }

    @objc private func closeClicked() { window?.close() }

    func setImporting(_ on: Bool) {
        importing = on
        if on { showOverlay("正在导入曲库…") } else { hideOverlay() }
    }

    private func showOverlay(_ text: String) {
        overlay.stringValue = text
        overlay.sizeToFit()
        overlay.frame = overlay.frame.insetBy(dx: -14, dy: -7)
        overlay.frame.origin.x = bounds.midX - overlay.frame.width / 2
        overlay.frame.origin.y = bounds.midY - overlay.frame.height / 2
        overlay.isHidden = false
    }
    private func hideOverlay() {
        if !importing { overlay.isHidden = true }
    }

    override func layout() {
        super.layout()
        subviews.first?.frame = bounds      // webView 铺满
        closeBtn.frame.origin = NSPoint(x: 8, y: bounds.height - 30)
    }

    // 悬停整窗 → 浮现关闭按钮
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways],
                                       owner: self, userInfo: nil))
    }
    override func mouseEntered(with event: NSEvent) {
        hover = true
        revealClose(true)
    }
    override func mouseExited(with event: NSEvent) {
        hover = false
        revealClose(false)
    }
    private func revealClose(_ show: Bool) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            closeBtn.animator().alphaValue = show ? 1 : 0
        }
    }

    // MARK: 拖放导入

    private func draggedURLs(_ sender: NSDraggingInfo) -> [URL] {
        let pb = sender.draggingPasteboard
        let opts: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let urls = (pb.readObjects(forClasses: [NSURL.self], options: opts) as? [URL]) ?? []
        return urls.filter { LibraryBuilder.isAudio($0) || hasDirectoryKey($0) }
    }
    private func hasDirectoryKey(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !importing, !draggedURLs(sender).isEmpty else { return [] }
        showOverlay("松手导入音乐")
        revealClose(true)
        return .copy
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !importing, !draggedURLs(sender).isEmpty else { return [] }
        return .copy
    }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        hideOverlay()
        if !hover { revealClose(false) }
    }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = draggedURLs(sender)
        hideOverlay()
        guard !urls.isEmpty else { return false }
        onImport?(urls)
        return true
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSWindowDelegate {
    private var server: LocalHTTPServer!
    private var window: NSWindow!
    private var webView: WKWebView!
    private var content: DropView!
    private var libraryWC: LibraryWindowController?
    private var floatItem: NSMenuItem!
    private var sizeItems: [NSMenuItem] = []

    private let pad: CGFloat = 14          // app.html 里的 PAD（窗口呼吸边）
    // 组件实测总高（倒影两处都隐藏后 ≈692）。上次实测值存起来，窗口一创建就是准确尺寸；
    // 写错了窗口会先按错的高度出现、再缩，设备看起来"往下跳一下"
    private var totalH: CGFloat = {
        let h = UserDefaults.standard.double(forKey: "ipod.totalH")
        return h > 600 && h < 900 ? CGFloat(h) : 692
    }()
    private var scale: CGFloat = 1.0
    private var bootAttempts = 0

    // 曲库不进 .app bundle：落在 Application Support，重建 App 不丢歌
    private var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BrickPod", isDirectory: true)
    }
    private var musicDir: URL { appSupport.appendingPathComponent("music", isDirectory: true) }
    private var libraryJSON: URL { appSupport.appendingPathComponent("en-US.json") }

    // 尺寸档位（菜单里的 小/中/大）
    private let sizeOptions: [(label: String, scale: CGFloat, key: String)] = [
        ("小", 0.8, "1"), ("中", 1.0, "2"), ("大", 1.25, "3"),
    ]

    private enum Key {
        static let topLeft = "ipod.frameTopLeft"   // "x,maxY"：存左上角，换尺寸档后顶边不跑
        static let scale = "ipod.scale"
        static let floating = "ipod.floating"
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        migrateFromIPodName()
        // webroot：默认用 .app bundle 内 Resources/webroot；开发时可 IPOD_ROOT=/path 指向项目目录
        let env = ProcessInfo.processInfo.environment
        let devRoot = env["IPOD_ROOT"].flatMap { $0.isEmpty ? nil : $0 }
        let root: URL
        if let p = devRoot {
            root = URL(fileURLWithPath: p)
        } else if let r = Bundle.main.resourceURL?.appendingPathComponent("webroot", isDirectory: true) {
            root = r
        } else {
            fatalError("找不到资源目录")
        }

        // 曲库目录就位 + server（dev 模式不覆盖，直接用项目目录里的曲库）
        let fm = FileManager.default
        try? fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        let overrides: (music: URL, json: URL)?
        if devRoot == nil { overrides = (musicDir, libraryJSON) } else { overrides = nil }
        let firstRun = overrides != nil && !fm.fileExists(atPath: libraryJSON.path)
        if firstRun { _ = try? LibraryBuilder.rebuild(musicDir: musicDir, writing: libraryJSON) }

        server = LocalHTTPServer(rootURL: root,
                                 musicDir: overrides?.music,
                                 libraryJSON: overrides?.json)
        do {
            let port: UInt16 = try server.start()
            buildMenu()
            // app.html：无边框透明窗口专用宿主页（项目根目录，rsync 会带进 bundle）
            buildWindow(url: URL(string: "http://127.0.0.1:\(port)/app.html")!)
            print("[server] webroot=\(root.path) url=http://127.0.0.1:\(port)/app.html")
            print("[library] music=\(musicDir.path)")
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法启动本地服务器"
            alert.informativeText = "\(error)"
            alert.runModal()
            NSApp.terminate(nil)
        }

        // 首启迁移：曲库为空时自动导入 .app 旁边的项目 Music/（本机开发场景）
        if firstRun {
            var candidates: [URL] = []
            if let p = env["IPOD_IMPORT"], !p.isEmpty {
                candidates = [URL(fileURLWithPath: p)]
            } else {
                let projectMusic = Bundle.main.bundleURL
                    .deletingLastPathComponent()   // mac-app/
                    .deletingLastPathComponent()   // apple-ipod-404/
                    .appendingPathComponent("Music")
                if fm.fileExists(atPath: projectMusic.path) { candidates = [projectMusic] }
            }
            if let first = candidates.first {
                importFrom(urls: [first])
            }
        } else if overrides != nil {
            syncLibrary(reason: "启动同步")
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 改名（iPod → BrickPod）迁移，只在新位置还没有数据时做一次：
    /// - 曲库文件夹 Application Support/iPod → Application Support/BrickPod（整体移动）
    /// - 设置（窗口位置/尺寸档/置顶/曲库窗口状态）从旧 bundle id 的偏好里复制过来
    private func migrateFromIPodName() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("iPod"), new = appSupport
        if !fm.fileExists(atPath: new.path), fm.fileExists(atPath: old.path) {
            do {
                try fm.moveItem(at: old, to: new)
                print("[migrate] 曲库 \(old.path) → \(new.path)")
            } catch {
                print("[migrate] 曲库迁移失败: \(error)")
            }
        }
        let ud = UserDefaults.standard
        guard ud.object(forKey: "brickpod.migrated") == nil else { return }
        if let legacy = UserDefaults(suiteName: "local.nanxian.ipod")?.persistentDomain(forName: "local.nanxian.ipod") {
            var n = 0
            for (k, v) in legacy where k.hasPrefix("ipod.") || k.hasPrefix("NSWindow Frame ipod")
                || k.hasPrefix("NSTableView") || k.hasPrefix("NSSplitView") {
                if ud.object(forKey: k) == nil { ud.set(v, forKey: k); n += 1 }
            }
            print("[migrate] 从 local.nanxian.ipod 复制了 \(n) 项设置")
        }
        ud.set(true, forKey: "brickpod.migrated")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { window.makeKeyAndOrderFront(nil) }
        return true
    }

    // MARK: - 窗口 + WebView

    private func buildWindow(url: URL) {
        scale = fittedScale(savedScale(), totalH: totalH)
        let size = NSSize(width: 440 * scale + pad * 2, height: totalH * scale + pad * 2)

        // 位置：记住的 > 屏幕右侧竖直居中（桌面配件习惯位）
        let frame: NSRect
        if let tl = savedTopLeft() {
            let origin = NSPoint(x: tl.x, y: tl.y - size.height)
            frame = NSRect(origin: clampToScreen(origin, size: size), size: size)
        } else if let vf = NSScreen.main?.visibleFrame {
            frame = NSRect(x: vf.maxX - size.width - 48,
                           y: vf.midY - size.height / 2,
                           width: size.width, height: size.height)
        } else {
            frame = NSRect(x: 200, y: 200, width: size.width, height: size.height)
        }

        let w = PanelWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false                  // 设备自带 CSS 投影，避免双重阴影
        w.isMovableByWindowBackground = true // 配合额头拖拽条
        w.level = UserDefaults.standard.bool(forKey: Key.floating) ? .floating : .normal
        w.delegate = self
        w.makeKeyAndOrderFront(nil)
        window = w

        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        // 把页面 console.error/warn 转发到 stdout，方便从终端跑时排障
        config.userContentController.addUserScript(
            WKUserScript(source: Self.consoleHook, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        config.userContentController.add(self, name: "log")
        config.userContentController.add(self, name: "drag")
        // 缩放值在页面加载前注入，app.html 首帧就按它排版（不再先大后小）
        config.userContentController.addUserScript(
            WKUserScript(source: "window.__ipodInitialScale = \(scale);",
                         injectionTime: .atDocumentStart, forMainFrameOnly: true))

        let wv = IPodWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        wv.contextMenuProvider = { [weak self] in self?.contextMenu() ?? NSMenu() }
        webView = wv
        webView.setValue(false, forKey: "drawsBackground")   // 透明底：窗口=设备本体
        webView.underPageBackgroundColor = .clear
        webView.navigationDelegate = self

        // DropView 接管拖放（并防止 WKWebView 把拖入文件当导航）
        content = DropView(frame: NSRect(origin: .zero, size: size))
        content.autoresizingMask = []
        content.addSubview(webView, positioned: .below, relativeTo: nil)   // 垫底：关闭钮/遮罩要浮在上面
        w.contentView = content
        content.onImport = { [weak self] urls in self?.importFrom(urls: urls) }
        content.layout()


        webView.load(URLRequest(url: url))
    }

    // MARK: - 菜单

    private func buildMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem(title: "BrickPod", action: nil, keyEquivalent: "")
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 BrickPod", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "关闭", action: #selector(closeWindow), keyEquivalent: "w")
        appMenu.addItem(withTitle: "退出 BrickPod", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let fileItem = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        let fileMenu = NSMenu()
        fileMenu.addItem(withTitle: "导入音乐…", action: #selector(importPanel), keyEquivalent: "o")
        fileMenu.addItem(withTitle: "管理曲库…", action: #selector(showLibrary), keyEquivalent: "l")
        fileMenu.addItem(withTitle: "打开曲库文件夹", action: #selector(revealMusic), keyEquivalent: "")
        fileMenu.addItem(withTitle: "清空曲库…", action: #selector(clearLibrary), keyEquivalent: "")
        fileMenu.addItem(NSMenuItem.separator())
        fileMenu.addItem(withTitle: "重新加载", action: #selector(reloadPage), keyEquivalent: "r")
        fileItem.submenu = fileMenu
        main.addItem(fileItem)

        // 标准「编辑」菜单：⌘V/⌘C/⌘X/⌘A/⌘Z 靠这些菜单项沿响应链转发给输入框，
        // 没有它曲库窗口里编辑时粘贴不进去
        let editItem = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)

        let viewItem = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu()
        floatItem = NSMenuItem(title: "悬浮在最前", action: #selector(toggleFloat), keyEquivalent: "t")
        floatItem.state = UserDefaults.standard.bool(forKey: Key.floating) ? .on : .off
        viewMenu.addItem(floatItem)
        viewMenu.addItem(NSMenuItem.separator())
        for opt in sizeOptions {
            let item = NSMenuItem(title: "尺寸 · " + opt.label,
                                  action: #selector(setSize(_:)), keyEquivalent: opt.key)
            item.target = self
            item.tag = sizeItems.count
            viewMenu.addItem(item)
            sizeItems.append(item)
        }
        viewItem.submenu = viewMenu
        main.addItem(viewItem)

        NSApp.mainMenu = main
        updateSizeChecks()
    }

    @objc private func closeWindow() { window.close() }

    @objc private func reloadPage() { webView.reload() }

    // MARK: - 曲库导入/管理

    @objc private func importPanel() {
        let p = NSOpenPanel()
        p.message = "选择音频文件或包含音乐的文件夹（可多选）"
        p.prompt = "导入"
        p.allowsMultipleSelection = true
        p.canChooseFiles = true
        p.canChooseDirectories = true
        p.level = .floating
        let host = (libraryWC?.window?.isKeyWindow == true ? libraryWC?.window : nil) ?? window!
        p.beginSheetModal(for: host) { [weak self] resp in
            guard resp == .OK, let self else { return }
            self.importFrom(urls: p.urls)
        }
    }

    @objc private func revealMusic() {
        NSWorkspace.shared.open(musicDir)
    }

    @objc private func clearLibrary() {
        let a = NSAlert()
        a.messageText = "清空曲库"
        a.informativeText = "曲库里的全部歌曲会移到废纸篓（可恢复）。只删除 BrickPod 曲库里的副本，不影响你导入时选的原文件。"
        a.addButton(withTitle: "全部移到废纸篓")
        a.addButton(withTitle: "取消")
        a.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self else { return }
            let items = (try? FileManager.default.contentsOfDirectory(
                at: self.musicDir, includingPropertiesForKeys: nil)) ?? []
            for item in items where !item.lastPathComponent.hasPrefix(".") {
                try? FileManager.default.trashItem(at: item, resultingItemURL: nil)
            }
            self.syncLibrary(reason: "清空曲库")
        }
    }

    @objc private func showLibrary() {
        if libraryWC == nil {
            let wc = LibraryWindowController(musicDir: musicDir, jsonURL: libraryJSON)
            wc.onChanged = { [weak self] in self?.syncLibrary(reason: "曲库修改") }
            wc.onImport = { [weak self] in self?.importPanel() }
            libraryWC = wc
        }
        libraryWC?.reload()
        libraryWC?.showWindow(nil)
        libraryWC?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// 按曲库文件夹重建 JSON；内容有变化才刷新 iPod（避免无谓打断播放）
    private func syncLibrary(reason: String) {
        let musicDir = self.musicDir, jsonURL = self.libraryJSON
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let c = try? LibraryBuilder.rebuild(musicDir: musicDir, writing: jsonURL)
            DispatchQueue.main.async {
                guard let self, let c else { return }
                print("[library] \(reason): \(c.songs) 首\(c.changed ? "，已更新" : "，无变化")")
                self.libraryWC?.reload()
                if c.changed { self.webView.reload() }
            }
        }
    }

    /// 拷入 → 重建 JSON → 重载页面
    private func importFrom(urls: [URL]) {
        content.setImporting(true)
        let musicDir = self.musicDir
        let jsonURL = self.libraryJSON
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let copied = LibraryBuilder.importURLs(urls, into: musicDir)
            do {
                let c = try LibraryBuilder.rebuild(musicDir: musicDir, writing: jsonURL)
                DispatchQueue.main.async {
                    self?.content.setImporting(false)
                    print("[library] 新增 \(copied) 个文件 → \(c.songs) 首 / \(c.artists) 位艺术家 / \(c.playlists) 个播放列表")
                    self?.libraryWC?.reload()
                    if c.changed { self?.webView.reload() }
                }
            } catch {
                DispatchQueue.main.async {
                    self?.content.setImporting(false)
                    print("[library] 重建失败: \(error.localizedDescription)")
                }
            }
        }
    }


    @objc private func toggleFloat() {
        let on = floatItem.state == .on
        floatItem.state = on ? .off : .on
        window.level = on ? .normal : .floating
        UserDefaults.standard.set(!on, forKey: Key.floating)
    }

    @objc private func setSize(_ sender: NSMenuItem) {
        guard sizeOptions.indices.contains(sender.tag) else { return }
        applyScale(sizeOptions[sender.tag].scale)
    }

    /// 右键菜单：每次现建（勾选状态跟当前一致）
    private func contextMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector, tag: Int = 0, on: Bool = false) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
            item.target = self
            item.tag = tag
            item.state = on ? .on : .off
            m.addItem(item)
            return item
        }
        _ = add("导入音乐…", #selector(importPanel))
        _ = add("管理曲库…", #selector(showLibrary))
        m.addItem(.separator())
        for (i, opt) in sizeOptions.enumerated() {
            _ = add("尺寸 · " + opt.label, #selector(setSize(_:)), tag: i,
                    on: abs(opt.scale - scale) < 0.01)
        }
        _ = add("悬浮在最前", #selector(toggleFloat), on: window.level == .floating)
        m.addItem(.separator())
        _ = add("退出 BrickPod", #selector(quitApp))
        return m
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func updateSizeChecks() {
        for (i, item) in sizeItems.enumerated() {
            item.state = abs(sizeOptions[i].scale - scale) < 0.01 ? .on : .off
        }
    }

    // MARK: - 缩放（窗口尺寸跟着设备走，无边框无拉伸）

    /// 屏幕装不下时降到能完整放下的最大档位（手动选大档仍允许超出）
    private func fittedScale(_ k: CGFloat, totalH: CGFloat) -> CGFloat {
        guard let vf = NSScreen.main?.visibleFrame, totalH > 100 else { return k }
        let maxK = min((vf.height - 8 - pad * 2) / totalH, (vf.width - 8 - pad * 2) / 440)
        guard k > maxK else { return k }
        let presets = sizeOptions.map(\.scale).sorted()
        return presets.last(where: { $0 <= maxK }) ?? min(maxK, presets.first ?? 0.8)
    }

    /// 等 web 组件挂载、__ipod 可用后设定初始尺寸
    private func bootScale() {
        webView.evaluateJavaScript("window.__ipod && __ipod.ready()") { [weak self] ok, _ in
            guard let self else { return }
            if ok as? Bool == true {
                self.webView.evaluateJavaScript("__ipod.totalH()") { r, _ in
                    if let h = r as? Double, h > 600 {
                        self.totalH = CGFloat(h)
                        UserDefaults.standard.set(h, forKey: "ipod.totalH")
                    }
                    // 启动校正固定顶边：万一还有误差，设备也不会上下跳
                    self.applyScale(self.fittedScale(self.scale, totalH: self.totalH), anchorTop: true)
                }
            } else {
                self.bootAttempts += 1
                if self.bootAttempts < 15 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.bootScale() }
                }
            }
        }
    }

    private func applyScale(_ k: CGFloat, anchorTop: Bool = false) {
        scale = k
        UserDefaults.standard.set(Double(k), forKey: Key.scale)
        webView.evaluateJavaScript("""
        window.__ipod && __ipod.ready() ? (__ipod.apply(\(k)), JSON.stringify(__ipod.extent())) : null
        """) { [weak self] result, _ in
            guard let self, let s = result as? String,
                  let data = s.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let w = obj["w"] as? Double, let h = obj["h"] as? Double
            else { return }
            let old = self.window.frame
            let newSize = NSSize(width: w, height: h)
            var f = NSRect(x: old.midX - newSize.width / 2,
                           y: anchorTop ? old.maxY - newSize.height : old.midY - newSize.height / 2,
                           width: newSize.width, height: newSize.height)
            f.origin = self.clampToScreen(f.origin, size: newSize)
            if f != old { print("[frame] \(NSStringFromRect(old)) → \(NSStringFromRect(f))") }
            self.window.setFrame(f, display: true)
        }
        updateSizeChecks()
    }

    // MARK: - 位置持久化

    func windowDidMove(_ notification: Notification) {
        saveTopLeft()
    }

    func windowDidResize(_ notification: Notification) { saveTopLeft() }

    private func saveTopLeft() {
        let f = window.frame
        UserDefaults.standard.set("\(f.minX),\(f.maxY)", forKey: Key.topLeft)
    }

    private func savedTopLeft() -> NSPoint? {
        guard let s = UserDefaults.standard.string(forKey: Key.topLeft) else { return nil }
        let parts = s.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return NSPoint(x: parts[0], y: parts[1])
    }

    private func savedScale() -> CGFloat {
        let d = UserDefaults.standard.double(forKey: Key.scale)
        return d > 0.2 && d < 2.5 ? CGFloat(d) : 1.0
    }

    private func clampToScreen(_ p: NSPoint, size: NSSize) -> NSPoint {
        guard let vf = NSScreen.main?.visibleFrame else { return p }
        var q = p
        q.x = max(vf.minX, min(q.x, vf.maxX - size.width))
        q.y = max(vf.minY, min(q.y, vf.maxY - size.height))
        return q
    }

    // MARK: - WKScriptMessageHandler（页面 console 转发）

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        if message.name == "drag" {
            (webView as? IPodWebView)?.beginWindowDrag()
            return
        }
        if let text = message.body as? String { print("[js] " + text) }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        bootAttempts = 0
        print("[nav] loaded \(webView.url?.absoluteString ?? "?")")
        // 组件挂载是异步的，稍等再走尺寸初始化 + 探测
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.bootScale()
            self?.probeCJK()
            self?.debugSnapshot()
            self?.probeAudio()
            self?.probeNav()
            self?.probeEvalJS()
            self?.probeDrag()
            self?.probeDOM()
            self?.probeLibrary()
        }
    }

    /// 组件里歌名等是链接（曲库 url 为 "/"），点了会把整页换成 widget.html
    /// （白底、倒影、不缩放）。App 只有一个页面，主框架导航只放行 app.html
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard let frame = navigationAction.targetFrame, frame.isMainFrame else {
            // 子框架照常；targetFrame 为 nil（新窗口/_blank）直接拒绝
            decisionHandler(navigationAction.targetFrame == nil ? .cancel : .allow)
            return
        }
        let url = navigationAction.request.url
        if url?.host == "127.0.0.1", url?.path == "/app.html" {
            decisionHandler(.allow)
        } else {
            print("[nav] 已拦截跳转: \(url?.absoluteString ?? "?")")
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        print("[nav] provisional fail: \(error)")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        print("[nav] fail: \(error)")
    }

    /// 验证 ipod-cjk.js 的字体 hack 在 WKWebView 里生效（返回 true = 中文不会再被裁）
    private func probeCJK() {
        webView.evaluateJavaScript("document.fonts.check('26px \"IPOD-CJK\"', '中文测试')") { result, error in
            if let error { print("[cjk] 探测失败: \(error)") }
            else { print("[cjk] IPOD-CJK 字体可用: \(result ?? "nil")") }
        }
        webView.evaluateJavaScript("""
        (function () {
          var host = document.querySelector('web-music-ipod');
          if (!host || !host.shadowRoot) return 'no-shadow-root';
          var c = host.shadowRoot.querySelector('.ipod-container');
          var inner = host.shadowRoot.querySelector('.ipod-shadow-inner');
          if (!c) return 'no-container';
          var r = c.getBoundingClientRect();
          return 'reflect=' + (getComputedStyle(c).webkitBoxReflect || 'none')
            + ' before=' + (inner ? getComputedStyle(inner, '::before').display : '?')
            + ' device=' + (r.width | 0) + 'x' + (r.height | 0)
            + ' viewport=' + (innerWidth | 0) + 'x' + (innerHeight | 0);
        })();
        """) { result, error in
            if let error { print("[layout] 探测失败: \(error)") }
            else { print("[layout] \(result ?? "nil")") }
        }
    }

    /// IPOD_SNAPSHOT=1 跑时保存 WebView 截图到 /tmp/ipod-webview.png（调试用）
    private func debugSnapshot() {
        guard ProcessInfo.processInfo.environment["IPOD_SNAPSHOT"] != nil else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // 关闭钮平时只在悬停时浮现，截图时强制显示，方便核对位置
            self.content.closeBtn.alphaValue = 1
            let order = self.content.subviews.map { String(describing: type(of: $0)) }
            print("[snap] z-order(底→顶) \(order) closeBtn=\(NSStringFromRect(self.content.closeBtn.frame))")
            self.webView.takeSnapshot(with: nil) { image, _ in
                guard let image else { print("[snap] 失败"); return }
                // WebView 截图拍不到原生控件：把 WebView 之上的原生子视图逐个叠上去
                let size = self.content.bounds.size
                let out = NSImage(size: size)
                out.lockFocus()
                image.draw(in: NSRect(origin: .zero, size: size))
                for v in self.content.subviews where v !== self.webView && !v.isHidden {
                    guard let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { continue }
                    v.cacheDisplay(in: v.bounds, to: rep)
                    rep.draw(in: v.frame, from: .zero, operation: .sourceOver,
                             fraction: 1, respectFlipped: true, hints: nil)
                }
                out.unlockFocus()
                self.content.closeBtn.alphaValue = 0
                guard let tiff = out.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:])
                else { print("[snap] 失败"); return }
                try? png.write(to: URL(fileURLWithPath: "/tmp/ipod-webview.png"))
                print("[snap] saved /tmp/ipod-webview.png")
            }
        }
    }

    /// IPOD_LIBTEST=1：打开曲库窗口并截图到 /tmp/ipod-library.png（只跑一次）
    private var libTested = false
    private func probeLibrary() {
        guard ProcessInfo.processInfo.environment["IPOD_LIBTEST"] != nil, !libTested else { return }
        libTested = true
        showLibrary()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            // 顺带验证窗口能被拉宽（styleMask/约束有问题时 setFrame 会被弹回）
            if let w = self?.libraryWC?.window {
                let before = w.frame.width
                var f = w.frame; f.size.width += 120
                w.setFrame(f, display: true)
                w.contentView?.layoutSubtreeIfNeeded()
                print("[libtest] 窗口宽 \(before) → \(w.frame.width)  resizable=\(w.styleMask.contains(.resizable))")
            }
            guard let v = self?.libraryWC?.window?.contentView,
                  let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) else { return }
            v.cacheDisplay(in: v.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?
                .write(to: URL(fileURLWithPath: "/tmp/ipod-library.png"))
            print("[libtest] saved /tmp/ipod-library.png")
            if let wc = self?.libraryWC {
                print("[libtest] 按时长降序:", wc.debugSort("time", ascending: false))
                print("[libtest] 按时长升序:", wc.debugSort("time", ascending: true))
                print("[libtest] 按歌名升序:", wc.debugSort("name", ascending: true))
                wc.debugResetSort()      // 测试别留下排序状态（会被自动保存）
            }
            self?.probePaste()
        }
    }

    /// IPOD_DOMDUMP=1：打印组件 shadow DOM 结构（标签.类名 + 尺寸 + cursor），排查交互区域用
    private func probeDOM() {
        guard ProcessInfo.processInfo.environment["IPOD_DOMDUMP"] != nil else { return }
        webView.evaluateJavaScript("""
        (function () {
          var root = document.querySelector('web-music-ipod').shadowRoot, out = [];
          function walk(el, d) {
            if (d > 9 || out.length > 120) return;
            var r = el.getBoundingClientRect();
            if (r.width > 4 && r.height > 4) {
              out.push(Array(d + 1).join('  ') + el.tagName.toLowerCase()
                + (el.className && el.className.baseVal === undefined ? '.' + String(el.className).split(' ').join('.') : '')
                + (el.getAttribute('role') ? ' [role=' + el.getAttribute('role') + ']' : '')
                + ' ' + (r.width | 0) + 'x' + (r.height | 0) + ' cursor=' + getComputedStyle(el).cursor);
            }
            for (var c of el.children) walk(c, d + 1);
          }
          for (var c of root.children) walk(c, 0);
          return out.join('\\n');
        })();
        """) { r, e in print("[dom]\n\(r ?? e ?? "?")") }
    }

    /// 曲库窗口编辑框里模拟 ⌘V（走菜单栏快捷键，和真实按键同一路径），随后放弃编辑、恢复剪贴板
    private func probePaste() {
        guard let wc = libraryWC, let w = wc.window, wc.debugBeginEdit() else { return }
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        pb.setString("粘贴测试PASTE", forType: .string)
        let before = wc.debugEditorText() ?? "(没有进入编辑)"
        // 编辑状态下全选会选中原文字，粘贴后应整体替换成测试文字
        let ev = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command,
                                  timestamp: ProcessInfo.processInfo.systemUptime,
                                  windowNumber: w.windowNumber, context: nil,
                                  characters: "v", charactersIgnoringModifiers: "v",
                                  isARepeat: false, keyCode: 9)!
        let handled = NSApp.mainMenu?.performKeyEquivalent(with: ev) ?? false
        print("[pastetest] 编辑前=\(before) ⌘V 被菜单处理=\(handled) 编辑后=\(wc.debugEditorText() ?? "nil")")
        wc.debugAbortEdit()
        pb.clearContents()
        if let saved { pb.setString(saved, forType: .string) }
    }

    /// IPOD_EVALJS=文件：页面加载后执行文件里的 JS（作为 async 函数体，可 await），打印返回值。只跑一次
    private var evalDone = false
    private func probeEvalJS() {
        guard let path = ProcessInfo.processInfo.environment["IPOD_EVALJS"], !evalDone,
              let js = try? String(contentsOfFile: path, encoding: .utf8) else { return }
        evalDone = true
        webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { result in
            switch result {
            case .success(let v): print("[evaljs] \(v)")
            case .failure(let e): print("[evaljs] 出错: \(e)")
            }
        }
    }

    /// IPOD_DRAGTEST=1：在几个典型位置模拟鼠标移动，打印是否判定为控件（光标是否切成手指）
    private func probeDrag() {
        guard ProcessInfo.processInfo.environment["IPOD_DRAGTEST"] != nil else { return }
        webView.evaluateJavaScript("""
        (function () {
          var root = document.querySelector('web-music-ipod').shadowRoot;
          var w = root.querySelector('.click-wheel').getBoundingClientRect();
          var scr = root.querySelector('.ipod-screen').getBoundingClientRect();
          var dev = root.querySelector('.ipod-container').getBoundingClientRect();
          var cx = w.left + w.width / 2, cy = w.top + w.height / 2, R = w.width / 2;
          var pts = [
            ['滚轮中心确认键', cx, cy], ['滚轮外圈(右侧)', cx + R * 0.85, cy],
            ['滚轮方框的角(圆外)', cx + R * 0.95, cy + R * 0.95], ['屏幕中央', scr.left + scr.width / 2, scr.top + scr.height / 2],
            ['额头', dev.left + dev.width / 2, dev.top + 12], ['机身底部', dev.left + dev.width / 2, dev.bottom - 8]
          ];
          var fit = document.getElementById('fit');
          return pts.map(function (p) {
            document.dispatchEvent(new MouseEvent('mousemove', { clientX: p[1], clientY: p[2], bubbles: true }));
            return p[0] + ': ' + (fit.classList.contains('on-control') ? '控件(手指)' : '机身(抓手，可拖)')
              + ' cursor=' + getComputedStyle(fit).cursor;
          }).join('\\n');
        })();
        """) { r, e in print("[dragtest]\n\(r ?? e ?? "?")") }
    }

    /// IPOD_NAVTEST=1：模拟点歌名链接（应被拦截），再重载一次（应放行），各只跑一次
    private var navTested = false
    private func probeNav() {
        guard ProcessInfo.processInfo.environment["IPOD_NAVTEST"] != nil, !navTested else { return }
        navTested = true
        webView.evaluateJavaScript("var a=document.createElement('a');a.href='/';document.body.appendChild(a);a.click();")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.webView.evaluateJavaScript("location.pathname") { r, _ in
                print("[navtest] 点击链接后仍在: \(r ?? "?")")
                self?.webView.reload()
            }
        }
    }

    /// IPOD_AUDIOTEST=1 跑时用曲库第一首做真实试播（canplay/playing = WKWebView 能解码 FLAC）
    private func probeAudio() {
        guard ProcessInfo.processInfo.environment["IPOD_AUDIOTEST"] != nil else { return }
        webView.evaluateJavaScript(Self.audioTestJS, completionHandler: nil)
    }

    private static let audioTestJS = """
    (function () {
      fetch('/includes/ipod/data/us/en-US.json').then(function (r) { return r.json(); }).then(function (d) {
        var url = d.songs[0].previewUrl;
        var a = new Audio(url);
        a.volume = 0.05;
        var t0 = performance.now();
        a.addEventListener('canplay', function () { console.log('AUDIOTEST canparse+canplay ' + ((performance.now() - t0) | 0) + 'ms'); });
        a.addEventListener('playing', function () {
          console.log('AUDIOTEST playing duration=' + (a.duration | 0) + 's');
          setTimeout(function () { a.pause(); console.log('AUDIOTEST ok'); }, 1500);
        });
        a.addEventListener('error', function () { console.error('AUDIOTEST error code=' + (a.error && a.error.code)); });
        return a.play();
      }).catch(function (e) { console.error('AUDIOTEST fail', e && e.message); });
    })();
    """

    private static let consoleHook = """
    (function () {
      function fmt(a) { try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (e) { return String(a); } }
      function send(level, args) {
        try { window.webkit.messageHandlers.log.postMessage(level + ': ' + Array.prototype.map.call(args, fmt).join(' ')); } catch (e) {}
      }
      ['log', 'info', 'warn', 'error'].forEach(function (m) {
        var orig = console[m] ? console[m].bind(console) : function () {};
        console[m] = function () { send(m, arguments); orig.apply(null, arguments); };
      });
      window.addEventListener('error', function (e) { send('error', [(e.message || 'Error') + ' @ ' + (e.filename || '') + ':' + e.lineno]); });
      window.addEventListener('unhandledrejection', function (e) { send('error', ['unhandledrejection: ' + (e && e.reason)]); });
    })();
    """
}
