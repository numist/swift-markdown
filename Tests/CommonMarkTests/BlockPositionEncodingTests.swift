/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source positions of block constructs holding multibyte UTF-8. A column counts bytes, so a scalar advances it by
/// its UTF-8 length (2 for `é`, 3 for `€` and `U+FFFD`, 4 for `😀`), `e` + `U+0301` by 3, and a tab by 1.
@Suite("Block source positions with multibyte UTF-8")
struct BlockPositionEncodingTests {

    private static let opts: MarkdownDocument.ParseOptions =
        [.sourcePosition, .smart, .tables, .strikethrough, .tasklist, .tableSpans]

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: Self.opts, sourceRanges: true)
    }

    // MARK: - Paragraph

    @Test("paragraph — byte columns track multibyte, combining, replacement, and tab bytes")
    func paragraph() {
        // ASCII baseline: 11 bytes → end column 12 (last byte column + 1).
        #expect(tree("hello world") == """
            document @1:1-1:12
              paragraph @1:1-1:12
                text "hello world" @1:1-1:12

            """)
        // é (U+00E9, 2 bytes) then " x": 4 bytes → end column 5.
        #expect(tree("\u{E9} x") == """
            document @1:1-1:5
              paragraph @1:1-1:5
                text "\u{E9} x" @1:1-1:5

            """)
        // € (U+20AC, 3 bytes) then " x": 5 bytes → end column 6.
        #expect(tree("\u{20AC} x") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "\u{20AC} x" @1:1-1:6

            """)
        // 😀 (U+1F600, 4 bytes) then " x": 6 bytes → end column 7.
        #expect(tree("\u{1F600} x") == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "\u{1F600} x" @1:1-1:7

            """)
        // e + combining acute (U+0301): "e"(1) + combining(2) = 3 bytes, then " x": 5 bytes → col 6.
        #expect(tree("e\u{301} x") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "e\u{301} x" @1:1-1:6

            """)
        // U+FFFD (3 bytes) then " x": 5 bytes → end column 6.
        #expect(tree("\u{FFFD} x") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "\u{FFFD} x" @1:1-1:6

            """)
        // TAB is a single byte, not expanded: "a\tb" = 3 bytes → end column 4.
        #expect(tree("a\tb") == """
            document @1:1-1:4
              paragraph @1:1-1:4
                text "a\\tb" @1:1-1:4

            """)
        // Multibyte INSIDE the run (not leading): "x" + é + " y" = 5 bytes → end column 6.
        #expect(tree("x\u{E9} y") == """
            document @1:1-1:6
              paragraph @1:1-1:6
                text "x\u{E9} y" @1:1-1:6

            """)

        // Multi-line paragraph: the second line's columns reset to line-relative byte offsets.
        // "é" (2 bytes, @1:1-1:3), softbreak, "€" (3 bytes, @2:1-2:4).
        #expect(tree("\u{E9}\n\u{20AC}") == """
            document @1:1-2:4
              paragraph @1:1-2:4
                text "\u{E9}" @1:1-1:3
                softbreak @-
                text "\u{20AC}" @2:1-2:4

            """)
    }

    // MARK: - ATX heading

    @Test("ATX heading — content starts at byte column 3 and its end tracks multibyte width")
    func atxHeading() {
        // "# hi": content "hi" at columns 3-4 → text @1:3-1:5; heading spans @1:1-1:5.
        #expect(tree("# hi") == """
            document @1:1-1:5
              heading 1 @1:1-1:5
                text "hi" @1:3-1:5

            """)
        // é content (2 bytes): text @1:3-1:5, heading @1:1-1:5.
        #expect(tree("# \u{E9}") == """
            document @1:1-1:5
              heading 1 @1:1-1:5
                text "\u{E9}" @1:3-1:5

            """)
        // €x (3 + 1 bytes): text @1:3-1:7, heading @1:1-1:7.
        #expect(tree("# \u{20AC}x") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "\u{20AC}x" @1:3-1:7

            """)
        // "😀 y" (4 + 1 + 1 bytes): text @1:3-1:9, heading @1:1-1:9.
        #expect(tree("# \u{1F600} y") == """
            document @1:1-1:9
              heading 1 @1:1-1:9
                text "\u{1F600} y" @1:3-1:9

            """)
        // "e" + combining + "x" (3 + 1 bytes): text @1:3-1:7.
        #expect(tree("# e\u{301}x") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "e\u{301}x" @1:3-1:7

            """)
        // U+FFFD + "x" (3 + 1 bytes): text @1:3-1:7.
        #expect(tree("# \u{FFFD}x") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "\u{FFFD}x" @1:3-1:7

            """)
        // TAB inside content counts as one byte: "a\tb" → text @1:3-1:6.
        #expect(tree("# a\tb") == """
            document @1:1-1:6
              heading 1 @1:1-1:6
                text "a\\tb" @1:3-1:6

            """)
        // The closing "#" sequence is the heading's syntax but not its text: "# hi #" → text @1:3-1:5,
        // heading @1:1-1:7.
        #expect(tree("# hi #") == """
            document @1:1-1:7
              heading 1 @1:1-1:7
                text "hi" @1:3-1:5

            """)
    }

    // MARK: - Setext heading

    @Test("setext heading — content on line 1, range extends over the underline line")
    func setextHeading() {
        // "hi\n===": level 1, text @1:1-1:3, heading extends to end of underline @1:1-2:4.
        #expect(tree("hi\n===") == """
            document @1:1-2:4
              heading 1 @1:1-2:4
                text "hi" @1:1-1:3

            """)
        // "ab\n---": level 2 (dash underline), text @1:1-1:3, heading @1:1-2:4.
        #expect(tree("ab\n---") == """
            document @1:1-2:4
              heading 2 @1:1-2:4
                text "ab" @1:1-1:3

            """)
        // é content (2 bytes): text @1:1-1:3, heading @1:1-2:4, level 1.
        #expect(tree("\u{E9}\n===") == """
            document @1:1-2:4
              heading 1 @1:1-2:4
                text "\u{E9}" @1:1-1:3

            """)
        // "€ x" content (3 + 1 + 1 bytes) with dash underline: text @1:1-1:6, level 2.
        #expect(tree("\u{20AC} x\n---") == """
            document @1:1-2:4
              heading 2 @1:1-2:4
                text "\u{20AC} x" @1:1-1:6

            """)
        // Combining content "e" + U+0301 (3 bytes): text @1:1-1:4.
        #expect(tree("e\u{301}\n===") == """
            document @1:1-2:4
              heading 1 @1:1-2:4
                text "e\u{301}" @1:1-1:4

            """)
        // Multi-line setext content: "a\nb\n===" → two text runs joined by a soft break, heading
        // extends over the underline on line 3 (@1:1-3:4).
        #expect(tree("a\nb\n===") == """
            document @1:1-3:4
              heading 1 @1:1-3:4
                text "a" @1:1-1:2
                softbreak @-
                text "b" @2:1-2:2

            """)
    }

    // MARK: - Thematic break

    @Test("thematic break — full-marker span across the three marker styles")
    func thematicBreak() {
        // 3 marker bytes → end column 4.
        for marker in ["***", "---", "___"] {
            #expect(tree(marker) == """
                document @1:1-1:4
                  thematic_break @1:1-1:4

                """)
        }
    }

    // MARK: - Block quote

    @Test("block quote — content column 3 after `> `, tracks multibyte, nesting, and matched continuation")
    func blockQuote() {
        // "> hi": block quote @1:1-1:5, paragraph/text at content column 3.
        #expect(tree("> hi") == """
            document @1:1-1:5
              block_quote @1:1-1:5
                paragraph @1:3-1:5
                  text "hi" @1:3-1:5

            """)
        // "> é x" (2 + 1 + 1 bytes of content): text @1:3-1:7.
        #expect(tree("> \u{E9} x") == """
            document @1:1-1:7
              block_quote @1:1-1:7
                paragraph @1:3-1:7
                  text "\u{E9} x" @1:3-1:7

            """)
        // "> €" (3-byte content only): text @1:3-1:6.
        #expect(tree("> \u{20AC}") == """
            document @1:1-1:6
              block_quote @1:1-1:6
                paragraph @1:3-1:6
                  text "\u{20AC}" @1:3-1:6

            """)
        // Nested "> > hi": inner content column 5.
        #expect(tree("> > hi") == """
            document @1:1-1:7
              block_quote @1:1-1:7
                block_quote @1:3-1:7
                  paragraph @1:5-1:7
                    text "hi" @1:5-1:7

            """)
        // Nested with multibyte "> > é": text @1:5-1:7.
        #expect(tree("> > \u{E9}") == """
            document @1:1-1:7
              block_quote @1:1-1:7
                block_quote @1:3-1:7
                  paragraph @1:5-1:7
                    text "\u{E9}" @1:5-1:7

            """)
        // Matched multi-line "> a\n> b": both lines' content starts at column 3.
        #expect(tree("> a\n> b") == """
            document @1:1-2:4
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:3-2:4

            """)
        // Matched multi-line with multibyte "> é\n> €".
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

    /// A quote opened after a tab starts at its `>`, whatever the tab expands to.
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

    // MARK: - Unordered list

    @Test("unordered list — marker styles and content column 3, tracking multibyte and tab")
    func unorderedList() {
        // Marker styles: -, *, + all put content at column 3: list and item @1:1-1:4, paragraph and text @1:3-1:4.
        for marker in ["-", "*", "+"] {
            #expect(tree("\(marker) x") == """
                document @1:1-1:4
                  list bullet '\(marker)' tight @1:1-1:4
                    item @1:1-1:4
                      paragraph @1:3-1:4
                        text "x" @1:3-1:4

                """)
        }
        // "- é" (2-byte content): text @1:3-1:5, list @1:1-1:5.
        #expect(tree("- \u{E9}") == """
            document @1:1-1:5
              list bullet '-' tight @1:1-1:5
                item @1:1-1:5
                  paragraph @1:3-1:5
                    text "\u{E9}" @1:3-1:5

            """)
        // "- € x" (3 + 1 + 1 bytes): text @1:3-1:8.
        #expect(tree("- \u{20AC} x") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                item @1:1-1:8
                  paragraph @1:3-1:8
                    text "\u{20AC} x" @1:3-1:8

            """)
        // TAB inside content is one byte: "- a\tb" → text @1:3-1:6.
        #expect(tree("- a\tb") == """
            document @1:1-1:6
              list bullet '-' tight @1:1-1:6
                item @1:1-1:6
                  paragraph @1:3-1:6
                    text "a\\tb" @1:3-1:6

            """)
    }

    // MARK: - Ordered list

    @Test("ordered list — start number, delimiter, and content column 4 tracking multibyte")
    func orderedList() {
        // "1. x": start 1, period delimiter, content column 4.
        #expect(tree("1. x") == """
            document @1:1-1:5
              list ordered start=1 delim=period tight @1:1-1:5
                item @1:1-1:5
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5

            """)
        // "2) x": start 2, paren delimiter.
        #expect(tree("2) x") == """
            document @1:1-1:5
              list ordered start=2 delim=paren tight @1:1-1:5
                item @1:1-1:5
                  paragraph @1:4-1:5
                    text "x" @1:4-1:5

            """)
        // "1. 😀 z" (4 + 1 + 1 bytes content): text @1:4-1:10.
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

    // MARK: - Task list

    @Test("task list — checkbox state, content column 7, tracking multibyte")
    func taskList() {
        // "- [ ] x": unchecked item, content after "[ ] " at column 7.
        #expect(tree("- [ ] x") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                tasklist unchecked @1:1-1:8
                  paragraph @1:7-1:8
                    text "x" @1:7-1:8

            """)
        // "- [x] x": checked item.
        #expect(tree("- [x] x") == """
            document @1:1-1:8
              list bullet '-' tight @1:1-1:8
                tasklist checked @1:1-1:8
                  paragraph @1:7-1:8
                    text "x" @1:7-1:8

            """)
        // "- [ ] é" (2-byte content): text @1:7-1:9.
        #expect(tree("- [ ] \u{E9}") == """
            document @1:1-1:9
              list bullet '-' tight @1:1-1:9
                tasklist unchecked @1:1-1:9
                  paragraph @1:7-1:9
                    text "\u{E9}" @1:7-1:9

            """)
    }

    // MARK: - Indented code

    @Test("indented code — content starts at column 5, end tracks multibyte body width")
    func indentedCode() {
        // "    code": indented code block, content @1:5-1:9, body "code\n".
        #expect(tree("    code") == """
            document @1:1-1:9
              code_block "" "code\\n" @1:5-1:9

            """)
        #expect(codeBlockKinds("    code", options: Self.opts)
            == ["code_block indented fence=none length=0 offset=0"])
        // "    é code": multibyte body (é = 2 bytes) → line-1 end column 12 (11 bytes + 1).
        #expect(tree("    \u{E9} code") == """
            document @1:1-1:12
              code_block "" "\u{E9} code\\n" @1:5-1:12

            """)
        #expect(codeBlockKinds("    \u{E9} code", options: Self.opts)
            == ["code_block indented fence=none length=0 offset=0"])
    }

    // MARK: - Fenced code

    @Test("fenced code — fence metadata, info string, and body across encodings")
    func fencedCode() {
        // "```swift\nlet x = 1\n```": backtick fence, length 3, info "swift", body "let x = 1\n".
        // The code block spans fence-to-fence (@1:1-3:4).
        #expect(tree("```swift\nlet x = 1\n```") == """
            document @1:1-3:4
              code_block "swift" "let x = 1\\n" @1:1-3:4

            """)
        #expect(codeBlockKinds("```swift\nlet x = 1\n```", options: Self.opts)
            == ["code_block fenced fence='`' length=3 offset=0"])
        // Multibyte info string "```é": info "é", body "code\n".
        #expect(tree("```\u{E9}\ncode\n```") == """
            document @1:1-3:4
              code_block "\u{E9}" "code\\n" @1:1-3:4

            """)
        #expect(codeBlockKinds("```\u{E9}\ncode\n```", options: Self.opts)
            == ["code_block fenced fence='`' length=3 offset=0"])
        // Multibyte body with a combining sequence: empty info, body `e` U+0301 ` code` and a line feed.
        #expect(tree("```\ne\u{301} code\n```") == """
            document @1:1-3:4
              code_block "" "e\u{301} code\\n" @1:1-3:4

            """)
        // Multibyte in both info (€) and body (😀): info "€", body "😀\n".
        #expect(tree("```\u{20AC}\n\u{1F600}\n```") == """
            document @1:1-3:4
              code_block "\u{20AC}" "\u{1F600}\\n" @1:1-3:4

            """)
    }

    // MARK: - HTML block

    @Test("HTML block — span covers the raw lines, body tracks multibyte content")
    func htmlBlock() {
        // "<div>\n</div>": HTML block @1:1-2:7, body includes both lines and a trailing line ending.
        #expect(tree("<div>\n</div>") == """
            document @1:1-2:7
              html_block "<div>\\n</div>\\n" @1:1-2:7

            """)
        // Multibyte in the first line "<div>é": the block's source range ends on line 2, at column 7.
        #expect(tree("<div>\u{E9}\n</div>") == """
            document @1:1-2:7
              html_block "<div>\u{E9}\\n</div>\\n" @1:1-2:7

            """)
    }

    // MARK: - Byte-order mark

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

    /// A BOM alone is one line, which the document spans: the BOM's three bytes.
    @Test("BOM-only input — the document spans the BOM")
    func byteOrderMarkOnly() {
        #expect(tree("\u{FEFF}") == """
            document @1:1-1:4

            """)
    }
}
