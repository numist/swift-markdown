/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Link label length cap")
struct LinkLabelLengthCapTests {

    private func label(_ n: Int) -> String { String(repeating: "a", count: n) }

    @Test("a link reference definition with a 999-character label is valid and produces no block")
    func referenceDefinitionAtTheCap() {
        #expect(TreeDump.dump("[\(label(999))]: /u", options: []) == """
            document

            """)
    }

    @Test("a 999-character shortcut reference resolves")
    func shortcutReferenceAtTheCap() {
        #expect(TreeDump.dump("[\(label(999))]: /u\n\n[\(label(999))]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(label(999))"

            """)
    }

    // Both references' labels normalize to the defined label (Links), but the space before the second's line ending
    // makes it 1,000 characters.
    @Test("a full reference label across a line ending resolves at the cap but not one past it")
    func multiSegmentReferenceLabelCap() {
        let half = label(499)
        let definition = "[\(half) \(half)]: /u\n\n"

        #expect(TreeDump.dump(definition + ">[t][\(half)\n>\(half)]", options: []) == """
            document
              block_quote
                paragraph
                  link "/u" ""
                    text "t"

            """)
        #expect(TreeDump.dump(definition + ">[t][\(half) \n>\(half)]", options: []) == """
            document
              block_quote
                paragraph
                  text "[t][\(half)"
                  softbreak
                  text "\(half)]"

            """)
    }

    @Test("1000- and 1001-character labels neither define nor resolve", arguments: [1000, 1001])
    func overCapLabelsNeitherDefineNorResolve(_ length: Int) {
        #expect(TreeDump.dump("[\(label(length))]: /u", options: []) == """
            document
              paragraph
                text "[\(label(length))]: /u"

            """)
        // The reference's label normalizes to the defined 999-character label, so only its own length keeps it from
        // resolving.
        let half = label(499)
        let reference = "[\(half)\(String(repeating: " ", count: length - 998))\(half)]"
        #expect(TreeDump.dump("[\(half) \(half)]: /u\n\n" + reference, options: []) == """
            document
              paragraph
                text "\(reference)"

            """)
    }
}
