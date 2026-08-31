/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Emphasis (and its inner text) parsed from a container-item paragraph whose content was
/// materialized by tab expansion.
///
/// A tab after a container marker (`*\t`, `>\t`, `- \t`) makes the parser materialize a
/// tab-expanded per-line buffer, so the item's paragraph content is not read straight from the
/// source span. The surviving content must still resolve to its literal source bytes with its
/// inlines carrying source positions, exactly like the space-indented (`- *5*`) and plain-text
/// (`*\tfoo`) forms already do. This holds whether the content maps to a same-width source range
/// (`*5*`, where `expandPrefixTabs` expanded only the consumed indentation) or straddles an
/// expanded tab (`**\tx`, where doubled marker bytes are inline content, not a block marker, so
/// the tab is never consumed as indentation and lands inside the paragraph). cmark expands tabs
/// only for block-structure indentation and preserves them in inline content, so the literal tab
/// survives. Columns are byte-projected (a tab counts as one byte) in the shipped, flag-off parser.
class MaterializedEmphasisSourcePositionTests: XCTestCase {
    /// A bullet marker followed by a tab: the emphasis and its text keep their source positions.
    func testBulletTabEmphasis() {
        let text = "*\t*5*"

        let expectedDump = """
        Document @1:1-1:6
        └─ UnorderedList @1:1-1:6
           └─ ListItem @1:1-1:6
              └─ Paragraph @1:3-1:6
                 └─ Emphasis @1:3-1:6
                    └─ Text @1:4-1:5 "5"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A block-quote marker followed by a tab: same, through the block-quote container path.
    func testBlockQuoteTabEmphasis() {
        let text = ">\t*5*"

        let expectedDump = """
        Document @1:1-1:6
        └─ BlockQuote @1:1-1:6
           └─ Paragraph @1:3-1:6
              └─ Emphasis @1:3-1:6
                 └─ Text @1:4-1:5 "5"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// A content tab that expands to exactly one space (`\t` at a 4-column boundary: `4 - (col & 3) == 1`).
    ///
    /// This is the boundary of the contiguity rule: the tab's expansion preserves the buffer width, so
    /// the content maps to a same-width source range, yet the materialized buffer byte (a space) differs
    /// from the source byte (the tab). Mapping to the source range is what keeps the tab literal - cmark
    /// expands tabs only for block-structure indentation and preserves them in inline content - so the
    /// text and its byte-projected range (`@1:1-1:6`, the tab counting as one byte) match the reference.
    func testContentTabExpandingToOneSpace() {
        let text = "***\tx"

        let expectedDump = """
        Document @1:1-1:6
        └─ Paragraph @1:1-1:6
           └─ Text @1:1-1:6 "***\tx"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Doubled marker bytes then a tab (`**\tx`), all inline content: `**` is not a block marker, so
    /// nothing consumes the tab as indentation and the expanded tab lands inside the paragraph content.
    ///
    /// The materialized buffer widened the tab to spaces (source width < buffer width), so the content
    /// does not map to a same-width source range. It must nonetheless resolve to the literal source
    /// bytes: cmark keeps the content tab literal and byte-projects columns, so the single text node is
    /// `**\tx` at `@1:1-1:5` (the tab counting as one byte).
    func testInteriorTabParagraph() {
        let text = "**\tx"

        let expectedDump = """
        Document @1:1-1:5
        └─ Paragraph @1:1-1:5
           └─ Text @1:1-1:5 "**\tx"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}
