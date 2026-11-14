/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// `referenceExpansionBudget` bounds the bytes of destination and title that link references expand to. The budget
/// is the larger of the limit and the source's byte count. Each resolved link reference, in document order, is charged
/// its definition's destination and title bytes after backslash escapes and character references are resolved, and a
/// reference whose charge would exceed what is left of the budget stays text. Footnote and inline attribute
/// references are not charged.
@Suite("Reference expansion budget")
struct ReferenceExpansionBudgetTests {

    private func limits(_ budget: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.referenceExpansionBudget = budget
        return limits
    }

    @Test("references resolve while their charges fit the budget")
    func budgetBoundary() {
        let source = "[a]: uuuuuuuuuuuuuuuuuuuu\n\n[a] [a] [a] [a]"
        #expect(source.utf8.count == 42)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " [a]"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " [a] [a]"

            """)
    }

    @Test("the default limits resolve every reference")
    func defaultLimits() {
        #expect(TreeDump.dump("[a]: uuuuuuuuuuuuuuuuuuuu\n\n[a] [a] [a] [a]", options: []) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"

            """)
    }

    @Test("the default limits resolve 1000 uses of a 2001-byte destination")
    func defaultLimitsAtScale() {
        let source = "[a]: /" + String(repeating: "u", count: 2000) + "\n\n"
            + Array(repeating: "[a]", count: 1000).joined(separator: " ")
        let tree = TreeDump.dump(source, options: [])
        #expect(tree.components(separatedBy: "link \"/").count - 1 == 1000)
        #expect(tree.components(separatedBy: "text \" \"").count - 1 == 999)
    }

    @Test("a budget below the source's byte count is the source's byte count")
    func sourceByteCount() {
        let fits = "[a]: uuuuuuuuuuuuuuuuuuuu\n\n[a] [a]\n\nzzzz"
        let short = "[a]: uuuuuuuuuuuuuuuuuuuu\n\n[a] [a]\n\nzzz"
        #expect(fits.utf8.count == 40)
        #expect(short.utf8.count == 39)
        #expect(TreeDump.dump(fits, options: [], limits: limits(0)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
              paragraph
                text "zzzz"

            """)
        #expect(TreeDump.dump(short, options: [], limits: limits(0)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " [a]"
              paragraph
                text "zzz"

            """)
        #expect(TreeDump.dump(short, options: [], limits: limits(-1)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " [a]"
              paragraph
                text "zzz"

            """)
    }

    @Test("a reference is charged its title")
    func title() {
        let source = "[a]: uuuuuuuuuuuuuuu \"ttttt\"\n\n[a] [a] [a] [a]"
        #expect(source.utf8.count == 45)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuu" "ttttt"
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuu" "ttttt"
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuu" "ttttt"
                  text "a"
                text " [a]"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuu" "ttttt"
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuu" "ttttt"
                  text "a"
                text " [a] [a]"

            """)
    }

    @Test("a reference is charged its destination after backslash escapes are resolved")
    func backslashEscapes() {
        let source = "[a]: uuuuuuuuuu\\!\\!\\!\\!\\!\\!\\!\\!\\!\\!\n\n[a] [a] [a] [a]"
        #expect(source.utf8.count == 52)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuu!!!!!!!!!!" ""
                  text "a"
                text " "
                link "uuuuuuuuuu!!!!!!!!!!" ""
                  text "a"
                text " "
                link "uuuuuuuuuu!!!!!!!!!!" ""
                  text "a"
                text " [a]"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                link "uuuuuuuuuu!!!!!!!!!!" ""
                  text "a"
                text " "
                link "uuuuuuuuuu!!!!!!!!!!" ""
                  text "a"
                text " [a] [a]"

            """)
    }

    @Test("a reference is charged its destination after character references are resolved")
    func characterReferences() {
        let source = "[a]: &amp;&amp;&amp;&amp;uuuuuuuuuuuuuuii\n\n[a] [a] [a] [a]"
        #expect(source.utf8.count == 58)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                link "&&&&uuuuuuuuuuuuuuii" ""
                  text "a"
                text " "
                link "&&&&uuuuuuuuuuuuuuii" ""
                  text "a"
                text " "
                link "&&&&uuuuuuuuuuuuuuii" ""
                  text "a"
                text " [a]"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                link "&&&&uuuuuuuuuuuuuuii" ""
                  text "a"
                text " "
                link "&&&&uuuuuuuuuuuuuuii" ""
                  text "a"
                text " [a] [a]"

            """)
    }

    @Test("a reference is charged a NUL in its destination as the three bytes of U+FFFD")
    func nul() {
        let source = "[a]: uuuuuuuuuuuuuuuuu\u{0}\n\n[a] [a] [a] [a]"
        #expect(source.utf8.count == 40)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuu\u{FFFD}" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuu\u{FFFD}" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuu\u{FFFD}" ""
                  text "a"
                text " [a]"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuu\u{FFFD}" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuu\u{FFFD}" ""
                  text "a"
                text " [a] [a]"

            """)
    }

    @Test("a reference is charged bytes, not characters")
    func multibyte() {
        let source = "[a]: éééééééééé\n\n[a] [a] [a] [a]"
        #expect(source.utf8.count == 42)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                link "éééééééééé" ""
                  text "a"
                text " "
                link "éééééééééé" ""
                  text "a"
                text " "
                link "éééééééééé" ""
                  text "a"
                text " [a]"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                link "éééééééééé" ""
                  text "a"
                text " "
                link "éééééééééé" ""
                  text "a"
                text " [a] [a]"

            """)
    }

    @Test("references are charged in document order, across blocks and before their definition")
    func documentOrder() {
        let source = "[a]\n\n# [a]\n\n> [a]\n\n|[a]|\n|-|\n\n[a]: uuuuuuuuuuuuuuuuuuuu"
        #expect(source.utf8.count == 55)
        #expect(TreeDump.dump(source, options: .tables, limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
              heading 1
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
              block_quote
                paragraph
                  link "uuuuuuuuuuuuuuuuuuuu" ""
                    text "a"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "[a]"

            """)
        #expect(TreeDump.dump(source, options: .tables, limits: limits(80)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
              heading 1
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
              block_quote
                paragraph
                  link "uuuuuuuuuuuuuuuuuuuu" ""
                    text "a"
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    link "uuuuuuuuuuuuuuuuuuuu" ""
                      text "a"

            """)
    }

    @Test("image, collapsed and full references are charged")
    func referenceForms() {
        let source = "[a]: uuuuuuuuuuuuuuuuuuuu\n\n![a] [a][] [x][a]"
        #expect(source.utf8.count == 44)
        #expect(TreeDump.dump(source, options: [], limits: limits(60)) == """
            document
              paragraph
                image "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "x"

            """)
        #expect(TreeDump.dump(source, options: [], limits: limits(59)) == """
            document
              paragraph
                image "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                link "uuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " [x][a]"

            """)
    }

    @Test("footnote references are not charged")
    func footnoteReferences() {
        let source = "[^n]: x\n\n[a]: uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu\n\n[^n] [a] [^n] [a]"
        #expect(source.utf8.count == 68)
        #expect(TreeDump.dump(source, options: .footnotes, limits: limits(70)) == """
            document
              paragraph
                footnote_reference "1"
                text " "
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                footnote_reference "1"
                text " "
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
              footnote_definition "n"
                paragraph
                  text "x"

            """)
    }

    @Test("inline attribute references are not charged")
    func attributeReferences() {
        let source = "^[b]: k\n[a]: uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu\n\n[a] ^[x][b] [a]"
        #expect(source.utf8.count == 60)
        #expect(TreeDump.dump(source, options: .attributes, limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " "
                attribute "k"
                  text "x"
                text " "
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"

            """)
    }

    /// Attribute and link labels are separate namespaces, so an inline attribute label never reads or charges a link
    /// definition of the same label.
    @Test("an inline attribute label that matches a link definition is not charged")
    func attributeLabelNamingLinkDefinition() {
        let source = "[a]: uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu\n\n[a] ^[x][a] [a]"
        #expect(source.utf8.count == 52)
        #expect(TreeDump.dump(source, options: .attributes, limits: limits(60)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " ^[x] "
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"

            """)
        #expect(TreeDump.dump(source, options: .attributes, limits: limits(59)) == """
            document
              paragraph
                link "uuuuuuuuuuuuuuuuuuuuuuuuuuuuuu" ""
                  text "a"
                text " ^[x] [a]"

            """)
    }
}
