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
    private func surface(_ bytes: [UInt8]) -> String {
        let (markdown, options) = FuzzRegressionTests.splitInput(bytes)!
        return Document(parsing: markdown, options: options.union(.cmarkBugCompatibility)).debugDescription(options: [])
    }

    func testNULBeforePI() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4]))
    }

    func testTrailingNULAfterRetryLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x] \u{fffd}\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 0, 4]))
    }

    func testNULBeforeDeclaration() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <!X\n\u{fffd}\n            └─ Text \" [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 4]))
    }

    func testLinkTitleMaterialized() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"[a](/u \"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \")\"", surface([45, 32, 62, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 4]))
    }

    func testNULLaterOnOrphanLine() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x] b\u{fffd}c\"", surface([45, 32, 62, 97, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 0, 99, 10, 4]))
    }

    func testMultiByteScalarOrphanInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 50, 195, 169, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testCDATACloserCountsOrphanInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <![CDATA[\n\u{fffd} [\n            └─ Text \"x]\"", surface([45, 32, 62, 97, 0, 60, 33, 91, 67, 68, 65, 84, 65, 91, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testDeclarationCloserIsFirstOfTwoOrphansInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <!X\n\u{fffd}\n            └─ Text \"\u{fffd} [x]\"", surface([45, 32, 62, 97, 0, 60, 33, 88, 10, 32, 32, 50, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testReferenceDefinitionTitleStopsAtOrphan() {
        XCTAssertEqual("Document\n├─ UnorderedList\n│  └─ ListItem checkbox: [x]\n│     └─ BlockQuote\n│        └─ Paragraph\n│           ├─ Text \"[a]: /u \"\"\n│           ├─ SoftBreak\n│           └─ Text \"\u{fffd} [x] \"\"\n└─ Paragraph\n   └─ Text \"[a]\"", surface([45, 32, 62, 91, 97, 93, 58, 32, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 10, 10, 91, 97, 93, 10, 4]))
    }

    func testInlineLinkTitleStopsAtOrphanInFlattenedContent() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"x\u{fffd}[a](/u \"\"\n            ├─ SoftBreak\n            └─ Text \"\u{fffd} [x] \")\"", surface([45, 32, 62, 120, 0, 91, 97, 93, 40, 47, 117, 32, 34, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 34, 41, 10, 4]))
    }

    func testSetextHeadingReseedKeepsOrphan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Heading level: 1\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 61, 61, 61, 10, 4]))
    }

    func testTablePrecedingLinesStayParagraph() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\u{fffd}\"\n            ├─ InlineHTML <?\n\u{fffd} \n            ├─ Text \"[x]\"\n            ├─ SoftBreak\n            ├─ Text \"b|c\"\n            ├─ SoftBreak\n            └─ Text \"-|-\"", surface([45, 32, 62, 97, 0, 60, 63, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 32, 32, 62, 98, 124, 99, 10, 32, 32, 62, 45, 124, 45, 10, 4]))
    }

    func testNULInsidePIBodyIsNotAnOrphan() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ Paragraph\n            ├─ Text \"a\"\n            ├─ InlineHTML <?b\u{fffd}c\n\u{fffd} \n            └─ Text \"[x]\"", surface([45, 32, 62, 97, 60, 63, 98, 0, 99, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 10, 4]))
    }

    func testFuzzedArtifact() {
        XCTAssertEqual("Document\n└─ UnorderedList\n   └─ ListItem checkbox: [x]\n      └─ BlockQuote\n         └─ BlockQuote\n            └─ Paragraph\n               ├─ Text \"\u{fffd}\u{7}=\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [x] b\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [a]:\"\n               ├─ SoftBreak\n               ├─ Text \"/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{7}=\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd} [x] b\u{fffd}/u\"\n               ├─ SoftBreak\n               ├─ Text \"\u{fffd}\u{fffd}\u{9}\"\n               ├─ InlineHTML <?p;;\u{fffd} \u{c}\u{fffd}\u{fffd}\u{fffd};\n?\u{fffd}\u{fffd}\u{fffd}ha\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}qqqqqqqqqqqqqqq\u{4};\n?\u{fffd} \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{4}\u{fffd}qq\u{fffd}\u{fffd}\u{fffd};\n?\u{fffd}\u{fffd}\u{fffd}ha\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}\u{3}\u{fffd}gs\n</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}\u{3}\u{fffd}gs\n</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}ha\u{4}\u{4}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}\u{fffd}\u{fffd}q\u{4};\n?\u{fffd}\u{3}\u{fffd}gs\n</TextAre<pre t   echqqqqqq \u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{1}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{5}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{fffd}\u{4};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}q\u{4}\u{9}\u{fffd}t \u{9}\u{fffd}\u{fffd}\u{9}\u{3}\u{fffd}gs\n\u{4}\u{fffd}\u{fffd}\u{fffd};\n?\u{fffd}  ech;\n?\u{fffd}\u{fffd}\u{fffd}\u{fffd}!\u{fffd}\u{4}\u{fffd}\u{fffd}\u{4}\u{4}\u{4};\n?\u{fffd}qqqqqqq\u{fffd}\u{fffd}\u{fffd}\u{fffd}<qq  > \u{fffd}\u{7}=\n2\u{fffd} [\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}\u{5}x] b\n\u{fffd}\u{fffd} [a]:\n/u\n\u{fffd}\u{7}=\n\u{fffd} \n               └─ Text \"[x] b\u{fffd}\"", surface([45, 32, 62, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 10, 0, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 47, 117, 10, 32, 9, 174, 250, 9, 60, 63, 112, 59, 59, 255, 32, 12, 128, 0, 0, 59, 10, 63, 255, 255, 255, 104, 97, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 113, 4, 59, 10, 63, 255, 32, 255, 255, 255, 133, 255, 4, 255, 113, 113, 128, 0, 0, 59, 10, 63, 255, 253, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 255, 104, 97, 4, 4, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 255, 255, 113, 4, 59, 10, 63, 255, 3, 192, 103, 115, 10, 60, 47, 84, 101, 120, 116, 65, 114, 101, 60, 112, 114, 101, 32, 116, 32, 32, 32, 101, 99, 104, 113, 113, 113, 113, 113, 113, 32, 255, 255, 255, 133, 255, 255, 255, 255, 255, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 0, 0, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 4, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 113, 4, 9, 174, 116, 32, 9, 174, 250, 9, 3, 192, 103, 115, 10, 4, 0, 0, 0, 59, 10, 63, 255, 32, 32, 101, 99, 104, 59, 10, 63, 255, 255, 255, 255, 33, 255, 4, 255, 255, 4, 4, 4, 59, 10, 63, 255, 113, 113, 113, 113, 113, 113, 113, 0, 0, 0, 0, 60, 113, 113, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 120, 93, 32, 98, 10, 0, 219, 32, 91, 97, 93, 58, 10, 32, 32, 62, 32, 47, 117, 10, 32, 32, 62, 32, 128, 7, 61, 10, 32, 32, 50, 0, 32, 91, 120, 93, 32, 98, 255, 0]))
    }

}
