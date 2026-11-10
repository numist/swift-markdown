/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// A `~` closer and a `~` opener of different lengths form no strikethrough and stay text, so emphasis whose
/// delimiters lie on either side of the tilde closer still forms.
@Suite("Emphasis across a strikethrough length mismatch")
struct StrikethroughLengthMismatchEmphasisTests {

    @Test("emphasis spanning a tilde closer of another length forms", arguments: [
        ("~~a *b c~ d*", """
            document
              paragraph
                text "~~a "
                emph
                  text "b c~ d"

            """),
        ("~~a _b c~ d_", """
            document
              paragraph
                text "~~a "
                emph
                  text "b c~ d"

            """),
        ("~~a **b c~ d**", """
            document
              paragraph
                text "~~a "
                strong
                  text "b c~ d"

            """),
    ])
    func emphasisAcrossMismatch(markdown: String, tree: String) {
        #expect(TreeDump.dump(markdown, options: .strikethrough) == tree)
    }
}
