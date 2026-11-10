/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Storage for a code or HTML block line whose stripped indentation splits a tab or that holds a NUL.
///
/// Only the bytes that differ from the source are copied into the materialized string buffer: the tab's leftover
/// columns as spaces (Tabs) and each NUL's U+FFFD (Insecure characters). The rest of the line stays in the source. The
/// buffer also holds the line ending that joins lines.
@Suite("Code and HTML block lines copy only the bytes that differ from the source")
struct LiteralBlockLineStorageTests {

    private func materializedSize(_ source: String) -> Int {
        MarkdownDocument.withParsedDocument(source, options: [.sourcePosition]) { $0._materializedStringSize }
    }

    @Test("an indented code line whose indentation splits a tab")
    func indentedCodeSplitTab() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = ">\t\tfoo bar baz qux\n"
        #expect(materializedSize(source) == 1 + 2)
        #expect(TreeDump.dumpSegments(source) == """
            document
              block_quote
                code_block "" "  foo bar baz qux\\n" ["  ", "foo bar baz qux", "\\n"]

            """)
    }

    @Test("an indented code line holding NULs")
    func indentedCodeNUL() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = "    \u{0}\u{0}x\u{0}\n"
        #expect(materializedSize(source) == 1 + 9)
        #expect(TreeDump.dumpSegments(source) == """
            document
              code_block "" "\u{FFFD}\u{FFFD}x\u{FFFD}\\n" ["\u{FFFD}\u{FFFD}", "x", "\u{FFFD}", "\\n"]

            """)
    }

    @Test("the last indented code line, holding a NUL before spaces, keeps its spaces")
    func indentedCodeNULBeforeTrailingSpaces() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = "    a\u{0}  \n"
        #expect(materializedSize(source) == 1 + 3)
        #expect(TreeDump.dumpSegments(source) == """
            document
              code_block "" "a\u{FFFD}  \\n" ["a", "\u{FFFD}", "  ", "\\n"]

            """)
    }

    @Test("a trailing blank indented code line whose indentation splits a tab")
    func indentedCodeTrailingBlankSplitTab() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = ">     a\n>\t\t \n"
        #expect(materializedSize(source) == 1 + 2)
        #expect(TreeDump.dumpSegments(source) == """
            document
              block_quote
                code_block "" "a\\n" ["a", "\\n"]

            """)
    }

    @Test("a fenced code line holding a NUL")
    func fencedCodeNUL() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = "```\na\u{0}b\n```\n"
        #expect(materializedSize(source) == 1 + 3)
        #expect(TreeDump.dumpSegments(source) == """
            document
              code_block "" "a\u{FFFD}b\\n" ["a", "\u{FFFD}", "b", "\\n"]

            """)
    }

    @Test("an HTML block line holding a NUL")
    func htmlBlockNUL() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = "<div>\na\u{0}b\n"
        #expect(materializedSize(source) == 1 + 3)
        #expect(TreeDump.dumpSegments(source) == """
            document
              html_block "<div>\\na\u{FFFD}b\\n" ["<div>", "\\n", "a", "\u{FFFD}", "b", "\\n"]

            """)
    }

    @Test("an HTML block line whose indentation splits a tab")
    func htmlBlockSplitTab() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        let source = ">\t<div>\n"
        #expect(materializedSize(source) == 1 + 2)
        #expect(TreeDump.dumpSegments(source) == """
            document
              block_quote
                html_block "  <div>\\n" ["  ", "<div>", "\\n"]

            """)
    }
}
