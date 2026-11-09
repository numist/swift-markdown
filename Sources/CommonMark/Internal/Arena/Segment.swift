/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// One piece of a node's content: a byte range in the source (`inSource`) or the string arena.
///
/// A run of segments (`ContentRef`) represents content that spans several source ranges or mixes in synthetic bytes, without copying the source. `Int32` fields keep the segment pool compact.
internal struct Segment: Equatable {
    internal var offset: Int32
    internal var length: Int32
    internal var inSource: Bool

    internal init(offset: Int32, length: Int32, inSource: Bool) {
        self.offset = offset
        self.length = length
        self.inSource = inSource
    }

    internal init(_ chunk: Chunk) {
        self.init(offset: Int32(chunk.offset), length: Int32(chunk.length), inSource: chunk.inSource)
    }

    internal var chunk: Chunk {
        Chunk(offset: Int(offset), length: Int(length), inSource: inSource)
    }
}

/// One run of an arena chunk's map to the source: `length` content bytes that image the source from `sourceOffset`.
///
/// A negative `sourceOffset` marks a `"\n"` line join, which has no source position. Runs tile the content in order, so inline positions resolve through arena content such as a non-contiguous setext heading or a `\|`-unescaped table cell.
internal struct ArenaRun: Equatable {
    internal var length: Int32
    internal var sourceOffset: Int32

    internal init(length: Int32, sourceOffset: Int32) {
        self.length = length
        self.sourceOffset = sourceOffset
    }
}

/// An arena chunk's run map, for the chunk starting at arena offset `base`.
internal struct ContentImage {
    internal let base: Int
    internal let runs: [ArenaRun]
    /// `runEnds[i]` is the content-relative offset just past run `i`.
    private let runEnds: [Int]

    internal init(base: Int, runs: [ArenaRun]) {
        self.base = base
        self.runs = runs
        var end = 0
        runEnds = runs.map { run in
            end += Int(run.length)
            return end
        }
    }

    /// The source offset imaged by arena byte `offset`, or `nil` outside the chunk. `offset` must not be a line join.
    internal func sourceOffset(ofArenaByte offset: Int) -> Int? {
        let k = offset - base
        guard k >= 0, let total = runEnds.last, k < total else {
            return nil
        }
        let i = firstRun(endingAfter: k)
        precondition(runs[i].sourceOffset >= 0, "a resolved byte is not a line join")
        return Int(runs[i].sourceOffset) + (k - runStart(i))
    }

    /// The index of the first run ending past content-relative offset `k`, or `runs.count` when none does.
    private func firstRun(endingAfter k: Int) -> Int {
        var lo = 0
        var hi = runEnds.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if runEnds[mid] > k {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        return lo
    }

    /// The content-relative offset of run `i`'s first byte.
    private func runStart(_ i: Int) -> Int {
        i == 0 ? 0 : runEnds[i - 1]
    }
}

/// A node's content: the slice `[first, first + count)` of `DocumentStorage.segments`. `totalLength` is the byte length summed over the segments.
internal struct ContentRef: Equatable {
    internal var first: Int32
    internal var count: Int32
    internal var totalLength: Int32

    internal init(first: Int32, count: Int32, totalLength: Int32) {
        self.first = first
        self.count = count
        self.totalLength = totalLength
    }

    internal static let empty = ContentRef(first: 0, count: 0, totalLength: 0)
}
