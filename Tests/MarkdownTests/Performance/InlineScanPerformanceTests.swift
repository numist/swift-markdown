/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Markdown

final class InlineScanPerformanceTests: XCTestCase {
    /// Many unclosed `<local@domain` email-autolink candidates in one paragraph whose continuation lines are indented (so its inline content is multi-segment) must parse in time that does not grow cubically with their count.
    func testUnclosedEmailAutolinkCandidatesInIndentedParagraph() throws {
        let repetitions = 400
        let source = "x\n" + String(repeating: "<MO@CBARuuu\n zR.B", count: repetitions)

        let clock = ContinuousClock()
        var document: Document!
        let elapsed = clock.measure {
            document = Document(parsing: source)
        }

        // Fixture sanity: a single paragraph whose `repetitions + 1` line endings are all soft breaks, with every `<` left literal.
        XCTAssertEqual(document.childCount, 1)
        let paragraph = try XCTUnwrap(document.child(at: 0) as? Paragraph)
        XCTAssertEqual(paragraph.children.filter { $0 is SoftBreak }.count, repetitions + 1)
        XCTAssertFalse(paragraph.children.contains { $0 is Link })

        // Generous bound for a loaded machine and a debug build; the cubic scan took about a minute here.
        XCTAssertLessThan(elapsed, .seconds(5))
    }
}
