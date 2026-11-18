/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// A pair of smart quotes, or of `~` runs of unequal length, forms no node, so the delimiters between them stay on the
// delimiter stack for later closers (Emphasis and strong emphasis, Strikethrough (extension)).
@Suite("Delimiters between quote pairs and unequal tilde pairs")
struct DelimitersBetweenQuoteAndTildePairsTests {
    @Test func tildeCloserPairsPastUnequalPair() {
        #expect(TreeDump.dump("~a ~~b c~ d~\n", options: .strikethrough) == """
            document
              paragraph
                strikethrough
                  text "a ~~b c~ d"

            """)
    }

    @Test func emphasisSpansUnequalTildePair() {
        #expect(TreeDump.dump("~~a *b c~ d*\n", options: .strikethrough) == """
            document
              paragraph
                text "~~a "
                emph
                  text "b c~ d"

            """)
    }

    @Test func emphasisSpansQuotePair() {
        #expect(TreeDump.dump("\"a *b\" c*\n", options: .smart) == """
            document
              paragraph
                text "“a "
                emph
                  text "b” c"

            """)
    }

    @Test
    func manyUnequalTildePairsAroundEmphasisOpeners() {
        let source = String(repeating: "~~a ", count: 100) + String(repeating: "*a ", count: 100)
            + String(repeating: "a~ ", count: 100) + "\n"
        let text = String(repeating: "~~a ", count: 100) + String(repeating: "*a ", count: 100)
            + String(repeating: "a~ ", count: 99) + "a~"
        #expect(TreeDump.dump(source, options: .strikethrough) == """
            document
              paragraph
                text "\(text)"

            """)
    }

    @Test
    func manyQuotePairsAroundEmphasisOpeners() {
        let source = String(repeating: "\"a ", count: 100) + String(repeating: "*a ", count: 100)
            + String(repeating: "a\" ", count: 100) + "\n"
        let text = String(repeating: "“a ", count: 100) + String(repeating: "*a ", count: 100)
            + String(repeating: "a” ", count: 99) + "a”"
        #expect(TreeDump.dump(source, options: .smart) == """
            document
              paragraph
                text "\(text)"

            """)
    }
}
