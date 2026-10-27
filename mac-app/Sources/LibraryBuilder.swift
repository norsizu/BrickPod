import Foundation

// 原生曲库构建器：make-library.py 的 Swift 等价物（不依赖 ffprobe）
// - 标签：FLAC 读 Vorbis Comment，MP3 读 ID3v2，M4A 读 ilst，WAV 无标签
// - 缺失时回退：歌名=文件名，歌手=未知艺术家，专辑=文件夹名（同 python 版）
// - 输出 JSON schema 与 python 版完全一致（schemaVersion 3）

struct AudioMeta {
    var title: String?
    var artist: String?
    var album: String?
    var albumArtist: String?
    var duration: Double
}

enum LibraryBuilder {
    // ogg/opus 故意不含：WKWebView(Safari 内核) 解不了这些容器
    static let audioExts: Set<String> = ["mp3", "flac", "m4a", "wav", "aiff", "aif"]

    static func isAudio(_ url: URL) -> Bool {
        audioExts.contains(url.pathExtension.lowercased())
    }

    // MARK: - 导入（拷贝进曲库目录）

    /// 文件夹按顶层目录名拷入；散文件统一进「导入的音乐」。
    /// 若拖进来的是"曲库根"（自己不直接含音频、只有子文件夹有），则摊平拷子文件夹，
    /// 避免出现 music/Music/1998.… 这种双层嵌套
    @discardableResult
    static func importURLs(_ urls: [URL], into musicDir: URL) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: musicDir, withIntermediateDirectories: true)
        var copied = 0
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if isLibraryRoot(url) {
                    if let children = try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) {
                        for child in children where !child.lastPathComponent.hasPrefix(".") {
                            var cd: ObjCBool = false
                            if fm.fileExists(atPath: child.path, isDirectory: &cd), cd.boolValue {
                                copied += copyTree(child, to: musicDir.appendingPathComponent(child.lastPathComponent))
                            }
                        }
                    }
                } else {
                    copied += copyTree(url, to: musicDir.appendingPathComponent(url.lastPathComponent))
                }
            } else if isAudio(url) {
                let folder = musicDir.appendingPathComponent("导入的音乐")
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let dst = folder.appendingPathComponent(url.lastPathComponent)
                if !fm.fileExists(atPath: dst.path) {
                    try? fm.copyItem(at: url, to: dst)
                    copied += 1
                }
            }
        }
        return copied
    }

    private static func isLibraryRoot(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        else { return false }
        var hasDirectAudio = false
        var hasAudioSubdir = false
        for item in items {
            if item.lastPathComponent.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if containsAudio(item) { hasAudioSubdir = true }
            } else if isAudio(item) {
                hasDirectAudio = true
            }
        }
        return !hasDirectAudio && hasAudioSubdir
    }

    private static func containsAudio(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        else { return false }
        for item in items {
            if item.lastPathComponent.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if containsAudio(item) { return true }
            } else if isAudio(item) {
                return true
            }
        }
        return false
    }

    private static func copyTree(_ src: URL, to dst: URL) -> Int {
        let fm = FileManager.default
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        guard let items = try? fm.contentsOfDirectory(at: src, includingPropertiesForKeys: [.isDirectoryKey])
        else { return 0 }
        var n = 0
        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                n += copyTree(item, to: dst.appendingPathComponent(name))
            } else if isAudio(item) {
                let d = dst.appendingPathComponent(name)
                if !fm.fileExists(atPath: d.path) {
                    try? fm.copyItem(at: item, to: d)
                    n += 1
                }
            }
        }
        return n
    }

    // MARK: - 删除

    /// 曲库 JSON 里的 previewUrl（"music/专辑/歌.flac"，百分号编码）→ 曲库目录里的文件
    static func fileURL(forPreviewUrl previewUrl: String, musicDir: URL) -> URL? {
        guard previewUrl.hasPrefix("music/"),
              let rel = String(previewUrl.dropFirst("music/".count)).removingPercentEncoding
        else { return nil }
        let comps = rel.split(separator: "/").map(String.init)
        guard !comps.isEmpty, !comps.contains(".."), !comps.contains(".") else { return nil }
        return comps.reduce(musicDir) { $0.appendingPathComponent($1) }
    }

    /// 移到废纸篓（可恢复），再把因此变空的文件夹一路往上清掉（不超过 musicDir）。
    /// 返回成功删除的数量
    @discardableResult
    static func trash(_ files: [URL], musicDir: URL) -> Int {
        let fm = FileManager.default
        let root = musicDir.standardizedFileURL.path
        var n = 0
        var parents = Set<URL>()
        for f in files {
            // 只动曲库目录里的东西
            guard f.standardizedFileURL.path.hasPrefix(root + "/") else { continue }
            if (try? fm.trashItem(at: f, resultingItemURL: nil)) != nil {
                n += 1
                parents.insert(f.deletingLastPathComponent().standardizedFileURL)
            }
        }
        // 深的先处理，子文件夹删掉后父文件夹才可能变空
        for dir in parents.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            var d = dir
            while d.path.hasPrefix(root + "/") {
                let visible = ((try? fm.contentsOfDirectory(atPath: d.path)) ?? []).filter { !$0.hasPrefix(".") }
                guard visible.isEmpty else { break }
                try? fm.removeItem(at: d)
                d = d.deletingLastPathComponent()
            }
        }
        return n
    }

    // MARK: - 元数据修改（不改音频文件，存在曲库旁的 overrides.json）

    /// 可编辑字段，key 与曲库 JSON 里的字段名一致
    static let editableFields = ["name", "artistName", "albumName"]

    private static func overridesURL(musicDir: URL) -> URL {
        musicDir.deletingLastPathComponent().appendingPathComponent("overrides.json")
    }

    /// [曲库内相对路径: [字段: 值]]
    static func loadOverrides(musicDir: URL) -> [String: [String: String]] {
        guard let data = try? Data(contentsOf: overridesURL(musicDir: musicDir)),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String: String]]
        else { return [:] }
        return obj
    }

    static func saveOverrides(_ ov: [String: [String: String]], musicDir: URL) {
        guard let data = try? JSONSerialization.data(withJSONObject: ov, options: [.prettyPrinted, .sortedKeys])
        else { return }
        try? data.write(to: overridesURL(musicDir: musicDir), options: .atomic)
    }

    /// 批量设置：value 为空字符串 = 撤销修改，恢复文件里的标签
    static func setOverride(field: String, value: String, files: [URL], musicDir: URL) {
        guard editableFields.contains(field) else { return }
        var ov = loadOverrides(musicDir: musicDir)
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        for f in files {
            guard let rel = relativePath(of: f, in: musicDir) else { continue }
            var entry = ov[rel] ?? [:]
            entry[field] = v.isEmpty ? nil : v
            ov[rel] = entry.isEmpty ? nil : entry
        }
        saveOverrides(ov, musicDir: musicDir)
    }

    static func relativePath(of file: URL, in musicDir: URL) -> String? {
        let root = musicDir.standardizedFileURL.path + "/"
        let p = file.standardizedFileURL.path
        return p.hasPrefix(root) ? String(p.dropFirst(root.count)) : nil
    }

    // MARK: - 重建 JSON

    struct Counts {
        var songs = 0, artists = 0, playlists = 0
        var changed = true      // false = 内容和磁盘上的一致，没重写（页面也不用刷新）
    }

    /// 扫描 musicDir 重建 en-US.json（原子写入）
    static func rebuild(musicDir: URL, writing jsonURL: URL) throws -> Counts {
        var files: [(rel: String, url: URL)] = []
        collect(musicDir, rel: "", into: &files)
        // 空目录也照常写出（songs: []），组件拿到 404 会报错，空曲库则正常显示

        let sizeOf: (URL) -> Int64 = { (try? FileManager.default.attributesOfItem(atPath: $0.path))?[.size] as? Int64 ?? 0 }

        var songs: [[String: Any]] = []
        var artistOrder: [String] = []
        var artistSongs: [String: [String]] = [:]
        var albumOrder: [String] = []
        var albumSongs: [String: [String]] = [:]

        // 用户在曲库窗口里改的元数据，盖在文件标签之上；顺手清掉已删文件的记录
        var overrides = loadOverrides(musicDir: musicDir)
        let present = Set(files.map(\.rel))
        if overrides.keys.contains(where: { !present.contains($0) }) {
            overrides = overrides.filter { present.contains($0.key) }
            saveOverrides(overrides, musicDir: musicDir)
        }

        for (i, f) in files.enumerated() {
            let m = readMeta(f.url, fileSize: sizeOf(f.url))
            let ov = overrides[f.rel] ?? [:]
            let name = ov["name"] ?? m.title ?? (f.url.deletingPathExtension().lastPathComponent)
            let artist = ov["artistName"] ?? m.artist ?? m.albumArtist ?? "未知艺术家"
            let album = ov["albumName"] ?? m.album ?? f.url.deletingLastPathComponent().pathComponents.last ?? "未知专辑"
            let sid = String(format: "local-%04d", i + 1)
            songs.append([
                "id": sid,
                "name": name,
                "artistName": artist,
                "artistIds": ["local-artist-\(artist)"],
                "previewUrl": "music/" + enc(f.rel),
                "albumName": album,
                "durationInMillis": Int((m.duration * 1000).rounded()),
                "playParams": ["id": sid, "kind": "song"],
                "url": "/",
            ])
            if artistSongs[artist] == nil { artistOrder.append(artist) }
            artistSongs[artist, default: []].append(sid)
            if albumSongs[album] == nil { albumOrder.append(album) }
            albumSongs[album, default: []].append(sid)
        }

        let artists: [[String: Any]] = artistOrder.map {
            ["id": "local-artist-\($0)", "name": $0, "songIds": artistSongs[$0]!]
        }
        let playlists: [[String: Any]] = albumOrder.enumerated().map { j, alb in
            ["id": String(format: "local-pl-%03d", j + 1), "name": alb, "url": "/",
             "songIds": albumSongs[alb]!, "trackCount": albumSongs[alb]!.count,
             "curatorName": "我"]
        }

        let out: [String: Any] = ["schemaVersion": 3, "storefront": "us", "language": "en-US",
                                  "songs": songs, "artists": artists, "playlists": playlists]
        // sortedKeys：输出稳定，才能和旧文件逐字节比较
        let data = try JSONSerialization.data(withJSONObject: out, options: [.prettyPrinted, .sortedKeys])
        var counts = Counts(songs: songs.count, artists: artists.count, playlists: playlists.count)
        if let old = try? Data(contentsOf: jsonURL), old == data {
            counts.changed = false
            return counts
        }
        try data.write(to: jsonURL, options: .atomic)
        return counts
    }

    /// os.walk 语义：每层先文件（按名排序）再子目录（按名排序）
    private static func collect(_ dir: URL, rel: String, into out: inout [(rel: String, url: URL)]) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey])
        else { return }
        var dirs: [URL] = []
        var files: [URL] = []
        for item in items {
            if item.lastPathComponent.hasPrefix(".") { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: item.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue { dirs.append(item) }
            else if isAudio(item) { files.append(item) }
        }
        files.sort { $0.lastPathComponent < $1.lastPathComponent }
        dirs.sort { $0.lastPathComponent < $1.lastPathComponent }
        for f in files { out.append((rel + f.lastPathComponent, f)) }
        for d in dirs { collect(d, rel: rel + d.lastPathComponent + "/", into: &out) }
    }

    /// 和 python urllib.parse.quote 默认行为一致：字母数字和 -._~ / 之外全部转义
    private static func enc(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~/")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    // MARK: - 标签解析

    static func readMeta(_ url: URL, fileSize: Int64) -> AudioMeta {
        var m = AudioMeta(title: nil, artist: nil, album: nil, albumArtist: nil, duration: 0)
        guard let h = try? FileHandle(forReadingFrom: url) else { return m }
        defer { try? h.close() }
        switch url.pathExtension.lowercased() {
        case "flac": parseFLAC(h, fileSize: fileSize, into: &m)
        case "mp3": parseMP3(h, fileSize: fileSize, into: &m)
        case "m4a", "mp4": parseMP4(h, fileSize: fileSize, into: &m)
        case "wav": parseWAV(h, fileSize: fileSize, into: &m)
        default: break
        }
        return m
    }

    private static func read(_ h: FileHandle, _ n: Int) -> Data? {
        try? h.read(upToCount: n)
    }

    private static func u32(_ d: Data, _ o: Int) -> Int { o + 4 <= d.count ? Int(d[o])<<24 | Int(d[o+1])<<16 | Int(d[o+2])<<8 | Int(d[o+3]) : 0 }
    private static func u24(_ d: Data, _ o: Int) -> Int { o + 3 <= d.count ? Int(d[o])<<16 | Int(d[o+1])<<8 | Int(d[o+2]) : 0 }
    // Vorbis Comment 载荷是小端（FLAC 块头是大端，别搞混）
    private static func le32(_ d: Data, _ o: Int) -> Int { o + 4 <= d.count ? Int(d[o]) | Int(d[o+1])<<8 | Int(d[o+2])<<16 | Int(d[o+3])<<24 : 0 }

    // FLAC: "fLaC" + 元数据块流。STREAMINFO(0) 里有采样率/总采样数，VORBIS_COMMENT(4) 里有标签
    private static func parseFLAC(_ h: FileHandle, fileSize: Int64, into m: inout AudioMeta) {
        guard read(h, 4) == Data("fLaC".utf8) else { return }
        while true {
            guard let hd = read(h, 4), hd.count == 4 else { return }
            let last = hd[0] & 0x80 != 0
            let type = hd[0] & 0x7F
            let len = u24(hd, 1)
            guard let body = read(h, len) else { return }
            if type == 0, body.count >= 18 {
                let v = UInt64(u32(body, 10)) << 32 | UInt64(u32(body, 14))
                let sr = Int((v >> 44) & 0xFFFFF)
                let total = v & 0xF_FFFF_FFFF
                if sr > 0 { m.duration = Double(total) / Double(sr) }
            } else if type == 4, body.count > 8 {
                var o = 4 + le32(body, 0)          // 跳过 vendor 串
                guard o + 4 <= body.count else { return }
                let count = le32(body, o); o += 4
                for _ in 0..<count {
                    guard o + 4 <= body.count else { break }
                    let l = le32(body, o); o += 4
                    guard o + l <= body.count, let kv = String(data: body.subdata(in: o..<(o+l)), encoding: .utf8)
                    else { o += l; continue }
                    o += l
                    let parts = kv.split(separator: "=", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    let key = parts[0].uppercased(), val = String(parts[1])
                    switch key {
                    case "TITLE": m.title = m.title ?? val
                    case "ARTIST": m.artist = m.artist ?? val
                    case "ALBUMARTIST", "ALBUM_ARTIST": m.albumArtist = m.albumArtist ?? val
                    case "ALBUM": m.album = m.album ?? val
                    default: break
                    }
                }
            }
            if last { return }
        }
    }

    // MP3: ID3v2 标签 + 首帧 CBR 时长估算
    private static func parseMP3(_ h: FileHandle, fileSize: Int64, into m: inout AudioMeta) {
        var tagEnd: Int64 = 0
        if let hd = read(h, 10), hd.count == 10, hd.prefix(3) == Data("ID3".utf8) {
            let size = syncsafe(hd, 6)
            tagEnd = 10 + Int64(size)
            guard let body = read(h, size), body.count == size else {
                try? h.seek(toOffset: 0)
                m.duration = estimateMP3(h, from: 0, fileSize: fileSize)
                return
            }
            let ver = Int(hd[3])
            var o = 0
            let idLen = ver <= 2 ? 3 : 4
            while o + idLen + (ver <= 2 ? 3 : 6) <= body.count {
                let id = String(data: body.subdata(in: o..<(o+idLen)), encoding: .ascii) ?? ""
                if id.allSatisfy({ $0 == "\0" }) { break }
                o += idLen
                let fsize: Int
                if ver <= 2 { fsize = u24(body, o); o += 3 }
                else if ver == 3 { fsize = u32(body, o); o += 6 }
                else { fsize = syncsafe(body, o); o += 6 }
                guard fsize > 0, o + fsize <= body.count else { break }
                let frame = body.subdata(in: o..<(o+fsize))
                let map = ["TIT2": "T", "TT2": "T", "TPE1": "A", "TP1": "A",
                           "TALB": "L", "TAL": "L", "TPE2": "AA", "TP2": "AA"]
                if let k = map[id], let s = decodeTextFrame(frame) {
                    switch k {
                    case "T" where m.title == nil: m.title = s
                    case "A" where m.artist == nil: m.artist = s
                    case "L" where m.album == nil: m.album = s
                    case "AA" where m.albumArtist == nil: m.albumArtist = s
                    default: break
                    }
                }
                o += fsize
            }
        } else {
            try? h.seek(toOffset: 0)
        }
        m.duration = estimateMP3(h, from: tagEnd, fileSize: fileSize)
    }

    private static func syncsafe(_ d: Data, _ o: Int) -> Int {
        guard o + 4 <= d.count else { return 0 }
        return Int(d[o] & 0x7F) << 21 | Int(d[o+1] & 0x7F) << 14 | Int(d[o+2] & 0x7F) << 7 | Int(d[o+3] & 0x7F)
    }

    /// 文本帧：[编码字节][数据]，0=Latin1 1=UTF16(BOM) 2=UTF16BE 3=UTF8
    private static func decodeTextFrame(_ f: Data) -> String? {
        guard f.count > 1 else { return nil }
        let enc = f[0]
        var d = f.subdata(in: 1..<f.count)
        let raw: String?
        switch enc {
        case 0: raw = String(data: d, encoding: .isoLatin1)
        case 3: raw = String(data: d, encoding: .utf8)
        case 1, 2:
            var e: String.Encoding = enc == 2 ? .utf16BigEndian : .utf16LittleEndian
            if d.prefix(2) == Data([0xFF, 0xFE]) { e = .utf16LittleEndian; d = d.dropFirst(2) }
            else if d.prefix(2) == Data([0xFE, 0xFF]) { e = .utf16BigEndian; d = d.dropFirst(2) }
            if d.count % 2 == 1 { d = d.dropLast() }
            raw = String(data: d, encoding: e)
        default: raw = String(data: d, encoding: .utf8)
        }
        // 多值以 \0 分隔只取第一个；去掉残留 BOM 和空白
        guard let first = raw?.split(separator: "\0", omittingEmptySubsequences: true).first else { return nil }
        let clean = first.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespaces)
        return clean.isEmpty ? nil : clean
    }

    private static func estimateMP3(_ h: FileHandle, from: Int64, fileSize: Int64) -> Double {
        guard from < fileSize else { return 0 }
        try? h.seek(toOffset: UInt64(from))
        guard let buf = read(h, 65536), buf.count > 4 else { return 0 }
        var i = 0
        while i + 4 <= buf.count {
            if buf[i] == 0xFF, buf[i+1] & 0xE0 == 0xE0, buf[i+1] & 0x06 == 0x02 { break }
            i += 1
        }
        guard i + 4 <= buf.count else { return 0 }
        let verBits = (buf[i+1] & 0x18) >> 3
        let v1 = verBits == 3
        let brIdx = Int(buf[i+2] & 0xF0) >> 4
        let v1l3: [Int] = [0,32,40,48,56,64,80,96,112,128,160,192,224,256,320,0]
        let v2l3: [Int] = [0,8,16,24,32,40,48,56,64,80,96,112,128,144,160,0]
        let br = v1 ? v1l3[brIdx] : v2l3[brIdx]
        guard br > 0, fileSize > from else { return 0 }
        return Double(fileSize - from) * 8 / Double(br * 1000)
    }

    // MP4: 顶层找 moov 整块载入内存，递归走 udta>meta(+4)>ilst，顺路读 mvhd 时长
    private static func parseMP4(_ h: FileHandle, fileSize: Int64, into m: inout AudioMeta) {
        var pos: Int64 = 0
        while pos + 8 <= fileSize {
            try? h.seek(toOffset: UInt64(pos))
            guard let hd = read(h, 8), hd.count == 8 else { return }
            let size = Int64(u32(hd, 0))
            let type = [UInt8](hd.subdata(in: 4..<8))
            guard size >= 8, pos + size <= fileSize else { return }
            if type == Array("moov".utf8) {
                guard let body = read(h, Int(size - 8)) else { return }
                walkMP4(body, range: 0..<body.count, skipHeader: false, into: &m)
                return
            }
            pos += size
        }
    }

    private static func walkMP4(_ d: Data, range: Range<Int>, skipHeader: Bool, into m: inout AudioMeta) {
        var o = range.lowerBound + (skipHeader ? 4 : 0)
        while o + 8 <= range.upperBound {
            let size = u32(d, o)
            let type = [UInt8](d.subdata(in: (o+4)..<(o+8)))
            guard size >= 8, o + size <= range.upperBound else { return }
            let inner = (o+8)..<(o+size)
            if type == Array("mvhd".utf8), d.count > inner.lowerBound + 4 {
                let ver = d[inner.lowerBound]
                let base = inner.lowerBound + 4
                if ver == 0, d.count >= base + 16 {
                    let ts = u32(d, base + 8), dur = u32(d, base + 12)
                    if ts > 0 { m.duration = Double(dur) / Double(ts) }
                } else if d.count >= base + 28 {
                    let ts = u32(d, base + 16)
                    let dur = UInt64(u32(d, base + 20)) << 32 | UInt64(u32(d, base + 24))
                    if ts > 0 { m.duration = Double(dur) / Double(ts) }
                }
            } else if type == Array("udta".utf8) || type == Array("ilst".utf8) {
                walkMP4(d, range: inner, skipHeader: false, into: &m)
            } else if type == Array("meta".utf8) {
                walkMP4(d, range: Range(uncheckedBounds: (inner.lowerBound, range.upperBound)), skipHeader: true, into: &m)
            } else if type[0] == 0xA9 || type == Array("aART".utf8) {
                // ilst 条目：子 atom 'data'，payload 前有 8 字节 ver/flags+保留
                var p = inner.lowerBound
                while p + 16 <= inner.upperBound {
                    let dsz = u32(d, p)
                    let dtype = [UInt8](d.subdata(in: (p+4)..<(p+8)))
                    if dtype == Array("data".utf8), dsz >= 16, p + dsz <= inner.upperBound {
                        let payload = d.subdata(in: (p+16)..<(p+dsz))
                        if let s = String(data: payload, encoding: .utf8) {
                            let key = String(bytes: type, encoding: .isoLatin1) ?? ""
                            switch key {
                            case "\u{A9}nam": m.title = m.title ?? s
                            case "\u{A9}ART": m.artist = m.artist ?? s
                            case "\u{A9}alb": m.album = m.album ?? s
                            case "aART": m.albumArtist = m.albumArtist ?? s
                            default: break
                            }
                        }
                    }
                    p += max(Int(dsz), 8)
                }
            }
            o += Int(size)
        }
    }

    // WAV: fmt 块的 byteRate + data 块大小
    private static func parseWAV(_ h: FileHandle, fileSize: Int64, into m: inout AudioMeta) {
        guard let hdr = read(h, 12), hdr.count == 12, hdr.prefix(4) == Data("RIFF".utf8)
        else { return }
        var byteRate = 0
        var dataSize: Int64 = 0
        var pos: Int64 = 12
        while pos + 8 <= fileSize {
            try? h.seek(toOffset: UInt64(pos))
            guard let ch = read(h, 8), ch.count == 8 else { break }
            let size = Int64(le32(ch, 4))
            let id = ch.prefix(4)
            if id == Data("fmt ".utf8), size >= 16 {
                guard let fmt = read(h, 16) else { break }
                byteRate = le32(fmt, 8)
            } else if id == Data("data".utf8) {
                dataSize = size
            }
            pos += 8 + size + (size & 1)
        }
        if byteRate > 0, dataSize > 0 { m.duration = Double(dataSize) / Double(byteRate) }
    }
}
