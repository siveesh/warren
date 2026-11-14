// SPDX-License-Identifier: GPL-3.0-or-later
import SwiftUI

/// Shows `Help.md`, which ships inside the app, as a readable guide with a contents menu.
struct HelpView: View {
    private static let fallback = "# Warren Help\n\nHelp.md was not found in this build. Open a section from the sidebar; each page explains what it will do before it changes anything."

    private let content: String = {
        guard let url = Bundle.main.url(forResource: "Help", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return HelpView.fallback }
        return text
    }()

    private var blocks: [String] {
        content.components(separatedBy: "\n\n").map { $0.trimmingCharacters(in: .newlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                        helpBlock(block).id(index)
                    }
                }
                .textSelection(.enabled)
                .frame(maxWidth: 720, alignment: .leading)
                .padding(30)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar {
                ToolbarItem {
                    Menu("Contents", systemImage: "list.bullet") {
                        ForEach(blocks.indices.filter { blocks[$0].hasPrefix("## ") }, id: \.self) { index in
                            Button(String(blocks[index].dropFirst(3))) {
                                withAnimation { reader.scrollTo(index, anchor: .top) }
                            }
                        }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    @ViewBuilder
    private func helpBlock(_ block: String) -> some View {
        if block.hasPrefix("# ") {
            Text(String(block.dropFirst(2))).font(.largeTitle.weight(.semibold))
        } else if block.hasPrefix("## ") {
            Text(String(block.dropFirst(3))).font(.title2.weight(.semibold)).padding(.top, 10)
        } else if block.hasPrefix("### ") {
            Text(String(block.dropFirst(4))).font(.headline).padding(.top, 4)
        } else if block.hasPrefix("```") {
            Text(block.components(separatedBy: "\n").dropFirst().dropLast().joined(separator: "\n"))
                .font(.system(.callout, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        } else if block.hasPrefix("- ") || block.hasPrefix("1. ") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(block.components(separatedBy: "\n").enumerated()), id: \.offset) { _, line in
                    listLine(line)
                }
            }
        } else {
            inline(block).font(.body).lineSpacing(4)
        }
    }

    private func listLine(_ line: String) -> some View {
        let isBullet = line.hasPrefix("- ")
        let number = line.prefix { $0.isNumber }
        let text = isBullet ? String(line.dropFirst(2)) : String(line.drop { $0.isNumber || $0 == "." || $0 == " " })
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(isBullet ? "•" : "\(number).").foregroundStyle(.secondary).frame(minWidth: 16, alignment: .trailing)
            inline(text).lineSpacing(3)
        }
    }

    private func inline(_ text: String) -> Text {
        let formatted = (try? AttributedString(
            markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
        return Text(formatted)
    }
}
