/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Labels match when their Unicode case folds are canonically equivalent. Precomposed `é` (U+00E9) matches `e` followed
/// by a combining acute accent (U+0301), the compatibility ideograph U+F900 matches U+8C48, its canonical decomposition,
/// the Greek question mark U+037E matches `;`, and U+1F80 matches `α` U+0313 U+0345, whose folds U+1F00 U+03B9 and `α`
/// U+0313 U+03B9 are canonically equivalent. Pairs whose folds are identical match too.
@Suite("Canonically equivalent labels")
struct CanonicallyEquivalentLabelTests {
    static let equivalentPairs = [
        ("\u{E9}", "e\u{301}"), ("e\u{301}", "\u{E9}"), ("\u{F900}", "\u{8C48}"), ("\u{8C48}", "\u{F900}"),
        ("\u{37E}", ";"), (";", "\u{37E}"), ("\u{1F80}", "\u{3B1}\u{313}\u{345}"), ("\u{3B1}\u{313}\u{345}", "\u{1F80}"),
    ]

    static let labels = ["\u{E9}", "e\u{301}", "\u{F900}", "\u{8C48}", "\u{37E}", ";", "\u{1F80}", "\u{3B1}\u{313}\u{345}"]

    static let pairsWithIdenticalFolds = [
        ("\u{1F80}", "\u{1F00}\u{3B9}"), ("\u{1F00}\u{3B9}", "\u{1F80}"), ("\u{3B1}\u{313}\u{345}", "\u{3B1}\u{313}\u{3B9}"),
        ("\u{3B1}\u{313}\u{3B9}", "\u{3B1}\u{313}\u{345}"), ("\u{1F88}", "\u{1F80}"), ("\u{1F80}", "\u{1F88}"),
    ]

    @Test(arguments: equivalentPairs)
    func canonicallyEquivalentReferenceLabelsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(use)"

            """)
    }

    @Test(arguments: labels)
    func identicalReferenceLabelsMatch(_ label: String) {
        #expect(TreeDump.dump("[\(label)]: /u\n\n[\(label)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(label)"

            """)
    }

    @Test(arguments: pairsWithIdenticalFolds)
    func referenceLabelsWithIdenticalFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(use)"

            """)
    }

    @Test(arguments: equivalentPairs)
    func canonicallyEquivalentFootnoteLabelsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(definition)"
                paragraph
                  text "d"

            """)
    }

    @Test(arguments: labels)
    func identicalFootnoteLabelsMatch(_ label: String) {
        #expect(TreeDump.dump("[^\(label)]: d\n\n[^\(label)]", options: [.footnotes]) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(label)"
                paragraph
                  text "d"

            """)
    }

    @Test(arguments: pairsWithIdenticalFolds)
    func footnoteLabelsWithIdenticalFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "\(definition)"
                paragraph
                  text "d"

            """)
    }

    @Test(arguments: equivalentPairs)
    func canonicallyEquivalentAttributeLabelsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }

    @Test(arguments: labels)
    func identicalAttributeLabelsMatch(_ label: String) {
        #expect(TreeDump.dump("^[\(label)]: c\n\n^[x][\(label)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }

    @Test(arguments: pairsWithIdenticalFolds)
    func attributeLabelsWithIdenticalFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }
}
