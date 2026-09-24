/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Markdown

final class SegmentedContentPerformanceTests: XCTestCase {
    /// A paragraph with many indented continuation lines (so its inline content is multi-segment, one segment per line plus a join per line ending) must parse in time that does not grow quadratically with its line count.
    func testManyIndentedContinuationLines() throws {
        let repetitions = 8000
        let source = "x\n" + String(repeating: "word\n word", count: repetitions)

        let clock = ContinuousClock()
        var document: Document!
        let elapsed = clock.measure {
            document = Document(parsing: source)
        }

        // Fixture sanity: a single paragraph whose `repetitions + 1` line endings are all soft breaks, separating plain text.
        XCTAssertEqual(document.childCount, 1)
        let paragraph = try XCTUnwrap(document.child(at: 0) as? Paragraph)
        XCTAssertEqual(paragraph.children.filter { $0 is SoftBreak }.count, repetitions + 1)
        XCTAssertTrue(paragraph.children.allSatisfy { $0 is SoftBreak || $0 is Text })

        // Generous bound for a loaded machine and a debug build; the quadratic walk took about 45 seconds here.
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    /// A setext heading with many non-contiguous lines (inside a block quote, so its content is flattened into the arena with an arena→source run per line) must parse in time that does not grow quadratically with its line count.
    func testManyLineSetextHeadingInBlockQuote() throws {
        let lines = 16000
        let source = "> x\n" + String(repeating: ">  word\n", count: lines) + "> ===\n"

        let clock = ContinuousClock()
        var document: Document!
        let elapsed = clock.measure {
            document = Document(parsing: source)
        }

        // Fixture sanity: a block quote holding a single level-1 heading whose `lines` line endings are all soft breaks, separating plain text.
        XCTAssertEqual(document.childCount, 1)
        let blockQuote = try XCTUnwrap(document.child(at: 0) as? BlockQuote)
        XCTAssertEqual(blockQuote.childCount, 1)
        let heading = try XCTUnwrap(blockQuote.child(at: 0) as? Heading)
        XCTAssertEqual(heading.level, 1)
        XCTAssertEqual(heading.children.filter { $0 is SoftBreak }.count, lines)
        XCTAssertTrue(heading.children.allSatisfy { $0 is SoftBreak || $0 is Text })

        // Generous bound for a loaded machine and a debug build; the quadratic walk took about 45 seconds here.
        XCTAssertLessThan(elapsed, .seconds(5))
    }
}
