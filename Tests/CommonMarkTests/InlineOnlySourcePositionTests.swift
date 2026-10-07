/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Inline-only parsing reports line-aware source positions, like block parsing does.
///
/// In `a` LF `b *c*` the text on the second line starts at line 2, column 1 (UTF-8 byte columns), and the document and
/// its single paragraph span the whole input.
@Suite("Inline-only source positions")
struct InlineOnlySourcePositionTests {

    private static let inlineOnly: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .inlineOnly,
    ]

    private static let preserveWhitespace: MarkdownDocument.ParseOptions = [
        .tables, .strikethrough, .tasklist, .tableSpans, .attributes, .sourcePosition, .smart, .preserveWhitespace,
    ]

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func secondLineTextIsOnLineTwo(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\nb *c*", options: options, sourceRanges: true) == """
            document @1:1-2:6
              paragraph @1:1-2:6
                text "a\\nb " @1:1-2:3
                emph @2:3-2:6
                  text "c" @2:4-2:5

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func backslashHardBreakAcrossLines(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\\\nb", options: options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "a" @1:1-1:2
                linebreak @-
                text "b" @2:1-2:2

            """)
    }

    /// A CRLF is normalized to one `\n` in the content but still occupies two source bytes, so line 2 starts after both.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func crlfLineEnding(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\r\nb *c*", options: options, sourceRanges: true) == """
            document @1:1-2:6
              paragraph @1:1-2:6
                text "a\\nb " @1:1-2:3
                emph @2:3-2:6
                  text "c" @2:4-2:5

            """)
        // The normalized `\n` images the LF, so text ending at a CRLF covers both bytes and ends at the next line's start...
        #expect(CmarkTreeDump.dump("a\r\n*b*", options: options, sourceRanges: true) == """
            document @1:1-2:4
              paragraph @1:1-2:4
                text "a\\n" @1:1-2:1
                emph @2:1-2:4
                  text "b" @2:2-2:3

            """)
        // ...while text starting at a CRLF starts at its LF, one byte past the CR.
        #expect(CmarkTreeDump.dump("*a*\r\nb", options: options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                emph @1:1-1:4
                  text "a" @1:2-1:3
                text "\\nb" @1:5-2:2

            """)
    }

    /// A lone CR ends a line just like LF does.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func loneCRLineEnding(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\rb *c*", options: options, sourceRanges: true) == """
            document @1:1-2:6
              paragraph @1:1-2:6
                text "a\\nb " @1:1-2:3
                emph @2:3-2:6
                  text "c" @2:4-2:5

            """)
    }

    /// A NUL is one source byte even though it surfaces as the three-byte U+FFFD.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func nul(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\u{0}b *c*", options: options, sourceRanges: true) == """
            document @1:1-1:8
              paragraph @1:1-1:8
                text "a\u{FFFD}b " @1:1-1:5
                emph @1:5-1:8
                  text "c" @1:6-1:7

            """)
    }

    /// A NUL ending the input, after a CRLF: the U+FFFD text ends at the source's last byte, not two bytes past it.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func trailingNULAfterCRLF(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\r\n*b*\u{0}", options: options, sourceRanges: true) == """
            document @1:1-2:5
              paragraph @1:1-2:5
                text "a\\n" @1:1-2:1
                emph @2:1-2:4
                  text "b" @2:2-2:3
                text "\u{FFFD}" @2:4-2:5

            """)
    }

    /// A leading byte-order mark is skipped: line 1's columns count from the byte after it.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func leadingByteOrderMark(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("\u{FEFF}a\nb", options: options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "a\\nb" @1:1-2:2

            """)
        #expect(CmarkTreeDump.dump("\u{FEFF}a\r\nb", options: options, sourceRanges: true) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "a\\nb" @1:1-2:2

            """)
    }

    /// A BOM-only input's empty paragraph sits at the start of line 1, past the BOM; a blank line after the BOM ends where its line ending starts, so the ranges are empty.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func byteOrderMarkWithoutContent(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("\u{FEFF}", options: options, sourceRanges: true) == """
            document @1:1-1:1
              paragraph @1:1-1:1

            """)
        #expect(CmarkTreeDump.dump("\u{FEFF}\n", options: options, sourceRanges: true) == """
            document @1:1-1:1
              paragraph @1:1-1:1
                text "\\n" @1:1-1:1

            """)
    }

    /// Blank lines and a trailing line ending are literal paragraph content, so the paragraph and document span them, but every range ends where the final line ending starts, at the end of the last line.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func blankLinesAndTrailingLineEnding(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\n\n  b\n", options: options, sourceRanges: true) == """
            document @1:1-3:4
              paragraph @1:1-3:4
                text "a\\n\\n  b\\n" @1:1-3:4

            """)
    }

    /// Columns are UTF-8 byte offsets, so a two-byte scalar on line 2 advances the column by two.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func multibyteScalarOnSecondLine(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("a\né *c*", options: options, sourceRanges: true) == """
            document @1:1-2:7
              paragraph @1:1-2:7
                text "a\\né " @1:1-2:4
                emph @2:4-2:7
                  text "c" @2:5-2:6

            """)
    }

    /// Leading reference definitions are consumed from the normalized CRLF content; what remains keeps its original-source positions.
    @Test(arguments: [inlineOnly, preserveWhitespace])
    func leadingReferenceDefinitionWithCRLF(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a]: /u\r\n\r\n[a]", options: options, sourceRanges: true) == """
            document @1:1-3:4
              paragraph @1:1-3:4
                text "\\n" @2:2-3:1
                link "/u" "" @3:1-3:4
                  text "a" @3:2-3:3

            """)
    }

    @Test(arguments: [inlineOnly, preserveWhitespace])
    func linkSpanningLines(options: MarkdownDocument.ParseOptions) {
        #expect(CmarkTreeDump.dump("[a\nb](u)", options: options, sourceRanges: true) == """
            document @1:1-2:6
              paragraph @1:1-2:6
                link "u" "" @1:1-2:6
                  text "a\\nb" @1:2-2:2

            """)
    }
}
