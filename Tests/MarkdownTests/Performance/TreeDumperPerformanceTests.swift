/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import XCTest
import Markdown

final class TreeDumperPerformanceTests: XCTestCase {
    /// Dumping a paragraph with many sibling inlines must take time that does not grow quadratically with their count.
    func testDumpParagraphWithManySiblingInlines() throws {
        let lines = 5_000
        let document = Document(parsing: String(repeating: "x\n", count: lines))

        // Fixture sanity: one paragraph holding `lines` texts separated by `lines - 1` soft breaks.
        XCTAssertEqual(document.childCount, 1)
        let paragraph = try XCTUnwrap(document.child(at: 0) as? Paragraph)
        XCTAssertEqual(paragraph.childCount, 2 * lines - 1)
        XCTAssertEqual(paragraph.children.filter { $0 is SoftBreak }.count, lines - 1)

        let clock = ContinuousClock()
        var dump = ""
        let elapsed = clock.measure {
            dump = document.debugDescription()
        }

        XCTAssertEqual(dump.split(separator: "\n").count, 2 + 2 * lines - 1)

        // Generous for a loaded machine and a debug build, and far below the 45 seconds that copying every sibling once per dumped node takes.
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    /// Dumping a document with many top-level blocks must take time that does not grow quadratically with their count, including the indentation drawn for each block's descendants.
    func testDumpDocumentWithManyTopLevelBlocks() throws {
        let paragraphs = 5_000
        let document = Document(parsing: String(repeating: "x\n\n", count: paragraphs))

        // Fixture sanity: `paragraphs` top-level paragraphs, each holding a single text.
        XCTAssertEqual(document.childCount, paragraphs)
        XCTAssertTrue(document.children.allSatisfy { $0 is Paragraph && $0.childCount == 1 && $0.child(at: 0) is Text })

        let clock = ContinuousClock()
        var dump = ""
        let elapsed = clock.measure {
            dump = document.debugDescription()
        }

        XCTAssertEqual(dump.split(separator: "\n").count, 1 + 2 * paragraphs)

        // Generous for a loaded machine and a debug build, and far below the 20 seconds that copying every sibling once per dumped node and once per ancestor takes.
        XCTAssertLessThan(elapsed, .seconds(5))
    }
}
