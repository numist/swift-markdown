/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// The lines before a table's header row form an ordinary paragraph (Paragraphs), so a `\|` in them is a backslash
/// escape (Backslash escapes) rather than a cell's escaped pipe (Tables (extension)).
@Suite("Escaped pipe in the paragraph before a table")
struct TablePrecedingParagraphPipeEscapeTests {
    private static let options: MarkdownDocument.ParseOptions = [.tables, .sourcePosition]

    private func surface(_ markdown: String) -> String {
        TreeDump.dump(markdown, options: Self.options, sourceRanges: true)
    }

    private func table(line: Int) -> String {
        """
          table @\(line):1-\(line + 1):4
            table_header @\(line):1-\(line):6
              table_cell align=none colspan=1 rowspan=1 @\(line):2-\(line):5
                text "a" @\(line):3-\(line):4

        """
    }

    @Test func testBackslashBeforePipeInCodeSpanIsLiteral() {
        #expect(surface("`a\\|b`\n| a |\n|-|") == """
            document @1:1-3:4
              paragraph @1:1-1:7
                code "a\\\\|b" @1:1-1:7

            """ + table(line: 2))
    }

    @Test func testEscapedBackslashBeforePipeIsBackslash() {
        #expect(surface("x\\\\|y\n| a |\n|-|") == """
            document @1:1-3:4
              paragraph @1:1-1:6
                text "x\\\\|y" @1:1-1:6

            """ + table(line: 2))
    }

    @Test func testEscapedPipeIsPipe() {
        #expect(surface("x\\|y\n| a |\n|-|") == """
            document @1:1-3:4
              paragraph @1:1-1:5
                text "x|y" @1:1-1:5

            """ + table(line: 2))
    }
}
