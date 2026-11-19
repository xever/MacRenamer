//
//  RenameItem.swift
//  MacRename
//
//  定义一个“待重命名的条目”（可以是文件，也可以是文件夹）。
//

import Foundation

/// 一个待重命名的条目。
struct RenameItem: Identifiable {

    /// 唯一标识，供 SwiftUI 的 ForEach / Table 使用。
    let id = UUID()

    /// 原始文件/文件夹路径。改名成功后会被更新成新路径。
    var url: URL

    /// 是否是文件夹。
    let isDirectory: Bool

    /// 预计的新文件名（预览用，界面里用红色显示）。
    /// 为 nil 表示“名字没有变化”。
    var newName: String?

    /// 错误信息（比如“重名冲突”“新名称为空”等）。
    var error: String?

    /// 原始文件名（含扩展名），直接从路径计算得到。
    var originalName: String {
        url.lastPathComponent
    }
}
