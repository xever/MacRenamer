//
//  RuleRowView.swift
//  MacRename
//
//  单条规则的编辑行。根据规则类型显示不同的控件：转换 / 随机 / 插入 / 替换。
//

import SwiftUI

/// 单条规则的编辑行。
struct RuleRowView: View {

    /// 当前这一行正在编辑的规则。
    @ObservedObject var rule: RenameRule

    /// 全局设置（用于读取历史记录、刷新预览、删除/移动规则等）。
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        HStack(spacing: 8) {
            // 左侧的“拖动把手”图标，提示这一行可以上下拖动排序。
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary)

            // 规则类型名称。
            Text(rule.kind.displayName)
                .font(.callout.weight(.medium))
                .frame(width: 40, alignment: .leading)

            // 根据类型显示对应的编辑控件。
            controls

            Spacer(minLength: 4)

            // 上移 / 下移 / 删除按钮。
            HStack(spacing: 2) {
                Button {
                    settings.moveRuleUp(rule)
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .help("上移")

                Button {
                    settings.moveRuleDown(rule)
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .help("下移")

                Button {
                    settings.removeRule(rule)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("删除这条规则")
            }
        }
        .padding(.vertical, 4)
        // 只要规则里任意字段发生变化，就重新计算预览。
        .onReceive(rule.objectWillChange) { _ in
            // objectWillChange 是在“改变之前”发出的，
            // 所以放到主线程下一个循环再刷新，这样读到的就是更新后的新值。
            DispatchQueue.main.async {
                settings.refreshPreviews()
            }
        }
    }

    /// 根据规则类型返回不同的控件。
    @ViewBuilder
    private var controls: some View {
        switch rule.kind {
      // MARK: - 转换
        case .transform:
            Picker("", selection: $rule.transform) {
                ForEach(TransformOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
            
     // MARK: - 随机
        case .random:
            Picker("", selection: $rule.random) {
                ForEach(RandomOption.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 120)
            
     // MARK: - 插入
        case .insert:
            Text("插入文字")
            HistoryTextField(
                title: "要插入的文字",
                text: $rule.insertText,
                history: settings.insertHistory,
                onCommit: { settings.addToInsertHistory(rule.insertText) }
            )
            .frame(width: 200)

            Text("位置")
            Picker("", selection: $rule.insertPosition) {
                ForEach(InsertPosition.allCases) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 100)

            // 选择了“指定位置”时，再显示一个数字选择器。
            if rule.insertPosition == .index {
//                Stepper("第 \(rule.insertIndex) 个字符后", value: $rule.insertIndex, in: 0...1000)
//                    .fixedSize()
                
                HStack(spacing: 5) {
                    Text("第 ") + Text("\(rule.insertIndex)").foregroundStyle(.orange).font(.system(size: 16)) + Text(" 个字符后")
                    Stepper(value: $rule.insertIndex, in: 0...50){}
                        .labelsHidden()
                }
            }
            
     // MARK: - 替换
        case .replace:
            Text("查找")
            HistoryTextField(
                title: "要查找的文字",
                text: $rule.findText,
                history: settings.findHistory,
                onCommit: { settings.addToFindHistory(rule.findText) }
            )
            .frame(width: 180)

            Text("替换为")
            HistoryTextField(
                title: "替换后的文字",
                text: $rule.replaceText,
                history: settings.replaceHistory,
                onCommit: { settings.addToReplaceHistory(rule.replaceText) }
            )
            .frame(width: 180)

            Toggle("正则", isOn: $rule.useRegex)
                .toggleStyle(.checkbox)
            
     // MARK: - 正则表达式
            if rule.useRegex {
                // 勾选正则后，右侧出现“常用表达式”下拉框，
                // 提供一些日期、随机字符、纯数字等常用正则。
                Menu {
                    Button("日期：\\d{4}-\\d{2}-\\d{2}") {
                        rule.findText = #"\d{4}-\d{2}-\d{2}"#
                    }
                    Button("字符：[A-Za-z0-9]+") {
                        rule.findText = #"[A-Za-z0-9]+"#
                    }
                    Button("纯数字：\\d+") {
                        rule.findText = #"\d+"#
                    }
                    Button("纯字母：[A-Za-z]+") {
                        rule.findText = #"[A-Za-z]+"#
                    }
                } label: {
                    Label("常用表达式", systemImage: "chevron.down")
                }
                .menuIndicator(.hidden)
                .fixedSize()
            }
            
     // MARK: - 删除
        case .delete:
            // 左侧：单选框，选择“位置”或“定位符”。
            Picker("", selection: $rule.deleteMode) {
                Text("位置").tag(DeleteMode.position)
                Text("定位符").tag(DeleteMode.locator)
            }
            .pickerStyle(.radioGroup)
            .horizontalRadioGroupLayout()
            .fixedSize()

            if rule.deleteMode == .position {
                // 位置：按数字选择。1 表示最左边，-1 表示（忽略扩展名时）除扩展名外的最右边。
                HStack(spacing: 5) {
                 //   Text("第 \(rule.deletePosition) 个字符")
                    Text("第 ")+Text("\(rule.deletePosition)").foregroundStyle(.orange).font(.system(size: 16))+Text(" 个字符")
                    Stepper(value: $rule.deletePosition, in: -50...50) {}
                        .labelsHidden()
                }
                .help("1 表示最左边，-1 表示最右边")
            } else {
                // 定位符：输入一个指定字符，删除从该字符处开始。
                TextField("指定字符", text: $rule.deleteLocator)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 65)
            }

            // 右侧：往（左/右箭头）删除 xx 个字符。
            Text("往")
            Button {
                // 每次点击，方向在“左/右”之间切换。
                rule.deleteDirection = (rule.deleteDirection == .right) ? .left : .right
            } label: {
                Image(systemName: rule.deleteDirection == .right ? "arrow.right" : "arrow.left")
                    .foregroundStyle(rule.deleteDirection == .right ? .blue : .brown)
                        .fontWeight(.bold) // 加粗箭头线条，视觉上更清晰
            }
            .buttonStyle(.borderless)
            .help("点击切换删除方向")

            HStack(spacing: 5) {
                Text("删除 ") + Text("\(rule.deleteCount)").foregroundStyle(.orange).font(.system(size: 16)) + Text(" 个字符")
                Stepper(value: $rule.deleteCount, in: 1...50){}
                    .labelsHidden()
            }
            
     // MARK: - 序号
        case .sequence:
            // 位置：最前 / 最后。
            Picker("", selection: $rule.sequencePosition) {
                ForEach(SequencePosition.allCases) { position in
                    Text(position.rawValue).tag(position)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 80)

            // 起始值 / 增量 / 位数（都是 1~10 的数字）。
            numberStepper("起始", value: $rule.sequenceStart)
            numberStepper("增量", value: $rule.sequenceStep)
            numberStepper("位数", value: $rule.sequenceWidth)

            // 分隔符：最长 9 个字符，禁止非法文件名字符。
            Text("分隔符")
            TextField("分隔符", text: $rule.sequenceSeparator)
                .textFieldStyle(.roundedBorder)
                .frame(width: 100)
                .onChange(of: rule.sequenceSeparator) { _, newValue in
                    // 先限制长度，再去掉非法文件名字符（"/" 和 ":"）。
                    var cleaned = String(newValue.prefix(9))
                    cleaned = cleaned.replacingOccurrences(of: "\\", with: "")
                    cleaned = cleaned.replacingOccurrences(of: "/", with: "")
                    cleaned = cleaned.replacingOccurrences(of: ":", with: "")
                    if cleaned != rule.sequenceSeparator {
                        rule.sequenceSeparator = cleaned
                    }
                }
        }
    }

    /// 一个紧凑的“标签 + 数字”选择器（用于序号规则的起始值/增量/位数）。
    private func numberStepper(_ label: String, value: Binding<Int>) -> some View {
        HStack(spacing: 5) {
            Text("\(label) \(value.wrappedValue)")
            Stepper(value: value, in: 1...10) {}
                .labelsHidden()
        }
    }
}
