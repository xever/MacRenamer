//
//  MacRenameApp.swift
//  MacRename
//
//  应用程序入口：负责创建主窗口、注入全局状态、设置菜单栏。
//

import SwiftUI

/// 应用程序入口点。
/// `@main` 表示这是整个程序的启动位置（相当于其他语言的 main 函数）。
@main
struct MacRenameApp: App {

    /// 全局共享状态：保存勾选选项、规则列表、文件列表、历史记录等。
    /// `@StateObject` 保证这个对象在 App 生命周期内只创建一次。
    @StateObject private var settings = AppSettings()

    /// 描述 App 有哪些“场景”（窗口）。
    var body: some Scene {
        // WindowGroup 是 macOS 上最常见的主窗口场景。
        // 括号里的 "批量重命名" 会作为窗口标题显示。
        WindowGroup("MacRenamer") {
            ContentView()
                // 通过 environmentObject 把 settings 共享给所有子视图。
                // 子视图里用 @EnvironmentObject 就能拿到它。
                .environmentObject(settings)
                // 设置窗口的最小尺寸，避免布局太挤。
                .frame(minWidth: 800, minHeight: 600)
        }
        // 自定义菜单栏：在“文件”菜单里加上“选择文件夹 / 选择文件”等。
        .commands {
            // replacing: .newItem 表示替换系统默认的“新建窗口”等菜单项，
            // 换成我们自己的命令。
            CommandGroup(replacing: .newItem) {
                // “选择文件夹…”菜单项（快捷键 ⇧⌘O）
                Button("选择文件夹…") {
                    settings.chooseFolder()
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                // “选择文件…”菜单项（支持多选，快捷键 ⌘O）
                Button("选择文件…") {
                    settings.chooseFiles()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Divider()

                // 顺手也放一个“执行改名”菜单项（快捷键 ⌘R）
                Button("执行改名") {
                    settings.executeRename()
                }
                .keyboardShortcut("r", modifiers: [.command])
            }
            
            // 用空内容替换，从而移除默认的菜单组
                // 移除 Edit 菜单（剪切、拷贝、粘贴、撤销等）
                CommandGroup(replacing: .pasteboard) { }
                CommandGroup(replacing: .undoRedo) { }

                // 移除 View 菜单（通常包含全屏切换、工具栏显示等）
                CommandGroup(replacing: .toolbar) { }
                CommandGroup(replacing: .systemServices) { }
                CommandGroup(replacing: .sidebar) { } // 如果有侧边栏控制也可一并移除

                // 移除 Window 菜单（最小化、缩放、窗口列表等）
                CommandGroup(replacing: .windowList) { }
                CommandGroup(replacing: .windowArrangement) { }
                CommandGroup(replacing: .windowSize) { }
        }
    }
}
