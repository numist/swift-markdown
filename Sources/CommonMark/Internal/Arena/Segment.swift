/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// One piece of a node's content: a byte range that lives in either the borrowed source `Span` (`inSource == true`) or `DocumentStorage`'s additions arena (`inSource == false`).
///
/// A `Segment` is the N-way generalization of `Chunk`'s `inSource` two-buffer scheme. Nodes reference an ordered run of these (see `ContentRef`) so that content spanning multiple source ranges (a multi-line paragraph) or mixing source with synthetic bytes (a joined newline, a decoded entity) can be represented without copying the source bytes into an intermediate buffer.
internal struct Segment: Equatable {
    internal var offset: Int
    private var lengthAndInSource: UInt

    private static let inSourceBit: UInt = 1 << (UInt.bitWidth - 1)

    internal var length: Int {
        get { Int(bitPattern: lengthAndInSource & ~Self.inSourceBit) }
        set { lengthAndInSource = (lengthAndInSource & Self.inSourceBit) | UInt(newValue) }
    }

    internal var inSource: Bool {
        lengthAndInSource & Self.inSourceBit != 0
    }

    internal init(offset: Int, length: Int, inSource: Bool) {
        self.offset = offset
        self.lengthAndInSource = UInt(length) | (inSource ? Self.inSourceBit : 0)
    }

    internal init(_ chunk: Chunk) {
        self.init(offset: chunk.offset, length: chunk.length, inSource: chunk.inSource)
    }

    /// Reconstruct a `Chunk` view of this segment. Used by internal parser code that still works in the single-buffer `Chunk` vocabulary.
    internal var chunk: Chunk {
        Chunk(offset: offset, length: length, inSource: inSource)
    }
}

internal struct ArenaRun {
    internal var length: Int
    internal var sourceOffset: Int

    internal init(length: Int, sourceOffset: Int) {
        self.length = length
        self.sourceOffset = sourceOffset
    }
}

internal struct ContentImage {
    internal let base: Int
    internal let runs: [ArenaRun]
    private let runEnds: [Int]

    internal init(base: Int, runs: [ArenaRun]) {
        self.base = base
        self.runs = runs
        var end = 0
        runEnds = runs.map { run in
            end += run.length
            return end
        }
    }

    internal func sourceOffset(ofArenaByte offset: Int) -> Int? {
        let k = offset - base
        guard k >= 0, let total = runEnds.last, k < total else {
            return nil
        }
        let i = firstRun(endingAfter: k)
        precondition(runs[i].sourceOffset >= 0, "a resolved byte is not a line join")
        return runs[i].sourceOffset + (k - runStart(i))
    }

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

    private func runStart(_ i: Int) -> Int {
        i == 0 ? 0 : runEnds[i - 1]
    }
}

/// A node's content, expressed as a contiguous slice `[first, first + count)` of `DocumentStorage.segments`.
///
/// The overwhelmingly common case is `count == 1` (a single source range - most text runs, URLs, and labels), which costs the same as a single inline `Chunk`. `totalLength` caches the total byte length across the segments so length queries don't have to walk the pool.
internal struct ContentRef {
    internal var first: Int
    internal var count: Int
    internal var totalLength: Int

    internal init(first: Int, count: Int, totalLength: Int) {
        self.first = first
        self.count = count
        self.totalLength = totalLength
    }

    internal static let empty = ContentRef(first: 0, count: 0, totalLength: 0)
}
