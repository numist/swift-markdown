/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Source ranges for the two raw-scan inlines (code spans, inline HTML) whose token crosses a newline.
///
/// The old C path set `CMARK_OPT_SOURCEPOS` only when `disableSourcePosOpts` was unset, and with it
/// off cmark flattened these two constructs' END onto their start line (`(startLine, startColumn +
/// tokenByteLength)`), ignoring the interior break. That flat end is the `.cmarkBugCompatibility`
/// quirk, reproduced ONLY for the differential and only when `.disableSourcePosOpts` is also set
/// (covered by the `rawinline-*` fuzzer regression pairs, which parse flag-on). This suite is the
/// deliverable-side guardrail: it parses with `.disableSourcePosOpts` but WITHOUT
/// `.cmarkBugCompatibility`, proving the shipped parser tracks the precise end regardless of
/// `.disableSourcePosOpts` - the flat behavior is quarantined to the differential.
class FlatRawInlineEndTests: XCTestCase {
    /// A two-line code span ends at its closing backtick's physical position (byte-projected @2:3),
    /// not at cmark's sourcepos-off flat @1:6. `.disableSourcePosOpts` alone does not flatten it.
    func testMultilineCodeSpanEndsOnPhysicalLine() {
        let text = "`a\nb`"

        let expectedDump = """
        Document @1:1-2:3
        └─ Paragraph @1:1-2:3
           └─ InlineCode @1:1-2:3 `a b`
        """

        let document = Document(parsing: text, options: [.disableSourcePosOpts])
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A two-line inline HTML span keeps its precise half-open end (byte-projected @2:5, one past the
    /// closing `>` on line 2), not cmark's sourcepos-off flat @1:10.
    func testMultilineInlineHTMLEndsOnPhysicalLine() {
        let text = "<foo\nbar>"

        let expectedDump = """
        Document @1:1-2:5
        └─ Paragraph @1:1-2:5
           └─ InlineHTML @1:1-2:5 <foo
        bar>
        """

        let document = Document(parsing: text, options: [.disableSourcePosOpts])
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Control: the shipped default (no options) is likewise precise, so `.disableSourcePosOpts` is
    /// shown to change nothing about the deliverable's raw-inline ends.
    func testMultilineCodeSpanUnchangedByDefault() {
        let text = "`a\nb`"

        let expectedDump = """
        Document @1:1-2:3
        └─ Paragraph @1:1-2:3
           └─ InlineCode @1:1-2:3 `a b`
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
