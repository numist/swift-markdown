/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import CommonMark
import Testing

/// Footnote-shaped brackets nested inside one another with no footnote label limit.
///
/// A footnote definition's label holds no unescaped bracket, as a link label doesn't (Links), so a bracket holding
/// another bracket references no footnote however long its label, and 16,000 nested brackets, about 64 KB of source,
/// parse within the time limit.
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

    @Test(.timeLimit(.minutes(1)))
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
