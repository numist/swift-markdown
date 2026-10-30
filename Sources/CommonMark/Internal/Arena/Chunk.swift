/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A byte range in either the source (`inSource`) or `DocumentStorage`'s string arena, which holds bytes the parser materializes, such as decoded entities.
internal struct Chunk: Equatable, Hashable {
    internal var offset: Int
    internal var length: Int
    internal var inSource: Bool

    internal init(offset: Int, length: Int, inSource: Bool) {
        self.offset = offset
        self.length = length
        self.inSource = inSource
    }

    internal static let empty = Chunk(offset: 0, length: 0, inSource: true)

    internal var isEmpty: Bool { length == 0 }
    
    internal var range: Range<Int> {
        offset..<(offset + length)
    }

    /// Narrows to `bounds`, which is relative to this chunk's first byte.
    internal func extracting(_ bounds: Range<Int>) -> Chunk {
        Chunk(offset: offset + bounds.lowerBound, length: bounds.count, inSource: inSource)
    }

    /// Drops leading and trailing spaces, tabs, and line endings.
    internal func trimming(using parser: borrowing BlockParser) -> Chunk {
        trimming(using: parser, leading: true, where: \.isSpaceTabOrNewline)
    }

    /// Drops trailing spaces, tabs, and line endings.
    internal func trimmingTrailing(using parser: borrowing BlockParser) -> Chunk {
        trimming(using: parser, leading: false, where: \.isSpaceTabOrNewline)
    }

    /// Drops leading and trailing whitespace characters (Characters and lines), as forms a paragraph's or setext heading's raw content.
    internal func trimmingWhitespace(using parser: borrowing BlockParser) -> Chunk {
        trimming(using: parser, leading: true, where: \.isASCIISpace)
    }

    @inline(__always)
    private func trimming(using parser: borrowing BlockParser, leading: Bool, where isTrimmed: (UInt8) -> Bool) -> Chunk {
        var lo = 0
        var hi = length
        while leading, lo < hi, isTrimmed(parser.readByte(at: offset + lo, in: self)) {
            lo += 1
        }
        while hi > lo, isTrimmed(parser.readByte(at: offset + hi - 1, in: self)) {
            hi -= 1
        }
        return extracting(lo..<hi)
    }
}

/// A link reference definition, stored in `DocumentStorage.referenceMap` under its normalized label.
internal struct ReferenceDefinition {
    internal var destination: Chunk
    internal var title: Chunk
}
