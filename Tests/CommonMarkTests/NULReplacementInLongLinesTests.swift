/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Every U+0000 becomes U+FFFD (Insecure characters), at any offset in a line and however many NULs the line holds.
@Suite("NUL replacement in long lines")
struct NULReplacementInLongLinesTests {
    /// 40-byte lines with NULs at various offsets, each with its replaced form.
    private static let lines: [(line: String, replaced: String)] = [
        ("\u{0}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
         "\u{FFFD}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"),
        ("xxxxxxxxxxxxxxx\u{0}xxxxxxxxxxxxxxxxxxxxxxxx",
         "xxxxxxxxxxxxxxx\u{FFFD}xxxxxxxxxxxxxxxxxxxxxxxx"),
        ("xxxxxxxxxxxxxxxx\u{0}xxxxxxxxxxxxxxxxxxxxxxx",
         "xxxxxxxxxxxxxxxx\u{FFFD}xxxxxxxxxxxxxxxxxxxxxxx"),
        ("xxxxxxxxxxxxxxxxx\u{0}xxxxxxxxxxxxxxxxxxxxxx",
         "xxxxxxxxxxxxxxxxx\u{FFFD}xxxxxxxxxxxxxxxxxxxxxx"),
        ("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{0}xxxxxxxx",
         "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{FFFD}xxxxxxxx"),
        ("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{0}xxxxxxx",
         "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{FFFD}xxxxxxx"),
        ("xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{0}",
         "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{FFFD}"),
        ("\u{0}xxxxxxxxxxxxxx\u{0}\u{0}xxxxxxxxxxxxxx\u{0}\u{0}xxxxxx\u{0}",
         "\u{FFFD}xxxxxxxxxxxxxx\u{FFFD}\u{FFFD}xxxxxxxxxxxxxx\u{FFFD}\u{FFFD}xxxxxx\u{FFFD}"),
        ("xxxxxxxxxxxxxx\u{0}\u{0}\u{0}\u{0}\u{0}xxxxxxxxxxxxxxxxxxxxx",
         "xxxxxxxxxxxxxx\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}xxxxxxxxxxxxxxxxxxxxx"),
    ]

    /// The literal of each code block in `source`.
    private func codeBlockLiterals(_ source: String, options: MarkdownDocument.ParseOptions = []) -> [String] {
        MarkdownDocument.withParsedDocument(source, options: options) { doc in
            var out: [String] = []
            func walk(_ node: borrowing MarkdownNode) {
                if case .codeBlock = node.kind, let literal = node.literal() { out.append(literal) }
                node.children.forEach { walk($0) }
            }
            walk(doc.root)
            return out
        }
    }

    @Test("NULs anywhere in a long fenced code line", arguments: lines)
    func fencedCodeLine(line: String, replaced: String) {
        #expect(codeBlockLiterals("```\n" + line + "\n```\n") == [replaced + "\n"])
    }

    @Test("NULs in several long fenced code lines")
    func fencedCodeLines() {
        let source = """
            ```
            xxxxxxxxxxxxxxxx\u{0}xxxxxxxxxxxxxxxxxxxxxxx
            plain
            \u{0}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{0}
            ```

            """
        let expected = """
            xxxxxxxxxxxxxxxx\u{FFFD}xxxxxxxxxxxxxxxxxxxxxxx
            plain
            \u{FFFD}xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\u{FFFD}

            """
        #expect(codeBlockLiterals(source) == [expected])
        #expect(codeBlockLiterals(source, options: [.sourcePosition]) == [expected])
    }

    @Test("NULs anywhere in a long indented code line", arguments: lines)
    func indentedCodeLine(line: String, replaced: String) {
        #expect(codeBlockLiterals("    " + line + "\n") == [replaced + "\n"])
    }

    /// The list item's content is indented two columns, so the second tab of each `\t\t` line supplies the last two of
    /// the four columns an indented code block strips and leaves two spaces of content (Tabs).
    @Test("NULs in an indented code line whose indent splits a tab", arguments: lines)
    func splitTabCodeLine(line: String, replaced: String) {
        #expect(codeBlockLiterals("- foo\n\n\t\t" + line + "\n") == ["  " + replaced + "\n"])
    }

    @Test("NULs anywhere in a long HTML block line", arguments: lines)
    func htmlBlockLine(line: String, replaced: String) {
        let literals = MarkdownDocument.withParsedDocument("<div>\n" + line + "\n</div>\n") { doc in
            var out: [String] = []
            doc.root.children.forEach { if case .htmlBlock = $0.kind, let literal = $0.literal() { out.append(literal) } }
            return out
        }
        #expect(literals == ["<div>\n" + replaced + "\n</div>\n"])
    }

    @Test("NULs anywhere in a long paragraph line keep the text's source range", arguments: lines)
    func paragraphLine(line: String, replaced: String) throws {
        let (text, range) = try MarkdownDocument.withParsedDocument(line, options: [.sourcePosition]) { doc in
            var texts: [(String, String)] = []
            doc.root.children.forEach { paragraph in
                paragraph.children.forEach { inline in
                    if case .text = inline.kind, let literal = inline.literal(), let r = inline.sourceRange {
                        texts.append((literal, "\(r.lowerBound.line):\(r.lowerBound.column)-\(r.upperBound.line):\(r.upperBound.column)"))
                    }
                }
            }
            try #require(texts.count == 1)
            return texts[0]
        }
        #expect(text == replaced)
        #expect(range == "1:1-1:41")
    }
}
