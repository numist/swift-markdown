/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Storage for a paragraph or setext heading whose lines aren't contiguous in the source and hold a NUL.
///
/// Its content is copied into the materialized string buffer once, with each NUL replaced by U+FFFD (Insecure
/// characters). The buffer also holds the line ending that joins lines, so `> a\0b` and `> c` take 1 + 7 bytes.
@Suite("A non-contiguous paragraph holding a NUL is copied once")
struct NULNoncontiguousLeafStorageTests {

    private func materializedSize(_ source: String, options: MarkdownDocument.ParseOptions) -> Int {
        MarkdownDocument.withParsedDocument(source, options: options) { $0._materializedStringSize }
    }

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    @Test("a paragraph", arguments: [[], [MarkdownDocument.ParseOptions.sourcePosition]])
    func paragraph(_ options: MarkdownDocument.ParseOptions) {
        let source = "> a\u{0}b\n> c\n"
        #expect(materializedSize(source, options: options) == 1 + 7)
        #expect(tree(source, options: options) == """
            document @1:1-3:1
              block_quote @1:1-2:4
                paragraph @1:3-2:4
                  text "a\u{FFFD}b" @1:3-1:6
                  softbreak @-
                  text "c" @2:3-2:4

            """)
    }

    @Test("a setext heading", arguments: [[], [MarkdownDocument.ParseOptions.sourcePosition]])
    func setextHeading(_ options: MarkdownDocument.ParseOptions) {
        let source = "> a\u{0}b\n> c\n> ===\n"
        #expect(materializedSize(source, options: options) == 1 + 7)
        #expect(tree(source, options: options) == """
            document @1:1-4:1
              block_quote @1:1-3:6
                heading 1 @1:3-3:6
                  text "a\u{FFFD}b" @1:3-1:6
                  softbreak @-
                  text "c" @2:3-2:4

            """)
    }

    @Test("the lines before a table's header row", arguments: [[.tables], [MarkdownDocument.ParseOptions.tables, .sourcePosition]])
    func linesBeforeTableHeader(_ options: MarkdownDocument.ParseOptions) {
        let source = "> a\u{0}b\n> c\n> x|y\n> -|-\n"
        #expect(materializedSize(source, options: options) == 1 + 7)
        #expect(tree(source, options: options) == """
            document @1:1-5:1
              block_quote @1:1-4:6
                paragraph @1:3-2:4
                  text "a\u{FFFD}b" @1:3-1:6
                  softbreak @-
                  text "c" @2:3-2:4
                table @3:3-4:6
                  table_header @3:3-3:6
                    table_cell align=none colspan=1 rowspan=1 @3:3-3:4
                      text "x" @3:3-3:4
                    table_cell align=none colspan=1 rowspan=1 @3:5-3:6
                      text "y" @3:5-3:6

            """)
    }
}
