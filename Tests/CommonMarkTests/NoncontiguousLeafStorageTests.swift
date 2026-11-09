/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Storage for paragraphs and setext headings whose lines are not contiguous in the source.
///
/// Such content is read in place as its source lines joined by line endings, including where leading definitions and
/// a task list item marker are matched, so only a link title spanning lines is copied into the materialized string
/// buffer. The empty document's buffer holds one byte, the line ending that joins lines.
@Suite("Content of non-contiguous lines stays in the source")
struct NoncontiguousLeafStorageTests {

    private static let options: MarkdownDocument.ParseOptions = [.tasklist, .attributes, .sourcePosition]

    private func materializedSize(_ source: String) -> Int {
        MarkdownDocument.withParsedDocument(source, options: Self.options) { $0._materializedStringSize }
    }

    private func tree(_ source: String) -> String {
        TreeDump.dump(source, options: Self.options, sourceRanges: true)
    }

    @Test("the empty document holds the line ending")
    func emptyDocument() {
        #expect(materializedSize("") == 1)
    }

    @Test("a setext heading")
    func setextHeading() {
        let source = "> abc\n> def\n> ===\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                heading 1 @1:3-3:6
                  text "abc" @1:3-1:6
                  softbreak @-
                  text "def" @2:3-2:6

            """)
    }

    @Test("a setext heading after a definition")
    func setextHeadingAfterDefinition() {
        let source = "> [x]: /u\n> abc\n> ===\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                heading 1 @2:3-3:6
                  text "abc" @2:3-2:6

            """)
    }

    @Test("a paragraph beginning with a bracket that begins no definition")
    func bracketWithoutDefinition() {
        let source = "> [abc\n> def\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-2:6
              block_quote @1:1-2:6
                paragraph @1:3-2:6
                  text "[abc" @1:3-1:7
                  softbreak @-
                  text "def" @2:3-2:6

            """)
    }

    @Test("a paragraph after a definition")
    func paragraphAfterDefinition() {
        let source = "> [a]: /u\n> abc\n> [a]\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @2:3-3:6
                  text "abc" @2:3-2:6
                  softbreak @-
                  link "/u" "" @3:3-3:6
                    text "a" @3:4-3:5

            """)
    }

    @Test("a paragraph after an attribute definition")
    func paragraphAfterAttributeDefinition() {
        let source = "> ^[a]: b\n> ^[c][a]\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-2:10
              block_quote @1:1-2:10
                paragraph @2:3-2:10
                  attribute "b" @2:3-2:10
                    text "c" @2:5-2:6

            """)
    }

    @Test("a definition whose title spans lines copies the title")
    func titleSpanningLines() {
        let source = "> [a]: /u \"t\n> u\"\n> [a]\n"
        // "t\nu"
        #expect(materializedSize(source) == 1 + 3)
        #expect(tree(source) == """
            document @1:1-3:6
              block_quote @1:1-3:6
                paragraph @3:3-3:6
                  link "/u" "t\\nu" @3:3-3:6
                    text "a" @3:4-3:5

            """)
    }

    @Test("a task list item marker")
    func taskListItemMarker() {
        let source = "- [x] a\n  b\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-2:4
              list bullet '-' tight @1:1-2:4
                tasklist checked @1:1-2:4
                  paragraph @1:7-2:4
                    text "a" @1:7-1:8
                    softbreak @-
                    text "b" @2:3-2:4

            """)
    }

    @Test("line tabulations around a definition")
    func lineTabulationsAroundDefinition() {
        let source = "> \u{0B}[a]: /u\n> b\u{0B}\n"
        #expect(materializedSize(source) == 1)
        #expect(tree(source) == """
            document @1:1-2:5
              block_quote @1:1-2:5
                paragraph @2:3-2:4
                  text "b" @2:3-2:4

            """)
    }
}
