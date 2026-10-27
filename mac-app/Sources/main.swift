import AppKit

// 无 storyboard 启动：NSApplication + 程序化构建的窗口/菜单
setvbuf(stdout, nil, _IOLBF, 0)   // 重定向到文件时也按行刷新，排障日志不丢
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
