/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A backslash before a line ending is a literal backslash (Backslash escapes), so a link label whose line ends in one
/// is still open and a `]` on a later line closes it (Link reference definitions). An underline that a line of only
/// whitespace keeps from forming a heading leaves the definition to complete, and a later underline forms a heading of
/// the lines past it (Setext headings).
@Suite("An open label ending in a backslash at a setext underline")
struct SetextUnderlineOpenLabelBackslashTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = [.sourcePosition]) -> String {
        TreeDump.dump(source, options: options, sourceRanges: true)
    }

    @Test("a link reference definition")
    func linkReferenceDefinition() {
        #expect(tree("[a\\\n\u{0B}\n=\n]: /u\nx\n=\n") == """
            document @1:1-7:1
              heading 1 @5:1-6:2
                text "x" @5:1-5:2

            """)
    }

    @Test("a link reference definition in a block quote")
    func linkReferenceDefinitionInBlockQuote() {
        #expect(tree("> [a\\\n> \u{0B}\n> =\n> ]: /u\n> x\n> =\n") == """
            document @1:1-7:1
              block_quote @1:1-6:4
                heading 1 @5:3-6:4
                  text "x" @5:3-5:4

            """)
    }

    @Test("an attribute definition")
    func attributeDefinition() {
        #expect(tree("^[a\\\n\u{0B}\n=\n]: x\ny\n=\n", options: [.attributes, .sourcePosition]) == """
            document @1:1-7:1
              heading 1 @5:1-6:2
                text "y" @5:1-5:2

            """)
    }
}
