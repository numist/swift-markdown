/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// The default parse limits, and parsing with limits set.
@Suite("Parse limits")
struct ParseLimitsTests {

    @Test("Default limits")
    func defaults() {
        let limits = MarkdownDocument.ParseLimits()
        #expect(limits.maxLinkLabelCharacters == 999)
        #expect(limits.maxLinkLabelBytes == Int.max)
        #expect(limits.maxFootnoteLabelCharacters == 999)
        #expect(limits.maxFootnoteLabelBytes == Int.max)
        #expect(limits.maxDecimalCharacterReferenceDigits == 7)
        #expect(limits.maxHexadecimalCharacterReferenceDigits == 6)
        #expect(limits.maxLinkDestinationParenthesisNesting == Int.max)
        #expect(limits.maxAttributeParenthesisNesting == Int.max)
        #expect(limits.maxCodeSpanOpeningBackticks == Int.max)
        #expect(limits.maxContainersOpenedOnLineBeforeListMarker == Int.max)
        #expect(limits.fenceLengthClampForClosing == Int.max)
        #expect(limits.strikethroughTildeRunChunk == Int.max)
        #expect(limits.referenceExpansionBudget == Int.max)
        #expect(limits.maxTableRowCells == Int.max)
        #expect(limits.maxTableAutocompletedCells == Int.max)
    }

    static let source = "# Title\n\nA paragraph with *emphasis* and ````a````."

    static let expected = """
        document
          heading 1
            text "Title"
          paragraph
            text "A paragraph with "
            emph
              text "emphasis"
            text " and ````a````."

        """

    static var nonDefaultLimits: MarkdownDocument.ParseLimits {
        var limits = MarkdownDocument.ParseLimits()
        limits.maxLinkLabelCharacters = 10
        limits.maxLinkLabelBytes = 10
        limits.maxFootnoteLabelCharacters = 10
        limits.maxFootnoteLabelBytes = 10
        limits.maxDecimalCharacterReferenceDigits = 3
        limits.maxHexadecimalCharacterReferenceDigits = 3
        limits.maxLinkDestinationParenthesisNesting = 3
        limits.maxAttributeParenthesisNesting = 3
        limits.maxCodeSpanOpeningBackticks = 3
        limits.maxContainersOpenedOnLineBeforeListMarker = 3
        limits.fenceLengthClampForClosing = 3
        limits.strikethroughTildeRunChunk = 2
        limits.referenceExpansionBudget = 3
        limits.maxTableRowCells = 3
        limits.maxTableAutocompletedCells = 3
        return limits
    }

    @Test("Limits that differ from the defaults are unequal to them")
    func nonDefaultLimitsDiffer() {
        #expect(Self.nonDefaultLimits != MarkdownDocument.ParseLimits())
    }

    @Test("withParsedDocument parses with limits set")
    func withParsedDocumentParses() {
        #expect(TreeDump.dump(Self.source, options: [], limits: Self.nonDefaultLimits) == Self.expected)
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @Test("String and UTF8Span initializers parse with limits set")
    func initializersParse() {
        let source = Self.source
        let viaString = MarkdownDocument(parsing: source, limits: Self.nonDefaultLimits)
        #expect(TreeDump.dump(viaString.root, sourceRanges: false) == Self.expected)
        let viaSpan = MarkdownDocument(parsing: source.utf8Span, limits: Self.nonDefaultLimits)
        #expect(TreeDump.dump(viaSpan.root, sourceRanges: false) == Self.expected)
    }
}
