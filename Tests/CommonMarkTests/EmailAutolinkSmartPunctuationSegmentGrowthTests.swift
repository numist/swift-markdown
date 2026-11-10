/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Testing
import CommonMark

/// Storage growth for many email addresses interleaved with smart punctuation: ellipses, dashes, single quotes, double
/// quotes paired around a word, and lone double quotes.
///
/// Each of these glyphs is stored apart from the text around it, so a paragraph of addresses separated by them is one
/// text run of many pieces. Splitting that run into email links must store content in proportion to the input, so
/// doubling the addresses doubles the segments and the materialized bytes, give or take a constant.
@Suite("Email autolinks among smart punctuation store linear content")
struct EmailAutolinkSmartPunctuationSegmentGrowthTests {

    private static let block: MarkdownDocument.ParseOptions = [.gfmAutolink, .smart]
    private static let inlineOnly: MarkdownDocument.ParseOptions = [.gfmAutolink, .smart, .inlineOnly]

    @Test("segments and materialized bytes grow linearly with the addresses", arguments: [
        ("a@b.c ...", block, 6001, 12001, 15001, 30001),
        ("a@b.c ...", inlineOnly, 6000, 12000, 15001, 30001),
        ("a@b.c --", block, 6001, 12001, 15001, 30001),
        ("a@b.c --", inlineOnly, 6000, 12000, 15001, 30001),
        ("a@b.c '", block, 6001, 12001, 15001, 30001),
        ("a@b.c '", inlineOnly, 6000, 12000, 15001, 30001),
        ("a@b.c \"x\" ", block, 16000, 32000, 21001, 42001),
        ("a@b.c \"x\" ", inlineOnly, 16002, 32002, 21001, 42001),
        ("a@b.c \"", block, 6001, 12001, 15001, 30001),
        ("a@b.c \"", inlineOnly, 6000, 12000, 15001, 30001),
    ])
    func linearSegments(
        _ unit: String,
        _ options: MarkdownDocument.ParseOptions,
        _ segmentsFor1000: Int,
        _ segmentsFor2000: Int,
        _ bytesFor1000: Int,
        _ bytesFor2000: Int
    ) {
        func storage(_ count: Int) -> (segments: Int, bytes: Int, links: Int) {
            MarkdownDocument.withParsedDocument(String(repeating: unit, count: count), options: options) { document in
                var links = 0
                document.root.children.forEach { paragraph in
                    paragraph.children.forEach { inline in
                        if case .link = inline.kind { links += 1 }
                    }
                }
                return (document._segmentCount, document._materializedStringSize, links)
            }
        }
        let thousand = storage(1000)
        let twoThousand = storage(2000)
        #expect(thousand.links == 1000)
        #expect(twoThousand.links == 2000)
        #expect(thousand.segments == segmentsFor1000)
        #expect(twoThousand.segments == segmentsFor2000)
        #expect(thousand.bytes == bytesFor1000)
        #expect(twoThousand.bytes == bytesFor2000)
    }
}
