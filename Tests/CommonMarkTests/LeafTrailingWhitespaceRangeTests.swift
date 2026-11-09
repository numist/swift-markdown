/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A paragraph's raw content has its final whitespace removed (Paragraphs), as does a setext heading's (Setext
/// headings), so a paragraph ends just past its last content byte and a setext heading just past its underline's last
/// `=` or `-`, before any trailing whitespace. An ATX heading's content excludes trailing spaces and tabs (ATX
/// headings), so it ends just past its content, or past its opening sequence when it has none.
@Suite("Paragraph and heading ranges before trailing whitespace")
struct LeafTrailingWhitespaceRangeTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = []) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    @Test("a paragraph line ending in spaces")
    func trailingSpaces() {
        #expect(tree("a  \n") == """
            document @1:1-1:4
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test("a paragraph line ending in a line tabulation and a form feed")
    func trailingControlWhitespace() {
        #expect(tree("a\u{0B}\u{0C}\n") == """
            document @1:1-1:4
              paragraph @1:1-1:2
                text "a" @1:1-1:2

            """)
    }

    @Test("a paragraph's last line ending in spaces")
    func lastLineTrailingSpaces() {
        #expect(tree("a  \nb  \n") == """
            document @1:1-2:4
              paragraph @1:1-2:2
                text "a" @1:1-1:2
                linebreak @-
                text "b" @2:1-2:2

            """)
    }

    @Test("a paragraph in a block quote")
    func inBlockQuote() {
        #expect(tree("> a\n> b  \n") == """
            document @1:1-2:6
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:3-2:4

            """)
    }

    @Test("a paragraph in a block quote ending in a line tabulation")
    func inBlockQuoteTrailingControlWhitespace() {
        #expect(tree("> a\n> b\u{0B}\n") == """
            document @1:1-2:5
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:3-2:4

            """)
    }

    @Test("a lazy continuation line ending in spaces")
    func lazyLine() {
        #expect(tree("> a\nb  \n") == """
            document @1:1-2:4
              block_quote @1:1-2:2
                paragraph @1:3-2:2
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:1-2:2

            """)
    }

    @Test("a paragraph ending in a NUL before spaces")
    func trailingNUL() {
        #expect(tree("a\u{0}  \n") == """
            document @1:1-1:5
              paragraph @1:1-1:3
                text "a\u{FFFD}" @1:1-1:3

            """)
    }

    @Test("a task list item's paragraph")
    func taskListItem() {
        #expect(tree("- [x] a  \n", options: .tasklist) == """
            document @1:1-1:10
              list bullet '-' tight @1:1-1:8
                tasklist checked @1:1-1:8
                  paragraph @1:7-1:8
                    text "a" @1:7-1:8

            """)
    }

    @Test("a paragraph after a definition")
    func afterDefinition() {
        #expect(tree("[x]: /u\na  \n") == """
            document @1:1-2:4
              paragraph @2:1-2:2
                text "a" @2:1-2:2

            """)
    }

    @Test("a setext heading whose lines end in spaces")
    func setextHeading() {
        #expect(tree("a  \n===  \n") == """
            document @1:1-2:6
              heading 1 @1:1-2:4
                text "a" @1:1-1:2

            """)
    }

    @Test("a setext heading in a block quote")
    func setextHeadingInBlockQuote() {
        #expect(tree("> a\n> b  \n> ---  \n") == """
            document @1:1-3:8
              block_quote @1:1-3:6
                heading 2 @1:3-3:6
                  text "a" @1:3-1:4
                  softbreak @-
                  text "b" @2:3-2:4

            """)
    }

    @Test("an ATX heading with content")
    func atxHeading() {
        #expect(tree("## a  \n") == """
            document @1:1-1:5
              heading 2 @1:1-1:5
                text "a" @1:4-1:5

            """)
    }

    @Test("an empty ATX heading followed by spaces and tabs", arguments: ["## \n", "##\t \n"])
    func emptyATXHeading(_ source: String) {
        #expect(tree(source) == """
            document @1:1-1:3
              heading 2 @1:1-1:3

            """)
    }

    @Test("an empty ATX heading in a block quote")
    func emptyATXHeadingInBlockQuote() {
        #expect(tree("> ## \n> a\n") == """
            document @1:1-2:4
              block_quote @1:1-2:4
                heading 2 @1:3-1:5
                paragraph @2:3-2:4
                  text "a" @2:3-2:4

            """)
    }
}
