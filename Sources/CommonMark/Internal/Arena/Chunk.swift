/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A byte-range reference into either the original source buffer or `DocumentStorage`'s string arena.
///
/// Two-buffer scheme because some node content (text spans, URLs) points directly into the source while other content (entity-decoded text, normalized link references) is materialized into the string arena during parsing.
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

    /// Narrow to `bounds`, a range of indices relative to this chunk's own content (0-based, like `Span.extracting(_:)`), preserving `inSource`.
    internal func extracting(_ bounds: Range<Int>) -> Chunk {
        Chunk(offset: offset + bounds.lowerBound, length: bounds.count, inSource: inSource)
    }

    /// Return a copy narrowed to drop leading and trailing ASCII whitespace (space, tab, `\n`, `\r`), reading bytes through `parser` (which resolves this chunk's buffer via `inSource`).
    internal func trimming(using parser: borrowing BlockParser) -> Chunk {
        trimming(using: parser, leading: true, where: \.isSpaceTabOrNewline)
    }

    /// Return a copy narrowed to drop TRAILING ASCII whitespace only (space, tab, `\n`, `\r`), preserving any leading whitespace. Used for the paragraph / flag-ON setext-heading content that reaches inline parsing after ref-def stripping: a lazy-continuation line's leading whitespace can survive at the front (flag-ON the block parser keeps that residual, `BlockParser.addLineSegment`), and cmark does not re-strip it - the ref-def parser consumes the earlier line through its newline, leaving the residual as literal text (`* [o]:e\n ~` -> Text " ~").
    internal func trimmingTrailing(using parser: borrowing BlockParser) -> Chunk {
        trimming(using: parser, leading: false, where: \.isSpaceTabOrNewline)
    }

    /// Return a copy narrowed to drop leading and trailing whitespace characters as the spec defines them -
    /// space, tab, line feed, line tabulation, form feed and carriage return - the removal that forms a
    /// paragraph's or setext heading's raw content (spec "Paragraphs", "Setext headings").
    internal func trimmingWhitespace(using parser: borrowing BlockParser) -> Chunk {
        parser.storage.options.contains(.cmarkBugCompatibility)
            ? trimming(using: parser)
            : trimming(using: parser, leading: true, where: \.isASCIISpace)
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

/// A registered link reference definition.
///
/// Each successful `[label]: dest "title"` parsed at the start of a paragraph populates one of these in `DocumentStorage.referenceMap`, keyed by the label's normalized form (CommonMark 0.31 §4.7).
///
/// `destination` and `title` are `Chunk`s pointing into the materialized string arena (`storage.strings`) since paragraph content is normalized into that buffer before ref-def extraction runs.
internal struct ReferenceDefinition {
    internal var destination: Chunk
    internal var title: Chunk
}
