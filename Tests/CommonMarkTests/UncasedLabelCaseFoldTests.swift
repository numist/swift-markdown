/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A character without case, such as a CJK ideograph, an emoji or U+FFFD, is its own Unicode case fold, so labels
/// holding such characters match when those characters are equal and the cased characters fold alike (Links).
@Suite("Labels holding characters without case")
struct UncasedLabelCaseFoldTests {

    @Test(arguments: [
        ("日本", "日本"), ("日本 Ab", "日本 aB"), ("\u{FFFD}x", "\u{FFFD}X"), ("😀A", "😀a"), ("→ Straße", "→ STRASSE"),
        ("Σ日ß", "σ日SS"), ("\u{FFFD}\u{FFFD} ı", "\u{FFFD}\u{FFFD} ı"),
    ])
    func referenceLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(use)"

            """)
    }

    @Test(arguments: [("日本", "日木"), ("\u{FFFD}x", "x"), ("😀ı", "😀I"), ("日i", "日ı"), ("→ ß", "→ S")])
    func referenceLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                text "[\(use)]"

            """)
    }

    @Test(arguments: [("日本Ab", "日本aB"), ("\u{FFFD}ß", "\u{FFFD}ss")])
    func footnoteLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(definition)"
                paragraph
                  text "d"

            """)
    }

    @Test(arguments: [("日本 Ab", "日本 aB"), ("\u{FFFD}ß", "\u{FFFD}ss")])
    func attributeLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }
}
