/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

// A footnote label, like a link label, holds no unescaped bracket (Links), so a bracket holding another bracket
// references no footnote.
@Suite("Nested footnote brackets with unlimited labels")
struct UnlimitedFootnoteLabelNestingTests {
    private static let unlimited: MarkdownDocument.ParseLimits = {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxFootnoteLabelCharacters = .max
        limits.maxFootnoteLabelBytes = .max
        return limits
    }()

    private static let depth = 16_000
    private static let openers = String(repeating: "[^b ", count: depth)
    private static let closers = String(repeating: "]", count: depth)

    @Test
    func referenceInsideBracketsResolves() {
        #expect(TreeDump.dump("[[^a]]\n\n[^a]: x", options: .footnotes, limits: Self.unlimited) == """
            document
              paragraph
                text "["
                footnote_reference "1"
                text "]"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }

    @Test
    func bracketHoldingBracketIsText() {
        #expect(TreeDump.dump("[^a [b]]\n\n[^a]: x", options: .footnotes, limits: Self.unlimited) == """
            document
              paragraph
                text "[^a [b]]"

            """)
    }

    @Test
    func deeplyNestedBracketsResolveOnlyTheInnermost() {
        #expect(TreeDump.dump(Self.openers + "[^a]" + Self.closers + "\n\n[^a]: x", options: .footnotes, limits: Self.unlimited) == """
            document
              paragraph
                text "\(Self.openers)"
                footnote_reference "1"
                text "\(Self.closers)"
              footnote_definition "a"
                paragraph
                  text "x"

            """)
    }
}
