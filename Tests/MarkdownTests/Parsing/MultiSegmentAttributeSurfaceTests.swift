/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2025 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

@_spi(CmarkBugCompatibility) import Markdown
import Testing

/// Never-crash coverage for the `^[…](attrs)` extended-attribute inline form scanned over
/// multi-segment content, exercised through the exact comparison surface the differential fuzzer
/// uses (`Document.debugDescription(options: .printSourceLocations)` with `.cmarkBugCompatibility`).
///
/// The attribute scanner used to build a single `Chunk` from *virtual* offsets; for content that
/// straddles a line join (a block-quote / list body where the `(attrs)` spans lines) that chunk
/// indexed the wrong buffer / ran past a source segment and trapped when the surface materialized
/// the attribute string. The fix defers such an unrepresentable attribute to the no-match path
/// (the `^[…]` stays literal text), so the surface is produced without crashing. The exact deferred
/// surface is the rewrite's (a cross-line attribute isn't reconstructed); this only pins no-crash.
@Suite("Multi-segment attribute surface (never-crash)")
struct MultiSegmentAttributeSurfaceTests {

    private static func surface(_ markdown: String) -> String {
        Document(parsing: markdown, options: [.cmarkBugCompatibility])
            .debugDescription(options: .printSourceLocations)
    }

    @Test(arguments: [
        "> ^[a](\n> b)",
        "> ^[hi](\n> x)",
        "- ^[a](\n  b)",
        ">^[a](b\n>c)",
    ])
    func crossLineAttributeSurfaceDoesNotCrash(_ markdown: String) {
        let rendered = Self.surface(markdown)
        #expect(!rendered.isEmpty)
        #expect(!rendered.contains("Attribute"))
    }
}
