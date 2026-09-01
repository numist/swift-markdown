/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@testable import Markdown
import XCTest

/// Emphasis-resolution nesting when a run of `**` delimiters flanks an unpairable interior `**`.
///
/// CommonMark §6.2 uses a delimiter's *original* run length for the rule-of-three modular
/// arithmetic and for the `openers_bottom` search-floor slot; the number of characters a partial
/// pairing consumes is tracked separately (on the inline text). For `****a**o****` the interior
/// `**` can both open and close, and `(4 + 2) % 3 == 0`, so it never pairs and it lowers the
/// search floor for the length-≡-2 slot. The outer `****`/`****` runs pair once (consuming two
/// delimiters a side, leaving two), and the leftover pair must nest as a second strong. That
/// second pairing succeeds only because the closer's *original* length 4 selects the length-≡-1
/// slot, which the interior `**` never poisoned — the consumed count must not feed the `% 3`
/// slot. All the interior bytes stay literal inside the inner strong.
class EmphasisNestingTests: XCTestCase {
    /// `****a**o****`: both outer runs are consumed by two nested strongs; the interior `**` is text.
    func testDoubleRunNestsAroundUnpairableInterior() {
        let text = "****a**o****"

        // Default (flag-off) stamping pulls the inner strong's range in past the outer strong's two
        // consumed delimiters a side, so the inner span is @1:3-1:11 while the outer covers the run.
        let expectedDump = """
        Document @1:1-1:13
        └─ Paragraph @1:1-1:13
           └─ Strong @1:1-1:13
              └─ Strong @1:3-1:11
                 └─ Text @1:5-1:9 "a**o"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Guard: `****a**o**` — the closing run is only `**`, so no leftover pair survives to nest; the
    /// opening `****` stays literal text and a single strong wraps `o`. Unchanged by the fix.
    func testShortCloserLeavesOpenerLiteral() {
        let text = "****a**o**"

        let expectedDump = """
        Document @1:1-1:11
        └─ Paragraph @1:1-1:11
           ├─ Text @1:1-1:6 "****a"
           └─ Strong @1:6-1:11
              └─ Text @1:8-1:9 "o"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// Guard: `****o****` — no interior delimiter poisons any slot, so both `****` runs nest as two
    /// strongs regardless of the fix. Confirms the fix does not disturb the no-interior case.
    func testDoubleRunWithoutInteriorNests() {
        let text = "****o****"

        // As with the target, flag-off stamping pulls the inner strong in (@1:3-1:8) past the outer
        // run's consumed delimiters; the structure (two nested strongs, no interior text) is unchanged.
        let expectedDump = """
        Document @1:1-1:10
        └─ Paragraph @1:1-1:10
           └─ Strong @1:1-1:10
              └─ Strong @1:3-1:8
                 └─ Text @1:5-1:6 "o"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }

    /// `****a**foo******`: the interior `**` pairs with the `******` closer (admitted because the
    /// closer length is a multiple of three), wrapping `foo` in the innermost strong; the leftover
    /// `****`/`****` then nest as two more strongs. Three levels deep, all runs consumed.
    func testInteriorPairsWithMultipleOfThreeCloser() {
        let text = "****a**foo******"

        // Flag-off stamping pulls each inner strong in past the consumed delimiters of the strongs
        // that wrap it, so the spans tighten from @1:1-1:17 outward to @1:6-1:13 innermost.
        let expectedDump = """
        Document @1:1-1:17
        └─ Paragraph @1:1-1:17
           └─ Strong @1:1-1:17
              └─ Strong @1:3-1:15
                 ├─ Text @1:5-1:6 "a"
                 └─ Strong @1:6-1:13
                    └─ Text @1:8-1:11 "foo"
        """

        let document = Document(parsing: text)
        XCTAssertEqual(expectedDump, document.debugDescription(options: .printSourceLocations))
    }
}

