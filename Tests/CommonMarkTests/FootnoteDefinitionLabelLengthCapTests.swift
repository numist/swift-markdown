/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote definition's label has at most 999 characters, as a link label does (Links), so a `[^label]:` with a
/// longer label begins no definition and can't interrupt a paragraph.
@Suite("Footnote definition label length cap")
struct FootnoteDefinitionLabelLengthCapTests {

    @Test("an opener whose label has 999 characters interrupts a paragraph")
    func openerAtCapInterruptsParagraph() {
        let label = String(repeating: "a", count: 999)
        #expect(TreeDump.dump("x[^\(label)]\n[^\(label)]: note\n", options: .footnotes) == """
            document
              paragraph
                text "x"
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "note"

            """)
    }

    @Test("an opener whose label has 1,000 characters continues a paragraph")
    func openerOverCapContinuesParagraph() {
        let label = String(repeating: "a", count: 1000)
        #expect(TreeDump.dump("x[^\(label)]\n[^\(label)]: note\n", options: .footnotes) == """
            document
              paragraph
                text "x[^\(label)]"
                softbreak
                text "[^\(label)]: note"

            """)
    }
}
