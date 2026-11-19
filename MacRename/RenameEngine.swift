//
//  RenameEngine.swift
//  MacRename
//
//  重命名引擎：负责根据“规则列表”计算一个新文件名。
//  这里全部是纯计算（不涉及界面），方便理解和测试。
//

import Foundation

/// 重命名引擎。
/// 所有方法都是静态方法，直接调用即可。
enum RenameEngine {

    // MARK: - 对外主入口

    /// 根据规则计算新文件名。
    /// - Parameters:
    ///   - fullName: 原始文件名（含扩展名），例如 "photo.JPG"
    ///   - creationDate: 文件的创建日期（用于“日期”类随机规则）
    ///   - rules: 规则数组，按顺序执行
    ///   - ignoreExtension: 是否忽略扩展名
    ///   - ordinal: 该文件在列表里的序号（从 1 开始，用于“序号”规则）
    /// - Returns: 计算后的新文件名（含扩展名）
    static func applyRules(to fullName: String,
                           creationDate: Date,
                           rules: [RenameRule],
                           ignoreExtension: Bool,
                           ordinal: Int) -> String {
        // 把文件名拆成“基础名”和“扩展名”两部分。
        let parts = splitName(fullName)

        // 当前正在处理的名字：
        //   - 忽略扩展名：只处理基础名，扩展名最后原样拼回。
        //   - 不忽略扩展名：处理完整名字（扩展名也参与规则）。
        var name: String
        if ignoreExtension {
            name = parts.base
        } else {
            name = fullName
        }

        // 按顺序执行每一条规则。
        for rule in rules {
            switch rule.kind {
            case .transform:
                name = applyTransform(rule.transform, to: name)
            case .random:
                name = applyRandom(rule.random, to: name, creationDate: creationDate)
            case .insert:
                name = applyInsert(rule, to: name)
            case .replace:
                name = applyReplace(rule, to: name)
            case .delete:
                name = applyDelete(rule, to: name)
            case .sequence:
                name = applySequence(rule, to: name, ordinal: ordinal)
            }
        }

        // 忽略扩展名时，把原扩展名拼回去。
        if ignoreExtension {
            if parts.ext.isEmpty {
                return name
            } else {
                return name + "." + parts.ext
            }
        } else {
            return name
        }
    }

    // MARK: - 拆分文件名

    /// 把文件名拆成“基础名”和“扩展名（不含点）”。
    /// 例如 "photo.JPG" -> (base: "photo", ext: "JPG")。
    private static func splitName(_ fullName: String) -> (base: String, ext: String) {
        guard let dotIndex = fullName.lastIndex(of: "."),
              dotIndex != fullName.startIndex else {
            // 没有扩展名，或者是以 "." 开头的隐藏文件（如 ".gitignore"）。
            return (fullName, "")
        }
        let base = String(fullName[..<dotIndex])
        let ext = String(fullName[fullName.index(after: dotIndex)...])
        return (base, ext)
    }

    // MARK: - 转换规则

    private static func applyTransform(_ option: TransformOption, to name: String) -> String {
        switch option {
        case .none:
            return name

        case .upperAll:
            return name.uppercased()

        case .lowerAll:
            return name.lowercased()

        case .capitalizeFirst:
            // 首字母大写（其余保持不变）。
            return capitalizeFirst(name)

        case .upperExtension, .lowerExtension:
            // 只改变扩展名（最后一个 "." 之后的部分）的大小写。
            // 注意：当“忽略扩展名”勾选时，传入的 name 是不含扩展名的基础名，
            // 里面没有 "."，所以这里会自然变成“什么都不做”，正好符合要求。
            guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
                return name
            }
            let base = String(name[..<dotIndex])
            let ext = String(name[name.index(after: dotIndex)...])
            let newExt = (option == .upperExtension) ? ext.uppercased() : ext.lowercased()
            return base + "." + newExt
        }
    }

    private static func capitalizeFirst(_ s: String) -> String {
        guard let first = s.first else { return s }
        return String(first).uppercased() + String(s.dropFirst())
    }

    // MARK: - 随机规则

    private static func applyRandom(_ option: RandomOption, to name: String, creationDate: Date) -> String {
        switch option {
        case .none:
            return name

        case .letters8:
            // 用 8 位随机字母替换掉整个名字。
            return randomLetters(8)

        case .digits8:
            // 用 8 位随机数字替换掉整个名字。
            return randomDigits(8)

        case .date:
            // 用创建日期替换整个名字。
            return dateString(creationDate)

        case .datePlusRandom:
            // 日期 + 4 位随机数字。
            return dateString(creationDate) + randomDigits(4)

        case .originalPlusDate:
            // 原名 + 日期。这里的“原名”指当前这一时刻的名字；
            // 如果这条规则放在最前面，就等于文件的原始名字。
            return name + dateString(creationDate)
        }
    }

    private static func randomLetters(_ count: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
        return String((0..<count).compactMap { _ in letters.randomElement() })
    }

    private static func randomDigits(_ count: Int) -> String {
        let digits = "0123456789"
        return String((0..<count).compactMap { _ in digits.randomElement() })
    }

    /// 日期格式化器（使用文件创建日期）。
    /// 格式为：年(4位) 月(2位) 日(2位) 时(2位) 分(2位) 秒(2位)，例如 20260118153045。
    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        // 固定使用一种地区设置，避免受系统 12/24 小时制等影响。
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter
    }()

    private static func dateString(_ date: Date) -> String {
        dateFormatter.string(from: date)
    }

    // MARK: - 插入规则

    private static func applyInsert(_ rule: RenameRule, to name: String) -> String {
        switch rule.insertPosition {
        case .start:
            return rule.insertText + name
        case .end:
            return name + rule.insertText
        case .index:
            // 插到“第 N 个字符之后”（N 从 0 开始，0 表示开头）。
            return insert(rule.insertText, into: name, at: rule.insertIndex)
        }
    }

    private static func insert(_ text: String, into name: String, at charIndex: Int) -> String {
        if charIndex <= 0 { return text + name }
        let chars = Array(name)
        if charIndex >= chars.count { return name + text }
        let prefix = String(chars[0..<charIndex])
        let suffix = String(chars[charIndex...])
        return prefix + text + suffix
    }

    // MARK: - 替换规则

    private static func applyReplace(_ rule: RenameRule, to name: String) -> String {
        // 查找文字为空时，什么都不做（避免意外）。
        if rule.findText.isEmpty { return name }

        if rule.useRegex {
            return regexReplace(rule.findText, in: name, with: rule.replaceText)
        } else {
            return name.replacingOccurrences(of: rule.findText, with: rule.replaceText)
        }
    }

    /// 用正则表达式替换。支持 $1、$2 等捕获组引用（和 Perl 类似）。
    private static func regexReplace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            // 正则写错了就原样返回，不报错，避免崩溃。
            return text
        }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    // MARK: - 删除规则

    /// 删除规则：从“指定位置”或“指定字符（定位符）”开始，往左或往右删除若干字符。
    private static func applyDelete(_ rule: RenameRule, to name: String) -> String {
        let chars = Array(name)
        guard !chars.isEmpty else { return name }

        // 1) 计算“锚点”字符的下标（从 0 开始）。
        let anchor: Int
        switch rule.deleteMode {
        case .position:
            if rule.deletePosition >= 1 {
                // 正数：从最左边数，1 表示第一个字符。
                anchor = rule.deletePosition - 1
            } else {
                // 负数：从最右边数，-1 表示最后一个字符。
                // 当“忽略扩展名”勾选时（默认），这里就是“除扩展名外的最右边”。
                anchor = chars.count + rule.deletePosition
            }
        case .locator:
            // 定位符：找到用户输入字符/字符串第一次出现的位置。
            guard !rule.deleteLocator.isEmpty,
                  let range = name.range(of: rule.deleteLocator) else {
                // 找不到定位符就不删。
                return name
            }
            anchor = name.distance(from: name.startIndex, to: range.lowerBound)
        }

        // 把锚点限制在有效范围内。
        let a = min(max(anchor, 0), chars.count - 1)
        let count = max(1, rule.deleteCount)   // 至少要删 1 个字符

        // 2) 计算要删除的范围 [lower, upper)。
        let lower: Int
        let upper: Int
        switch rule.deleteDirection {
        case .right:
            // 往右删：从锚点（含锚点）向右删 count 个字符。
            lower = a
            upper = min(chars.count, a + count)
        case .left:
            // 往左删：从锚点（含锚点）向左删 count 个字符。
            upper = a + 1
            lower = max(0, upper - count)
        }

        var result = chars
        result.removeSubrange(lower..<upper)
        return String(result)
    }

    // MARK: - 序号规则

    /// 序号规则：在名字的最前或最后，依次加上递增的序号。
    /// - Parameters:
    ///   - rule: 序号规则（含起始值、增量、位数、位置、分隔符）
    ///   - name: 当前名字
    ///   - ordinal: 该文件在列表里的序号（从 1 开始）
    private static func applySequence(_ rule: RenameRule, to name: String, ordinal: Int) -> String {
        // 序号 = 起始值 + (序号 - 1) * 增量
        let value = rule.sequenceStart + (ordinal - 1) * rule.sequenceStep

        // 把数字转成字符串，位数不够的在前面补 0（例如位数 3 -> 001、002）。
        let digits = String(value)
        let numberString = String(repeating: "0", count: max(0, rule.sequenceWidth - digits.count)) + digits

        switch rule.sequencePosition {
        case .front:
            // 最前：序号 + 分隔符 + 名字，例如 "001-名字"
            return numberString + rule.sequenceSeparator + name
        case .end:
            // 最后：名字 + 分隔符 + 序号，例如 "名字-01"
            return name + rule.sequenceSeparator + numberString
        }
    }
}
