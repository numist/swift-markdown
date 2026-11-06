/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Link references, footnote references and attribute labels each match only definitions of their own kind, so a
/// document that defines only other kinds resolves none of them, while the forms keep the text they consume.
@Suite("Label lookups in documents without definitions of that kind")
struct LabelLookupWithoutDefinitionsTests {

    private func tree(_ source: String, options: MarkdownDocument.ParseOptions = []) -> String {
        TreeDump.dump(source, options: options.union(.sourcePosition), sourceRanges: true)
    }

    @Test("full, collapsed and shortcut references stay text in a document without definitions")
    func linkReferencesWithoutDefinitions() {
        #expect(tree("[x][b] [x][] [x]") == """
            document @1:1-1:17
              paragraph @1:1-1:17
                text "[x][b] [x][] [x]" @1:1-1:17

            """)
    }

    @Test("full, collapsed and shortcut references stay text when only other kinds are defined")
    func linkReferencesWithOnlyOtherDefinitions() {
        #expect(tree("^[b]: c\n[^b]: d\n\n[x][b] [b][] [b]", options: [.attributes, .footnotes]) == """
            document @1:1-4:17
              paragraph @4:1-4:17
                text "[x][b] [b][] [b]" @4:1-4:17

            """)
    }

    @Test("full, collapsed and shortcut references resolve when a link definition matches")
    func linkReferencesWithDefinition() {
        #expect(tree("[b]: /u\n\n[x][b] [b][] [b]") == """
            document @1:1-3:17
              paragraph @3:1-3:17
                link "/u" "" @3:1-3:7
                  text "x" @3:2-3:3
                text " " @3:7-3:8
                link "/u" "" @3:8-3:13
                  text "b" @3:9-3:10
                text " " @3:13-3:14
                link "/u" "" @3:14-3:17
                  text "b" @3:15-3:16

            """)
    }

    @Test("a footnote reference stays text when only a link is defined")
    func footnoteReferenceWithOnlyLinkDefinition() {
        #expect(tree("[b]: /u\n\n[^b]", options: [.footnotes]) == """
            document @1:1-3:5
              paragraph @3:1-3:5
                text "[^b]" @3:1-3:5

            """)
    }

    @Test("an attribute's label is dropped in a document without definitions")
    func attributeLabelWithoutDefinitions() {
        #expect(tree("^[x][b] y", options: [.attributes]) == """
            document @1:1-1:10
              paragraph @1:1-1:10
                text "^[x] y" @1:1-1:10

            """)
    }

    @Test("an attribute's label is dropped when only a link is defined with that label")
    func attributeLabelWithOnlyLinkDefinition() {
        #expect(tree("[b]: /u\n\n^[x][b] y", options: [.attributes]) == """
            document @1:1-3:10
              paragraph @3:1-3:10
                text "^[x] y" @3:1-3:10

            """)
    }
}
