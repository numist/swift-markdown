/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline-only mode has no footnote definitions, so a footnote-shaped bracket is text.
@Suite("Footnote-shaped brackets in inline-only mode")
struct InlineOnlyFootnoteShapedBracketTests {
    private static let inlineOnly: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes, .inlineOnly]
    private static let preserveWhitespace: MarkdownDocument.ParseOptions = [.tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .footnotes, .preserveWhitespace]

    @Test func test_footnote_multiline_label() {
        #expect(TreeDump.dump(String(decoding: [91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.inlineOnly) == """
            document
              paragraph
                text "[^\\n\u{FFFD}]"

            """)
        #expect(TreeDump.dump(String(decoding: [91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^\\n\u{FFFD}]"

            """)
    }

    @Test func test_footnote_caret_bracket_innerclose() {
        #expect(TreeDump.dump("[^[]\n]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^[]\\n]"

            """)
        #expect(TreeDump.dump("[^[]\n]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^[]\\n]"

            """)
    }

    @Test func test_footnote_caret_bracket_spans_empty() {
        #expect(TreeDump.dump("[^[\n]]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^[\\n]]"

            """)
        #expect(TreeDump.dump("[^[\n]]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^[\\n]]"

            """)
    }

    @Test func test_footnote_escaped_caret_crossline() {
        #expect(TreeDump.dump("[\\^\nx]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^\\nx]"

            """)
        #expect(TreeDump.dump("[\\^\nx]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^\\nx]"

            """)
    }

    @Test func test_footnote_escaped_caret_image() {
        #expect(TreeDump.dump("![\\^x]", options: Self.inlineOnly) == """
            document
              paragraph
                text "![^x]"

            """)
        #expect(TreeDump.dump("![\\^x]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "![^x]"

            """)
    }

    @Test func test_footnote_multiline_label_after_greater_than() {
        #expect(TreeDump.dump(String(decoding: [62, 91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.inlineOnly) == """
            document
              paragraph
                text ">[^\\n\u{FFFD}]"

            """)
        #expect(TreeDump.dump(String(decoding: [62, 91, 94, 10, 128, 93] as [UInt8], as: UTF8.self), options: Self.preserveWhitespace) == """
            document
              paragraph
                text ">[^\\n\u{FFFD}]"

            """)
    }

    @Test func test_footnote_multiline_label_multibyte() {
        #expect(TreeDump.dump(String(decoding: [91, 94, 10, 128, 112, 93] as [UInt8], as: UTF8.self), options: Self.inlineOnly) == """
            document
              paragraph
                text "[^\\n\u{FFFD}p]"

            """)
        #expect(TreeDump.dump(String(decoding: [91, 94, 10, 128, 112, 93] as [UInt8], as: UTF8.self), options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^\\n\u{FFFD}p]"

            """)
    }

    @Test func test_footnote_crossline_label() {
        #expect(TreeDump.dump("a[^x\ny]b", options: Self.inlineOnly) == """
            document
              paragraph
                text "a[^x\\ny]b"

            """)
        #expect(TreeDump.dump("a[^x\ny]b", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "a[^x\\ny]b"

            """)
    }

    @Test func test_footnote_crossline_crlf_label() {
        #expect(TreeDump.dump("[^a\r\nb]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^a\\nb]"

            """)
        #expect(TreeDump.dump("[^a\r\nb]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^a\\nb]"

            """)
    }

    /// The line ending inside the code span becomes a space (Code spans).
    @Test func test_footnote_label_containing_code_span() {
        #expect(TreeDump.dump("[^`a\nb`\nc]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^"
                code "a b"
                text "\\nc]"

            """)
        #expect(TreeDump.dump("[^`a\nb`\nc]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^"
                code "a b"
                text "\\nc]"

            """)
    }

    @Test func test_footnote_escaped_caret_crossline_long() {
        #expect(TreeDump.dump("[\\^abcdef\nxxxxx]", options: Self.inlineOnly) == """
            document
              paragraph
                text "[^abcdef\\nxxxxx]"

            """)
        #expect(TreeDump.dump("[\\^abcdef\nxxxxx]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "[^abcdef\\nxxxxx]"

            """)
    }

    @Test func test_footnote_escaped_caret_image_crossline() {
        #expect(TreeDump.dump("![\\^a\nb]", options: Self.inlineOnly) == """
            document
              paragraph
                text "![^a\\nb]"

            """)
        #expect(TreeDump.dump("![\\^a\nb]", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "![^a\\nb]"

            """)
    }

    @Test func test_footnote_escaped_caret_image_trailing_line_ending() {
        #expect(TreeDump.dump("![\\^x]\n", options: Self.inlineOnly) == """
            document
              paragraph
                text "![^x]\\n"

            """)
        #expect(TreeDump.dump("![\\^x]\n", options: Self.preserveWhitespace) == """
            document
              paragraph
                text "![^x]\\n"

            """)
    }
}
