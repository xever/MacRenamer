//
//  HistoryTextField.swift
//  MacRename
//
//  带“历史记录”下拉的文本框。
//  右侧有一个小时钟按钮，点开能看到以前用过的文字，点击即可填入。
//

import SwiftUI

/// 带“历史记录”下拉的文本框。
struct HistoryTextField: View {

    /// 占位提示文字。
    let title: String

    /// 绑定到外部的文本内容。
    @Binding var text: String

    /// 历史记录列表（由外部传入）。
    let history: [String]

    /// 按下回车时回调，用来把当前文字保存进历史。
    let onCommit: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                // 按下回车时，把当前文字保存进历史。
                .onSubmit { onCommit() }

            // 历史记录下拉按钮。
            Menu {
                if history.isEmpty {
                    Text("暂无历史")
                } else {
                    ForEach(history, id: \.self) { item in
                        Button(item) {
                            // 点击某条历史，就把它填回输入框。
                            text = item
                        }
                    }
                }
            } label: {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundColor(.secondary)
            }
            .menuIndicator(.hidden)  // 隐藏系统自带的箭头，保持简洁
            .fixedSize()
            .help("历史记录（在输入框里按回车可把当前文字存进历史）")
        }
    }
}
