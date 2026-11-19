//
//  ContentView.swift
//  MacRename
//
//  主界面。
//  布局从上到下：
//   1. 顶部勾选选项（忽略扩展名 / 包含子文件夹 / 文件夹改名）+ 添加规则按钮
//   2. 规则列表（可上下拖动排序）
//   3. 操作按钮栏（执行改名 / 清空列表 / 移除所选）+ 右侧“过滤”
//   4. 文件列表（原文件名 + 红色预览新名字）
//   5. 底部状态栏
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {

    /// 全局状态对象（由 App 注入）。
    @EnvironmentObject var settings: AppSettings

    /// 是否正有文件拖到窗口上（用于高亮提示）。
    @State private var isDropTargeted = false

    /// 文件列表里被选中的条目（用于“移除所选”）。
    @State private var selection: Set<RenameItem.ID> = []

    var body: some View {
        VStack(spacing: 0) {
            optionsBar
            Divider()
            rulesPanel
            Divider()
            actionBar
            Divider()
            fileList
            Divider()
            statusBar
        }
        // 让整个窗口都能接收拖拽文件。
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            settings.addDropped(providers: providers)
            return true
        }
        // 拖拽悬停时给一点淡色高亮提示。
        .background(Color.accentColor.opacity(isDropTargeted ? 0.06 : 0))
        // 执行改名完成后的提示弹窗。
        .alert("执行结果", isPresented: $settings.showRenameResult) {
            Button("好", role: .cancel) {}
        } message: {
            Text(settings.renameResultMessage)
        }
    }

    // MARK: - 顶部勾选选项

    private var optionsBar: some View {
        HStack(spacing: 24) {
            Toggle("忽略扩展名", isOn: $settings.ignoreExtension)
                .toggleStyle(.checkbox)

            Toggle("包含子文件夹", isOn: $settings.includeSubfolders)
                .toggleStyle(.checkbox)

            Toggle("文件夹改名", isOn: $settings.renameFolders)
                .toggleStyle(.checkbox)

            Spacer()

            addRuleMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    /// “添加规则”下拉菜单（每个规则名称右侧显示对应的快捷键）。
    private var addRuleMenu: some View {
        Menu {
            ForEach(RuleKind.allCases) { kind in
                Button {
                    settings.addRule(kind)
                } label: {
                    Text(kind.displayName)
                }
                // 核心修复：指定按键和 .option 修饰符
                .keyboardShortcut(KeyEquivalent(Character("\(kind.shortcutNumber)")), modifiers: .option)
            }
        } label: {
            Label("添加规则", systemImage: "plus")
        }
        .fixedSize()
    }

    // MARK: - 规则面板

    private var rulesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("重命名规则（从上到下依次执行，可拖动排序）")
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)

            if settings.rules.isEmpty {
                Text("还没有规则。点击右上角「+添加规则」开始 或 按下 ⌥ option")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // List 的 onMove 支持在 macOS 上直接拖动行进行排序。
                List {
                    ForEach(settings.rules) { rule in
                        RuleRowView(rule: rule)
                    }
                    .onMove { settings.moveRule(from: $0, to: $1) }
                }
                .listStyle(.inset)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 120, idealHeight: 180, maxHeight: 260)
    }

    // MARK: - 操作按钮栏

    private var actionBar: some View {
        HStack(spacing: 12) {
            // 执行改名（核心按钮）。
            Button {
                settings.executeRename()
            } label: {
                Label("执行改名", systemImage: "checkmark.circle.fill")
            }
            .tint(.orange) // 设置按钮背景为系统橙色
            .buttonStyle(.borderedProminent)
            .disabled(settings.items.isEmpty)

            // 清空列表。
            Button(action: {
                settings.clearItems()
                selection.removeAll()
            }) {
                // 使用 Label 组合图标和文字
                Label("清空列表", systemImage: "trash.fill")
            }
            .disabled(settings.items.isEmpty)

            // 移除所选。
            Button(action: {
                settings.removeItems(ids: selection)
                selection.removeAll()
            }) {
                // 使用 Label 组合图标和文字
                Label("移除所选", systemImage: "eject")
            }
            .disabled(selection.isEmpty)

            Spacer()

            // 右侧：按扩展名过滤。
            Text("过滤：")
                .foregroundColor(.secondary)
            filterMenu
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
    
 // MARK: - 过滤
    
    /// 过滤下拉菜单（按已拖入文件的后缀过滤，支持多选）。
    private var filterMenu: some View {
        Menu {
            // “全部”选项依然可以用 Button，因为它是单选逻辑（清空过滤）
            Button {
                settings.filterExtensions.removeAll()   // “全部” = 清空过滤
            } label: {
                if settings.filterExtensions.isEmpty {
                    Label("全部", systemImage: "checkmark")
                } else {
                    Text("全部")
                }
            }
            
            Divider()
            
            // 核心修复：将 Button 替换为 Toggle，并应用 .checkbox 样式
            ForEach(settings.availableExtensions, id: \.self) { ext in
                Toggle(isOn: Binding(
                    get: { settings.filterExtensions.contains(ext) },
                    set: { _ in settings.toggleFilterExtension(ext) }
                )) {
                    Text("  "+ext)
                }
                .toggleStyle(.checkbox) // 强制显示为 macOS 原生复选框
            }
        } label: {
            Label(settings.filterLabel, systemImage: "line.3.horizontal.decrease.circle")
        }
        .fixedSize()
    }

    // MARK: - 文件列表

    private var fileList: some View {
        Table(filteredItems, selection: $selection) {
            TableColumn("原文件名") { item in
                HStack(spacing: 6) {
                    Image(systemName: item.isDirectory ? "folder" : "doc")
                        .foregroundColor(item.isDirectory ? .accentColor : .secondary)
                    Text(item.originalName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .width(min: 180, ideal: 230, max: 500)

            TableColumn("新文件名（预览）") { item in
                if let newName = item.newName {
                    // 预览结果用红色显示。
                    Text(newName)
                        .foregroundColor(.red)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("（不变）")
                        .foregroundColor(.secondary)
                }
            }
            .width(min: 180, ideal: 230, max: 500)

            TableColumn("状态") { item in
                if let error = item.error {
                    Text(error)
                        .foregroundColor(.orange)
                } else {
                    Text("")
                }
            }
            .width(min: 30, ideal: 50, max: 100)
            
            TableColumn("路径") { item in
                Text(item.url.path)
                        .foregroundColor(.black)
                        .lineLimit(1) // 限制为单行
                        .truncationMode(.middle) // 中间省略，保留头尾信息
                        .help(item.url.path) // 鼠标悬停时显示完整路径
            }
            .width(min: 300, ideal: 350)
        }
        .overlay {
            // 没有文件时的提示。
            if settings.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("把文件或文件夹拖到这里，或使用菜单「文件」选择")
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// 根据“过滤”条件过滤后的列表。
    private var filteredItems: [RenameItem] {
        settings.items.filter { settings.passesFilter($0) }
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
            Text(settings.statusText)
                .foregroundColor(.secondary)
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }
}
