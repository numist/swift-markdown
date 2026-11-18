/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// Enumerate a UTF8-containing `Span` by lines.
internal struct LineReader: ~Escapable, ~Copyable {
    /// The unconsumed remainder of the source, as a byte `Span`. Shrinks as lines are read.
    internal var source: Span<UInt8>
    internal var lineNumber = 0

    /// Byte range of the most recently returned line, in the *original* (pre-shrink, post-BOM) source coordinate space - what the block parser indexes its cached `sourceBytes` with.
    internal var lineRange: Range<Int>

    // A byte order mark counts in line 1's columns.
    internal var lineStart: Int {
        lineNumber == 1 ? 0 : lineRange.lowerBound
    }

    internal var lineFirstNUL = 0
    var nextStart: Int

    @_lifetime(copy source)
    internal init(source: Span<UInt8>) {
        self.source = source
        lineNumber = 0
        lineRange = 0..<0
        nextStart = 0

        // Skip a leading UTF-8 byte-order mark (U+FEFF encodes as the three bytes EF BB BF).
        if source.count >= 3,
           source[0] == 0xEF, source[1] == 0xBB, source[2] == 0xBF {
            self.source = source.extracting(3..<source.count)
            nextStart = 3
        }
    }

    @_lifetime(copy self)
    internal mutating func next() -> Span<UInt8>? {
        // Start the next line at the last line's end (offset into the original source).
        let start = nextStart
        let bytes = source
        let count = bytes.count
        
        if count == 0 {
            // A byte order mark with nothing after it still begins a line.
            guard lineNumber == 0, start > 0 else { return nil }
            lineNumber = 1
            lineRange = start..<start
            lineFirstNUL = start
            return bytes
        }

        lineNumber += 1

        // Find the next line terminator (`\n` 0x0A or `\r` 0x0D). In valid UTF-8 these bytes only ever appear as standalone ASCII scalars - never inside a multi-byte sequence - so a raw byte scan finds boundaries correctly. The scan is vectorized (16 bytes per step) since it touches every source byte exactly once and is a measurable slice of parse time.
        var i = Self.firstLineTerminatorOrNUL(in: bytes)
        lineFirstNUL = start + i
        if i < count, bytes[i] == 0 {
            i += 1 + Self.firstLineTerminator(in: bytes.extracting((i + 1)..<count))
        }

        if i < count {
            let line = bytes.extracting(0..<i)
            lineRange = start..<(start + i)

            // Consume the terminator. A `\r` immediately followed by `\n` is a single CRLF terminator.
            let b = bytes[i]
            var terminatorEnd = i + 1
            if b == UInt8(ascii: "\r"), terminatorEnd < count, bytes[terminatorEnd] == UInt8(ascii: "\n") {
                terminatorEnd += 1
            }
            nextStart = start + terminatorEnd
            source = bytes.extracting(terminatorEnd..<count)
            return line
        }

        // EOF without terminator.
        lineRange = start..<(start + count)
        nextStart = lineRange.upperBound
        let result = source
        source = bytes.extracting(count..<count) // Empty
        return result
    }

    @inline(__always)
    internal static func firstLineTerminatorOrNUL(in span: Span<UInt8>) -> Int {
        let nl = SIMD16<UInt8>(repeating: UInt8(ascii: "\n"))
        let cr = SIMD16<UInt8>(repeating: UInt8(ascii: "\r"))
        let nul = SIMD16<UInt8>(repeating: 0)
        return span.firstIndex(
            matching: { ($0 .== nl) .| ($0 .== cr) .| ($0 .== nul) },
            or: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") || $0 == 0 }
        )
    }

    /// Index of the first `\n` or `\r` in `span`, or `span.count` if neither is present.
    ///
    /// Scans 16 bytes at a time with a SIMD compare against both terminators, recovering the first matching lane via a per-lane index reduce; the sub-16-byte remainder is scanned scalar.
    @inline(__always)
    internal static func firstLineTerminator(in span: Span<UInt8>) -> Int {
        let nl = SIMD16<UInt8>(repeating: UInt8(ascii: "\n"))
        let cr = SIMD16<UInt8>(repeating: UInt8(ascii: "\r"))
        return span.firstIndex(
            matching: { ($0 .== nl) .| ($0 .== cr) },
            or: { $0 == UInt8(ascii: "\n") || $0 == UInt8(ascii: "\r") }
        )
    }
}

extension Span where Element == UInt8 {
    // `matches` tests each 16-byte chunk and `isMatch` the fewer than 16 bytes after the last one, so the two must accept the same bytes.
    @inline(__always)
    internal func firstIndex(matching matches: (SIMD16<UInt8>) -> SIMDMask<SIMD16<Int8>>, or isMatch: (UInt8) -> Bool) -> Int {
        firstIndex(from: 0, to: count, matching: matches, or: isMatch)
    }

    @inline(__always)
    internal func firstIndex(from lo: Int, to hi: Int, matching matches: (SIMD16<UInt8>) -> SIMDMask<SIMD16<Int8>>, or isMatch: (UInt8) -> Bool) -> Int {
        let bytes = self.bytes
        // Lane index for matching lanes; non-matching lanes are forced to 16 so `.min()` yields the first matching lane (or 16 = "no match in this chunk").
        let lanes = SIMD16<UInt8>(0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)
        let noMatch = SIMD16<UInt8>(repeating: 16)

        var i = lo
        while i + 16 <= hi {
            let matched = matches(bytes.loadSIMD16(fromByteOffset: i))
            if any(matched) {
                let lane = lanes.replacing(with: noMatch, where: .!matched).min()
                return i + Int(lane)
            }
            i += 16
        }
        // Scalar tail (< 16 bytes).
        while i < hi {
            if isMatch(self[i]) {
                return i
            }
            i += 1
        }
        return hi
    }
}

extension RawSpan {
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
