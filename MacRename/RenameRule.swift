//
//  RenameRule.swift
//  MacRename
//
//  定义“重命名规则”以及各种下拉框的选项。
//

import Foundation
import SwiftUI

// MARK: - 各种下拉框的选项

/// 规则类型。
enum RuleKind: String, CaseIterable, Identifiable {
    case transform  // 转换（大小写等）
    case random     // 随机（随机字母/数字/日期等）
    case insert     // 插入文字
    case replace    // 替换（查找并替换，可选正则）
    case delete     // 删除（从指定位置/字符往左或往右删除若干字符）
    case sequence   // 序号（在最前/最后依次加上递增序号）

    var id: String { rawValue }

    /// 显示在界面上的中文名称。
    var displayName: String {
        switch self {
        case .transform: return "转换"
        case .random:    return "随机"
        case .insert:    return "插入"
        case .replace:   return "替换"
        case .delete:    return "删除"
        case .sequence:  return "序号"
        }
    }

    /// 该规则对应的快捷键编号（option + 数字，从 1 开始）。
    var shortcutNumber: Int {
        switch self {
        case .transform: return 1
        case .random:    return 2
        case .insert:    return 3
        case .replace:   return 4
        case .delete:    return 5
        case .sequence:  return 6
        }
    }

    /// 显示在“添加规则”下拉里的快捷键文字，例如 "⌥ + 1"。
    var shortcutDisplay: String {
        return "⌥ + \(shortcutNumber)"
    }
}

/// “转换”下拉框的选项。
enum TransformOption: String, CaseIterable, Identifiable {
    case none = "不选择"
    case upperExtension = "扩展名大写"
    case lowerExtension = "扩展名小写"
    case upperAll = "全部大写"
    case lowerAll = "全部小写"
    case capitalizeFirst = "首字母大写"

    var id: String { rawValue }
}

/// “随机”下拉框的选项。
enum RandomOption: String, CaseIterable, Identifiable {
    case none = "不选择"
    case letters8 = "随机字母"
    case digits8 = "随机数字"
    case date = "日期"
    case datePlusRandom = "日期+随机数"
    case originalPlusDate = "原名+日期"

    var id: String { rawValue }
}

/// “插入”规则里，插入位置的下拉选项。
enum InsertPosition: String, CaseIterable, Identifiable {
    case start = "开头"
    case end = "结尾"
    case index = "指定位置"

    var id: String { rawValue }
}

/// “删除”规则里，删除方式（位置 / 定位符）。
enum DeleteMode: String, CaseIterable, Identifiable {
    case position = "位置"   // 从指定位置开始删
    case locator = "定位符"  // 从指定字符处开始删

    var id: String { rawValue }
}

/// “删除”规则里，删除方向。
enum DeleteDirection: String, CaseIterable, Identifiable {
    case left = "左"   // 往左删
    case right = "右"  // 往右删

    var id: String { rawValue }
}

/// “序号”规则里，序号位置（最前 / 最后）。
enum SequencePosition: String, CaseIterable, Identifiable {
    case front = "最前"  // 加在最前面
    case end = "最后"    // 加在最后面

    var id: String { rawValue }
}

// MARK: - 规则对象

/// 一条重命名规则。
///
/// 这里特意用“类”而不是“结构体”，并给每个字段加 `@Published`：
/// 这样修改规则里的任意字段，界面都能实时刷新、重新计算预览。
final class RenameRule: ObservableObject, Identifiable {

    /// 唯一标识。
    let id = UUID()

    /// 规则类型。
    @Published var kind: RuleKind

    /// 转换规则：下拉框选中的选项。
    @Published var transform: TransformOption

    /// 随机规则：下拉框选中的选项。
    @Published var random: RandomOption

    /// 插入规则：要插入的文字。
    @Published var insertText: String

    /// 插入规则：插入位置（开头 / 结尾 / 指定位置）。
    @Published var insertPosition: InsertPosition

    /// 插入规则：当位置是“指定位置”时，插到第几个字符之后。
    @Published var insertIndex: Int

    /// 替换规则：要查找的文字（或正则表达式）。
    @Published var findText: String

    /// 替换规则：替换后的文字。
    @Published var replaceText: String

    /// 替换规则：是否按正则表达式处理。
    @Published var useRegex: Bool

    /// 删除规则：删除方式（位置 / 定位符）。
    @Published var deleteMode: DeleteMode

    /// 删除规则：位置模式下的数字（1 = 最左边，-1 = 除扩展名外的最右边）。
    @Published var deletePosition: Int

    /// 删除规则：定位符模式下的指定字符。
    @Published var deleteLocator: String

    /// 删除规则：删除方向（往左 / 往右）。
    @Published var deleteDirection: DeleteDirection

    /// 删除规则：删除的字符个数。
    @Published var deleteCount: Int

    /// 序号规则：序号位置（最前 / 最后）。
    @Published var sequencePosition: SequencePosition

    /// 序号规则：起始值（1~10）。
    @Published var sequenceStart: Int

    /// 序号规则：增量（1~10）。
    @Published var sequenceStep: Int

    /// 序号规则：位数（1~10，数字不够时前面补 0）。
    @Published var sequenceWidth: Int

    /// 序号规则：分隔符（最长 5 个字符，不能含非法文件名字符）。
    @Published var sequenceSeparator: String

    /// 创建一个指定类型的新规则，并给所有字段一个默认值。
    init(kind: RuleKind) {
        self.kind = kind
        self.transform = .none
        self.random = .none
        self.insertText = ""
        self.insertPosition = .start
        self.insertIndex = 0
        self.findText = ""
        self.replaceText = ""
        self.useRegex = false
        self.deleteMode = .position
        self.deletePosition = 1
        self.deleteLocator = ""
        self.deleteDirection = .right
        self.deleteCount = 1
        self.sequencePosition = .front
        self.sequenceStart = 1
        self.sequenceStep = 1
        self.sequenceWidth = 3
        self.sequenceSeparator = "-"
    }
}
