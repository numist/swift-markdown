/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A bracket whose second byte is not `^` is no footnote reference, even when the bytes after that second byte spell
/// the label of a footnote definition.
@Suite("Footnote-shaped brackets require the caret")
struct FootnoteReferenceCaretRequiredTests {
    @Test(arguments: [
        ("[xa]", """
            document
              paragraph
                text "[xa]"

            """),
        ("[xa]\n\n[^a]: n", """
            document
              paragraph
                text "[xa]"

            """),
        ("> [xa]", """
            document
              block_quote
                paragraph
                  text "[xa]"

            """),
        ("> [xa]\n\n[^a]: n", """
            document
              block_quote
                paragraph
                  text "[xa]"

            """),
        ("- [xa]", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "[xa]"

            """),
        ("- [xa]\n\n[^a]: n", """
            document
              list bullet '-' tight
                item
                  paragraph
                    text "[xa]"

            """),
        ("[^a]\n\n[^a]: n", """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "n"

            """),
    ])
    func bracketNeedsCaret(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.footnotes]) == tree)
    }
}
