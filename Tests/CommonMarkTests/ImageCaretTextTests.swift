/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// An image is `!` followed by a link (Images), whatever its text begins with. With footnotes, a bracket whose
/// `[^label]` names a footnote definition is a footnote reference only when it forms neither an inline nor a
/// reference link or image; an image's `!` then stays text.
@Suite("Images whose text begins with a caret")
struct ImageCaretTextTests {

    @Test("an inline image's text may begin with a caret")
    func inlineImage() {
        #expect(TreeDump.dump("![^a](b)", options: []) == """
            document
              paragraph
                image "b" ""
                  text "^a"

            """)
    }

    @Test("a reference image's label may begin with a caret")
    func referenceImage() {
        #expect(TreeDump.dump("![^a]\n\n[^a]: /u", options: []) == """
            document
              paragraph
                image "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, an inline image's text may begin with a caret naming a footnote definition")
    func inlineImageWithFootnotes() {
        #expect(TreeDump.dump("![^a](b)\n\n[^a]: z", options: [.footnotes]) == """
            document
              paragraph
                image "b" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a reference image's text may begin with a caret naming no footnote definition")
    func referenceImageWithFootnotes() {
        #expect(TreeDump.dump("![^a][c]\n\n[c]: /u", options: [.footnotes]) == """
            document
              paragraph
                image "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a shortcut image's caret label naming only a footnote definition is a footnote reference after the `!`")
    func footnoteReferenceAfterExclamationMark() {
        #expect(TreeDump.dump("![^a]\n\n[^a]: z", options: [.footnotes]) == """
            document
              paragraph
                text "!"
                footnote_reference "1"
              footnote_definition "a"
                paragraph
                  text "z"

            """)
    }

    @Test("with footnotes, a full reference link's caret text naming a footnote definition is link text")
    func fullReferenceLinkOverFootnote() {
        #expect(TreeDump.dump("[^a][c]\n\n[^a]: z\n\n[c]: /u", options: [.footnotes]) == """
            document
              paragraph
                link "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a full reference image's caret text naming a footnote definition is image text")
    func fullReferenceImageOverFootnote() {
        #expect(TreeDump.dump("![^a][c]\n\n[^a]: z\n\n[c]: /u", options: [.footnotes]) == """
            document
              paragraph
                image "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a collapsed reference link's caret label naming both definitions is a link")
    func collapsedReferenceLinkOverFootnote() {
        #expect(TreeDump.dump("[^a][]\n\n[^a]: z\n\n[ ^a]: /u", options: [.footnotes]) == """
            document
              paragraph
                link "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a collapsed reference image's caret label naming both definitions is an image")
    func collapsedReferenceImageOverFootnote() {
        #expect(TreeDump.dump("![^a][]\n\n[^a]: z\n\n[ ^a]: /u", options: [.footnotes]) == """
            document
              paragraph
                image "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a shortcut reference link's caret label naming both definitions is a link")
    func shortcutReferenceLinkOverFootnote() {
        #expect(TreeDump.dump("[^a]\n\n[^a]: z\n\n[ ^a]: /u", options: [.footnotes]) == """
            document
              paragraph
                link "/u" ""
                  text "^a"

            """)
    }

    @Test("with footnotes, a shortcut reference image's caret label naming both definitions is an image")
    func shortcutReferenceImageOverFootnote() {
        #expect(TreeDump.dump("![^a]\n\n[^a]: z\n\n[ ^a]: /u", options: [.footnotes]) == """
            document
              paragraph
                image "/u" ""
                  text "^a"

            """)
    }
}
