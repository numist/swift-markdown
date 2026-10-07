/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) @_spi(InlineOnly) @testable import Markdown
import XCTest

/// A tasklist-retry orphan byte inside paragraph content that is later flattened or materialized into one
/// arena buffer (a NUL elsewhere in the paragraph, or a `[`-led paragraph) still stops cmark's
/// UTF-8-validating scans, exactly as it does in segmented content. Expected surfaces are the cmark-gfm
/// reference's output bytes; inputs are `[markdown …][option byte]`, split as the fuzzer does.
class TaskListRetryOrphanInFlattenedContentTests: XCTestCase {
    private func surface(_ bytes: [UInt8], cmarkBugCompatible: Bool = true) -> String {
        let (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: markdown, options: cmarkBugCompatible ? options.union(.cmarkBugCompatibility) : options).debugDescription(options: [])
    }

    func testNULBeforePI() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testNULBeforeUnclosedProcessingInstructionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4], cmarkBugCompatible: false))
    }

    func testTrailingNULAfterRetryLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x] \u{fffd}\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 0, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testTrailingNULAfterLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] \u{fffd}\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 0, 4], cmarkBugCompatible: false))
    }

    func testNULBeforeDeclaration() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <!X\n\u{fffd}\n            └─ Text \" [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<!X`
    /// with no `>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry orphans
    /// a UTF-8 continuation byte that closes it as raw HTML.
    func testNULBeforeUnclosedDeclarationFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<!X\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4], cmarkBugCompatible: false))
    }

    func testLinkTitleMaterialized() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"[a](/u \"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \")\"", surface([45, 32, 62, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the link
    /// title runs across the line ending, so `[a](/u "…")` is a link (CommonMark links), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that stops its title scan.
    func testLinkTitleSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface([45, 32, 62, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 4], cmarkBugCompatible: false))
    }

    func testNULLaterOnOrphanLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x] b\u{fffd}c\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 0, 99, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testNULLaterOnLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x] b\u{fffd}c\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 0, 99, 10, 4], cmarkBugCompatible: false))
    }

    func testMultiByteScalarOrphanInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testUnclosedProcessingInstructionBeforeMultiByteLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"22\u{E9} [x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 10, 4], cmarkBugCompatible: false))
    }

    func testCDATACloserCountsOrphanInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <![CDATA[\n\u{fffd} [\n            └─ Text \"x]\"", surface([45, 32, 62, 97, 0, 60, 33, 91, 67, 68, 65, 84, 65, 91, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the CDATA
    /// opener with no `]]>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox
    /// retry orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testNULBeforeUnclosedCDATAFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<![CDATA[\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 91, 67, 68, 65, 84, 65, 91, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4], cmarkBugCompatible: false))
    }

    func testDeclarationCloserIsFirstOfTwoOrphansInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <!X\n\u{fffd}\n            └─ Text \"\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<!X`
    /// with no `>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry orphans
    /// a UTF-8 continuation byte that closes it as raw HTML.
    func testNULBeforeUnclosedDeclarationAfterTwoDigitsFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}<!X\"\n            ├─ SoftBreak\n            └─ Text \"22\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 50, 0, 32, 91, 120, 93, 32, 10, 4], cmarkBugCompatible: false))
    }

    func testReferenceDefinitionTitleStopsAtOrphan() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem checkbox: [x]\n│     └─ BlockQuote\n│        └─ Paragraph\n│           ├─ Text \"[a]: /u \"\"\n│           ├─ SoftBreak\n│           └─ Text \"\u{fffd} [x] \"\"\n└─ Paragraph\n   └─ Text \"[a]\"", surface([45, 32, 62, 91, 97, 93, 58, 32, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 10, 10, 91, 97, 93, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the link
    /// reference definition's title runs across the line ending, so the quote's paragraph is a definition
    /// that `[a]` resolves (CommonMark link reference definitions), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that stops its title scan.
    func testReferenceDefinitionTitleSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem\n│     └─ BlockQuote\n└─ Paragraph\n   └─ Link destination: \"/u\"\n      └─ Text \"a\"", surface([45, 32, 62, 91, 97, 93, 58, 32, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 10, 10, 91, 97, 93, 10, 4], cmarkBugCompatible: false))
    }

    func testInlineLinkTitleStopsAtOrphanInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\u{fffd}[a](/u \"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \")\"", surface([45, 32, 62, 120, 0, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the link
    /// title runs across the line ending, so `[a](/u "…")` is a link (CommonMark links), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that stops its title scan.
    func testNULBeforeLinkTitleSpanningLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\u{fffd}\"\n            └─ Link destination: \"/u\"\n               └─ Text \"a\"", surface([45, 32, 62, 120, 0, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 10, 4], cmarkBugCompatible: false))
    }

    func testSetextHeadingReseedKeepsOrphan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Heading level: 1\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 61, 61, 61, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `===`
    /// underline turns both paragraph lines, the unclosed `<?` as text, into a heading (CommonMark setext
    /// headings), where cmark's later-line checkbox retry orphans a UTF-8 continuation byte that closes the
    /// `<?` as raw HTML.
    func testSetextHeadingOverLazyLineFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Heading level: 1\n            ├─ Text \"a\u{fffd}<?\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 61, 61, 61, 10, 4], cmarkBugCompatible: false))
    }

    func testTablePrecedingLinesStayParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            ├─ Text \"[x]\"\n            ├─ SoftBreak\n            ├─ Text \"b|c\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 98, 124, 99, 10, 32, 32, 62, 45, 124, 45, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the
    /// unclosed `<?` stays text in the paragraph above the table (CommonMark raw HTML), where cmark's
    /// later-line checkbox retry orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testTablePrecedingLinesStayParagraphFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         ├─ Paragraph\n         │  ├─ Text \"a\u{fffd}<?\"\n         │  ├─ SoftBreak\n         │  └─ Text \"2\u{fffd} [x]\"\n         └─ Table alignments: |-|-|\n            ├─ Head\n            │  ├─ Cell\n            │  │  └─ Text \"b\"\n            │  └─ Cell\n            │     └─ Text \"c\"\n            └─ Body", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 98, 124, 99, 10, 32, 32, 62, 45, 124, 45, 10, 4], cmarkBugCompatible: false))
    }

    func testNULInsidePIBodyIsNotAnOrphan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ InlineHTML <?b\u{fffd}c\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 60, 63, 98, 0, 99, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and the `<?`
    /// with no `?>` closer stays text (CommonMark raw HTML), where cmark's later-line checkbox retry
    /// orphans a UTF-8 continuation byte that closes it as raw HTML.
    func testNULInsideUnclosedProcessingInstructionFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a<?b\u{fffd}c\"\n            ├─ SoftBreak\n            └─ Text \"2\u{fffd} [x]\"", surface([45, 32, 62, 97, 60, 63, 98, 0, 99, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4], cmarkBugCompatible: false))
    }

    func testFuzzedArtifact() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ BlockQuote\n            └─ Paragraph\n               ├─ Text \"\u{fffd}\u{7}=\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [x] b\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [a]:\"\n               ├─ SoftBreak\n               ├─ Text \"/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{7}=\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [x] b\u{fffd}/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{fffd}\u{9}\"\n               ├─ InlineHTML <?p;;\u{fffd} \u{c}\u{fffd}\u{fffd}\u{fffd};\n?\u{fffd}\u{fffd}\u{fffd}ha\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}qqqqqqqqqqqqqqq\u{4};\n?\u{fffd} \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{4}\u{fffd}qq\u{fffd}\u{fffd}\u{fffd};\n?\u{fffd}\u{fffd}\u{fffd}ha\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}\u{3}\u{fffd}gs\n</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}\u{3}\u{fffd}gs\n</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}\u{3}\u{fffd}gs\n</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{1}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{5}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4}\u{9}\u{fffd}t \u{9}\u{fffd}\u{fffd}\u{9}\u{3}\u{fffd}gs\n\u{4}\u{fffd}\u{fffd}\u{fffd};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}qqqqqqq\u{fffd}\u{fffd}\u{fffd}\u{fffd}<qq  > \u{fffd}\u{7}=\n2\u{fffd} [\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}x] b\n\u{fffd}\u{fffd} [a]:\n/u\n\u{fffd}\u{7}=\n\u{fffd} \n               └─ Text \"[x] b\u{fffd}\"", surface([45, 32, 62, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 10, 0, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 47, 117, 10, 32, 9, 174, 250, 9, 60, 63, 112, 59, 59, 255, 32, 12, 128, 0, 0, 59, 10, 63, 255, 255, 255, 104, 97, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 4, 59, 10, 63, 255, 32, 255, 255, 255, 133, 255, 4, 255, 113, 113, 128, 0, 0, 59, 10, 63, 255, 253, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 9, 174, 116, 32, 9, 174, 250, 9, 3, 192, 103, 115, 10, 4, 0, 0, 0, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 113, 113, 113, 113, 113, 113, 113, 0, 0, 0, 0, 60, 113, 113, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 120, 93, 32, 98, 10, 0, 219, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 0]))
    }

    /// Flag-off (spec-correct): the item has no checkbox (its first block is a block quote) and every lazy
    /// line stays paragraph text with its digit prefix, where cmark's later-line checkbox retry checks the
    /// item and orphans UTF-8 continuation bytes that change its inline scans.
    func testNestedQuoteLazyLinesFlagOff() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem\n      └─ BlockQuote\n         └─ BlockQuote\n            └─ Paragraph\n               ├─ Text \"\u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               ├─ Text \"2\u{fffd} [x] b\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [a]:\"\n               ├─ SoftBreak\n               ├─ Text \"/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               ├─ Text \"2\u{fffd} [x] b\u{fffd}/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{fffd}\t<?p;;\u{fffd} \u{0C}\u{fffd}\u{fffd}\u{fffd};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}ha\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}qqqqqqqqqqqqqqq\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd} \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{04}\u{fffd}qq\u{fffd}\u{fffd}\u{fffd};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}ha\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{01}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{05}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}q\u{04}\t\u{fffd}t \t\u{fffd}\u{fffd}\t\u{03}\u{fffd}gs\"\n               ├─ SoftBreak\n               ├─ Text \"\u{04}\u{fffd}\u{fffd}\u{fffd};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}  ech;\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{04}\u{fffd}\u{fffd}\u{04}\u{04}\u{04};\"\n               ├─ SoftBreak\n               ├─ Text \"?\u{fffd}qqqqqqq\u{fffd}\u{fffd}\u{fffd}\u{fffd}\"\n               ├─ InlineHTML <qq  >\n               ├─ Text \" \u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               ├─ Text \"2\u{fffd} [\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}\u{05}x] b\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{fffd} [a]:\"\n               ├─ SoftBreak\n               ├─ Text \"/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{07}=\"\n               ├─ SoftBreak\n               └─ Text \"2\u{fffd} [x] b\u{fffd}\"", surface([45, 32, 62, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 10, 0, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 47, 117, 10, 32, 9, 174, 250, 9, 60, 63, 112, 59, 59, 255, 32, 12, 128, 0, 0, 59, 10, 63, 255, 255, 255, 104, 97, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 4, 59, 10, 63, 255, 32, 255, 255, 255, 133, 255, 4, 255, 113, 113, 128, 0, 0, 59, 10, 63, 255, 253, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 9, 174, 116, 32, 9, 174, 250, 9, 3, 192, 103, 115, 10, 4, 0, 0, 0, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 113, 113, 113, 113, 113, 113, 113, 0, 0, 0, 0, 60, 113, 113, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 120, 93, 32, 98, 10, 0, 219, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 0], cmarkBugCompatible: false))
    }

}
