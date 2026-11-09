/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

/// A view of a `DocumentStorage`'s buffers and the borrowed source, carried by `MarkdownNode` and `Children`.
internal struct StorageView: ~Escapable, Copyable {
    internal let nodes: Span<NodeRecord>
    internal let strings: Span<UInt8>
    internal let segments: Span<Segment>
    internal let lineStarts: Span<Int>
    internal let sourceRanges: Span<DocumentStorage.SourceByteRange>
    internal let source: Span<UInt8>
    internal let options: MarkdownDocument.ParseOptions

    @_lifetime(borrow storage, copy source)
    internal init(storage: borrowing DocumentStorage, source: Span<UInt8>) {
        self.nodes = storage.nodes.span
        self.strings = storage.strings.span
        self.segments = storage.segments.span
        self.lineStarts = storage.lineStarts.span
        self.sourceRanges = storage.sourceRanges.span
        self.source = source
        self.options = storage.options
    }

    /// The 1-based line and byte column of a source byte. Requires a populated `lineStarts`.
    internal func position(ofByte offset: Int) -> MarkdownNode.SourcePosition {
        // Binary search for the last line starting at or before `offset`.
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

    /// The node's source range, or `nil` if positions are off or the node has none.
    internal func sourceRange(of index: DocumentStorage.Index) -> Range<MarkdownNode.SourcePosition>? {
        guard sourceRanges.count > index else { return nil }
        let r = sourceRanges[index]
        guard r.start >= 0, r.end >= 0 else { return nil }
        let start = position(ofByte: r.start)
        let end = position(ofByte: r.end)
        precondition(start <= end, "a stamped source range ends at or after its start")
        return start..<end
    }

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
    
    internal func string(of ref: ContentRef) -> String {
        if ref.count == 0 {
            return ""
        }
        if ref.count == 1, #available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *) {
            return String(copying: utf8Span(of: segments[ref.first]))
        }
        return String(unsafeUninitializedCapacity: ref.totalLength) { buffer in
            // SAFETY: The `OutputSpan` starts with none of `buffer` initialized, every append is capacity-checked against `ref.totalLength` (the sum of the segment lengths), `finalize(for:)` verifies `buffer` before reporting the initialized count, and the initializer repairs invalid UTF-8.
            //         No String initializer fills its UTF-8 storage through an `OutputSpan`. Building the bytes with `Array(capacity:initializingWith:)` and copying them with `String(decoding:as:)` measured 4.8% more instructions to parse spec.txt and read every node's `stringContent`. Building them in `withTemporaryAllocation(of:capacity:_:)` and copying them with `String(copying:)` after `UTF8Span(validating:)` exists only on anyAppleOS 26 and measured 0.7% more.
            var output = unsafe OutputSpan(buffer: buffer, initializedCount: 0)
            for i in 0..<ref.count {
                let span = bytes(of: segments[ref.first + i].chunk)
                for b in 0..<span.count {
                    output.append(span[b])
                }
            }
            return unsafe output.finalize(for: buffer)
        }
    }

    // MARK: - Content as UTF8Span (anyAppleOS 26 only)

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    internal func utf8Span(of segment: Segment) -> UTF8Span {
        utf8Span(of: segment.chunk)
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    internal func utf8Span(of ref: ContentRef) -> UTF8Span {
        // Single-span content (link URL and title, code info, attribute, footnote label) is stored as one segment;
        // a longer ref would be cut to its first segment here, while `stringContent` joins them all.
        assert(ref.count <= 1, "single-span content stored as \(ref.count) segments")
        if ref.count == 0 {
            return utf8Span(of: Chunk(offset: 0, length: 0, inSource: false))
        }
        return utf8Span(of: segments[ref.first])
    }

    @available(macOS 26, iOS 26, tvOS 26, watchOS 26, visionOS 26, *)
    @_lifetime(borrow self)
    internal func utf8Span(of chunk: Chunk) -> UTF8Span {
        // SAFETY: A source chunk lies within source text that a `String` or `UTF8Span` validated, and the parser cuts it only at ASCII bytes or just past a leading byte-order mark, so it starts and ends on scalar boundaries; an arena chunk holds bytes the parser writes as whole scalars. Either way the bytes are valid UTF-8, which is `UTF8Span(unchecked:)`'s precondition.
        //         A stored property can't have a type newer than the deployment target, so this view can carry the validated source only as an existential `UTF8Span` holder. Copying that holder with every node, deriving each source chunk from it with `UTF8Span.UnicodeScalarIterator.reset(roundingBackwardsFrom:)` and `prefix()`/`suffix()`, and validating arena chunks measured up to 8.4% more instructions to parse a document and read every node's content, and 19% more where the arena is half the size of the source. Calling `UTF8Span(validating:)` on every chunk instead measured up to 3.7% more, and 24% more where the arena is half the size of the source.
        unsafe UTF8Span(unchecked: bytes(of: chunk))
    }
}
