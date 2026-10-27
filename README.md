# BrickPod

把 Apple Music 网站 404 页面里藏着的初代 iPod 彩蛋，做成一个 macOS 桌面小应用：
无边框透明窗口，窗口本身就是一台悬浮在桌面上的 iPod，可以导入本地音乐播放，
还能玩隐藏的打砖块（Settings → About，按住中间键 5 秒）。

- **下载**：在 [Releases](../../releases) 下载 `BrickPod.zip`，解压后拖进「应用程序」。
  支持 Apple 芯片和 Intel，macOS 12+。没有 Apple 公证，第一次打开需要在
  「系统设置 → 隐私与安全性」里点「仍要打开」
- **自己编译**：`cd mac-app && ./build.sh`（只需要 Xcode Command Line Tools）
- **导入音乐**：⌘O 导入，⌘L 管理曲库（删除、改歌名/歌手/专辑）
- 仓库里**不含音乐**，也不含个人曲库清单 `includes/ipod/data/us/en-US.json`：
  原生 App 不需要它；要用下面的 Chrome/server.py 方式，先运行
  `python3 make-library.py` 生成，或者复制 Apple 原版 `en-US.json.orig`

iPod 组件、字体和图片的版权归 Apple 所有，见文末版权说明。下面是原始离线镜像的说明和开发笔记。

---

## Apple Music 404 页面 iPod 模拟器 · 离线镜像

原版页面：https://music.apple.com/us/new/1122 （任何不存在的路径都会显示）
这是该页面及全部静态资源的完整本地镜像，**未修改 Apple 的任何代码**，
离线（断网）状态下可完整使用：iPod 外观、点控轮导航、菜单、打砖块小游戏。

## 纯净模式（overlay.css）

页面顶部注入了一份本地 CSS（`overlay.css`，非 Apple 代码），隐藏了侧栏、
"Page Not Found" 文案区、Apple Music 图标、面包屑、底部播放条（未接功能的
音量/播放列表控件）、推广横幅和地区选择器，只保留居中的 iPod。

- 想恢复官方原版布局：删除两份 `index.html` 里的
  `<link rel="stylesheet" href="/overlay.css">` 这一行（或直接用 `*.orig` 备份覆盖）
- 想微调（iPod 大小/位置）：直接编辑 `overlay.css`

## 中文显示修复（ipod-cjk.js）

屏幕字体 ChicagoKare **没有任何中文字形**（解剖 woff2：214 个字形 CJK 覆盖为 0），
中文回退到系统中文字体（行度量约 1.42em），而菜单行是固定 26px 高 +
`overflow:hidden`，中文字形**上下被裁几像素**；英文用 ChicagoKare 本尊墨迹小，
永远没事——这就是"调字号也没用、只有中文被遮"的原因。

`ipod-cjk.js`（我写的，非 Apple 代码）的修法：文档级注册一个度量收紧的
本地字体（size-adjust 86% + ascent/descent-override），`unicode-range`
只劫持 CJK 码位。中文以 86% 大小完整显示（不再被裁，视觉上比英文略小），
英文数字和默认 26px 字号完全不变。

两个 Chrome 的坑（都踩过，别再踩）：

- `@font-face` 写进 Shadow DOM 的 `<style>` 不会注册，必须放文档级
- `local()` 用字体家族名（"PingFang SC"）全部 error，必须用 **PostScript 名**
  （如 `PingFangSC-Regular`）

想撤销此修复：删除三个页面里的 `<script src="/ipod-cjk.js">` 即可。

## 本地曲库（已启用）

当前 iPod 曲库 = `music/` 文件夹里的音乐（Apple 原 1029 首已移除，
原版 JSON 备份在 `includes/ipod/data/us/en-US.json.orig`）。

**加歌 / 重建曲库：**

```bash
# 把新专辑放进 music/ 后：
python3 make-library.py          # 扫描 music/ 重建 JSON（读标签，需 ffprobe）
python3 make-library.py ~/Music  # 也可以扫任意目录
```

- 支持 mp3 / flac / m4a / wav / ogg / opus
- 歌名/歌手/专辑优先读文件标签，缺失时用文件名/文件夹名
- 每张专辑自动生成一个播放列表
- 之后刷新 iPod 页面即可（widget 窗口里 Cmd+R）

**踩过的坑（别再踩）：**

- `web-music-ipod` 的 `locale` 是对象属性 `{storefront, language}`，
  不要在 HTML 里写 `locale="en-US"` 字符串——会覆盖默认值导致
  storefront 变 undefined、曲库加载失败。不设置 = 默认 us/en-US。
- `server.py` 对 `/assets/ /includes/ /music/` 等资源路径的 404 是真 404，
  不会用 HTML 兜底（否则组件会把 HTML 当 JSON 解析，报 No Music）。

## 使用方法

**方式一（原生 App · BrickPod）**：

```bash
cd mac-app && ./build.sh     # 产出 mac-app/BrickPod.app（~18MB，不含音乐）
open BrickPod.app
```

不依赖 Python / Chrome：**无边框透明窗口，窗口本身就是 iPod**（桌面配件风，
四周无白底）。WKWebView + 内嵌 Swift HTTP 服务器（随机端口，不与 server.py
的 8765 冲突）。

- 拖动：按住**机身任意位置**拖（光标是抓手）；点控轮上光标变手指，照常操作
- 关闭：鼠标移到 iPod 上，左上角浮现 ✕（Dashboard 风格）；或 `⌘W` / `⌘Q`
- **右键**设备：导入音乐 / 管理曲库 / 尺寸 / 置顶 / 退出
- 尺寸：小/中/大（⌘1/⌘2/⌘3），启动时屏幕放不下会自动降档
- `⌘T` 悬浮置顶、`⌘R` 重载；位置/尺寸/置顶会记住

**曲库（不内置在 App 里）**：音乐放在 `~/Library/Application Support/BrickPod/music/`，
曲库 JSON 也在同目录，重建/升级 App 不丢歌。

- 导入：`⌘O`（文件 → 导入音乐…）。导入是**复制**一份进曲库，原文件不动。
  也可以把文件拖到 iPod 上（拖 mp3 已实机确认；拖文件夹未实测）
- 支持 flac / mp3 / m4a / wav / aiff，标签由 App 自己解析（不需要 ffprobe）
- 拖文件夹按专辑归档；拖"曲库根"（只有子文件夹里有歌）会自动摊平一层；
  散文件进「导入的音乐」；重复导入自动跳过
- 每张专辑自动生成一个播放列表（规则同 make-library.py）
- 首次启动若曲库为空，会自动导入项目里的 `Music/`
- **管理曲库**（`⌘L`）：左栏按 全部 / 歌手 / 专辑 浏览；点表头排序；列宽可拖
  - 删除：选中后按 Delete 或「移到废纸篓」（可恢复）；右键左栏的歌手/专辑可整批删
  - 改信息：双击单元格改歌名/歌手/专辑；多选后「编辑信息…」批量改
    （多个值的字段留空 = 不改；清空某项 = 恢复文件原标签）
  - 修改不写进音频文件，存在曲库旁的 `overrides.json`，重建时盖在标签上
- 启动时按曲库文件夹自动同步：在 Finder 里手动增删文件也会反映到 iPod
- 「文件 → 清空曲库…」把曲库里的副本全部移到废纸篓，不动原文件

**装到另一台 Mac**：`build.sh` 会同时产出 `mac-app/BrickPod.zip`（约 6MB）。

- 支持 Apple 芯片和 Intel（通用二进制），要求 macOS 12 及以上
- 拷过去解压，把 BrickPod.app 拖进「应用程序」
- 签名是本机临时签名（ad-hoc），没有 Apple 公证：第一次打开会被拦。
  右键 App →「打开」；macOS 15 起要去「系统设置 → 隐私与安全性」底部点
  「仍要打开」。或者终端执行 `xattr -dr com.apple.quarantine /Applications/BrickPod.app`
- 曲库不在 App 里：新机器上是空的，用 ⌘O 导入。想带上现在的曲库（含改过的
  歌名），把 `~/Library/Application Support/BrickPod/` 整个文件夹拷到新机器同一位置
- 只限自己的设备使用：里面是 Apple 的代码和字体，别分发

**方式二（Chrome widget）**：双击 `启动iPod.command` —— 会弹出一个独立的 iPod 小窗口（Chrome app 模式，
无地址栏/标签页，像桌面 Widget 一样悬着，尺寸 600×1000）。

底层逻辑：

- 服务端 `server.py` 的根路径 `/` 直接返回 `widget.html`（我写的极简宿主页，
  只挂载原版 `web-music-ipod` 组件，底色与官网一致）
- 完整原版 404 页面仍在：http://localhost:8765/us/new/1122 （带 overlay.css 净化，iPod 居中）
- 访问任何其他不存在的路径也会渲染原版 404 页（SPA 回退，和官网行为一致）

手动启动：

```bash
cd ~/Downloads/MyAI/apple-ipod-404
python3 server.py 8765
# 然后访问 http://localhost:8765/  （widget）
#     或 http://localhost:8765/us/new/1122  （完整原版页面）
```

- 支持 HTTP Range（音频拖动进度需要）
- 端口被占用时说明服务已在运行，直接开浏览器即可
- widget 小窗口是独立的 Chrome 实例（`~/.ipod-widget-profile`），
  不影响你正在用的浏览器窗口；关掉窗口后再双击启动器即可重开

## 操作方式（和官网一样）

- 在点控轮圆环上**按住拖动**＝旋转滚轮（菜单上下移动）
- 圆环**上 / 下 / 左 / 右**四个位置＝快进快退等按键，中间圆键＝确认
- MENU 键返回上级
- 打砖块游戏（Brick）：Settings → **About**，**按住中间确认键 5 秒**进入（和原版 iPod 彩蛋一样）。转滚轮移动挡板，按中间键发球，MENU 退出

## 曲库数据（接你自己的本地音乐）

iPod 的曲库完全由一个 JSON 驱动，没有任何代码写死：

```
includes/ipod/data/us/en-US.json
```

结构（schemaVersion 3）：

- `songs[]`：`id` / `name` / `artistName` / `artistIds` / `previewUrl`
- `artists[]`：`id` / `name` / `songIds`
- `playlists[]`：`id` / `name` / `url` / `songIds`

**接入本地曲库的步骤（之后想做的时候）：**

1. 把你的音乐文件放进本目录，比如 `music/xxx.mp3`
2. 在 `en-US.json` 里把对应歌曲的 `previewUrl` 改成 `music/xxx.mp3`
   （相对路径即可，同源请求；也可以直接生成一份全新的 JSON，schema 照抄）
3. 刷新页面，iPod 里就能播放你的音乐了

原版 JSON 里 1029 首歌的 `previewUrl` 指向 Apple 的流媒体（30 秒试听），
这部分需要联网；页面、游戏、菜单全部离线可用。

## 目录说明

- `us/new/1122/index.html` — 原版 404 页面 HTML（根目录 `index.html` 是同一份）
- `assets/` — 主程序、所有懒加载 chunk、字体、图标（官网构建产物）
- `includes/ipod/` — **iPod 模拟器本体**（web-music-ipod.esm.js）+ 曲库数据
- `includes/js-cdn/musickit/`、`static-commerce/` — 页面引用的官方组件
- `app.html` — 原生 App 专用宿主页（铺满/无倒影，非 Apple 代码）
- `server.py` / `启动iPod.command` — 本地启动器（我写的，非 Apple 代码）
- `mac-app/` — 原生 App：Swift 源码 + build.sh（编译、打包 webroot、ad-hoc 签名）

## mac-app 架构与踩坑（别再踩）

- `Sources/HTTPServer.swift` — Network.framework 实现的本地 HTTP 服务器，
  路由语义照抄 `server.py`（`/`→widget、资源缺失真 404、未知路由 SPA 回退），
  支持 Range/206/416；所有响应带 `Cache-Control: no-store`
  （WKWebView 有磁盘缓存，不加这个改了页面不生效）
- `Sources/AppDelegate.swift` — 无边框透明窗口 + WKWebView + 菜单；
  页面 console 会转发到 stdout，终端跑二进制即可排障
- **NWListener 交出的新连接必须显式 `conn.start(queue:)`**，否则连接挂起无响应
- 透明窗口三件套：`styleMask=[.borderless]` + `isOpaque=false` +
  `backgroundColor=.clear`（NSWindow），WebView 侧要
  `setValue(false, forKey:"drawsBackground")` + `underPageBackgroundColor=.clear`
- **整机拖动**：WKWebView 不响应 `isMovableByWindowBackground`。做法是
  app.html 在 mousedown 时判定位置——点控轮**圆内**是控件（`.click-wheel`
  是 280×280 方块，四角不算，所以用几何判定），其余（含屏幕）发 `drag`
  消息给原生；IPodWebView 记下 mouseDown 事件，收到消息后 `performDrag`，
  结束后补发一个 mouseUp 给页面。光标同一套判定（抓手/手指）。
  早期版本用顶部原生拖拽条，注意 WKWebView 是 flipped 坐标系，
  y=0 在顶——当初写成 `height-52` 结果贴到了底部
- 组件缩放是**阶梯式容器查询**（宿主 ≥440px 才是 scale=1 档、设备 415px 封顶；
  440/400/360 三档降级）。宿主固定 440px + 外层 `transform: scale`。
  **不能用 CSS zoom**——WebKit 里容器查询按 zoom 后的宽度算，zoom 越缩档位
  越低，死锁；也别只按宽度放大——组件在设备下方还有倒影区的布局高度，
  会把点控轮底部裁掉
- 倒影是 `.ipod-container` 的 `-webkit-box-reflect`（shadow DOM 内），
  app.html 往 shadow root 注入样式干掉（同 ipod-cjk.js 套路）
- 无边框窗口不能拖边缩放：尺寸走菜单档位，`window.__ipod` JS API
  （app.html 提供 apply/extent）由 native 调用，窗口尺寸=设备缩放后尺寸
- FLAC 在 WKWebView 原生可解码播放（`IPOD_AUDIOTEST=1` 跑过真实验证）；
  ogg/opus 容器 Safari 系不支持，所以导入时直接过滤掉
- `Sources/LibraryBuilder.swift` — make-library.py 的原生版（标签解析 + JSON）。
  **字节序别搞混**：FLAC 块头/STREAMINFO、MP4 atom 是大端；Vorbis Comment
  和 WAV(RIFF) 是小端。ID3 文本帧要去 BOM、截掉 `\0`（否则屏幕上出方块）；
  M4A 的 `©nam` 里 0xA9 不是 ASCII，atom 名要按 Latin-1 解码
- 曲库缺失时写空 JSON（`songs: []`），别让组件拿到 404
- **改名 BrickPod**：App 名/bundle id（`local.nanxian.brickpod`）/数据目录都换了。
  首次启动把 `Application Support/iPod` 整体移到 `BrickPod`，并从旧 bundle id
  复制设置（标记 `brickpod.migrated`，只做一次）。屏幕顶部和 About 第一行的
  "iPod" 在组件里写死（不走多语言文本），app.html 用 MutationObserver 把文字节点
  **完全等于** "iPod" 的换成 BrickPod，歌名里带 iPod 的不受影响
- **启动后往下跳一下**：窗口按默认组件高度创建、实测后再改尺寸。倒影两处都
  隐藏后组件高从 733 变成 692，默认值没跟着改，窗口先高 33pt 再以中心收缩，
  顶边下移。解法：默认 692 + 持久化实测高度；启动校正固定顶边；
  位置存**左上角**（存左下角的话换尺寸档后顶边会跑）
- **启动先大后小**：窗口按目标档位创建，但页面缩放若等加载完再由原生调用，
  中间会按 1.0 画出一帧（只露一部分）。解法：缩放值用 atDocumentStart 的
  WKUserScript 预先注入（`__ipodInitialScale`），app.html 在组件长出来时
  立刻排好，之前 `#fit` 保持 opacity 0，排好再淡入
- WebView 必须垫在最底层（`addSubview(_, positioned: .below, …)`），
  否则关闭钮/导入遮罩被盖住
- **拖放导入**：WKWebView 自己注册了文件拖放类型，事件会被最深层的它截走，
  外层 DropView 收不到（第一版拖放因此完全无效）。IPodWebView 重写全套
  dragging 方法转交给 DropView
- **导航锁**：组件里歌名等是链接（曲库 `url` 是 `/`），点了会整页跳到
  widget.html（白底、倒影、不缩放）。`decidePolicyFor` 里主框架只放行
  `/app.html`。注意 Swift 6 SDK 下 decisionHandler 签名是
  `@escaping @MainActor @Sendable`，写差了只会报 "nearly matches" 警告，
  方法被静默忽略
- 调试环境变量：`IPOD_ROOT=项目目录`（不打包直接跑）、`IPOD_SNAPSHOT=1`
  （保存截图到 /tmp/ipod-webview.png，含原生关闭钮）、`IPOD_AUDIOTEST=1`
  （试播曲库第一首）、`IPOD_IMPORT=目录`（首启迁移改从该目录导入）、
  `IPOD_NAVTEST=1`（模拟点链接，验证导航锁）、`IPOD_LIBTEST=1`（打开曲库窗口
  截图 + 排序/缩放自检）、`IPOD_DRAGTEST=1`（拖动/控件区域判定）、
  `IPOD_DOMDUMP=1`（打印组件 shadow DOM 结构）、`IPOD_EVALJS=文件`
  （页面里执行一段 JS，可 await，打印返回值）
- **要有「编辑」菜单**：⌘V/⌘C/⌘X/⌘A/⌘Z 靠菜单项沿响应链转发，纯代码建菜单
  漏了它，输入框里就粘贴不了（`IPOD_LIBTEST=1` 会模拟一次 ⌘V 自检，测完
  放弃编辑、恢复剪贴板、复位排序）
- 曲库窗口：列要 `[.autoresizingMask, .userResizingMask]` 才能手动拖列宽；
  NSStackView 默认按 gravity 区排，要靠右的按钮放进 `.trailing`

## 版权说明

本目录内的 Apple 代码、字体、图片等内容版权归 Apple 所有，
仅作个人离线学习/怀旧使用，请勿再分发或公开部署。
