/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Labels match when their Unicode case folds are equal (Links), and so do footnote and attribute labels. The full case
/// fold maps `ß` and `ẞ` to `ss`, `µ` to `μ`, `ſ` to `s`, `ς` to `σ` and the Kelvin sign to `k`. Dotless `ı` folds to
/// itself, so it matches neither `I` nor `i`.
@Suite("Link and footnote labels under the Unicode case fold")
struct LabelCaseFoldTests {

    @Test(arguments: [
        ("ß", "SS"), ("SS", "ß"), ("ẞ", "ss"), ("ẞ", "ß"), ("µ", "Μ"), ("ſ", "S"), ("ς", "Σ"), ("\u{212A}", "k"),
        ("Straße  x", "STRASSE x"),
    ])
    func referenceLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(use)"

            """)
    }

    @Test(arguments: [("ı", "I"), ("ı", "i"), ("I", "ı"), ("i", "ı")])
    func referenceLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                text "[\(use)]"

            """)
    }

    @Test(arguments: [("ß", "SS"), ("SS", "ß"), ("ẞ", "ss"), ("ẞ", "ß"), ("µ", "Μ"), ("ſ", "S"), ("ς", "Σ")])
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

    @Test(arguments: [("ı", "I"), ("ı", "i"), ("I", "ı"), ("i", "ı")])
    func footnoteLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                text "[^\(use)]"

            """)
    }

    @Test(arguments: [("ß", "SS"), ("ſ", "S")])
    func attributeLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }

    @Test(arguments: [("ı", "I"), ("I", "ı")])
    func attributeLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                text "^[x]"

            """)
    }
}
