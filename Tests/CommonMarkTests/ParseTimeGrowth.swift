/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2026 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import Foundation
import Testing
import CommonMark

/// Expects the parse time of `make(count)` to grow in proportion to its size: parsing a source four times as large
/// may take at most ten times as long, where a parse quadratic in the input takes sixteen times as long. Each parse
/// must hold `blocks` top-level blocks.
///
/// The test compares two sizes rather than bounding one parse, so it holds on a machine of any speed. It measures the
/// processor time of the parsing thread, which other work on the machine doesn't stretch, and keeps the fastest of
/// five parses of each size, alternating sizes, so a parse slowed by a core switch or a cold cache doesn't decide the
/// ratio. The parses run on a dedicated thread of the highest quality of service, which keeps them on the fastest
/// cores.
internal func expectLinearParseTime(
    count: Int,
    options: MarkdownDocument.ParseOptions,
    blocks: Int = 1,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ make: (Int) -> String
) {
    let small = make(count)
    let large = make(4 * count)
    let (smallBlocks, smallSeconds, largeBlocks, largeSeconds) = onThread(stackSize: 8 * 1024 * 1024, qualityOfService: .userInteractive) {
        var smallBlocks = 0
        var largeBlocks = 0
        var smallSeconds = Double.infinity
        var largeSeconds = Double.infinity
        for _ in 0..<5 {
            let smallParse = parseTopLevelBlocks(small, options: options)
            smallBlocks = smallParse.blocks
            smallSeconds = min(smallSeconds, smallParse.seconds)
            let largeParse = parseTopLevelBlocks(large, options: options)
            largeBlocks = largeParse.blocks
            largeSeconds = min(largeSeconds, largeParse.seconds)
        }
        return (smallBlocks, smallSeconds, largeBlocks, largeSeconds)
    }
    #expect(smallBlocks == blocks, sourceLocation: sourceLocation)
    #expect(largeBlocks == blocks, sourceLocation: sourceLocation)
    let sizeRatio = Double(large.utf8.count) / Double(small.utf8.count)
    #expect(
        largeSeconds <= 2.5 * sizeRatio * smallSeconds,
        "\(largeSeconds) s for \(large.utf8.count) bytes, \(smallSeconds) s for \(small.utf8.count) bytes",
        sourceLocation: sourceLocation
    )
}

/// Parses `source` and returns the number of top-level blocks it holds, with the processor time the calling thread spent
/// parsing, in seconds.
private func parseTopLevelBlocks(_ source: String, options: MarkdownDocument.ParseOptions) -> (blocks: Int, seconds: Double) {
    let start = threadCPUSeconds()
    let blocks = MarkdownDocument.withParsedDocument(source, options: options) { document in
        var count = 0
        document.root.children.forEach { _ in count += 1 }
        return count
    }
    return (blocks, threadCPUSeconds() - start)
}

private func threadCPUSeconds() -> Double {
    var time = timespec()
    clock_gettime(CLOCK_THREAD_CPUTIME_ID, &time)
    return Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000
}
