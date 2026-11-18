/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Block source positions with multibyte UTF-8")
struct BlockPositionEncodingTests {

    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: Self.opts, sourceRanges: true)
    }

    @Test("paragraph — byte columns track multibyte, combining, replacement, and tab bytes")
    func paragraph() {
        #expect(tree("hello world") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                text "hello world" @1:1-1:12

            """)
        #expect(tree("\u{E9} x") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "\u{E9} x" @1:1-1:5

            """)
        #expect(tree("\u{20AC} x") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "\u{20AC} x" @1:1-1:6

            """)
        #expect(tree("\u{1F600} x") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "\u{1F600} x" @1:1-1:7

            """)
        #expect(tree("e\u{301} x") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "e\u{301} x" @1:1-1:6

            """)
        #expect(tree("\u{FFFD} x") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "\u{FFFD} x" @1:1-1:6

            """)
        #expect(tree("a\tb") == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "a\\tb" @1:1-1:4

            """)
        #expect(tree("x\u{E9} y") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "x\u{E9} y" @1:1-1:6

            """)

        #expect(tree("\u{E9}\n\u{20AC}") == """
            document @1:1-2:4
              paragraph @1:1-2:4
                text "\u{E9}" @1:1-1:3
                softbreak @-
                text "\u{20AC}" @2:1-2:4

            """)
    }

    @Test("ATX heading — content starts at byte column 3 and its end tracks multibyte width")
    func atxHeading() {
        #expect(tree("# hi") == """
            document @1:1-1:5
              heading 1 @1:1-1:5
                text "hi" @1:3-1:5

            """)
        #expect(tree("# \u{E9}") == """
            document @1:1-1:5
              heading 1 @1:1-1:5
                text "\u{E9}" @1:3-1:5

            """)
        #expect(tree("# \u{20AC}x") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "\u{20AC}x" @1:3-1:7

            """)
        #expect(tree("# \u{1F600} y") == """
            document @1:1-1:9
              heading 1 @1:1-1:9
                text "\u{1F600} y" @1:3-1:9

            """)
        #expect(tree("# e\u{301}x") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "e\u{301}x" @1:3-1:7

            """)
        #expect(tree("# \u{FFFD}x") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "\u{FFFD}x" @1:3-1:7

            """)
        #expect(tree("# a\tb") == """
            document @1:1-1:6
              heading 1 @1:1-1:6
                text "a\\tb" @1:3-1:6

            """)
        #expect(tree("# hi #") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "hi" @1:3-1:5

            """)
    }

    @Test("setext heading — content on line 1, range extends over the underline line")
    func setextHeading() {
        #expect(tree("hi\n===") == """
            document @1:1-2:4
              heading 1 @1:1-2:4
                text "hi" @1:1-1:3

            """)
        #expect(tree("ab\n---") == """
            document @1:1-2:4
              heading 2 @1:1-2:4
                text "ab" @1:1-1:3

            """)
        #expect(tree("\u{E9}\n===") == """
            document @1:1-2:4
              heading 1 @1:1-2:4
                text "\u{E9}" @1:1-1:3

            """)
        #expect(tree("\u{20AC} x\n---") == """
            document @1:1-2:4
              heading 2 @1:1-2:4
                text "\u{20AC} x" @1:1-1:6

            """)
        #expect(tree("e\u{301}\n===") == """
            document @1:1-2:4
              heading 1 @1:1-2:4
                text "e\u{301}" @1:1-1:4

            """)
        #expect(tree("a\nb\n===") == """
            document @1:1-3:4
              heading 1 @1:1-3:4
                text "a" @1:1-1:2
                softbreak @-
                text "b" @2:1-2:2

            """)
    }

    @Test("thematic break — full-marker span across the three marker styles")
    func thematicBreak() {
        for marker in ["***", "---", "___"] {
            #expect(tree(marker) == """
                document @1:1-1:4
                  thematic_break @1:1-1:4

                """)
        }
    }

    @Test("block quote — content column 3 after `> `, tracks multibyte, nesting, and matched continuation")
    func blockQuote() {
        #expect(tree("> hi") == """
            document @1:1-1:5
              block_quote @1:1-1:5
                paragraph @1:3-1:5
                  text "hi" @1:3-1:5

            """)
        #expect(tree("> \u{E9} x") == """
            document @1:1-1:7
              block_quote @1:1-1:7
                paragraph @1:3-1:7
                  text "\u{E9} x" @1:3-1:7

            """)
        #expect(tree("> \u{20AC}") == """
            document @1:1-1:6
              block_quote @1:1-1:6
                paragraph @1:3-1:6
                  text "\u{20AC}" @1:3-1:6

            """)
        #expect(tree("> > hi") == """
            document @1:1-1:7
              block_quote @1:1-1:7
                block_quote @1:3-1:7
                  paragraph @1:5-1:7
                    text "hi" @1:5-1:7

            """)
        #expect(tree("> > \u{E9}") == """
            document @1:1-1:7
              block_quote @1:1-1:7
                block_quote @1:3-1:7
                  paragraph @1:5-1:7
                    text "\u{E9}" @1:5-1:7

            """)
        #expect(tree("> a\n> b") == """
            document @1:1-2:4
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:3-2:4

            """)
        #expect(tree("> \u{E9}\n> \u{20AC}") == """
            document @1:1-2:6
              block_quote @1:1-2:6
                paragraph @1:3-2:6
                  text "\u{E9}" @1:3-1:5
                  softbreak @-
                  text "\u{20AC}" @2:3-2:6

            """)
    }

    @Test("block quote lazy continuation line — text starts at its own byte column")
    func blockQuoteLazyContinuation() {
        #expect(tree("> a\nb") == """
            document @1:1-2:2
              block_quote @1:1-2:2
                paragraph @1:3-2:2
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2

            """)
    }

    @Test("nested block quotes after tabs start at their markers")
    func nestedBlockQuotesAfterTabs() {
        #expect(TreeDump.dump(">\t>\t> a", options: .sourcePosition, sourceRanges: true) == """
            document @1:1-1:8
              block_quote @1:1-1:8
                block_quote @1:3-1:8
                  block_quote @1:5-1:8
                    paragraph @1:7-1:8
                      text "a" @1:7-1:8

            """)
    }

    @Test("unordered list — marker styles and content column 3, tracking multibyte and tab")
    func unorderedList() {
        for marker in ["-", "*", "+"] {
            #expect(tree("\(marker) x") == """
                document @1:1-1:4
                  list bullet '\(marker)' tight @1:1-1:4
                    item @1:1-1:4
                      paragraph @1:3-1:4
                        text "x" @1:3-1:4

                """)
        }
        #expect(tree("- \u{E9}") == """
            document @1:1-1:5
              list bullet '-' tight @1:1-1:5
                item @1:1-1:5
                  paragraph @1:3-1:5
                    text "\u{E9}" @1:3-1:5

            """)
        #expect(tree("- \u{20AC} x") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  paragraph @1:3-1:8
                    text "\u{20AC} x" @1:3-1:8

            """)
        #expect(tree("- a\tb") == """
            document @1:1-1:6
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  paragraph @1:3-1:6
                    text "a\\tb" @1:3-1:6

            """)
    }

    @Test("ordered list — start number, delimiter, and content column 4 tracking multibyte")
    func orderedList() {
        #expect(tree("1. x") == """
            document @1:1-1:5
              list ordered start=1 delim=period tight @1:1-1:5
                item @1:1-1:5
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5

            """)
        #expect(tree("2) x") == """
            document @1:1-1:5
              list ordered start=2 delim=paren tight @1:1-1:5
                item @1:1-1:5
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5

            """)
        #expect(tree("1. \u{1F600} z") == """
            document @1:1-1:10
              list ordered start=1 delim=period tight @1:1-1:10
                item @1:1-1:10
                  paragraph @1:4-1:10
                    text "\u{1F600} z" @1:4-1:10

            """)
    }

    @Test("list item lazy continuation line — text starts at its own byte column")
    func listLazyContinuation() {
        #expect(tree("- a\nb") == """
            document @1:1-2:2
              list bullet '-' tight @1:1-2:2
                item @1:1-2:2
                  paragraph @1:3-2:2
                    text "a" @1:3-1:4
                    softbreak @-
                    text "b" @2:1-2:2

            """)
    }

    @Test("task list — checkbox state, content column 7, tracking multibyte")
    func taskList() {
        #expect(tree("- [ ] x") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                tasklist unchecked @1:1-1:8
                  paragraph @1:7-1:8
                    text "x" @1:7-1:8

            """)
        #expect(tree("- [x] x") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                tasklist checked @1:1-1:8
                  paragraph @1:7-1:8
                    text "x" @1:7-1:8

            """)
        #expect(tree("- [ ] \u{E9}") == """
            document @1:1-1:9
              list bullet '-' tight @1:1-1:9
                tasklist unchecked @1:1-1:9
                  paragraph @1:7-1:9
                    text "\u{E9}" @1:7-1:9

            """)
    }

    @Test("indented code — content starts at column 5, end tracks multibyte body width")
    func indentedCode() {
        #expect(tree("    code") == """
            document @1:1-1:9
              code_block "" "code\\n" @1:5-1:9

            """)
        #expect(codeBlockKinds("    code", options: Self.opts)
            == ["code_block indented fence=none length=0 offset=0"])
        #expect(tree("    \u{E9} code") == """
            document @1:1-1:12
              code_block "" "\u{E9} code\\n" @1:5-1:12

            """)
        #expect(codeBlockKinds("    \u{E9} code", options: Self.opts)
            == ["code_block indented fence=none length=0 offset=0"])
    }

    @Test("fenced code — fence metadata, info string, and body across encodings")
    func fencedCode() {
        #expect(tree("```swift\nlet x = 1\n```") == """
            document @1:1-3:4
              code_block "swift" "let x = 1\\n" @1:1-3:4

            """)
        #expect(codeBlockKinds("```swift\nlet x = 1\n```", options: Self.opts)
            == ["code_block fenced fence='`' length=3 offset=0"])
        #expect(tree("```\u{E9}\ncode\n```") == """
            document @1:1-3:4
              code_block "\u{E9}" "code\\n" @1:1-3:4

            """)
        #expect(codeBlockKinds("```\u{E9}\ncode\n```", options: Self.opts)
            == ["code_block fenced fence='`' length=3 offset=0"])
        #expect(tree("```\ne\u{301} code\n```") == """
            document @1:1-3:4
              code_block "" "e\u{301} code\\n" @1:1-3:4

            """)
        #expect(tree("```\u{20AC}\n\u{1F600}\n```") == """
            document @1:1-3:4
              code_block "\u{20AC}" "\u{1F600}\\n" @1:1-3:4

            """)
    }

    @Test("HTML block — span covers the raw lines, body tracks multibyte content")
    func htmlBlock() {
        #expect(tree("<div>\n</div>") == """
            document @1:1-2:7
              html_block "<div>\\n</div>\\n" @1:1-2:7

            """)
        #expect(tree("<div>\u{E9}\n</div>") == """
            document @1:1-2:7
              html_block "<div>\u{E9}\\n</div>\\n" @1:1-2:7

            """)
    }

    @Test("leading BOM — line 1 columns count the BOM's three bytes, and the document starts at the BOM")
    func leadingByteOrderMark() {
        #expect(tree("\u{FEFF}a\nb") == """
            document @1:1-2:2
              paragraph @1:4-2:2
                text "a" @1:4-1:5
                softbreak @-
                text "b" @2:1-2:2

            """)
    }

    @Test("BOM-only input — the document spans the BOM")
    func byteOrderMarkOnly() {
        #expect(tree("\u{FEFF}") == """
            document @1:1-1:4

            """)
    }
}
