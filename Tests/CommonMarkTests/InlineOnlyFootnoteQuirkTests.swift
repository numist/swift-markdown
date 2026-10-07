/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Footnote-shaped brackets in inline-only mode.
@Suite("Footnote-shaped brackets in inline-only mode")
struct InlineOnlyFootnoteQuirkTests {
    private static let inlineOnly: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes, .inlineOnly]
    private static let preserveWhitespace: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes, .preserveWhitespace]

    @Test func test_footnote_multiline_label_flag_off() {
        #expect(CmarkTreeDump.dump(String(decoding: [91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.inlineOnly) == """
            document
              paragraph
                text "[^\\n\u{FFFD}]"

            """)
        #expect(CmarkTreeDump.dump(String(decoding: [91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^\\n\u{FFFD}]"

            """)
    }

    /// A footnote reference label cannot hold an unescaped `[`, so the bracket run stays literal text.
    @Test func test_footnote_caret_bracket_innerclose_flag_off() {
        #expect(CmarkTreeDump.dump("[^[]\n]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^[]\\n]"

            """)
        #expect(CmarkTreeDump.dump("[^[]\n]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^[]\\n]"

            """)
    }

    /// A footnote reference label cannot hold an unescaped `[`, so the bracket run stays literal text.
    @Test func test_footnote_caret_bracket_spans_empty_flag_off() {
        #expect(CmarkTreeDump.dump("[^[\n]]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^[\\n]]"

            """)
        #expect(CmarkTreeDump.dump("[^[\n]]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^[\\n]]"

            """)
    }

    /// An escaped `^` is a literal caret, so the text keeps its single `]`.
    @Test func test_footnote_escaped_caret_crossline_flag_off() {
        #expect(CmarkTreeDump.dump("[\\^\nx]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^\\nx]"

            """)
        #expect(CmarkTreeDump.dump("[\\^\nx]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^\\nx]"

            """)
    }

    /// An escaped `^` is a literal caret, so the text keeps its leading `!`.
    @Test func test_footnote_escaped_caret_image_flag_off() {
        #expect(CmarkTreeDump.dump("![\\^x]", options: Self.inlineOnly) == """
            document
              paragraph
                text "![^x]"

            """)
        #expect(CmarkTreeDump.dump("![\\^x]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "![^x]"

            """)
    }

    @Test func test_footnote_multiline_collapse_blockquote_flag_off() {
        #expect(CmarkTreeDump.dump(String(decoding: [62, 91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.inlineOnly) == """
            document
              paragraph
                text ">[^\\n\u{FFFD}]"

            """)
        #expect(CmarkTreeDump.dump(String(decoding: [62, 91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.preserveWhitespace) == """
            document
              paragraph
                text ">[^\\n\u{FFFD}]"

            """)
    }

    @Test func test_footnote_multiline_label_multibyte_flag_off() {
        #expect(CmarkTreeDump.dump(String(decoding: [91, 94, 10, 128, 112, 93] as [UInt8], as: UTF8.self), options: Self.inlineOnly) == """
            document
              paragraph
                text "[^\\n\u{FFFD}p]"

            """)
        #expect(CmarkTreeDump.dump(String(decoding: [91, 94, 10, 128, 112, 93] as [UInt8], as: UTF8.self), options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^\\n\u{FFFD}p]"

            """)
    }

    @Test func test_probe_crossline_plain_label_flag_off() {
        #expect(CmarkTreeDump.dump("a[^x\ny]b", options: Self.inlineOnly) == """
            document
              paragraph
                text "a[^x\\ny]b"

            """)
        #expect(CmarkTreeDump.dump("a[^x\ny]b", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "a[^x\\ny]b"

            """)
    }

    @Test func test_probe_crossline_crlf_label_flag_off() {
        #expect(CmarkTreeDump.dump("[^a\r\nb]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^a\\nb]"

            """)
        #expect(CmarkTreeDump.dump("[^a\r\nb]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^a\\nb]"

            """)
    }

    /// Backticks form a code span whose line ending becomes a space.
    @Test func test_probe_codespan_newline_resets_flag_off() {
        #expect(CmarkTreeDump.dump("[^`a\nb`\nc]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^"
                code "a b"
                text "\\nc]"

            """)
        #expect(CmarkTreeDump.dump("[^`a\nb`\nc]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^"
                code "a b"
                text "\\nc]"

            """)
    }

    /// An escaped `^` is a literal caret, so the text keeps its single `]`.
    @Test func test_probe_escaped_caret_crossline_long_flag_off() {
        #expect(CmarkTreeDump.dump("[\\^abcdef\nxxxxx]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^abcdef\\nxxxxx]"

            """)
        #expect(CmarkTreeDump.dump("[\\^abcdef\nxxxxx]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^abcdef\\nxxxxx]"

            """)
    }

    /// An escaped `^` is a literal caret, so the text keeps its leading `!`.
    @Test func test_probe_escaped_caret_image_crossline_flag_off() {
        #expect(CmarkTreeDump.dump("![\\^a\nb]", options: Self.inlineOnly) == """
            document
              paragraph
                text "![^a\\nb]"

            """)
        #expect(CmarkTreeDump.dump("![\\^a\nb]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "![^a\\nb]"

            """)
    }

    /// An escaped `^` is a literal caret, so the text is the source with its `!` and no extra `]`.
    @Test func test_probe_escaped_caret_image_trailing_newline_flag_off() {
        #expect(CmarkTreeDump.dump("![\\^x]\n", options: Self.inlineOnly) == """
            document
              paragraph
                text "![^x]\\n"

            """)
        #expect(CmarkTreeDump.dump("![\\^x]\n", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "![^x]\\n"

            """)
    }
}
