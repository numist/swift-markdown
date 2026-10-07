/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A lightweight, copyable view over a `DocumentStorage`'s heap-backed buffers plus the borrowed source bytes.
///
/// `~Escapable, Copyable` - the same shape as `Span<T>`. Used as the carrier in `MarkdownNode` and `Children` so each accessor reaches into stable heap memory (for storage-owned buffers) or the borrowed source (`Span<UInt8>`) without re-extracting pointers.
///
/// Construction is tied to both the storage's borrow scope and the source's lifetime.
internal struct StorageView: ~Escapable, Copyable {
    internal let nodes: Span<NodeRecord>
    internal let strings: Span<UInt8>
    internal let segments: Span<Segment>
    internal let tableAlignments: Span<MarkdownNode.TableAlignment>
    internal let lineStarts: Span<Int>
    internal let sourceRanges: Span<DocumentStorage.SourceByteRange>
    internal let source: Span<UInt8>
    internal let options: MarkdownDocument.ParseOptions

    @_lifetime(borrow storage, copy source)
    internal init(storage: borrowing DocumentStorage, source: Span<UInt8>) {
        self.nodes = storage.nodes.span
        self.strings = storage.strings.span
        self.segments = storage.segments.span
        self.tableAlignments = storage.tableAlignments.span
        self.lineStarts = storage.lineStarts.span
        self.sourceRanges = storage.sourceRanges.span
        self.source = source
        self.options = storage.options
    }

    /// Convert a source byte offset to a 1-based (line, column) position.
    ///
    /// `column` is the 1-based UTF-8 byte offset within the line. Requires a populated `lineStarts`.
    internal func position(ofByte offset: Int) -> MarkdownNode.SourcePosition {
        // Largest line index `i` with lineStarts[i] <= offset (binary search; lineStarts is ascending).
        var lo = 0
        var hi = lineStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= offset {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        let lineIndex = max(0, lo - 1)
        precondition(!lineStarts.isEmpty, "a stamped source range lies on a line the parser read")
        let lineStart = lineStarts[lineIndex]
        return MarkdownNode.SourcePosition(line: lineIndex + 1, column: Int(offset - lineStart) + 1)
    }

    /// The source range of a node, or `nil` if positions are off or the node has no recorded source range.
    ///
    /// The upper bound is the position just past the node's last content byte; see `MarkdownNode.sourceRange`.
    internal func sourceRange(of index: DocumentStorage.Index) -> Range<MarkdownNode.SourcePosition>? {
        guard sourceRanges.count > index else { return nil }
        let r = sourceRanges[index]
        guard r.start >= 0, r.end >= 0 else { return nil }
        let start = position(ofByte: r.start)
        let end = position(ofByte: r.end)
        precondition(start <= end, "a stamped source range ends at or after its start")
        return start..<end
    }

    /// Read a node record by index.
    internal func record(at index: DocumentStorage.Index) -> NodeRecord {
        nodes[index]
    }

    // MARK: - Content bytes (always available)

    @_lifetime(borrow self)
    internal func bytes(of chunk: Chunk) -> Span<UInt8> {
        let start = Int(chunk.offset)
        let length = Int(chunk.length)
        if chunk.inSource {
            return source.extracting(start..<(start + length))
        } else {
            return strings.extracting(start..<(start + length))
        }
    }

    // MARK: - Content as String (always available)
    
    /// Concatenate a (possibly multi-segment) `ContentRef` into one `String`.
    internal func string(of ref: ContentRef) -> String {
        if ref.count == 0 {
            return ""
        }
        if ref.count == 1, #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            return String(copying: utf8Span(of: segments[Int(ref.first)]))
        }
        return String(unsafeUninitializedCapacity: Int(ref.totalLength)) { buffer in
            // SAFETY: `buffer` is the string's uninitialized storage, valid for this closure only. `OutputSpan(buffer:initializedCount: 0)` claims none of it as initialized, every append is capacity-checked (`ref.totalLength` is the sum of the segment lengths), `output.finalize(for: buffer)` checks that `buffer` is the buffer `output` covers before reporting its initialized count, and the initializer repairs any invalid UTF-8 in that prefix.
            //         No String initializer fills its UTF-8 storage through an `OutputSpan`; the safe route builds the bytes in an owned array and copies them with `String(decoding:as:)`, which measured about 0.4% more corpus and 3% more spec.txt instructions to parse and read every node's content.
            var output = unsafe OutputSpan(buffer: buffer, initializedCount: 0)
            for i in 0..<Int(ref.count) {
                let span = bytes(of: segments[Int(ref.first) + i].chunk)
                for b in 0..<span.count {
                    output.append(span[b])
                }
            }
            return unsafe output.finalize(for: buffer)
        }
    }

    // MARK: - Content as UTF8Span (anyAppleOS 26 only)

    /// Returns a `UTF8Span` from the raw byte span for the `UTF8Span`-vending public content API.
    ///
    /// Source-derived chunks are cut on scalar boundaries (the parser splits only at ASCII bytes), so every chunk is valid UTF-8.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    internal func utf8Span(of segment: Segment) -> UTF8Span {
        utf8Span(of: segment.chunk)
    }

    /// Returns a `UTF8Span` from the raw byte span for the `UTF8Span`-vending public content API.
    ///
    /// Source-derived chunks are cut on scalar boundaries (the parser splits only at ASCII bytes), so every chunk is valid UTF-8.
    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    internal func utf8Span(of ref: ContentRef) -> UTF8Span {
        if ref.count == 0 {
            return utf8Span(of: Chunk(offset: 0, length: 0, inSource: false))
        }
        return utf8Span(of: segments[Int(ref.first)])
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    internal func utf8Span(of chunk: Chunk) -> UTF8Span {
        // SAFETY: Content bytes are known-valid UTF-8 (source-derived from a validated `String` or `UTF8Span`, or arena bytes the parser writes as whole scalars) and cut on scalar boundaries, which is `UTF8Span(unchecked:)`'s precondition.
        //         The safe `UTF8Span(validating:)` rescans every byte, which would make this O(1) zero-copy accessor O(n) per call; no API builds a `UTF8Span` from bytes already known valid without that scan.
        unsafe UTF8Span(unchecked: bytes(of: chunk))
    }
}
