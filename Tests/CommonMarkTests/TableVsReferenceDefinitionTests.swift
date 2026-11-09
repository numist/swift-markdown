/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A delimiter row turns the open paragraph into a table before any link reference definition is
/// extracted from it (Tables (extension), Link reference definitions), so text shaped like a link
/// reference definition becomes table content.
@Suite("GFM table vs link reference definition precedence")
struct TableVsReferenceDefinitionTests {

    /// Read as a whole, `[\n|-\n]:/` is a link reference definition with label `\n|-\n`.
    @Test("a delimiter-row second line forms a table even when the paragraph reads as a link reference definition")
    func delimiterRowBeatsReferenceDefinition() {
        #expect(TreeDump.dump("[\n|-\n]:/", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "["
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "]:/"

            """)
    }

    @Test("the same table forms when the paragraph does not read as a link reference definition")
    func delimiterRowWithoutColon() {
        #expect(TreeDump.dump("[\n|-\n]a", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "["
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "]a"

            """)
    }

    /// No definition exists, so a later `[foo]` stays literal.
    @Test("a complete first-line link reference definition becomes the header cell when a delimiter row follows")
    func firstLineReferenceDefinitionAbsorbedAsHeader() {
        #expect(TreeDump.dump("[foo]: /bar\n|-\n|x", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "[foo]: /bar"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"

            """)
        #expect(TreeDump.dump("[foo]: /bar\n|-\n|x\n\n[foo]", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "[foo]: /bar"
                table_row
                  table_cell align=none colspan=1 rowspan=1
                    text "x"
              paragraph
                text "[foo]"

            """)
    }

    @Test("a multi-line link reference definition without a delimiter row defines a link")
    func multiLineReferenceDefinition() {
        #expect(TreeDump.dump("[a\nb]: /u\n\n[a b]", options: [.tables]) == """
            document
              paragraph
                link "/u" ""
                  text "a b"

            """)
    }

    // MARK: - Delimiter row after a complete link reference definition

    /// The `-` underlines no setext heading, since the paragraph before it holds only a link reference definition
    /// (Setext headings), and an empty list item cannot interrupt a paragraph (List items), so the `-` is paragraph text.
    @Test("a bare `-` after a complete single-line link reference definition is paragraph text", arguments: [
        ("[o]:o\n-", """
            document
              paragraph
                text "-"

            """),
        ("[o]: o\n-", """
            document
              paragraph
                text "-"

            """),
    ])
    func bareDelimiterAfterCompleteReferenceDefinition(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.tables]) == tree)
    }

    @Test("a pipe delimiter row after a complete link reference definition forms a table")
    func pipeDelimiterAfterCompleteReferenceDefinitionFormsTable() {
        #expect(TreeDump.dump("[o]:o\n|-", options: [.tables]) == """
            document
              table
                table_header
                  table_cell align=none colspan=1 rowspan=1
                    text "[o]:o"

            """)
    }
}
