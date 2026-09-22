/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A fixed 8-byte inline buffer.
///
/// A value generic like `InlineArray<8, UInt8>` requires the anyAppleOS 26 runtime; this is a plain homogeneous tuple with unsafe-byte indexing, so it back-deploys and still stack-allocates. Indices are `0..<8`.
internal struct Bytes8 {
    private var storage: (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 0, 0, 0, 0, 0)

    internal init() {}

    internal subscript(_ i: Int) -> UInt8 {
        get { withUnsafeBytes(of: storage) { $0[i] } }
        set { withUnsafeMutableBytes(of: &storage) { $0[i] = newValue } }
    }
}

internal enum EntityParser {
    // MARK: - HTML entities

    internal struct EntityMatch {
        /// Decoded UTF-8 bytes, stored inline (no heap allocation). Named-entity values are at most 6 bytes (the longest entry in `HTMLEntities.entityValueBuffer`) and numeric entities at most 4, so 8 is a safely oversized fixed capacity. `count` is the number of leading bytes that are valid.
        var bytes: Bytes8
        var count: Int
        var afterSemi: Int
    }

    /// Try to match an HTML entity beginning at `start` (which points at `&`).
    ///
    /// Returns the decoded codepoints and the offset just past the trailing `;`. CommonMark 0.31 §6.5.
    ///
    /// `bugCompat` selects cmark-gfm's looser numeric digit limits (see `matchNumericEntity`); it is
    /// threaded from `MarkdownDocument.ParseOptions.cmarkBugCompatibility` at the call sites.
    internal static func matchEntity(start: Int, end: Int, source: Span<UInt8>, bugCompat: Bool) -> EntityMatch? {
        let after = start + 1
        if after >= end {
            return nil
        }
        let next = source[after]
        if next == UInt8(ascii: "#") {
            return matchNumericEntity(start: start, end: end, source: source, bugCompat: bugCompat)
        }
        return matchNamedEntity(start: start, end: end, source: source)
    }

    /// Match `&#NNN;` (decimal) or `&#xHHH;` / `&#XHHH;` (hex).
    ///
    /// The spec-correct digit limits are 1–7 decimal / 1–6 hex (CommonMark §6.5). When `bugCompat` is
    /// set, both branches accept up to 8 digits instead, matching cmark-gfm (see below).
    private static func matchNumericEntity(start: Int, end: Int, source: Span<UInt8>, bugCompat: Bool) -> EntityMatch? {
        var i = start + 2 // past `&#`
        if i >= end {
            return nil
        }
        var hex = false
        let firstByte = source[i]
        if firstByte == UInt8(ascii: "x") || firstByte == UInt8(ascii: "X") {
            hex = true
            i += 1
        }
        var n: UInt32 = 0
        var digits = 0
        // why: cmark-gfm decodes inline numeric refs with `houdini_unescape_ent` (swift-cmark
        // src/houdini_html_u.c), which `handle_entity` (src/inlines.c) calls directly — never the
        // stricter `_scan_entity` grammar (src/scanners.re). That decoder's shared gate is
        // `num_digits >= 1 && num_digits <= 8` for BOTH the decimal and hex branches, so cmark accepts
        // up to 8 digits either way — looser than CommonMark §6.5's 7-decimal / 6-hex limits. Flag-ON
        // (`.cmarkBugCompatibility`, adopted only by the differential fuzzer) match that 8-digit cap;
        // flag-OFF stays spec-correct so an 8+-digit decimal / 7+-digit hex ref remains literal.
        let maxDigits = bugCompat ? 8 : (hex ? 6 : 7)
        while i < end {
            let b = source[i]
            let value: UInt32
            if b.isASCIIDigit {
                value = UInt32(b - UInt8(ascii: "0"))
            } else if hex && b >= UInt8(ascii: "a") && b <= UInt8(ascii: "f") {
                value = UInt32(b - UInt8(ascii: "a") + 10)
            } else if hex && b >= UInt8(ascii: "A") && b <= UInt8(ascii: "F") {
                value = UInt32(b - UInt8(ascii: "A") + 10)
            } else {
                break
            }
            n = n * (hex ? 16 : 10) + value
            // Mirror cmark's overflow guard (`if (codepoint >= 0x110000) codepoint = 0x110000;`): clamp
            // once out of Unicode range so the next digit's multiply can't overflow `UInt32` (reachable
            // flag-ON, where a 9th hex digit is accumulated before the digit-count check rejects it).
            // The final validation below maps anything `> 0x10FFFF` to U+FFFD, so the clamp value is
            // observationally identical to the unclamped value — it only bounds the arithmetic.
            if n >= 0x110000 {
                n = 0x110000
            }
            digits += 1
            if digits > maxDigits {
                return nil
            }
            i += 1
        }
        if digits == 0 {
            return nil
        }
        if i >= end || source[i] != UInt8(ascii: ";") {
            return nil
        }
        let afterSemi = i + 1
        // Validate codepoint per CommonMark / Unicode.
        if n == 0 || n > 0x10FFFF || (n >= 0xD800 && n <= 0xDFFF) {
            let encoded = encodeCodepointUTF8(0xFFFD)
            return EntityMatch(bytes: encoded.bytes, count: encoded.count, afterSemi: afterSemi)
        }
        let encoded = encodeCodepointUTF8(n)
        return EntityMatch(bytes: encoded.bytes, count: encoded.count, afterSemi: afterSemi)
    }

    /// Match `&name;` against the embedded HTML entity table (binary search over `HTMLEntities.entityNames`).
    private static func matchNamedEntity(start: Int, end: Int, source: Span<UInt8>) -> EntityMatch? {
        // Scan name: ASCII letters or digits.
        var i = start + 1
        while i < end {
            let b = source[i]
            if !b.isASCIILetter && !b.isASCIIDigit {
                break
            }
            i += 1
        }
        if i == start + 1 {
            return nil
        }
        if i >= end || source[i] != UInt8(ascii: ";") {
            return nil
        }
        let nameRange = (start + 1)..<i
        let afterSemi = i + 1
        if let idx = lookupEntity(range: nameRange, source: source) {
            let off = HTMLEntities.entityValueOffsets[idx]
            // Length is derived from the next offset: values are packed contiguously in index order, and a trailing sentinel offset (== buffer count) gives the final entry its end.
            let len = HTMLEntities.entityValueOffsets[idx + 1] - off
            var bytes = Bytes8()
            for k in 0..<len {
                bytes[k] = HTMLEntities.entityValueBuffer[off + k]
            }
            return EntityMatch(bytes: bytes, count: len, afterSemi: afterSemi)
        }
        return nil
    }

    /// Binary search the entity-name table for a name spanning `range`.
    ///
    /// Returns the index into `HTMLEntities.entityNames` or nil.
    private static func lookupEntity(range: Range<Int>, source: Span<UInt8>) -> Int? {
        var lo = 0
        var hi = HTMLEntities.entityNames.count
        while lo < hi {
            let mid = (lo + hi) >> 1
            let cmp = compareEntityName(
                index: mid,
                range: range,
                source: source
            )
            if cmp == 0 {
                return mid
            } else if cmp < 0 {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return nil
    }

    /// Compare entityNames[index] against the bytes in `range`.
    ///
    /// Returns negative if the table entry is less, 0 if equal, positive otherwise.
    private static func compareEntityName(index: Int, range: Range<Int>, source: Span<UInt8>) -> Int {
        let name = HTMLEntities.entityNames[index]
        let nameLen = name.utf8CodeUnitCount
        let namePtr = name.utf8Start
        let inputLen = range.upperBound - range.lowerBound
        let minLen = nameLen < inputLen ? nameLen : inputLen
        for k in 0..<minLen {
            let a = namePtr[k]
            let b = source[range.lowerBound + k]
            if a != b {
                return Int(a) - Int(b)
            }
        }
        return nameLen - inputLen
    }

    /// Encode a single Unicode codepoint to its UTF-8 byte representation, returned inline with a valid-byte count.
    private static func encodeCodepointUTF8(_ cp: UInt32) -> (bytes: Bytes8, count: Int) {
        var bytes = Bytes8()
        if cp < 0x80 {
            bytes[0] = UInt8(cp)
            return (bytes, 1)
        }
        if cp < 0x800 {
            bytes[0] = UInt8(0xC0 | (cp >> 6))
            bytes[1] = UInt8(0x80 | (cp & 0x3F))
            return (bytes, 2)
        }
        if cp < 0x10000 {
            bytes[0] = UInt8(0xE0 | (cp >> 12))
            bytes[1] = UInt8(0x80 | ((cp >> 6) & 0x3F))
            bytes[2] = UInt8(0x80 | (cp & 0x3F))
            return (bytes, 3)
        }
        bytes[0] = UInt8(0xF0 | (cp >> 18))
        bytes[1] = UInt8(0x80 | ((cp >> 12) & 0x3F))
        bytes[2] = UInt8(0x80 | ((cp >> 6) & 0x3F))
        bytes[3] = UInt8(0x80 | (cp & 0x3F))
        return (bytes, 4)
    }
    
    // MARK: URL Escaping
    
    private static func urlChunkHasEscape(_ chunk: Chunk, source: Span<UInt8>) -> Bool {
        if chunk.isEmpty {
            return false
        }
        let endOff = chunk.offset + chunk.length
        // Quick scan: any backslash-escape sequences or entity references?
        var i = chunk.offset
        while i < endOff {
            let b = source[i]
            if b == UInt8(ascii: "\\") && i + 1 < endOff {
                let next = source[i + 1]
                if next.isASCIIPunct {
                    return true
                }
            }
            if b == UInt8(ascii: "&") {
                return true
            }
            i += 1
        }
        
        return false
    }
    
    private static func escapedURLChunkBytes(_ chunk: Chunk, source: Span<UInt8>, into storage: inout DocumentStorage) -> Chunk {
        // Materialize escaped form into storage.strings.
        let endOff = chunk.offset + chunk.length
        let outOffset = storage.strings.count
        var i = chunk.offset
        while i < endOff {
            let b = source[i]
            if b == UInt8(ascii: "\\"), i + 1 < endOff {
                let next = source[i + 1]
                if next.isASCIIPunct {
                    storage.strings.append(next)
                    i += 2
                    continue
                }
            }
            if b == UInt8(ascii: "&"),
               let entity = matchEntity(
                   start: i,
                   end: endOff,
                   source: source,
                   bugCompat: storage.options.contains(.cmarkBugCompatibility)
               ) {
                for k in 0..<entity.count {
                    storage.strings.append(entity.bytes[k])
                }
                i = entity.afterSemi
                continue
            }
            storage.strings.append(b)
            i += 1
        }
        return Chunk(
            offset: outOffset,
            length: storage.strings.count - outOffset,
            inSource: false
        )
    }
    
    /// Reproduces cmark's fenced-code info-string order: `blocks.c`'s `CMARK_NODE_CODE_BLOCK` case
    /// calls `houdini_unescape_html_f` (entity decode over the WHOLE chunk, backslashes untouched)
    /// and only afterwards `cmark_strbuf_unescape` (strip backslash escapes from THAT result) - two
    /// separate passes, entities first. That's a different order than `escapedURLChunkBytes`'s single
    /// left-to-right pass (which interleaves the two, matching standard CommonMark inline processing
    /// where a `\` immediately escapes a following `&` before it can start an entity). Under this
    /// order `\&#3;` entity-decodes first to `\` + U+0003, and the backslash then survives the second
    /// pass because U+0003 isn't escapable punctuation - whereas the interleaved pass would escape the
    /// `&` before `&#3;` ever becomes an entity. Gated `.cmarkBugCompatibility` at the one call site
    /// (the fence info string); this quirk is specific to cmark's fenced-code-info path, so it isn't
    /// threaded through the other `unescapeURLChunk` (link destination / title) callers.
    private static func entityFirstEscapedURLChunkBytes(_ chunk: Chunk, source: Span<UInt8>, into storage: inout DocumentStorage) -> Chunk {
        let endOff = chunk.offset + chunk.length
        var decoded = [UInt8]()
        decoded.reserveCapacity(chunk.length)
        var i = chunk.offset
        while i < endOff {
            let b = source[i]
            if b == UInt8(ascii: "&"),
               let entity = matchEntity(
                   start: i,
                   end: endOff,
                   source: source,
                   bugCompat: storage.options.contains(.cmarkBugCompatibility)
               ) {
                for k in 0..<entity.count {
                    decoded.append(entity.bytes[k])
                }
                i = entity.afterSemi
                continue
            }
            decoded.append(b)
            i += 1
        }
        let outOffset = storage.strings.count
        var r = 0
        while r < decoded.count {
            if decoded[r] == UInt8(ascii: "\\"), r + 1 < decoded.count, decoded[r + 1].isASCIIPunct {
                storage.strings.append(decoded[r + 1])
                r += 2
                continue
            }
            storage.strings.append(decoded[r])
            r += 1
        }
        return Chunk(
            offset: outOffset,
            length: storage.strings.count - outOffset,
            inSource: false
        )
    }

    /// If `chunk` contains any backslash escapes (`\<ASCII punct>`), materialize a clean copy into `storage.strings` with the escapes processed.
    ///
    /// Returns the original chunk untouched if no escapes are present. Used for inline-link / inline-image URLs and titles so that downstream rendering doesn't have to re-process them. Autolink URLs go through `emitAutolink` and are kept literal.
    internal static func unescapeURLChunk(_ chunk: Chunk, source: Span<UInt8>, into storage: inout DocumentStorage) -> Chunk {
        guard urlChunkHasEscape(chunk, source: source) else {
            return chunk
        }

        if storage.options.contains(.cmarkBugCompatibility) {
            return entityFirstEscapedURLChunkBytes(chunk, source: source, into: &storage)
        }
        return escapedURLChunkBytes(chunk, source: source, into: &storage)
    }
}
