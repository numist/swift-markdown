/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// A footnote reference's label is the raw text after its `^`, matched against a definition's label after the same
/// normalization as a link label (Links), so emphasis delimiters in it are part of the label and produce no emphasis
/// node. Without a definition of that label, the bracket is literal text and its emphasis is parsed as usual.
@Suite("Emphasis delimiters inside a footnote reference label")
struct FootnoteReferenceEmphasisLabelTests {
    @Test(arguments: [
        ("[^a*b*]", """
            document
              paragraph
                text "[^a"
                emph
                  text "b"
                text "]"

            """),
        ("[^a*b*]\n\n[^a*b*]: n", """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a*b*"
                paragraph
                  text "n"

            """),
        ("[^a*b*]\n\n[^a]: n", """
            document
              paragraph
                text "[^a"
                emph
                  text "b"
                text "]"

            """),
        ("[^*a_b_*]", """
            document
              paragraph
                text "[^"
                emph
                  text "a_b_"
                text "]"

            """),
        ("[^*a_b_*]\n\n[^*a_b_*]: n", """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "*a_b_*"
                paragraph
                  text "n"

            """),
        ("[^a**b**]", """
            document
              paragraph
                text "[^a"
                strong
                  text "b"
                text "]"

            """),
        ("[^a**b**]\n\n[^a**b**]: n", """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a**b**"
                paragraph
                  text "n"

            """),
        ("[^a*b*c*d*]", """
            document
              paragraph
                text "[^a"
                emph
                  text "b"
                text "c"
                emph
                  text "d"
                text "]"

            """),
        ("[^a*b*c*d*]\n\n[^a*b*c*d*]: n", """
            document
              paragraph
                footnote_reference "1"
              footnote_definition "a*b*c*d*"
                paragraph
                  text "n"

            """),
        ("> [^a*b*]\n\n[^a*b*]: n", """
            document
              block_quote
                paragraph
                  footnote_reference "1"
              footnote_definition "a*b*"
                paragraph
                  text "n"

            """),
        ("- [^a*b*]\n\n[^a*b*]: n", """
            document
              list bullet '-' tight
                item
                  paragraph
                    footnote_reference "1"
              footnote_definition "a*b*"
                paragraph
                  text "n"

            """),
    ])
    func emphasisInLabel(_ source: String, _ tree: String) {
        #expect(TreeDump.dump(source, options: [.footnotes]) == tree)
    }
}
