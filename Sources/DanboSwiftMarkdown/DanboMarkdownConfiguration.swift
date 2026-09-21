//
//  DanboMarkdownConfiguration.swift
//  danbo-swift-markdown
//
//  渲染管线的全局配置：宿主 App 在启动时按需覆盖（如字体大小跟随 App 字号、
//  内部链接 scheme 使用 App 自己的标识）。全部在主线程读写，与渲染管线同一线程约定。
//

import AppKit

public enum DanboMarkdownConfiguration {
    /// 正文字号：段落、标题、表格表头等的基础字号。
    public static var bodyFontSize: CGFloat = 15

    /// 内部链接（折叠标题、任务 checkbox）使用的 URL scheme。
    /// 渲染出的链接只在库内部生成与识别，改成宿主 App 自己的标识即可避免冲突。
    public static var linkScheme: String = "danbo-swift-markdown"
}
