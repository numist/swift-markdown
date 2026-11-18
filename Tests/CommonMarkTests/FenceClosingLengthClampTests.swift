/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

@Suite("Code fence closing length clamp")
struct FenceClosingLengthClampTests {

    private func limits(_ clamp: Int) -> MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.fenceLengthClampForClosing = clamp
        return limits
    }

    private func source(_ character: String, opening: Int, closing: Int) -> String {
        String(repeating: character, count: opening) + "\nx\n" + String(repeating: character, count: closing) + "\ny\n"
    }

    @Test("a closing fence as long as the clamp closes a longer opening fence", arguments: ["`", "~"])
    func closingAtClamp(_ character: String) {
        #expect(TreeDump.dump(source(character, opening: 6, closing: 4), options: [], limits: limits(4)) == """
            document
              code_block "" "x\\n"
              paragraph
                text "y"

            """)
    }

    @Test("a closing fence shorter than the clamp leaves a longer opening fence open", arguments: ["`", "~"])
    func closingBelowClamp(_ character: String) {
        let closing = String(repeating: character, count: 3)
        #expect(TreeDump.dump(source(character, opening: 6, closing: 3), options: [], limits: limits(4)) == """
            document
              code_block "" "x\\n\(closing)\\ny\\n"

            """)
    }

    @Test("a clamp one past the closing fence's length leaves the block open", arguments: ["`", "~"])
    func clampPastClosing(_ character: String) {
        let closing = String(repeating: character, count: 4)
        #expect(TreeDump.dump(source(character, opening: 6, closing: 4), options: [], limits: limits(5)) == """
            document
              code_block "" "x\\n\(closing)\\ny\\n"

            """)
    }

    @Test("an opening fence no longer than the clamp needs a closing fence as long as itself")
    func openingWithinClamp() {
        #expect(TreeDump.dump(source("`", opening: 4, closing: 3), options: [], limits: limits(5)) == """
            document
              code_block "" "x\\n```\\ny\\n"

            """)
        #expect(TreeDump.dump(source("`", opening: 4, closing: 4), options: [], limits: limits(5)) == """
            document
              code_block "" "x\\n"
              paragraph
                text "y"

            """)
    }

    @Test("the opening fence's recorded length is its full length")
    func recordedLength() {
        let kind = MarkdownDocument.withParsedDocument(source("`", opening: 6, closing: 4), limits: limits(4)) { document -> String? in
            guard let first = document.root.firstChild else { return nil }
            return TreeDump.describe(first.kind)
        }
        #expect(kind == "code_block fenced fence='`' length=6 offset=0")
    }

    @Test("the clamp applies to a fence inside a container")
    func insideBlockQuote() {
        #expect(TreeDump.dump("> ``````\n> x\n> ````\n> y\n", options: [], limits: limits(4)) == """
            document
              block_quote
                code_block "" "x\\n"
                paragraph
                  text "y"

            """)
        #expect(TreeDump.dump("> ``````\n> x\n> ```\n> y\n", options: [], limits: limits(4)) == """
            document
              block_quote
                code_block "" "x\\n```\\ny\\n"

            """)
    }

    @Test("a clamp below 3 behaves as 3", arguments: [2, 0, -1, Int.min])
    func clampBelowThree(_ clamp: Int) {
        #expect(TreeDump.dump(source("`", opening: 6, closing: 2), options: [], limits: limits(clamp)) == """
            document
              code_block "" "x\\n``\\ny\\n"

            """)
        #expect(TreeDump.dump(source("`", opening: 6, closing: 3), options: [], limits: limits(clamp)) == """
            document
              code_block "" "x\\n"
              paragraph
                text "y"

            """)
    }

    @Test("the default limits leave a longer opening fence open after a shorter closing fence")
    func defaultLimits() {
        #expect(TreeDump.dump(source("`", opening: 6, closing: 4), options: []) == """
            document
              code_block "" "x\\n````\\ny\\n"

            """)
    }
}
