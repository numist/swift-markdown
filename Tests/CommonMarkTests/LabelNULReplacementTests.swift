/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A NUL is replaced by U+FFFD (Insecure characters), so a label holding a NUL matches the same label written with
/// U+FFFD, and neither matches the label without it.
@Suite("Labels holding a NUL or U+FFFD")
struct LabelNULReplacementTests {
    static let replacedPairs = [("a\u{0}", "a\u{FFFD}"), ("a\u{FFFD}", "a\u{0}")]
    static let differentPairs = [("a\u{0}", "a"), ("a", "a\u{FFFD}"), ("a\u{FFFD}", "a")]

    @Test(arguments: replacedPairs)
    func referenceLabelsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "a\u{FFFD}"

            """)
    }

    @Test(arguments: differentPairs)
    func referenceLabelsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                text "[\(use)]"

            """)
    }

    @Test(arguments: replacedPairs)
    func footnoteLabelsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a\u{FFFD}"
                paragraph
                  text "d"

            """)
    }

    @Test(arguments: differentPairs)
    func footnoteLabelsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                text "[^\(use)]"

            """)
    }

    @Test(arguments: replacedPairs)
    func attributeLabelsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }

    @Test(arguments: differentPairs)
    func attributeLabelsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                text "^[x][\(use)]"

            """)
    }
}

