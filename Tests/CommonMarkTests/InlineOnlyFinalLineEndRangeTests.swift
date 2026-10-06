/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Source ranges in the inline-only modes (`.inlineOnly`, `.preserveWhitespace`) of input that ends in a line ending.
/// The document, the paragraph and any node holding the final line ending end where that line ending starts, so every
/// range stays on the input's last line, as in block mode. A line ending before the last one still ends a node at the
/// start of the next line. Columns are 1-based UTF-8 byte offsets and each end is half-open.
@Suite("Source ranges of inline-only input that ends in a line ending")
struct InlineOnlyFinalLineEndRangeTests {

    private static let modes: [MarkdownDocument.ParseOptions] = [.inlineOnly, .preserveWhitespace]

    private func tree(_ source: String, _ mode: MarkdownDocument.ParseOptions, _ extra: MarkdownDocument.ParseOptions = []) -> String {
        CmarkTreeDump.dump(source, options: mode.union(.sourcePosition).union(extra), sourceRanges: true)
    }

    /// cmark-gfm ends the text at `@1:3`, a column past the line, because it counts the line ending the text holds.
    @Test("a final line feed ends the text where the line feed starts", arguments: modes)
    func finalLineFeed(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\n", mode) == """
            document @1:1-1:2
              paragraph @1:1-1:2
                text "a\\n" @1:1-1:2

            """)
    }

    /// cmark-gfm ends the text at `@1:3`, a column past the line, because it counts the line ending the text holds.
    @Test("a final carriage return and line feed end the text where the carriage return starts", arguments: modes)
    func finalCRLF(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\r\n", mode) == """
            document @1:1-1:2
              paragraph @1:1-1:2
                text "a\\n" @1:1-1:2

            """)
    }

    /// cmark-gfm ends the text at `@1:3`, a column past the line, because it counts the line ending the text holds.
    @Test("a final lone carriage return ends the text where it starts", arguments: modes)
    func finalCR(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\r", mode) == """
            document @1:1-1:2
              paragraph @1:1-1:2
                text "a\\n" @1:1-1:2

            """)
    }

    /// A blank last line is a line of the input, so the ranges end at its start. cmark-gfm ends the text at `@1:4`,
    /// because it counts both line endings on the first line.
    @Test("a final blank line ends the text at the start of that line", arguments: modes)
    func finalBlankLine(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\n\n", mode) == """
            document @1:1-2:1
              paragraph @1:1-2:1
                text "a\\n\\n" @1:1-2:1

            """)
    }

    /// cmark-gfm ends the text at `@1:5`, because it counts the whole text on its first line.
    @Test("a line ending before the last line still ends the text at the start of the next line", arguments: modes)
    func interiorLineFeed(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\nb\n", mode) == """
            document @1:1-2:2
              paragraph @1:1-2:2
                text "a\\nb\\n" @1:1-2:2

            """)
    }

    /// The text holds only the final line ending, so its range is empty where the line ending starts. cmark-gfm ends it
    /// at `@1:5`, a column past the line.
    @Test("text holding only the final line feed has an empty range", arguments: modes)
    func lineFeedOnlyText(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("*a*\n", mode) == """
            document @1:1-1:4
              paragraph @1:1-1:4
                emph @1:1-1:4
                  text "a" @1:2-1:3
                text "\\n" @1:4-1:4

            """)
    }

    /// The text stands for the whole carriage return and line feed, so it starts with the carriage return. cmark-gfm
    /// gives it `@1:4-1:5`, a column past the line.
    @Test("text holding only a final carriage return and line feed has an empty range at the carriage return", arguments: modes)
    func crlfOnlyText(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("*a*\r\n", mode) == """
            document @1:1-1:4
              paragraph @1:1-1:4
                emph @1:1-1:4
                  text "a" @1:2-1:3
                text "\\n" @1:4-1:4

            """)
    }

    /// cmark-gfm ends the text at `@1:2`, a column past the line.
    @Test("input that is a single line feed has empty ranges at its start", arguments: modes)
    func lineFeedOnlyInput(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("\n", mode) == """
            document @1:1-1:1
              paragraph @1:1-1:1
                text "\\n" @1:1-1:1

            """)
    }

    /// The line break has no range, so the paragraph's end comes from the final line ending, not from any inline node.
    @Test("a backslash hard break before the final line feed leaves the paragraph ending at the line feed", arguments: modes)
    func backslashHardBreak(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\\\n", mode) == """
            document @1:1-1:3
              paragraph @1:1-1:3
                text "a" @1:1-1:2
                linebreak @-

            """)
    }

    @Test("a paragraph left empty by a reference definition ends where the final line feed starts", arguments: modes)
    func definitionOnly(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("[x]: /u\n", mode) == """
            document @1:1-1:8
              paragraph @1:1-1:8

            """)
    }

    /// The NUL takes the arena path; its replacement character stands for the one NUL byte at column 2. cmark-gfm ends
    /// the document at `@1:5` and the text at `@1:6`, because it counts the replacement character's three bytes.
    @Test("text with a replaced NUL ends where the final line feed starts", arguments: modes)
    func replacedNUL(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\u{0}\n", mode) == """
            document @1:1-1:3
              paragraph @1:1-1:3
                text "a\u{FFFD}\\n" @1:1-1:3

            """)
    }

    /// cmark-gfm gives the link, its text and the text after it no range.
    @Test("the text after an email autolink ends where the final line feed starts", arguments: modes)
    func afterEmailAutolink(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a@b.co\n", mode, [.gfmAutolink, .cmarkBugCompatibility]) == """
            document @1:1-1:7
              paragraph @1:1-1:7
                text "" @1:1-1:1
                link "mailto:a@b.co" "" @1:1-1:7
                  text "a@b.co" @1:1-1:7
                text "\\n" @1:7-1:7

            """)
    }
}
