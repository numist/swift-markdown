/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Enumerate a UTF8-containing `Span` by lines.
internal struct LineReader: ~Escapable, ~Copyable {
    /// The unread rest of the source.
    internal var source: Span<UInt8>
    internal var lineNumber = 0

    /// The source offsets of the most recently returned line.
    internal var lineRange: Range<Int>
    var nextStart: Int

    @_lifetime(copy source)
    internal init(source: Span<UInt8>) {
        self.source = source
        lineNumber = 0
        lineRange = 0..<0
        nextStart = 0

        // Skip a leading UTF-8 byte order mark.
        if source.count >= 3,
           source[0] == 0xEF, source[1] == 0xBB, source[2] == 0xBF {
            self.source = source.extracting(3..<source.count)
            nextStart = 3
        }
    }

    @_lifetime(copy self)
    internal mutating func next() -> Span<UInt8>? {
        let start = nextStart
        let bytes = source
        let count = bytes.count
        
        if count == 0 {
            // A byte order mark with nothing after it still begins a line.
            guard lineNumber == 0, start > 0 else { return nil }
            lineNumber = 1
            lineRange = start..<start
            return bytes
        }

        lineNumber += 1

        // `\n` and `\r` never occur inside a multi-byte UTF-8 sequence, so a byte scan finds line endings.
        let i = Self.firstLineTerminator(in: bytes)

        if i < count {
            let line = bytes.extracting(0..<i)
            lineRange = start..<(start + i)

            // Consume the line ending. A `\r` immediately followed by `\n` is a single line ending.
            let b = bytes[i]
            var terminatorEnd = i + 1
            if b == UInt8(ascii: "\r"), terminatorEnd < count, bytes[terminatorEnd] == UInt8(ascii: "\n") {
                terminatorEnd += 1
            }
            nextStart = start + terminatorEnd
            source = bytes.extracting(terminatorEnd..<count)
            return line
        }

        // End of input without a line ending.
        lineRange = start..<(start + count)
        nextStart = lineRange.upperBound
        let result = source
        source = bytes.extracting(count..<count) // Empty
        return result
    }

    /// The index of the first `\n` or `\r` in `span`, or `span.count` if there is none.
    @inline(__always)
    internal static func firstLineTerminator(in span: Span<UInt8>) -> Int {
        let count = span.count
        let bytes = span.bytes

        let nl = SIMD16<UInt8>(repeating: UInt8(ascii: "\n"))
        let cr = SIMD16<UInt8>(repeating: UInt8(ascii: "\r"))
        // Non-matching lanes become 16, so `.min()` is the first matching lane.
        let lanes = SIMD16<UInt8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
        let noMatch = SIMD16<UInt8>(repeating: 16)

        var i = 0
        while i + 16 <= count {
            let chunk = bytes.loadSIMD16(fromByteOffset: i)
            let matched = (chunk .== nl) .| (chunk .== cr)
            if any(matched) {
                let lane = lanes.replacing(with: noMatch, where: .!matched).min()
                return i + Int(lane)
            }
            i += 16
        }
        // Scalar tail (< 16 bytes).
        while i < count {
            let b = span[i]
            if b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") {
                return i
            }
            i += 1
        }
        return count
    }
}

extension RawSpan {
    /// The 16 bytes at `offset`, which must lie within the span.
    @inline(__always)
    internal func loadSIMD16(fromByteOffset offset: Int) -> SIMD16<UInt8> {
        #if compiler(>=6.4)
        return load(fromByteOffset: offset, as: SIMD16<UInt8>.self)
        #else
        // SAFETY: Every bit pattern is a valid `SIMD16<UInt8>`, and `unsafeLoadUnaligned` traps unless all 16 bytes lie within the span.
        //         Before Swift 6.4 the standard library has no `ConvertibleFromBytes`, so `RawSpan` has no safe `load`.
        return unsafe unsafeLoadUnaligned(fromByteOffset: offset, as: SIMD16<UInt8>.self)
        #endif
    }
}
