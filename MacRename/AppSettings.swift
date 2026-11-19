//
//  AppSettings.swift
//  MacRename
//
//  全局状态：保存顶部的勾选项、规则列表、文件列表、过滤条件、历史记录等，
//  并负责“选择文件/文件夹”“拖入文件”“计算预览”“真正执行改名”这些核心操作。
//

import Foundation
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 全局状态对象。
/// 继承 ObservableObject，用 @Published 标记的属性一旦变化，SwiftUI 界面会自动刷新。
final class AppSettings: ObservableObject {

    // MARK: - 顶部勾选选项

    /// 忽略扩展名（默认勾选）。
    /// 勾选后，所有规则都不会改变文件的扩展名（例如 .jpg）。
    @Published var ignoreExtension: Bool = true

    /// 包含子文件夹。
    /// 勾选后，拖入或选择文件夹时，会递归遍历它里面的所有子文件夹。
    @Published var includeSubfolders: Bool = false

    /// 文件夹改名。
    /// 勾选后，文件列表里也会显示文件夹本身，从而可以对文件夹改名。
    @Published var renameFolders: Bool = false

    // MARK: - 规则列表

    /// 顶部的重命名规则，按数组顺序从上到下依次执行。
    @Published var rules: [RenameRule] = []

    // MARK: - 文件列表与过滤

    /// 已经添加进来的文件/文件夹条目。
    @Published var items: [RenameItem] = []

    /// 当前选中的过滤后缀（可多选）。空集合表示“全部”（不过滤）。
    @Published var filterExtensions: Set<String> = []

    // MARK: - 改名结果提示（用于弹窗）

    /// 是否显示“执行结果”弹窗。
    @Published var showRenameResult: Bool = false

    /// 弹窗里显示的结果文字。
    @Published var renameResultMessage: String = ""

    // MARK: - 历史记录（“插入/替换/替换为”下拉里显示上次用过的文本）

    @Published var insertHistory: [String] = []
    @Published var findHistory: [String] = []
    @Published var replaceHistory: [String] = []

    // MARK: - 快捷键监听

    /// 全局快捷键监听器（用于 option+数字 添加规则）。
    private var keyMonitor: Any?

    /// 修饰键（flagsChanged）监听器，用于检测“单独按一下 Option”。
    private var optionMonitor: Any?

    /// Option 键当前是否处于按下状态。
    private var optionPressed = false

    /// Option 是否被当作修饰键用过（按住 Option 时又按了其它键）。
    private var optionUsedAsModifier = false

    /// 懒加载的“添加规则”NSMenu（供“单独按一下 Option”时弹出）。
    private var addRuleNSMenu: NSMenu?

    /// 强引用菜单项的回调对象，避免其被提前释放。
    private var menuTargets: [MenuTarget] = []

    // MARK: - 初始化

    init() {
        // 程序启动时，从 UserDefaults 读回之前保存过的历史记录。
        insertHistory = Self.loadHistory(key: "insertHistory")
        findHistory = Self.loadHistory(key: "findHistory")
        replaceHistory = Self.loadHistory(key: "replaceHistory")

        // 安装全局快捷键：option+1 ~ option+6 快速添加规则。
        installShortcutMonitor()
    }

    // MARK: - 快捷键

    /// 安装全局快捷键监听（只安装一次）。
    private func installShortcutMonitor() {
        guard keyMonitor == nil else { return }

        // 监听普通按键：option+1~6 添加规则。
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            // 按住 option 时又按了其它键，说明 option 被当作修饰键，
            // 之后松开 option 时就不再弹出菜单（避免和 option+1 等冲突）。
            if event.modifierFlags.contains(.option) {
                self.optionUsedAsModifier = true
            }
            // 命中快捷键就“吞掉”这个按键（返回 nil），否则原样返回继续传递。
            if self.handleShortcut(event) {
                return nil
            }
            return event
        }

        // 监听修饰键（Option）的按下/松开，用于“单独按一下 Option”弹出菜单。
        optionMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }
    }

    /// 处理 option+数字 快捷键，命中返回 true。
    private func handleShortcut(_ event: NSEvent) -> Bool {
        // 必须按住 option。
        guard event.modifierFlags.contains(.option) else { return false }
        // 不能同时按 command / control / shift。
        let forbidden: NSEvent.ModifierFlags = [.command, .control, .shift]
        guard event.modifierFlags.intersection(forbidden).isEmpty else { return false }
        // 取出按键本身对应的字符（忽略修饰键），例如 "1"。
        guard let key = event.charactersIgnoringModifiers else { return false }
        // 根据数字找到对应的规则类型。
        guard let kind = RuleKind.allCases.first(where: { String($0.shortcutNumber) == key }) else {
            return false
        }
        addRule(kind)
        return true
    }

    /// 处理修饰键变化：检测“单独按一下 Option”来弹出“添加规则”菜单。
    private func handleFlagsChanged(_ event: NSEvent) {
        let optionNow = event.modifierFlags.contains(.option)
        if optionNow && !optionPressed {
            // Option 刚按下：记录状态，并假设它是“单独按一下”。
            optionPressed = true
            optionUsedAsModifier = false
        } else if !optionNow && optionPressed {
            // Option 松开：如果中间没有按过其它键，就弹出“添加规则”菜单。
            optionPressed = false
            if !optionUsedAsModifier {
                // 延迟到下一个 runloop 再弹出，避免在事件处理中直接进入模态循环。
                DispatchQueue.main.async { [weak self] in
                    self?.showAddRuleMenu()
                }
            }
        }
    }

    /// 在鼠标当前位置弹出“添加规则”菜单（只构建一次）。
    private func showAddRuleMenu() {
        if addRuleNSMenu == nil {
            let menu = NSMenu(title: "添加规则")
            menuTargets.removeAll()
            for kind in RuleKind.allCases {
                let item = NSMenuItem(
                    title: "\(kind.displayName)   ⌥\(kind.shortcutNumber)",
                    action: #selector(MenuTarget.invoke),
                    keyEquivalent: ""
                )
                let target = MenuTarget { [weak self] in
                    self?.addRule(kind)
                }
                item.target = target
                menuTargets.append(target)   // 强引用，防止 target 被提前释放
                menu.addItem(item)
            }
            addRuleNSMenu = menu
        }
        addRuleNSMenu?.popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    // MARK: - 规则操作

    /// 添加一条指定类型的新规则。
    func addRule(_ kind: RuleKind) {
        rules.append(RenameRule(kind: kind))
        refreshPreviews()
    }

    /// 删除一条规则。
    func removeRule(_ rule: RenameRule) {
        rules.removeAll { $0.id == rule.id }
        refreshPreviews()
    }

    /// 拖动排序（List 的 onMove 回调）。
    func moveRule(from source: IndexSet, to destination: Int) {
        rules.move(fromOffsets: source, toOffset: destination)
        refreshPreviews()
    }

    /// 上移一条规则。
    func moveRuleUp(_ rule: RenameRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }), index > 0 else { return }
        rules.swapAt(index, index - 1)
        refreshPreviews()
    }

    /// 下移一条规则。
    func moveRuleDown(_ rule: RenameRule) {
        guard let index = rules.firstIndex(where: { $0.id == rule.id }), index < rules.count - 1 else { return }
        rules.swapAt(index, index + 1)
        refreshPreviews()
    }

    // MARK: - 选择文件 / 文件夹

    /// 通过顶部菜单“选择文件夹…”调用。
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false          // 不能选文件
        panel.canChooseDirectories = true     // 只能选文件夹
        panel.allowsMultipleSelection = true  // 允许一次选多个文件夹
        panel.canCreateDirectories = false
        panel.title = "选择文件夹"
        panel.message = "选择要重命名的文件夹（可多选）"
        panel.prompt = "选择"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    /// 通过顶部菜单“选择文件…”调用（支持多选）。
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true  // 支持多选
        panel.title = "选择文件"
        panel.message = "选择要重命名的文件（可多选）"
        panel.prompt = "选择"
        if panel.runModal() == .OK {
            add(urls: panel.urls)
        }
    }

    /// 处理拖拽进来的文件/文件夹。
    func addDropped(providers: [NSItemProvider]) {
        for provider in providers {
            // 只处理“文件 URL”类型的内容。
            guard provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) else { continue }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                // loadItem 的回调可能在后台线程，这里先把结果转成 URL。
                var url: URL?
                if let u = item as? URL {
                    url = u
                } else if let nsurl = item as? NSURL {
                    url = nsurl as URL
                } else if let data = item as? Data {
                    // 有时会以“书签数据”的形式返回，需要解析成 URL。
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let str = item as? String {
                    url = URL(string: str)
                }
                // 回到主线程更新界面（@Published 属性必须在主线程修改）。
                DispatchQueue.main.async {
                    if let url = url {
                        self.add(urls: [url])
                    }
                }
            }
        }
    }

    /// 核心：把一组 URL（文件或文件夹）按照顶部选项展开并加入列表。
    func add(urls: [URL]) {
        var collected: [URL] = []

        for url in urls {
            if isDirectory(url) {
                // 勾选了“文件夹改名”，就把这个文件夹本身也加进来。
                if renameFolders {
                    collected.append(url)
                }
                // 遍历文件夹内部内容（是否递归由“包含子文件夹”决定）。
                collectContents(of: url, into: &collected, recurse: includeSubfolders)
            } else {
                collected.append(url)
            }
        }

        // 去重后追加到列表（按“标准化路径”判断是否已经存在）。
        for url in collected {
            let standard = url.standardizedFileURL
            if !items.contains(where: { $0.url.standardizedFileURL == standard }) {
                items.append(RenameItem(url: url, isDirectory: isDirectory(url)))
            }
        }

        refreshPreviews()
    }

    /// 遍历一个文件夹里的内容（可递归）。
    private func collectContents(of directory: URL, into result: inout [URL], recurse: Bool) {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey]
        // 默认跳过隐藏文件（如 .DS_Store）和包（如 .app）。
        var options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
        if !recurse {
            // 不递归时，跳过子文件夹里的内容。
            options.insert(.skipsSubdirectoryDescendants)
        }
        guard let enumerator = fm.enumerator(at: directory, includingPropertiesForKeys: keys, options: options) else {
            return
        }
        for case let url as URL in enumerator {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            if isDir {
                // 只有勾选了“文件夹改名”才把文件夹加进来。
                if renameFolders {
                    result.append(url)
                }
            } else {
                result.append(url)
            }
        }
    }

    /// 判断一个 URL 是否是文件夹。
    private func isDirectory(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
        return values?.isDirectory ?? false
    }

    // MARK: - 预览与改名

    /// 重新计算所有条目的“预计新名字”，并检查重名/空名等错误。
    func refreshPreviews() {
        // 1. 计算每个条目的新名字。
        for index in items.indices {
            let item = items[index]
            let original = item.originalName
            let newName = RenameEngine.applyRules(
                to: original,
                creationDate: creationDate(of: item.url),
                rules: rules,
                ignoreExtension: ignoreExtension,
                ordinal: index + 1   // “序号”规则用它来生成递增的序号
            )
            if newName == original {
                // 名字没变，就不显示红色预览。
                items[index].newName = nil
                items[index].error = nil
            } else {
                items[index].newName = newName
                items[index].error = nil
            }
        }

        // 2. 检查“同一目录下重名”。
        var seen: [String: UUID] = [:]   // key = 父目录路径 + "/" + 新名字（小写）
        for index in items.indices {
            guard let newName = items[index].newName else { continue }
            let parent = items[index].url.deletingLastPathComponent().path
            let key = parent + "/" + newName.lowercased()
            if seen[key] != nil {
                items[index].error = "重名冲突"
            } else {
                seen[key] = items[index].id
            }
        }

        // 3. 检查“新名字为空”。
        for index in items.indices {
            if let newName = items[index].newName, newName.isEmpty {
                items[index].error = "新名称为空"
            }
        }
    }

    /// 获取文件的创建日期（拿不到就用当前时间）。
    private func creationDate(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate ?? Date()
    }

    /// 真正执行改名操作（只有点“执行改名”才会走到这里）。
    func executeRename() {
        let fm = FileManager.default

        // 只处理“有新名字、且没有错误、且符合当前过滤条件”的条目。
        let targets = items.filter {
            $0.newName != nil && $0.newName != $0.originalName && $0.error == nil && passesFilter($0)
        }

        // 先改“路径更深”的（子文件夹里的内容先改），
        // 避免父文件夹改名后，子文件的路径失效。
        let sortedTargets = targets.sorted { $0.url.path.count > $1.url.path.count }

        var successCount = 0
        var failCount = 0
        var messages: [String] = []

        for item in sortedTargets {
            guard let newName = item.newName else { continue }
            let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            do {
                try fm.moveItem(at: item.url, to: newURL)
                successCount += 1
            } catch {
                failCount += 1
                messages.append("\(item.originalName) → \(newName)：\(error.localizedDescription)")
            }
        }

        // 改完后：把成功改名的条目路径更新成新路径，再重新计算预览。
        for index in items.indices {
            let item = items[index]
            guard let newName = item.newName,
                  newName != item.originalName,
                  item.error == nil,
                  passesFilter(item) else { continue }
            let newURL = item.url.deletingLastPathComponent().appendingPathComponent(newName)
            if fm.fileExists(atPath: newURL.path) {
                items[index].url = newURL
            }
        }
        refreshPreviews()

        // 弹出结果提示。
        renameResultMessage = "成功改名 \(successCount) 个，失败 \(failCount) 个。"
        if !messages.isEmpty {
            renameResultMessage += "\n\n" + messages.prefix(5).joined(separator: "\n")
        }
        showRenameResult = true
    }

    // MARK: - 清空与移除

    /// 清空整个文件列表。
    func clearItems() {
        items.removeAll()
        filterExtensions.removeAll()
    }

    /// 移除选中的条目。
    func removeItems(ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
        refreshPreviews()
    }

    // MARK: - 过滤用扩展名列表

    /// 所有已添加文件的“扩展名”去重列表（小写），用于右侧的“过滤”下拉。
    var availableExtensions: [String] {
        let exts = items
            .filter { !$0.isDirectory }
            .map { $0.url.pathExtension.lowercased() }
            .filter { !$0.isEmpty }
        return Array(Set(exts)).sorted()
    }

    /// 判断某个条目是否符合当前的“后缀过滤”条件。
    func passesFilter(_ item: RenameItem) -> Bool {
        // 没选任何后缀 = 不过滤，全部通过。
        if filterExtensions.isEmpty { return true }
        // 文件夹没有后缀，不参与后缀过滤。
        guard !item.isDirectory else { return false }
        return filterExtensions.contains(item.url.pathExtension.lowercased())
    }

    /// 切换某个后缀的选中状态（用于过滤下拉框的多选）。
    func toggleFilterExtension(_ ext: String) {
        if filterExtensions.contains(ext) {
            filterExtensions.remove(ext)
        } else {
            filterExtensions.insert(ext)
        }
    }

    /// 过滤下拉框显示的标签文字。
    var filterLabel: String {
        if filterExtensions.isEmpty { return "全部" }
        let sorted = filterExtensions.sorted()
        if sorted.count == 1 { return sorted[0] }
        return "已选 \(sorted.count) 项"
    }

    // MARK: - 状态栏文字

    /// 底部状态栏提示文字。
    var statusText: String {
        if items.isEmpty {
            return "可直接拖拽文件夹或文件到框中"
        }
        let fileCount = items.filter { !$0.isDirectory }.count
        let folderCount = items.filter { $0.isDirectory }.count
        var parts: [String] = []
        if fileCount > 0 { parts.append("文件 \(fileCount) 个") }
        if folderCount > 0 { parts.append("文件夹 \(folderCount) 个") }
        return "已添加 " + parts.joined(separator: "、")
    }

    // MARK: - 历史记录读写

    /// 把一段文字加入“插入”历史（去重、最多保留 20 条）。
    func addToInsertHistory(_ text: String) {
        insertHistory = Self.updateHistory(insertHistory, with: text)
        Self.saveHistory(insertHistory, key: "insertHistory")
    }

    func addToFindHistory(_ text: String) {
        findHistory = Self.updateHistory(findHistory, with: text)
        Self.saveHistory(findHistory, key: "findHistory")
    }

    func addToReplaceHistory(_ text: String) {
        replaceHistory = Self.updateHistory(replaceHistory, with: text)
        Self.saveHistory(replaceHistory, key: "replaceHistory")
    }

    /// 把新文字放到历史列表最前面（去重、去空、限制条数）。
    private static func updateHistory(_ history: [String], with text: String) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return history }
        var list = history.filter { $0 != trimmed }
        list.insert(trimmed, at: 0)
        return Array(list.prefix(20))
    }

    private static func loadHistory(key: String) -> [String] {
        UserDefaults.standard.stringArray(forKey: key) ?? []
    }

    private static func saveHistory(_ history: [String], key: String) {
        UserDefaults.standard.set(history, forKey: key)
    }
}

/// 用于 NSMenu 菜单项回调的小工具（NSMenu 的菜单项需要 Objective-C 的 target/action）。
private final class MenuTarget: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    @objc func invoke() {
        handler()
    }
}
