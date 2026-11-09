/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The document's source range covers the whole input after any byte order mark, trailing whitespace, blank lines and
/// the final line ending included. Input that ends in a line ending ends at column 1 of the line after its last.
@Suite("Document source ranges")
struct DocumentSourceRangeTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = []) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    @Test
    func unterminatedLine() {
        #expect(tree("a") == """
            document @1:1-1:2
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test("a final line ending", arguments: ["a\n", "a\r\n", "a\r"])
    func finalLineEnding(_ source: String) {
        #expect(tree(source) == """
            document @1:1-2:1
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test
    func trailingWhitespaceAndBlankLines() {
        #expect(tree("a  \n\n  \n") == """
            document @1:1-4:1
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test
    func trailingWhitespaceWithoutFinalLineEnding() {
        #expect(tree("a\n  ") == """
            document @1:1-2:3
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test
    func leadingBlankLines() {
        #expect(tree("\n\n  a\n") == """
            document @1:1-4:1
              paragraph @3:3-3:4
                text "a" @3:3-3:4

            """)
    }

    @Test
    func thematicBreakWithTrailingSpaces() {
        #expect(tree("***  \n") == """
            document @1:1-2:1
              thematic_break @1:1-1:4

            """)
    }

    @Test
    func emptyATXHeadingWithTrailingSpaces() {
        #expect(tree("## \n") == """
            document @1:1-2:1
              heading 2 @1:1-1:3

            """)
    }

    @Test("input holding only a line ending or whitespace", arguments: [
        ("\n", "document @1:1-2:1\n"),
        ("  \n", "document @1:1-2:1\n"),
        ("  ", "document @1:1-1:3\n"),
    ])
    func blankInput(_ source: String, _ expected: String) {
        #expect(tree(source) == expected)
    }

    @Test
    func byteOrderMark() {
        #expect(tree("\u{FEFF}a\n") == """
            document @1:1-2:1
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test
    func emptyInput() {
        #expect(tree("") == """
            document @-

            """)
    }

    @Test("inline-only input ending in a line ending", arguments: [
        MarkdownDocument.ParseOptions.inlineOnly, .preserveWhitespace,
    ])
    func inlineOnlyFinalLineEnding(_ mode: MarkdownDocument.ParseOptions) {
        #expect(tree("a\n", options: mode) == """
            document @1:1-2:1
              paragraph @1:1-1:2
                text "a\\n" @1:1-1:2

            """)
    }
}
