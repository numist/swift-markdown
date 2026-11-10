/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A code or HTML block's body holds a segment for each nonempty line's content and a `\n` segment for each line
/// ending, CRLF included. A line whose stripped indentation splits a tab holds the tab's leftover columns as a segment
/// of spaces before its content's segment.
@Suite("Code/HTML block segment content")
struct CodeBlockSegmentTests {

    // MARK: - Fenced code

    @Test("fenced multi-line body is one segment per line and line ending")
    func fencedMultiLine() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```swift\nlet x = 1\nlet y = 2\nprint(x)\n```\n") == """
            document
              code_block "swift" "let x = 1\\nlet y = 2\\nprint(x)\\n" ["let x = 1", "\\n", "let y = 2", "\\n", "print(x)", "\\n"]

            """)
    }

    @Test("fenced single-line body")
    func fencedSingleLine() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```\nonly line\n```\n") == """
            document
              code_block "" "only line\\n" ["only line", "\\n"]

            """)
    }

    @Test("fenced empty body has no segments")
    func fencedEmpty() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```\n```\n") == """
            document
              code_block "" "" []

            """)
    }

    @Test("fenced body preserves a trailing blank line")
    func fencedTrailingBlank() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```\ncode\n\n```\n") == """
            document
              code_block "" "code\\n\\n" ["code", "\\n", "\\n"]

            """)
    }

    @Test("fenced body preserves interior blank lines")
    func fencedInteriorBlanks() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```\na\n\n\nb\n```\n") == """
            document
              code_block "" "a\\n\\n\\nb\\n" ["a", "\\n", "\\n", "\\n", "b", "\\n"]

            """)
    }

    // MARK: - Indented code

    @Test("indented multi-line body is one segment per line and line ending")
    func indentedMultiLine() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("    line one\n    line two\n    line three\n") == """
            document
              code_block "" "line one\\nline two\\nline three\\n" ["line one", "\\n", "line two", "\\n", "line three", "\\n"]

            """)
    }

    @Test("indented code strips trailing blank lines")
    func indentedStripsTrailingBlanks() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("    code\n\n\nmore text\n") == """
            document
              code_block "" "code\\n" ["code", "\\n"]
              paragraph
                text "more text" ["more text"]

            """)
    }

    @Test("indented code keeps interior blank lines but strips trailing")
    func indentedInteriorVsTrailing() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("    a\n\n    b\n\n\nparagraph\n") == """
            document
              code_block "" "a\\n\\nb\\n" ["a", "\\n", "\\n", "b", "\\n"]
              paragraph
                text "paragraph" ["paragraph"]

            """)
    }

    // MARK: - Tabs

    @Test("tab-indented code body")
    func tabIndentedCode() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        // The tab is each line's four columns of indentation (Tabs), so the content starts after it.
        #expect(TreeDump.dumpSegments("\tcode line one\n\tcode line two\n") == """
            document
              code_block "" "code line one\\ncode line two\\n" ["code line one", "\\n", "code line two", "\\n"]

            """)
    }

    @Test("content tab beyond the code indent is preserved literally")
    func tabPreservedBeyondCodeIndent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        // The first tab is the code block's four columns of indentation; the second is content (Tabs).
        #expect(TreeDump.dumpSegments("\t\tfoo\n") == """
            document
              code_block "" "\\tfoo\\n" ["\\tfoo", "\\n"]

            """)
    }

    @Test("bullet-like content and its trailing tab stay literal in indented code")
    func tabAfterBulletContent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        // The leading tab is four columns of indentation, so the line is indented code and `-` is content.
        #expect(TreeDump.dumpSegments("\t-\t\n") == """
            document
              code_block "" "-\\t\\n" ["-\\t", "\\n"]

            """)
    }

    @Test("content tab is preserved on an indented-code continuation line")
    func tabPreservedOnContinuation() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("\tfoo\n\t\tbar\n") == """
            document
              code_block "" "foo\\n\\tbar\\n" ["foo", "\\n", "\\tbar", "\\n"]

            """)
    }

    @Test("a tab split by a block quote marker becomes its remaining columns as spaces")
    func tabSplitByContainerIndent() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        // The block quote marker takes `>` and one column of the first tab (Tabs). Of the six columns of indentation
        // left, four make the line indented code and two are content spaces.
        #expect(TreeDump.dumpSegments(">\t\tfoo\n") == """
            document
              block_quote
                code_block "" "  foo\\n" ["  ", "foo", "\\n"]

            """)
    }

    // MARK: - CRLF

    @Test("CRLF fenced code normalizes line endings")
    func crlfFenced() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("```\r\nx\r\ny\r\n```\r\n") == """
            document
              code_block "" "x\\ny\\n" ["x", "\\n", "y", "\\n"]

            """)
    }

    // MARK: - HTML blocks

    @Test("multi-line HTML block is one segment per line and line ending")
    func htmlMultiLine() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("<div>\n  <p>hi</p>\n</div>\n") == """
            document
              html_block "<div>\\n  <p>hi</p>\\n</div>\\n" ["<div>", "\\n", "  <p>hi</p>", "\\n", "</div>", "\\n"]

            """)
    }

    @Test("HTML block preserves a content tab on a continuation line")
    func tabHTMLContinuation() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("<div>\n\tfoo\n") == """
            document
              html_block "<div>\\n\\tfoo\\n" ["<div>", "\\n", "\\tfoo", "\\n"]

            """)
    }

    @Test("single-line HTML block")
    func htmlSingleLine() {
        guard #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) else { return }
        #expect(TreeDump.dumpSegments("<!-- comment -->\n") == """
            document
              html_block "<!-- comment -->\\n" ["<!-- comment -->", "\\n"]

            """)
    }
}
