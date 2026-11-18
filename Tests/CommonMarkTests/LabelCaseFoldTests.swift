/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

@Suite("Link and footnote labels under the Unicode case fold")
struct LabelCaseFoldTests {
    static let pairsWithEqualFolds = [
        ("ß", "SS"), ("SS", "ß"), ("ß", "ss"), ("ss", "ß"), ("ẞ", "ss"), ("ẞ", "ß"), ("\u{FB03}", "ffi"),
        ("FFI", "\u{FB03}"), ("\u{149}", "\u{2BC}N"), ("\u{2BC}n", "\u{149}"), ("µ", "Μ"), ("ſ", "S"), ("ς", "Σ"),
        ("\u{212A}", "k"), ("k", "\u{212A}"), ("\u{212A}", "K"), ("K", "\u{212A}"), ("\u{212A}elvin", "KELVIN"),
        ("\u{1C90}", "\u{10D0}"), ("\u{10D0}", "\u{1C90}"), ("\u{A7CE}", "\u{A7CF}"), ("\u{A7CF}", "\u{A7CE}"),
    ]

    // Labels match by Unicode case fold (Links), under which dotless `ı` folds to itself, so it matches neither `I` nor
    // `i`.
    static let pairsWithDifferentFolds = [("ı", "I"), ("ı", "i"), ("I", "ı"), ("i", "ı")]

    static let foldLengthPairs = [
        ("\u{C9}abcde", "\u{E9}ABCDE"), ("\u{C9}abcdef", "\u{E9}ABCDEF"), ("\u{C9}abcdefg", "\u{E9}ABCDEFG"),
        ("\u{C9}abcdefghijklmn", "\u{E9}ABCDEFGHIJKLMN"), ("\u{C9}abcdefghijklmno", "\u{E9}ABCDEFGHIJKLMNO"),
    ]

    static let lastByteDifferencePairs = [
        ("\u{C9}abcde", "\u{C9}abcdf"), ("\u{C9}abcdef", "\u{C9}abcdeg"), ("\u{C9}abcdefg", "\u{C9}abcdefh"),
        ("\u{C9}abcdefghijklmn", "\u{C9}abcdefghijklmo"), ("\u{C9}abcdefghijklmno", "\u{C9}abcdefghijklmnp"),
    ]

    @Test func foldLengths() {
        #expect(Self.foldLengthPairs.map { $0.1.lowercased().utf8.count } == [7, 8, 9, 16, 17])
    }

    @Test(arguments: pairsWithEqualFolds + [("Straße  x", "STRASSE x")])
    func referenceLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(use)"

            """)
    }

    @Test(arguments: pairsWithDifferentFolds)
    func referenceLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                text "[\(use)]"

            """)
    }

    @Test(arguments: pairsWithEqualFolds)
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

    @Test(arguments: pairsWithDifferentFolds)
    func footnoteLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[^\(definition)]: d\n\n[^\(use)]", options: [.footnotes]) == """
            document
              paragraph
                text "[^\(use)]"

            """)
    }

    @Test(arguments: pairsWithEqualFolds)
    func attributeLabelsWithEqualFoldsMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                attribute "c"
                  text "x"

            """)
    }

    @Test(arguments: pairsWithDifferentFolds)
    func attributeLabelsWithDifferentFoldsDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("^[\(definition)]: c\n\n^[x][\(use)]", options: [.attributes]) == """
            document
              paragraph
                text "^[x]"

            """)
    }

    @Test(arguments: foldLengthPairs)
    func labelsOfEachFoldLengthMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                link "/u" ""
                  text "\(use)"

            """)
    }

    @Test(arguments: lastByteDifferencePairs)
    func labelsWhoseFoldsDifferInTheLastByteDoNotMatch(_ definition: String, _ use: String) {
        #expect(TreeDump.dump("[\(definition)]: /u\n\n[\(use)]", options: []) == """
            document
              paragraph
                text "[\(use)]"

            """)
    }
}
