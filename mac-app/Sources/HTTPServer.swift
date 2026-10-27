import Foundation
import Network

// MARK: - 错误

enum ServerError: LocalizedError {
    case listenFailed(String)

    var errorDescription: String? {
        switch self {
        case .listenFailed(let m): return "本地端口监听失败: \(m)"
        }
    }
}

// MARK: - 响应

struct HTTPResponse {
    var status: Int
    var reason: String
    var headers: [(String, String)] = []
    var body: Data = Data()
    var file: FileHandle?      // 非空 => 从文件流式发送（音频/大 chunk）
    var fileLength: Int64 = 0

    static func error(_ status: Int, _ reason: String) -> HTTPResponse {
        var r = HTTPResponse(status: status, reason: reason)
        r.headers = [("Content-Type", "text/plain; charset=utf-8")]
        r.body = Data("\(status) \(reason)".utf8)
        return r
    }
}

// MARK: - 路由（语义照抄 server.py）

final class WebRoot {
    let rootURL: URL
    private let fm = FileManager.default
    private let shellPath = "us/new/1122/index.html"   // SPA fallback，同 server.py
    /// 外部曲库覆盖：/music/* 与曲库 JSON 落在 ~/Library/Application Support/iPod，
    /// 不随 .app bundle 走（重建 App 不丢歌）。nil = 纯 dev 模式全走 webroot
    private let musicDir: URL?
    private let libraryJSON: URL?

    init(rootURL: URL, musicDir: URL? = nil, libraryJSON: URL? = nil) {
        self.rootURL = rootURL
        self.musicDir = musicDir
        self.libraryJSON = libraryJSON
    }

    private static let mimeTypes: [String: String] = [
        "html": "text/html; charset=utf-8",
        "htm": "text/html; charset=utf-8",
        "js": "text/javascript; charset=utf-8",
        "mjs": "text/javascript; charset=utf-8",
        "css": "text/css; charset=utf-8",
        "json": "application/json; charset=utf-8",
        "map": "application/json",
        "webmanifest": "application/manifest+json",
        "txt": "text/plain; charset=utf-8",
        "png": "image/png",
        "jpg": "image/jpeg",
        "jpeg": "image/jpeg",
        "gif": "image/gif",
        "svg": "image/svg+xml",
        "webp": "image/webp",
        "ico": "image/x-icon",
        "woff": "font/woff",
        "woff2": "font/woff2",
        "ttf": "font/ttf",
        "otf": "font/otf",
        "mp3": "audio/mpeg",
        "m4a": "audio/mp4",
        "mp4": "video/mp4",
        "flac": "audio/flac",
        "wav": "audio/wav",
        "ogg": "audio/ogg",
        "opus": "audio/ogg",
    ]

    func response(method: String, rawTarget: String, rangeHeader: String?) -> HTTPResponse {
        let rawPath = rawTarget.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let path = rawPath.removingPercentEncoding ?? rawPath

        // 根路径给 widget（同 server.py）
        if path.isEmpty || path == "/" {
            return fileResponse(relative: "widget.html", rangeHeader: rangeHeader)
        }

        let comps = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if comps.contains("..") {
            return .error(404, "Not Found")
        }

        // 外部曲库覆盖优先
        if let lib = libraryJSON, path == "/includes/ipod/data/us/en-US.json",
           fm.fileExists(atPath: lib.path) {
            return fileResponse(fileURL: lib, rangeHeader: rangeHeader)
        }
        if let music = musicDir, path.hasPrefix("/music/") {
            let rel = String(path.dropFirst("/music/".count))
            let mcomps = rel.split(separator: "/").map(String.init)
            if !mcomps.contains(".."), let url = resolveCaseInsensitive(mcomps, from: music),
               isRegularFile(url) {
                return fileResponse(fileURL: url, rangeHeader: rangeHeader)
            }
            return .error(404, "Not Found")   // 曲库路径缺失要真 404
        }

        if let url = resolveCaseInsensitive(comps), isRegularFile(url) {
            return fileResponse(fileURL: url, rangeHeader: rangeHeader)
        }

        // 资源缺失给真 404，别用 HTML 兜底（否则组件把 HTML 当 JSON 解析，报 No Music）
        let last = comps.last ?? ""
        let assetLike = last.contains(".")
            || path.hasPrefix("/assets/") || path.hasPrefix("/includes/")
            || path.hasPrefix("/static-commerce/") || path.hasPrefix("/music/")
        if assetLike {
            return .error(404, "Not Found")
        }

        // SPA fallback：未知路由渲染原版 404 页
        return fileResponse(relative: shellPath, rangeHeader: nil)
    }

    /// 逐段解析路径；精确命中直接用，未命中做大小写不敏感兜底
    /// （曲库 JSON 里写的是 music/，目录实际叫 Music/，大小写敏感卷上也兜得住）
    private func resolveCaseInsensitive(_ comps: [String]) -> URL? {
        resolveCaseInsensitive(comps, from: rootURL)
    }

    private func resolveCaseInsensitive(_ comps: [String], from base: URL) -> URL? {
        var url = base
        for comp in comps {
            if comp == "." || comp == ".." { return nil }
            let next = url.appendingPathComponent(comp)
            if fm.fileExists(atPath: next.path) {
                url = next
                continue
            }
            guard let items = try? fm.contentsOfDirectory(atPath: url.path),
                  let match = items.first(where: { $0.caseInsensitiveCompare(comp) == .orderedSame })
            else { return nil }
            url = url.appendingPathComponent(match)
        }
        return url
    }

    private func isRegularFile(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
    }

    private func fileResponse(relative: String, rangeHeader: String?) -> HTTPResponse {
        let comps = relative.split(separator: "/").map(String.init)
        guard let url = resolveCaseInsensitive(comps), isRegularFile(url) else {
            return .error(404, "Not Found")
        }
        return fileResponse(fileURL: url, rangeHeader: rangeHeader)
    }

    private func fileResponse(fileURL: URL, rangeHeader: String?) -> HTTPResponse {
        let size = Int64((try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int ?? 0)
        let type = Self.mimeTypes[fileURL.pathExtension.lowercased()] ?? "application/octet-stream"

        var resp = HTTPResponse(status: 200, reason: "OK")
        // 本地服务器，禁缓存：改 HTML/曲库后重载立即可见
        resp.headers = [("Content-Type", type), ("Accept-Ranges", "bytes"),
                        ("Cache-Control", "no-store")]

        var start: Int64 = 0
        var end: Int64 = max(size - 1, 0)

        if let rangeValue = rangeHeader, size > 0, let r = parseRange(rangeValue) {
            if let s = r.lowerBound {
                start = s
                end = min(r.upperBound ?? size - 1, size - 1)
            } else if let suffix = r.upperBound {
                // bytes=-N：最后 N 字节
                start = max(size - suffix, 0)
                end = size - 1
            }
            if start > end || start >= size {
                var e = HTTPResponse.error(416, "Range Not Satisfiable")
                e.headers.insert(("Content-Range", "bytes */\(size)"), at: 0)
                return e
            }
            resp.status = 206
            resp.reason = "Partial Content"
            resp.headers.append(("Content-Range", "bytes \(start)-\(end)/\(size)"))
        }

        let length = size == 0 ? 0 : end - start + 1
        resp.headers.append(("Content-Length", "\(length)"))

        if size > 0, let fh = try? FileHandle(forReadingFrom: fileURL) {
            try? fh.seek(toOffset: UInt64(start))
            resp.file = fh
            resp.fileLength = length
        }
        return resp
    }

    /// "bytes=a-b" / "bytes=a-" / "bytes=-b"
    private func parseRange(_ value: String) -> (lowerBound: Int64?, upperBound: Int64?)? {
        let v = value.trimmingCharacters(in: .whitespaces)
        guard v.lowercased().hasPrefix("bytes=") else { return nil }
        let parts = v.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let a = parts[0].trimmingCharacters(in: .whitespaces)
        let b = parts[1].trimmingCharacters(in: .whitespaces)
        var lower: Int64?
        var upper: Int64?
        if !a.isEmpty {
            guard let x = Int64(a), x >= 0 else { return nil }
            lower = x
        }
        if !b.isEmpty {
            guard let y = Int64(b), y >= 0 else { return nil }
            upper = y
        }
        guard lower != nil || upper != nil else { return nil }
        return (lower, upper)
    }
}

// MARK: - 单个连接（请求头 -> 响应头 -> 文件流式发送）

final class HTTPConnection {
    private let conn: NWConnection
    private let root: WebRoot
    private var buffer = Data()
    private var file: FileHandle?
    private var bytesLeft: Int64 = 0
    private var finished = false
    private let headerEnd = Data("\r\n\r\n".utf8)
    private static let chunkSize = 256 * 1024
    var onFinish: (() -> Void)?

    init(conn: NWConnection, root: WebRoot) {
        self.conn = conn
        self.root = root
    }

    func start(queue: DispatchQueue) {
        conn.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.finish()
            default: break
            }
        }
        conn.start(queue: queue)   // NWListener 交来的连接必须显式 start 才会收数据
        receiveLoop()
    }

    private func receiveLoop() {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if error != nil { self.finish(); return }
            if self.buffer.range(of: self.headerEnd) != nil {
                self.handleRequest()
            } else if isComplete || self.buffer.count > 64 * 1024 {
                self.respond(.error(400, "Bad Request"))
            } else {
                self.receiveLoop()
            }
        }
    }

    private func handleRequest() {
        guard let end = buffer.range(of: headerEnd),
              let head = String(data: buffer.subdata(in: 0..<end.lowerBound), encoding: .utf8)
        else {
            respond(.error(400, "Bad Request")); return
        }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { respond(.error(400, "Bad Request")); return }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { respond(.error(400, "Bad Request")); return }
        let method = String(requestLine[0]).uppercased()
        let target = String(requestLine[1])

        var rangeHeader: String?
        for line in lines {
            guard let idx = line.firstIndex(of: ":") else { continue }
            if line[..<idx].trimmingCharacters(in: .whitespaces).lowercased() == "range" {
                rangeHeader = String(line[line.index(after: idx)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        respond(root.response(method: method, rawTarget: target, rangeHeader: rangeHeader), method: method)
    }

    private func respond(_ resp: HTTPResponse, method: String = "GET") {
        var head = "HTTP/1.1 \(resp.status) \(resp.reason)\r\n"
        for (k, v) in resp.headers { head += "\(k): \(v)\r\n" }
        head += "Connection: close\r\n\r\n"

        conn.send(content: Data(head.utf8), completion: .contentProcessed { [weak self] _ in
            guard let self else { return }
            if method == "HEAD" {
                self.finish()
            } else if let f = resp.file {
                self.file = f
                self.bytesLeft = resp.fileLength
                self.streamFile()
            } else if !resp.body.isEmpty {
                self.conn.send(content: resp.body, completion: .contentProcessed { _ in self.finish() })
            } else {
                self.finish()
            }
        })
    }

    private func streamFile() {
        guard let f = file, bytesLeft > 0 else { finish(); return }
        let n = Int(min(Int64(Self.chunkSize), bytesLeft))
        let chunk = f.readData(ofLength: n)
        guard !chunk.isEmpty else { finish(); return }
        bytesLeft -= Int64(chunk.count)
        conn.send(content: chunk, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if error != nil { self.finish(); return }
            if self.bytesLeft <= 0 { self.finish() } else { self.streamFile() }
        })
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        file?.closeFile()
        file = nil
        conn.cancel()
        onFinish?()
    }
}

// MARK: - 服务器（NWListener，只绑 127.0.0.1 随机端口）

final class LocalHTTPServer {
    let webRoot: WebRoot
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: HTTPConnection] = [:]
    private let queue = DispatchQueue(label: "ipod.httpserver")
    private(set) var port: UInt16 = 0

    init(rootURL: URL, musicDir: URL? = nil, libraryJSON: URL? = nil) {
        webRoot = WebRoot(rootURL: rootURL, musicDir: musicDir, libraryJSON: libraryJSON)
    }

    func start() throws -> UInt16 {
        let params = NWParameters.tcp
        params.allowLocalEndpointReuse = true
        // 只绑 127.0.0.1，端口随机——避免和已在跑的 server.py(8765) 冲突
        params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: .any)

        let l = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        final class ErrorBox { var message: String? }
        let box = ErrorBox()
        l.stateUpdateHandler = { state in
            switch state {
            case .ready: ready.signal()
            case .failed(let e): box.message = "\(e)"; ready.signal()
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        l.start(queue: queue)

        if ready.wait(timeout: .now() + 5) == .timedOut {
            throw ServerError.listenFailed("listener 超时未就绪")
        }
        if let err = box.message { throw ServerError.listenFailed(err) }
        guard let p = l.port?.rawValue else { throw ServerError.listenFailed("未分配到端口") }

        port = p
        listener = l
        return p
    }

    private func accept(_ conn: NWConnection) {
        let c = HTTPConnection(conn: conn, root: webRoot)
        connections[ObjectIdentifier(c)] = c
        c.onFinish = { [weak self, weak c] in
            guard let self, let c else { return }
            self.connections[ObjectIdentifier(c)] = nil
        }
        c.start(queue: queue)
    }
}
