/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2021 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

internal import BasicContainers

/// A 3×5 `Int` matrix - rows indexed by `length % 3`, columns by delimiter-char index (`*_~'"`) - used as the emphasis `openersBottom` search-floor table.
///
/// Tuple-backed with unsafe indexing so it back-deploys and stack-allocates (a nested `InlineArray` would be value-generic and require the anyAppleOS 26 runtime). Offsets are multiples of `Int` stride over an `Int`-aligned tuple, so loads are aligned.
internal struct OpenersBottom {
    private var storage: (Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int, Int)

    internal init(fill: Int) {
        storage = (fill, fill, fill, fill, fill, fill, fill, fill, fill, fill, fill, fill, fill, fill, fill)
    }

    internal subscript(_ row: Int, _ col: Int) -> Int {
        get {
            withUnsafeBytes(of: storage) {
                $0.load(fromByteOffset: (row * 5 + col) * MemoryLayout<Int>.stride, as: Int.self)
            }
        }
        set {
            withUnsafeMutableBytes(of: &storage) {
                $0.storeBytes(of: newValue, toByteOffset: (row * 5 + col) * MemoryLayout<Int>.stride, as: Int.self)
            }
        }
    }
}

/// Inline-level Markdown parsing functions.
extension BlockParser {

    /// Parse the inline content of `parent`. The raw byte content of the parent has already been materialized into `content` (resolved from a `Chunk`, typically pointing into `storage.strings`) by the block parser.
    ///
    /// On exit, `parent` has zero or more inline child nodes attached. Returns without emitting any child if `content` is empty.
    mutating func parseInline(
        content: borrowing ContentSpan,
        into parent: DocumentStorage.Index,
        preserveWhitespace: Bool = false,
        delimiters: inout UniqueArray<DelimiterRecord>,
        brackets: inout UniqueArray<BracketRecord>
    ) throws (MarkdownDocument.Error) {
        if content.isEmpty {
            return
        }
        // The delimiter and bracket stacks are caller-owned scratch buffers, reused across every paragraph in the document. Reset them to empty rather than allocating per call.
        delimiters.removeAll(keepingCapacity: true)
        brackets.removeAll(keepingCapacity: true)
        
        var cursor = content.startOffset
        let endOffset = content.endOffset
        var pendingTextStart = cursor
        var lastDelim: Int? = nil
        var lastBracket: Int? = nil
        var noLinkOpeners = false

        // Hoisted once for the plain-text skip in the `default` case below.
        let strikethroughEnabled = storage.options.contains(.strikethrough)
        let gfmAutolinkEnabled = storage.options.contains(.gfmAutolink)
        let smartEnabled = storage.options.contains(.smart)

        // Reset the backslash-hard-break flat-column cursor, tracked in CONTENT-offset space. This holds for both single-segment source content (a content offset IS its source offset, identity map) and multi-segment source content, whose continuation lines have their prefixes/indents stripped - offsets cmark's inline cursor never counted, so measuring the flat column in content offsets (not source offsets) is what reproduces cmark. Single-segment arena content (a flattened setext heading, a `\|`-unescaped table cell) stays on the byte-projection path: its content offsets don't map to source columns linearly, so it isn't armed.
        inlineSawBackslashHardBreak = false
        inlineFlatColumnTracking = positionsEnabled && !preserveWhitespace && (content.inSource || content.isMultiSegment)
        inlineLogicalLineStarts.removeAll(keepingCapacity: true)
        // Reset cmark's per-subject backtick-closer cache (`matchCodeSpan`, flag-ON only). Flag-OFF the cache is never consulted, so leave it untouched - inert.
        if storage.options.contains(.cmarkBugCompatibility) {
            codeSpanScannedForBackticks = false
            for i in codeSpanBackticks.indices {
                codeSpanBackticks[i] = 0
            }
        }
        if inlineFlatColumnTracking {
            // Logical-line boundaries are CONTENT offsets. The block's start line/column come from the SOURCE projection of the first content byte (identity for single-segment source; the first line's real source column for multi-segment, after any container prefix). Disarm if the content start has no source image (arena-only), leaving every node on the byte path.
            let blockStart = content.startOffset
            if let blockStartSource = content.sourceOffset(ofVirtual: blockStart) {
                inlineLogicalLineStarts.append(blockStart)
                inlineBlockStartLine = sourceLineNumber(ofSource: blockStartSource)
                inlineBlockStartColumn = blockStartSource - lineStartByte(ofSource: blockStartSource) + 1
            } else {
                inlineFlatColumnTracking = false
            }
        }

        while cursor < endOffset {
            let byte = content[cursor]
            switch byte {
            case UInt8(ascii: "`"):
                if let span = matchCodeSpan(
                    start: cursor,
                    end: endOffset,
                    content: content
                ) {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    // Code-span content: replace newlines with single spaces (per CommonMark §6.1) before applying the single-space-strip rule. Keep the original chunk if there are no newlines so we don't materialize for the common case.
                    let normalized = normalizeCodeSpanContent(span.content)
                    let normalizedRef = storage.intern(normalized)
                    let codeIdx = storage.appendNode(
                        NodeRecord(
                            kind: .codeInline(backtickCount: span.backtickCount),
                            parent: parent,
                            data: .literal(normalizedRef)
                        )
                    )
                    storage.appendChild(codeIdx, to: parent)
                    stampInline(codeIdx, cursor, span.afterClose, content: content)
                    stampCodeSpanEnd(codeIdx, start: cursor, afterClose: span.afterClose, content: content)
                    stampFlatRawInlineEnd(codeIdx, start: cursor, end: span.afterClose, content: content)
                    cursor = span.afterClose
                    pendingTextStart = cursor
                    continue
                }
                // No matching close - skip past the run; the backticks become part of the pending text region.
                cursor = scanBacktickRun(
                    start: cursor,
                    end: endOffset,
                    content: content
                )

            case UInt8(ascii: "\n"):
                // Inline-only / preserve-whitespace mode: a newline is literal text, not a soft/hard break. Leave it in the pending-text region (it has already been normalized to `\n` by `parseInlineOnly`) and step past it.
                if preserveWhitespace {
                    cursor += 1
                    continue
                }
                let info = classifyLineBreak(
                    at: cursor,
                    pendingTextStart: pendingTextStart,
                    content: content
                )
                flushPendingText(
                    start: pendingTextStart,
                    end: info.textEnd,
                    content: content,
                    into: parent,
                    // A soft break and a trailing-space hard break both extend the preceding text node's source range to the newline at `cursor`, owning the line's trailing whitespace (cmark stamps up to the newline for both). A backslash hard break's `\` does NOT: cmark's handle_backslash consumes the backslash into the LINEBREAK, so the preceding text ends at the content (`info.textEnd`), before the `\`.
                    rangeEnd: info.isBackslash ? nil : cursor,
                    // A whitespace-only run before a soft OR trailing-space hard break survives flag-ON as an empty text node spanning the stripped whitespace (see `flushPendingText`). cmark's parse_inline creates and rtrims this node in its generic text path BEFORE handle_newline classifies the break, so the empty node is emitted the same way regardless of break kind - the `emptytext-*` (soft) and `brkhb-*` (hard) fuzzer pairs both assert it. A backslash hard break is excluded by `rangeEnd: nil` above (its `\` leaves no trailing whitespace to strip).
                    emitEmptyStrippedWhitespace: true
                )
                let kind: MarkdownNode.Kind = info.isHard ? .lineBreak : .softBreak
                let breakIdx = storage.appendNode(NodeRecord(kind: kind, parent: parent))
                storage.appendChild(breakIdx, to: parent)
                if inlineFlatColumnTracking {
                    if info.isBackslash {
                        // why: cmark's handle_backslash (swift-cmark src/inlines.c ~848-856) makes the LINEBREAK without touching subj->line or subj->column_offset, unlike handle_newline (~1498-1508, soft/space breaks) which does `++line; column_offset = -pos`. So every inline node after this point keeps counting columns flat across the backslash-break newline and stays on the current line - add no logical-line reset, and flag stamping to emit explicit flat positions.
                        inlineSawBackslashHardBreak = true
                    } else {
                        // Soft break or trailing-space hard break: cmark's handle_newline resets the inline cursor to the next line. Record the next logical line's CONTENT start as a boundary (`cursor` is the newline's content offset; `cursor + 1` is the first byte of the following line - the next source segment for multi-segment content).
                        inlineLogicalLineStarts.append(cursor + 1)
                    }
                }
                cursor += 1
                pendingTextStart = cursor
                
            case UInt8(ascii: "&"):
                // Entity matching reads a flat buffer by raw offset, so scan through a contiguous
                // window (see `contiguousChunk`): identity for single-segment content, the single
                // source segment's slice for multi-segment content (whose virtual offsets index no
                // single buffer). An entity can't cross a segment boundary - the join newline
                // terminates the name/number - so a window from `&` to the segment end is sufficient;
                // a synthetic (interned-newline) segment yields nil and the `&` stays literal.
                let window = content.contiguousChunk(fromVirtual: cursor, limit: endOffset)
                // Match in an expression of its own so the borrowed `source` span (lifetime-dependent) stays scoped to the call and can't escape into the body.
                let entity: EntityParser.EntityMatch? = if let window {
                    if window.inSource {
                        EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: sourceBytes)
                    } else {
                        EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: storage.strings.span)
                    }
                } else {
                    nil
                }
                if let entity, let window {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    let decoded = Self.appendUTF8Bytes(
                        bytes: entity.bytes,
                        count: entity.count,
                        into: &storage.strings
                    )
                    let decodedRef = storage.intern(decoded)
                    let textIdx = storage.appendNode(
                        NodeRecord(kind: .text, parent: parent, data: .literal(decodedRef))
                    )
                    storage.appendChild(textIdx, to: parent)
                    // Convert the scanner-returned buffer offset back to a virtual content offset via the window base (identity for single-segment content).
                    let afterSemi = cursor + (entity.afterSemi - window.offset)
                    stampInline(textIdx, cursor, afterSemi, content: content)
                    cursor = afterSemi
                    pendingTextStart = cursor
                    continue
                }
                cursor += 1
                
            case UInt8(ascii: "<"):
                if let auto = matchAutolink(
                    start: cursor,
                    end: endOffset,
                    content: content
                ) {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    emitAutolink(
                        auto: auto,
                        into: parent,
                        content: content
                    )
                    cursor = auto.afterClose
                    pendingTextStart = cursor
                    continue
                }
                if let htmlEnd = matchInlineHTML(
                    start: cursor,
                    end: endOffset,
                    content: content
                ) {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    // The literal is the tag's raw bytes. When the whole `[cursor, htmlEnd)` range lies
                    // in one contiguous buffer region - every single-segment tag, and any multi-segment
                    // tag that stays within one source segment - `contiguousChunk` returns it zero-copy,
                    // byte-identical to the old `content.chunk` fast path. A multi-line tag straddles a
                    // soft-break segment boundary (the tag's whitespace spanned a newline in a
                    // non-contiguous paragraph): its bytes live in separate source segments joined by the
                    // interned `\n`, so no single buffer holds them and a straddling `content.chunk` would
                    // read the wrong bytes. Materialize the joined literal into the arena through the
                    // segment-aware subscript - continuation lines already have their leading whitespace
                    // stripped in the segment list, matching cmark's paragraph buffer.
                    let chunkRef: ContentRef
                    if let contiguous = content.contiguousChunk(fromVirtual: cursor, limit: htmlEnd),
                       contiguous.length == htmlEnd - cursor {
                        chunkRef = storage.intern(contiguous)
                    } else {
                        let outOffset = storage.strings.count
                        for i in cursor..<htmlEnd {
                            storage.strings.append(content[i])
                        }
                        chunkRef = storage.intern(
                            Chunk(offset: outOffset, length: storage.strings.count - outOffset, inSource: false)
                        )
                    }
                    let nodeIdx = storage.appendNode(
                        NodeRecord(kind: .htmlInline, parent: parent, data: .literal(chunkRef))
                    )
                    storage.appendChild(nodeIdx, to: parent)
                    stampInline(nodeIdx, cursor, htmlEnd, content: content)
                    stampInlineHTMLEnd(nodeIdx, start: cursor, htmlEnd: htmlEnd, content: content)
                    stampFlatRawInlineEnd(nodeIdx, start: cursor, end: htmlEnd, content: content)
                    cursor = htmlEnd
                    pendingTextStart = cursor
                    continue
                }
                cursor += 1
                
            case UInt8(ascii: "*"), UInt8(ascii: "_"):
                cursor = try handleDelimRun(
                    char: byte,
                    start: cursor,
                    end: endOffset,
                    content: content,
                    parent: parent,
                    delimiters: &delimiters,
                    lastDelim: &lastDelim,
                    pendingTextStart: &pendingTextStart
                )

            case UInt8(ascii: "~"):
                if storage.options.contains(.strikethrough) {
                    cursor = try handleDelimRun(
                        char: byte,
                        start: cursor,
                        end: endOffset,
                        content: content,
                        parent: parent,
                        delimiters: &delimiters,
                        lastDelim: &lastDelim,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }
                
            case UInt8(ascii: "["):
                flushPendingText(
                    start: pendingTextStart,
                    end: cursor,
                    content: content,
                    into: parent
                )
                let textChunk = content.chunk(offset: cursor, length: 1)
                let textRef = storage.intern(textChunk)
                let textIdx = storage.appendNode(
                    NodeRecord(kind: .text, parent: parent, data: .literal(textRef))
                )
                storage.appendChild(textIdx, to: parent)
                // An opener whose link never resolves survives as literal `[` text; stamp it so it keeps its column when it consolidates with neighbors (a matched link unlinks this node first).
                stampInline(textIdx, cursor, cursor + 1, content: content)
                try pushBracket(
                    kind: .link,
                    inlText: textIdx,
                    virtualStart: cursor,
                    delimPosition: lastDelim ?? -1,
                    brackets: &brackets,
                    lastBracket: &lastBracket,
                    noLinkOpeners: &noLinkOpeners
                )
                cursor += 1
                pendingTextStart = cursor
                
            case UInt8(ascii: "!"):
                if cursor + 1 < endOffset,
                   content[cursor + 1] == UInt8(ascii: "[") {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    let textChunk = content.chunk(offset: cursor, length: 2)
                    let textRef = storage.intern(textChunk)
                    let textIdx = storage.appendNode(
                        NodeRecord(kind: .text, parent: parent, data: .literal(textRef))
                    )
                    storage.appendChild(textIdx, to: parent)
                    // An opener whose image never resolves survives as literal `![` text; stamp its full 2-byte span so it keeps its start column when it consolidates with neighbors (a matched image unlinks this node first). Without the stamp the node stays `.unset` and `mergeTextNode` drops it, adopting the next node's start and losing the `![` prefix's columns.
                    stampInline(textIdx, cursor, cursor + 2, content: content)
                    try pushBracket(
                        kind: .image,
                        inlText: textIdx,
                        virtualStart: cursor,
                        delimPosition: lastDelim ?? -1,
                        brackets: &brackets,
                        lastBracket: &lastBracket,
                        noLinkOpeners: &noLinkOpeners
                    )
                    cursor += 2
                    pendingTextStart = cursor
                } else {
                    cursor += 1
                }
                
            case UInt8(ascii: "^"):
                if cursor + 1 < endOffset,
                   content[cursor + 1] == UInt8(ascii: "[") {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    let textChunk = content.chunk(offset: cursor, length: 2)
                    let textRef = storage.intern(textChunk)
                    let textIdx = storage.appendNode(
                        NodeRecord(kind: .text, parent: parent, data: .literal(textRef))
                    )
                    storage.appendChild(textIdx, to: parent)
                    try pushBracket(
                        kind: .attribute,
                        inlText: textIdx,
                        virtualStart: cursor,
                        delimPosition: lastDelim ?? -1,
                        brackets: &brackets,
                        lastBracket: &lastBracket,
                        noLinkOpeners: &noLinkOpeners
                    )
                    cursor += 2
                    pendingTextStart = cursor
                } else {
                    cursor += 1
                }
                
            case UInt8(ascii: "]"):
                flushPendingText(
                    start: pendingTextStart,
                    end: cursor,
                    content: content,
                    into: parent
                )
                cursor = handleCloseBracket(
                    cursor: cursor,
                    end: endOffset,
                    content: content,
                    parent: parent,
                    delimiters: &delimiters,
                    lastDelim: &lastDelim,
                    brackets: &brackets,
                    lastBracket: &lastBracket,
                    noLinkOpeners: &noLinkOpeners
                )
                pendingTextStart = cursor

            case UInt8(ascii: "\\"):
                // Backslash escape: `\<ASCII punct>` emits the punct as a single-byte text node. `\<newline>` is detected by the line-break handler when we hit the newline. Anything else leaves the backslash as literal text.
                if cursor + 1 < endOffset {
                    let next = content[cursor + 1]
                    if next.isASCIIPunct {
                        flushPendingText(
                            start: pendingTextStart,
                            end: cursor,
                            content: content,
                            into: parent
                        )
                        let punctChunk = content.chunk(
                            offset: cursor + 1,
                            length: 1
                        )
                        let punctRef = storage.intern(punctChunk)
                        let textIdx = storage.appendNode(
                            NodeRecord(kind: .text, parent: parent, data: .literal(punctRef))
                        )
                        storage.appendChild(textIdx, to: parent)
                        // why: the node's content is the single unescaped char (`cursor + 1`), but its source span is the 2-byte `\<punct>` escape starting at `cursor` - stamp the 2-byte source range so the run keeps the backslash's column.
                        stampInline(textIdx, cursor, cursor + 2, content: content)
                        cursor += 2
                        pendingTextStart = cursor
                        continue
                    }
                }
                cursor += 1
                
            case UInt8(ascii: ":"), UInt8(ascii: "w"), UInt8(ascii: "W"), UInt8(ascii: "@"):
                if storage.options.contains(.gfmAutolink),
                   let auto = matchGFMAutolink(
                    trigger: byte,
                    cursor: cursor,
                    end: endOffset,
                    content: content
                   ) {
                    flushPendingText(
                        start: pendingTextStart,
                        end: auto.urlStart,
                        content: content,
                        into: parent
                    )
                    emitGFMAutolink(
                        auto: auto,
                        content: content,
                        into: parent
                    )
                    cursor = auto.urlEnd
                    pendingTextStart = cursor
                    continue
                }
                cursor += 1
                
            case UInt8(ascii: "'"), UInt8(ascii: "\""):
                // Smart quotes: push a quote delimiter (resolved to curly open/close in `processEmphasis`). Without `.smart`, the byte is ordinary text.
                if smartEnabled {
                    cursor = try handleQuoteDelim(
                        char: byte,
                        start: cursor,
                        end: endOffset,
                        content: content,
                        parent: parent,
                        delimiters: &delimiters,
                        lastDelim: &lastDelim,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "-"):
                // Smart dashes: a run of 2+ hyphens becomes en/em dashes. A lone `-` is left in the pending-text region (identical text, fewer nodes).
                if smartEnabled {
                    cursor = handleSmartHyphen(
                        start: cursor,
                        end: endOffset,
                        content: content,
                        parent: parent,
                        pendingTextStart: &pendingTextStart
                    )
                } else {
                    cursor += 1
                }

            case UInt8(ascii: "."):
                // Smart ellipsis: exactly `...` becomes a single ellipsis. Other runs of dots stay in the pending-text region.
                if smartEnabled,
                   cursor + 2 < endOffset,
                   content[cursor + 1] == UInt8(ascii: "."),
                   content[cursor + 2] == UInt8(ascii: ".") {
                    flushPendingText(
                        start: pendingTextStart,
                        end: cursor,
                        content: content,
                        into: parent
                    )
                    let ellipsisRef = internSmartLiteral(Self.ellipsis)
                    let textIdx = storage.appendNode(
                        NodeRecord(kind: .text, parent: parent, data: .literal(ellipsisRef))
                    )
                    storage.appendChild(textIdx, to: parent)
                    cursor += 3
                    pendingTextStart = cursor
                } else {
                    cursor += 1
                }

            default:
                // Plain text: SIMD-skip to the next inline-significant byte instead of stepping one byte at a time. The skipped run stays pending and is flushed when that byte emits.
                cursor = content.nextSignificant(
                    from: cursor,
                    strikethrough: strikethroughEnabled,
                    gfmAutolink: gfmAutolinkEnabled,
                    smart: smartEnabled
                )
            }
        }
        flushPendingText(
            start: pendingTextStart,
            end: endOffset,
            content: content,
            into: parent
        )
        processEmphasis(
            stackBottom: -1,
            content: content,
            delimiters: &delimiters,
            lastDelim: &lastDelim
        )
    }

    // MARK: - Links / images (bracket stack)

    /// Bracket-stack opener kind. `.link` and `.attribute` reset `noLinkOpeners` when pushed; `.image` does not.
    internal enum BracketKind {
        case link
        case image
        case attribute
    }

    /// Bracket-stack entry recording an open `[` (LINK), `![` (IMAGE), or `^[` (ATTRIBUTE - fork-specific extended-attribute syntax). Like the delimiter stack, it's a doubly-linked list embedded in an array; `previous` is an index into `brackets` (or `nil`).
    internal struct BracketRecord {
        var kind: BracketKind
        var inlText: DocumentStorage.Index
        /// Virtual content offset of the opening `[` / `![` / `^[` byte. `buildLinkOrImage` / `handleCloseBracketAttribute` derive the wrapper's start from this so the map-aware stamp resolves arena/multi-segment content (the opener text node's stored chunk offset is already a source offset and would double-map).
        var virtualStart: Int
        /// Delimiter-stack index at time of push. Passed to `processEmphasis` as `stackBottom` after a successful link match so emphasis inside the link text gets resolved without leaking out.
        var delimPosition: Int
        /// `true` once any later bracket has been pushed on top of this one. Used to disqualify the shortcut-reference form for outer brackets that contain nested ones.
        var bracketAfter: Bool
        var previous: Int?
    }

    private func pushBracket(kind: BracketKind, inlText: DocumentStorage.Index, virtualStart: Int, delimPosition: Int, brackets: inout UniqueArray<BracketRecord>, lastBracket: inout Int?, noLinkOpeners: inout Bool) throws (MarkdownDocument.Error) {
        if let lastBracket {
            brackets[lastBracket].bracketAfter = true
        }
        let prev = lastBracket
        let newIdx = brackets.count
        brackets.append(BracketRecord(
            kind: kind,
            inlText: inlText,
            virtualStart: virtualStart,
            delimPosition: delimPosition,
            bracketAfter: false,
            previous: prev
        ))
        lastBracket = newIdx
        if kind != .image {
            noLinkOpeners = false
        }
    }

    private func popBracket(brackets: inout UniqueArray<BracketRecord>, lastBracket: inout Int?) {
        if let last = lastBracket {
            lastBracket = brackets[last].previous
        }
    }
    
    /// Process a `]` while the parent's child list contains any text/inline nodes that were emitted after the matching `[`. Returns the new cursor position.
    private mutating func handleCloseBracket(cursor: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, brackets: inout UniqueArray<BracketRecord>, lastBracket: inout Int?, noLinkOpeners: inout Bool) -> Int {
        let initialPos = cursor + 1
        var pos = initialPos
        // No bracket open: emit `]` literal and return.
        guard let openerIdx = lastBracket else {
            emitBracketLiteral(at: cursor, content: content, parent: parent)
            return pos
        }
        let openerKind = brackets[openerIdx].kind
        let openerInl = brackets[openerIdx].inlText
        let openerDelimPos = brackets[openerIdx].delimPosition
        let openerBracketAfter = brackets[openerIdx].bracketAfter
        if openerKind == .attribute {
            return handleCloseBracketAttribute(
                cursor: cursor,
                end: end,
                content: content,
                parent: parent,
                openerInl: openerInl,
                openerVirtualStart: brackets[openerIdx].virtualStart,
                openerDelimPos: openerDelimPos,
                delimiters: &delimiters,
                lastDelim: &lastDelim,
                brackets: &brackets,
                lastBracket: &lastBracket
            )
        }
        let isImage = openerKind == .image
        // Inactive link opener: just pop and emit `]`.
        if !isImage && noLinkOpeners {
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            emitBracketLiteral(at: cursor, content: content, parent: parent)
            return pos
        }
        // The opener `[` / `![` text node always carries literal data (set when pushed); bail defensively if it somehow doesn't. Virtual arithmetic below uses `brackets[openerIdx].virtualStart` (correct for multi-segment content), not the node's stored source offset.
        guard case .literal = storage[openerInl].data else {
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            emitBracketLiteral(at: cursor, content: content, parent: parent)
            return pos
        }
        var url: Chunk = .empty
        var title: Chunk = .empty
        var matched = false
        // Try inline link: `(url "title")`.
        if pos < end,
           content[pos] == UInt8(ascii: "(") {
            let afterParen = pos + 1
            let afterSpaces1 = skipSpaceChars(start: afterParen, end: end, content: content)
            // Scan the destination through a contiguous window so multi-segment content reads real bytes in bounds; `dest.afterEnd` is a buffer offset, converted back to a virtual offset via the window base.
            if let destWindow = content.contiguousChunk(fromVirtual: afterSpaces1, limit: end),
               let dest = matchLinkDestination(destWindow) {
                let afterDest = afterSpaces1 + (dest.afterEnd - destWindow.offset)
                let afterSpaces2 = skipSpaceChars(start: afterDest, end: end, content: content)
                var titleEnd = afterDest
                var maybeTitle: Chunk = .empty
                if afterSpaces2 > afterDest,
                   let titleWindow = content.contiguousChunk(fromVirtual: afterSpaces2, limit: end),
                   let t = matchLinkTitle(titleWindow) {
                    maybeTitle = t.chunk
                    titleEnd = afterSpaces2 + (t.afterEnd - titleWindow.offset)
                }
                let afterTitleSpaces = skipSpaceChars(start: titleEnd, end: end, content: content)
                if afterTitleSpaces < end,
                   content[afterTitleSpaces] == UInt8(ascii: ")") {
                    pos = afterTitleSpaces + 1
                    // Read via the buffer-aware `unescapeURLChunk` (selects `sourceBytes` vs the arena per `chunk.inSource`): a link inside flattened/arena content (a non-contiguous setext heading, a `\|`-unescaped table cell) has an arena-backed destination/title, so unescaping must not index the source buffer at an arena offset.
                    url = unescapeURLChunk(dest.chunk)
                    title = unescapeURLChunk(maybeTitle)
                    matched = true
                }
            }
            if !matched {
                pos = initialPos
            }
        }
        // Try reference link forms: full `[label]`, collapsed `[]`, or shortcut.
        if !matched {
            var labelChunk: Chunk?
            var afterRefForm = pos
            // Scan the reference label through a contiguous window (see `contiguousChunk`); `lab.interior` is already a real buffer chunk and `lab.afterEnd` a buffer offset converted back to virtual via the window base.
            if let labelWindow = content.contiguousChunk(fromVirtual: pos, limit: end),
               let lab = matchLinkLabel(labelWindow) {
                labelChunk = lab.interior
                afterRefForm = pos + (lab.afterEnd - labelWindow.offset)
            }
            // Collapsed `[]` or absent - fall back to shortcut form (the bracket text itself becomes the label) when no inner brackets were nested under this opener.
            let labelLen = labelChunk?.length ?? 0
            if labelLen == 0 && !openerBracketAfter {
                // Virtual offsets: the opener's `[` / `![` sits at `virtualStart`; the shortcut label runs from just past it to the `]` (`cursor`). `contiguousChunk` maps that virtual range to a real buffer chunk and, for multi-segment content, only when it lies within a single source segment - a shortcut label that straddles a line join isn't resolved here (falls through to literal text) rather than reading past the segment.
                let openerContentStart = brackets[openerIdx].virtualStart + (isImage ? 2 : 1)
                let shortcutLen = cursor - openerContentStart
                if shortcutLen > 0,
                   let sc = content.contiguousChunk(fromVirtual: openerContentStart, limit: cursor),
                   sc.length == shortcutLen {
                    labelChunk = sc
                }
            }
            if let lc = labelChunk, lc.length > 0 {
                let key = normalizeLabel(
                    chunk: lc
                )
                if !key.isEmpty, let ref = storage.referenceMap[key] {
                    url = ref.destination
                    title = ref.title
                    pos = afterRefForm
                    matched = true
                }
            }
        }
        if matched {
            buildLinkOrImage(
                isImage: isImage,
                openerInl: openerInl,
                openerDelimPos: openerDelimPos,
                url: url,
                title: title,
                linkStart: brackets[openerIdx].virtualStart,
                linkEnd: pos,
                closeBracket: cursor,
                content: content,
                delimiters: &delimiters,
                lastDelim: &lastDelim
            )
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            if !isImage {
                noLinkOpeners = true
            }
            return pos
        }
        // GFM footnote reference: when no link form matches but the bracket contents start with `^` (and have at least one more byte), treat the whole `[^label]` as a `.footnoteReference`.
        if storage.options.contains(.footnotes),
           !isImage,
           let labelChunk = footnoteRefLabel(
               openerVirtualStart: brackets[openerIdx].virtualStart,
               closeBracket: cursor,
               content: content
           ) {
            emitFootnoteReference(
                openerInl: openerInl,
                labelChunk: labelChunk
            )
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            return initialPos
        }
        // No match: pop bracket, emit `]` text, rewind to just past `]`.
        popBracket(brackets: &brackets, lastBracket: &lastBracket)
        emitBracketLiteral(at: cursor, content: content, parent: parent)
        return initialPos
    }

    /// Append a one-byte `]` text node at `cursor`. Used by the failure paths of `handleCloseBracket`.
    private mutating func emitBracketLiteral(at cursor: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index) {
        let chunk = content.chunk(offset: cursor, length: 1)
        let chunkRef = storage.intern(chunk)
        let idx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(chunkRef))
        )
        storage.appendChild(idx, to: parent)
        stampInline(idx, cursor, cursor + 1, content: content)
    }

    /// Construct the `.link` / `.image` node, splice it in front of the opener's `[` text node, reparent every following sibling into it, and remove the opener's `[` text from the tree. Then resolve emphasis inside the link with the bracket's `delimPosition` as the floor.
    private mutating func buildLinkOrImage(isImage: Bool, openerInl: DocumentStorage.Index, openerDelimPos: Int, url: Chunk, title: Chunk, linkStart: Int, linkEnd: Int, closeBracket: Int, content: borrowing ContentSpan, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?) {
        let parentIdx = storage[openerInl].parent
        let kind: MarkdownNode.Kind = isImage ? .image : .link
        let urlRef = storage.intern(url)
        let titleRef = storage.intern(title)
        let linkIdx = storage.appendNode(NodeRecord(
            kind: kind,
            parent: parentIdx,
            data: .link(url: urlRef, title: titleRef)
        ))
        // The link/image spans from its opening `[`/`![` (virtual `linkStart`) to just past the closing `)` or reference label (virtual `linkEnd`).
        stampInline(linkIdx, linkStart, linkEnd, content: content)
        stampCloseBracketEnd(linkIdx, closeBracket: closeBracket, linkEnd: linkEnd, content: content)
        storage.insertChildBefore(linkIdx, before: openerInl)
        var sib = storage[openerInl].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            storage.appendChild(sib_, to: linkIdx)
            sib = nextSib
        }
        storage.unlinkChild(openerInl)
        processEmphasis(
            stackBottom: openerDelimPos,
            content: content,
            delimiters: &delimiters,
            lastDelim: &lastDelim
        )
    }

    // MARK: - Footnote references

    /// Match a footnote-reference label inside an unmatched `[…]`.
    ///
    /// Returns the label chunk (excluding `[^` and `]`) if the bracket contents start with `^` and contain at least one more byte. `openerVirtualStart` and `closeBracket` are *virtual* content offsets; the returned chunk is resolved to a real buffer chunk via `contiguousChunk`, so multi-segment content reads real bytes. A label that straddles a line join (not representable as one contiguous chunk) yields `nil` (the reference isn't recognized) rather than reading past a segment.
    private func footnoteRefLabel(openerVirtualStart: Int, closeBracket: Int, content: borrowing ContentSpan) -> Chunk? {
        let interiorStart = openerVirtualStart + 1
        if interiorStart >= closeBracket {
            return nil
        }
        if content[interiorStart] != UInt8(ascii: "^") {
            return nil
        }
        let labelStart = interiorStart + 1
        if labelStart >= closeBracket {
            return nil
        }
        guard let chunk = content.contiguousChunk(fromVirtual: labelStart, limit: closeBracket),
              chunk.length == closeBracket - labelStart else {
            return nil
        }
        return chunk
    }

    /// Splice a `.footnoteReference` node in place of the opener `[`'s text node and any inner-content text nodes.
    ///
    /// Assigns or reuses the 1-based index for this label. If the matching definition is already in `storage.footnoteMap`, increments its `referenceCount`.
    private mutating func emitFootnoteReference(openerInl: DocumentStorage.Index, labelChunk: Chunk) {
        let key = normalizeLabel(chunk: labelChunk)
        let index: Int32
        if let existing = storage.footnoteIndices[key] {
            index = existing
        } else {
            storage.nextFootnoteIndex += 1
            index = storage.nextFootnoteIndex
            storage.footnoteIndices[key] = index
        }
        if let defIdx = storage.footnoteMap[key],
           case .footnoteDefinition(let lbl, let count) = storage[defIdx].data {
            storage[defIdx].data = .footnoteDefinition(
                label: lbl,
                referenceCount: count + 1
            )
        }
        let parentIdx = storage[openerInl].parent
        let labelRef = storage.intern(labelChunk)
        let fnRefIdx = storage.appendNode(NodeRecord(
            kind: .footnoteReference(index: Int(index)),
            parent: parentIdx,
            data: .footnoteReference(label: labelRef)
        ))
        storage.insertChildBefore(fnRefIdx, before: openerInl)
        // Detach inner-content text nodes (the `^label` part). They aren't part of the reference's emitted text - the reference is rendered by the consumer based on its label and index.
        var sib = storage[openerInl].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            sib = nextSib
        }
        storage.unlinkChild(openerInl)
    }

    // MARK: - Extended attributes (`^[..]`)

    /// Resolve a `]` that closes an `^[…]` attribute opener. Tries the inline form `(attrs)` first, then the reference form `[label]` whose label resolves in `storage.attributeReferenceMap`.
    ///
    /// On match emits a `.attribute` node and reparents the inner siblings into it.
    private mutating func handleCloseBracketAttribute(cursor: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, openerInl: DocumentStorage.Index, openerVirtualStart: Int, openerDelimPos: Int, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, brackets: inout UniqueArray<BracketRecord>, lastBracket: inout Int?) -> Int {
        var pos = cursor + 1
        var attrs: Chunk = .empty
        var matched = false
        // Try inline `(attrs)` form. The attribute scanner allows whitespace and balanced parens - this is *not* a link-URL scan.
        if pos < end,
           content[pos] == UInt8(ascii: "(") {
            let startAttrs = pos + 1
            if let scanned = matchAttributeAttributes(start: startAttrs, end: end, content: content) {
                let endAttrs = scanned.afterEnd
                if endAttrs < end,
                   content[endAttrs] == UInt8(ascii: ")") {
                    attrs = scanned.chunk
                    pos = endAttrs + 1
                    matched = true
                }
            }
        }
        // Try reference form `[label]` looking up in attribute refmap. Scan through a contiguous window (see `contiguousChunk`) so multi-segment content reads real bytes; `lab.interior` is a real buffer chunk and `lab.afterEnd` a buffer offset converted back to virtual via the window base.
        if !matched,
           let labelWindow = content.contiguousChunk(fromVirtual: pos, limit: end),
           let lab = matchLinkLabel(labelWindow) {
            let labelChunk = lab.interior
            if labelChunk.length > 0 {
                let key = normalizeLabel(
                    chunk: labelChunk
                )
                if !key.isEmpty,
                   let storedAttrs = storage.attributeReferenceMap[key] {
                    attrs = storedAttrs
                    pos = pos + (lab.afterEnd - labelWindow.offset)
                    matched = true
                }
            }
        }
        if !matched {
            // Fail: pop bracket, emit `]` text. The `^[` text node stays as regular text in the tree, which matches the C behavior.
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            emitBracketLiteral(at: cursor, content: content, parent: parent)
            return cursor + 1
        }
        // Match: build attribute node, reparent siblings, drop opener `^[`.
        let parentIdx = storage[openerInl].parent
        let attrsRef = storage.intern(attrs)
        let attrIdx = storage.appendNode(NodeRecord(
            kind: .attribute,
            parent: parentIdx,
            data: .attribute(attrsRef)
        ))
        // The `^[…](…)` attribute spans from its opening `^[` (virtual `openerVirtualStart`) to just past the closing form (virtual `pos`).
        stampInline(attrIdx, openerVirtualStart, pos, content: content)
        stampCloseBracketEnd(attrIdx, closeBracket: cursor, linkEnd: pos, content: content)
        storage.insertChildBefore(attrIdx, before: openerInl)
        var sib = storage[openerInl].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            storage.appendChild(sib_, to: attrIdx)
            sib = nextSib
        }
        storage.unlinkChild(openerInl)
        processEmphasis(
            stackBottom: openerDelimPos,
            content: content,
            delimiters: &delimiters,
            lastDelim: &lastDelim
        )
        popBracket(brackets: &brackets, lastBracket: &lastBracket)
        return pos
    }

    private struct AttributeAttributesMatch {
        var chunk: Chunk
        var afterEnd: Int
    }

    /// Scan the inside of an attribute form's `(…)`.
    ///
    /// Allows whitespace and nested balanced parens up to depth 32. Backslash before ASCII punctuation is treated as an escape (and consumed as a 2-byte unit). Differs from a link-URL scan in that whitespace is not a terminator.
    private func matchAttributeAttributes(start: Int, end: Int, content: borrowing ContentSpan) -> AttributeAttributesMatch? {
        var i = start
        var nbParen = 0
        while i < end {
            let c = content[i]
            if c == UInt8(ascii: "\\") && i + 1 < end {
                let next = content[i + 1]
                if next.isASCIIPunct {
                    i += 2
                    continue
                }
                i += 1
                continue
            }
            if c == UInt8(ascii: "(") {
                nbParen += 1
                if nbParen > 32 {
                    return nil
                }
                i += 1
                continue
            }
            if c == UInt8(ascii: ")") {
                if nbParen == 0 {
                    // The attribute content `[start, i)` must be representable as one contiguous buffer chunk. Single-segment content always is; multi-segment content that straddles a line join is not (the range would run past a single source segment), so treat it as no match - the `^[…]` stays literal text, mirroring how the reference-form label defers. An empty `()` is representable (zero length). Without this, `content.chunk` would build a chunk from virtual offsets whose reads index the wrong buffer / overrun a segment when the content is materialized.
                    if i == start {
                        return AttributeAttributesMatch(chunk: content.chunk(offset: start, length: 0), afterEnd: i)
                    }
                    guard let chunk = content.contiguousChunk(fromVirtual: start, limit: i),
                          chunk.length == i - start else {
                        return nil
                    }
                    return AttributeAttributesMatch(chunk: chunk, afterEnd: i)
                }
                nbParen -= 1
                i += 1
                continue
            }
            i += 1
        }
        return nil
    }

    // MARK: - Emphasis / strong (delimiter stack)

    /// One node in the delimiter stack - the side data structure used by CommonMark's emphasis-resolution algorithm (§6.2 + Appendix). Each record points at a `.text` node whose literal contains the run of `*` or `_` characters scanned during the forward pass.
    ///
    /// The stack is a doubly-linked list embedded in a `UniqueArray<DelimiterRecord>` array - `previous`/`next` are array indices, `nil` means "none". When emphasis is resolved, individual records are unlinked from the list but the array itself isn't shrunk (so other indices stay valid).
    internal struct DelimiterRecord {
        var character: UInt8
        var length: Int
        var canOpen: Bool
        var canClose: Bool
        var inlText: DocumentStorage.Index
        /// The delimiter run's span in *virtual* content coordinates (`[virtualStart, virtualEnd)`), fixed at creation. `insertEmph` derives the emph/strong node's source range from these virtual offsets so the map-aware stamp resolves arena/multi-segment content correctly - not from the run's stored chunk offset, which is already a source offset and would double-map.
        var virtualStart: Int
        var virtualEnd: Int
        var previous: Int?
        var next: Int?
    }

    /// Scan a maximal run of `c` (`*` or `_`) starting at `start`, classify its left/right-flanking + can_open/can_close per CommonMark 0.31 §6.2, emit a `.text` node for the run, and (if it can open or close) push a delimiter record onto the stack. Returns the offset just past the run.
    ///
    /// The start of the content (`content.startOffset`) determines whether `start - 1` is a real "before" character or implicitly a newline (start of inline content acts like a line break).
    private mutating func handleDelimRun(char: UInt8, start: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, pendingTextStart: inout Int) throws (MarkdownDocument.Error) -> Int {
        let chunkStart = content.startOffset
        var runEnd = start
        while runEnd < end, content[runEnd] == char {
            runEnd += 1
        }
        
        let count = runEnd - start
        // "Before" character - treat content boundaries as a line break.
        let beforeChar: UInt8 = if start > chunkStart { content[start - 1] } else { UInt8(ascii: "\n") }
        // "After" character - same convention at end of content.
        let afterChar: UInt8 = if runEnd < end { content[runEnd] } else { UInt8(ascii: "\n") }
        
        // NBSP detection: U+00A0 in UTF-8 is `0xC2 0xA0`. The single-byte checks above won't catch it, so peek backward from `start` and forward from `runEnd` to detect the multi-byte sequence.
        let beforeIsNBSP = beforeChar == 0xA0 && start - 2 >= chunkStart && content[start - 2] == 0xC2
        let afterIsNBSP = afterChar == 0xC2 && runEnd + 1 < end && content[runEnd + 1] == 0xA0
        let beforeIsSpace = beforeChar.isASCIISpace || beforeIsNBSP
        let beforeIsPunct = beforeChar.isASCIIPunct
        let afterIsSpace = afterChar.isASCIISpace || afterIsNBSP
        let afterIsPunct = afterChar.isASCIIPunct
        let leftFlanking = !afterIsSpace && (!afterIsPunct || beforeIsSpace || beforeIsPunct)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunct || afterIsSpace || afterIsPunct)
        
        let canOpen: Bool
        let canClose: Bool
        if char == UInt8(ascii: "_") {
            // Intraword `_` is rejected on whichever side has letters/digits.
            canOpen = leftFlanking && (!rightFlanking || beforeIsPunct)
            canClose = rightFlanking && (!leftFlanking || afterIsPunct)
        } else {
            canOpen = leftFlanking
            canClose = rightFlanking
        }
        // Non-flanking run: leave it as part of pending text. Don't emit a text node and don't flush - important so GFM autolink scan-back can later consume these bytes (e.g. `a.b-c_d@a.b` - the `_` mustn't fragment the local-part text). Strikethrough is exempt: cmark-gfm emits a text node for every `~` run it scans (`strikethrough.c` `match`), flanking or not, so a `~` isolated by whitespace still surfaces (as the zero-width node stamped below) rather than folding into surrounding text. A non-flanking `~` is always whitespace-surrounded, so it never sits inside a URL and this exemption can't disturb autolink scan-back.
        let isStrikethrough = char == UInt8(ascii: "~")
        if !canOpen && !canClose && !isStrikethrough {
            return runEnd
        }
        // Flush pending text up to the run start, then emit the run as text.
        flushPendingText(
            start: pendingTextStart,
            end: start,
            content: content,
            into: parent
        )
        let runChunk = content.chunk(offset: start, length: count)
        let runRef = storage.intern(runChunk)
        let textIdx = storage.appendNode(NodeRecord(kind: .text, parent: parent, data: .literal(runRef)))
        storage.appendChild(textIdx, to: parent)
        // Stamp the run's own source span. A delimiter that never forms emphasis stays as literal text, and this range lets it keep its columns when it consolidates with adjacent text; a matched delimiter's text node is unlinked before it can matter. The reference stamps this node at creation for the same reason.
        //
        // why: an unmatched `~`/`~~` run's range is stamped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). Only the stamping differs - the run's emission (the strikethrough exemption above) and delimiter push (below) are the same either way.
        //
        // Flag ON reproduces cmark-gfm's strikethrough extension (`strikethrough.c` `match`), which records only the run's start column and never sets its end column, so a run that never forms a strikethrough reports a zero-width range (see `stampInlineZeroWidth`). Consolidation takes the end from the last merged text node, so a run that abuts following text (`a~b`, `~x`) recovers a real width while a standalone or trailing run stays zero-width.
        //
        // Flag OFF is spec-correct: the run is ordinary literal text and gets a normal, width-bearing range over its own `[start, runEnd)` span, exactly like emphasis (`*`/`_`) delimiters and every other text run stamped via `stampInline`.
        if isStrikethrough && storage.options.contains(.cmarkBugCompatibility) {
            stampInlineZeroWidth(textIdx, at: start, content: content)
        } else {
            stampInline(textIdx, start, runEnd, content: content)
        }
        // Push a delimiter record only when the run can open or close. A non-flanking `~` (emitted above to mirror cmark-gfm) can do neither, so it contributes no delimiter and stays literal text.
        if canOpen || canClose {
            let prev = lastDelim
            let newIdx = delimiters.count
            delimiters.append(DelimiterRecord(
                character: char,
                length: count,
                canOpen: canOpen,
                canClose: canClose,
                inlText: textIdx,
                virtualStart: start,
                virtualEnd: runEnd,
                previous: prev,
                next: nil
            ))
            if let prev {
                delimiters[prev].next = newIdx
            }
            lastDelim = newIdx
        }
        pendingTextStart = runEnd
        return runEnd
    }

    /// Resolve emphasis pairs. Walks forward from the first delimiter above `stackBottom` (use `-1` to process the entire stack). For each closer, looks back for the most recent compatible opener and pairs them via `insertEmph`.
    ///
    /// `openersBottom` is the per-(length%3, char) search-floor optimization: once we fail to find an opener for a closer of a given (length%3, char), no later closer of the same shape needs to look behind that point.
    private mutating func processEmphasis(stackBottom: Int, content: borrowing ContentSpan, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?) {
        let doubleTilde = storage.options.contains(.strikethroughDoubleTilde)
        // openersBottom[length % 3, char-index]: 0=`*`, 1=`_`, 2=`~`, 3=`'`, 4=`"`.
        var openersBottom = OpenersBottom(fill: stackBottom)
        // Find the earliest (smallest-index) delimiter strictly above stackBottom.
        var closer: Int? = nil
        var walker = lastDelim
        while let w = walker, w > stackBottom {
            closer = w
            walker = delimiters[w].previous
        }
        while let c = closer {
            if !delimiters[c].canClose {
                closer = delimiters[c].next
                continue
            }
            let closerChar = delimiters[c].character
            let charIdx = charIndex(for: closerChar)
            let lenMod = delimiters[c].length % 3
            // Look backward for first matching opener.
            var opener = delimiters[c].previous
            var openerFound = false
            while let o = opener, o > stackBottom,
                  o >= openersBottom[lenMod, charIdx] {
                if delimiters[o].canOpen
                    && delimiters[o].character == closerChar {
                    let cl = delimiters[c]
                    let op = delimiters[o]
                    if closerChar == UInt8(ascii: "~") {
                        // Strikethrough: lengths must match exactly. With the doubleTilde option, both sides must be exactly 2.
                        if doubleTilde {
                            if op.length == 2 && cl.length == 2 {
                                openerFound = true
                                break
                            }
                        } else if op.length == cl.length {
                            openerFound = true
                            break
                        }
                    } else if !(cl.canOpen || op.canClose)
                        || cl.length % 3 == 0
                        || (op.length + cl.length) % 3 != 0 {
                        openerFound = true
                        break
                    }
                }
                opener = delimiters[o].previous
            }
            let oldCloser = c
            if closerChar == UInt8(ascii: "'") || closerChar == UInt8(ascii: "\"") {
                // Smart quote: the closer is already the right (closing) curly form - `handleQuoteDelim` sets `'`→rightSingleQuote and a `"` closer (which by definition `canClose`)→rightDoubleQuote at creation, so re-interning it here would only move its segment to the pool's end and break the pool-contiguity that `consolidateTextNodes` relies on to merge it with its neighbours (e.g. the apostrophe in `it's`). Only the opener needs its glyph flipped.
                let single = closerChar == UInt8(ascii: "'")
                let next = delimiters[c].next
                if openerFound, let opener {
                    setSmartLiteral(
                        of: delimiters[opener].inlText,
                        single ? Self.leftSingleQuote : Self.leftDoubleQuote
                    )
                    removeDelim(opener, delimiters: &delimiters, lastDelim: &lastDelim)
                    removeDelim(oldCloser, delimiters: &delimiters, lastDelim: &lastDelim)
                }
                closer = next
            } else if openerFound, let opener {
                closer = insertEmph(
                    opener: opener,
                    closer: c,
                    content: content,
                    delimiters: &delimiters,
                    lastDelim: &lastDelim
                )
            } else {
                closer = delimiters[c].next
            }
            if !openerFound {
                openersBottom[delimiters[oldCloser].length % 3, charIdx] = oldCloser
                if !delimiters[oldCloser].canOpen {
                    removeDelim(oldCloser, delimiters: &delimiters, lastDelim: &lastDelim)
                }
            }
        }
        // Free remaining delimiters above stackBottom.
        while let last = lastDelim, last > stackBottom {
            removeDelim(last, delimiters: &delimiters, lastDelim: &lastDelim)
        }
    }

    private func charIndex(for c: UInt8) -> Int {
        switch c {
        case UInt8(ascii: "_"): return 1
        case UInt8(ascii: "~"): return 2
        case UInt8(ascii: "'"): return 3
        case UInt8(ascii: "\""): return 4
        default: return 0
        }
    }

    /// Pair `opener` with `closer`, build an `.emphasis` (1-char match) or `.strong` (2-char match) node, reparent the inner siblings into it, trim the matched chars off the opener's and closer's text nodes, remove freed delimiters from the stack, and return the next closer to process (which is `closer.next` if we consumed the closer's text fully, otherwise `closer` itself for another round).
    private mutating func insertEmph(opener: Int, closer: Int, content: borrowing ContentSpan, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?) -> Int? {
        let openerInl = delimiters[opener].inlText
        let closerInl = delimiters[closer].inlText
        let openerChar = delimiters[opener].character
        var openerNumChars = literalLength(of: openerInl)
        var closerNumChars = literalLength(of: closerInl)
        let useDelims: Int
        let kind: MarkdownNode.Kind
        if openerChar == UInt8(ascii: "~") {
            // Strikethrough: opener and closer have equal length (enforced by processEmphasis). Consume the entire run from each side.
            useDelims = openerNumChars
            kind = .strikethrough
        } else {
            useDelims = (closerNumChars >= 2 && openerNumChars >= 2) ? 2 : 1
            kind = useDelims == 1 ? .emphasis : .strong
        }
        openerNumChars -= useDelims
        closerNumChars -= useDelims
        // The delimiter records' `length` fields stay at their ORIGINAL run lengths and are never
        // synced down to the remaining count. `processEmphasis` uses `delimiters[i].length` only for
        // the rule-of-three modular arithmetic (`% 3`) and the `openersBottom` slot index, and the
        // reference (cmark `S_insert_emph`) likewise reduces only the inline text literal length,
        // never the delimiter's `length` — that field is fixed at creation (`inlines.c` line 551).
        // Keeping it original is load-bearing: a closer whose remaining count changes its `length % 3`
        // slot (e.g. a `****` run reduced 4→2 after one pairing) must still index its original slot, or
        // a floor lowered by an unpairable interior run of a different original length would wrongly
        // suppress the leftover pairing (`****a**o****` must nest as Strong>Strong>Text "a**o"). The
        // remaining count that governs how many chars this pairing consumes is read from the inline
        // text literal length (`literalLength` above), exactly as the reference reads it.
        // Trim `useDelims` chars off the END of the opener literal.
        storage.trimLiteral(of: openerInl, trimStart: 0, newLength: openerNumChars)
        // Trim `useDelims` chars off the START of the closer literal.
        storage.trimLiteral(of: closerInl, trimStart: useDelims, newLength: closerNumChars)
        // Free intervening delimiters (their inl_text nodes survive - they become children of the new emph/strong).
        var d = delimiters[closer].previous
        while let dd = d, dd != opener {
            let prev = delimiters[dd].previous
            removeDelim(dd, delimiters: &delimiters, lastDelim: &lastDelim)
            d = prev
        }
        // Build the wrapping node and reparent siblings.
        let parentIdx = storage[openerInl].parent
        let emphIdx = storage.appendNode(NodeRecord(kind: kind, parent: parentIdx))
        // why: the emph/strong range is stamped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). Both branches express VIRTUAL content offsets so the map-aware `content:` overload resolves them through the arena/segment map (identity for source-backed content).
        //
        // Flag ON reproduces cmark-gfm's `S_insert_emph` (inlines.c), which stamps the node from `opener_inl->start_column` / `closer_inl->end_column` - the FULL opener and closer delimiter runs. Trimming the consumed delimiters changes only the inline text nodes' literal length, never their recorded columns, so cmark's range spans the whole runs regardless of how many delimiters this level actually consumed. When a run is only partially paired (leftover delimiters survive), that range overlaps the leftover-delimiter text nodes - e.g. `**o*` yields both `Text "*" @1:1-1:3` and `Emphasis @1:1-1:5` starting at column 1. That overlap is cmark's shipped behavior.
        //
        // Flag OFF is spec-correct: advance the start past the opener's leftover delimiters and pull the end back before the closer's, so the range covers only the consumed delimiters plus content and never overlaps the leftover text (`**o*` → `Emphasis @1:2-1:5`). For balanced runs both counts are zero and the branches coincide.
        let start: Int
        let end: Int
        if storage.options.contains(.cmarkBugCompatibility) {
            start = delimiters[opener].virtualStart
            end = delimiters[closer].virtualEnd
        } else {
            start = delimiters[opener].virtualStart + openerNumChars
            end = delimiters[closer].virtualEnd - closerNumChars
        }
        stampInline(emphIdx, start, end, content: content)
        var sibling = storage[openerInl].next
        while let sibling_ = sibling, sibling_ != closerInl {
            let nextSibling = storage[sibling_].next
            storage.unlinkChild(sibling_)
            storage.appendChild(sibling_, to: emphIdx)
            sibling = nextSibling
        }
        storage.insertChildAfter(emphIdx, after: openerInl)
        var resultCloser: Int? = closer
        if openerNumChars == 0 {
            storage.unlinkChild(openerInl)
            removeDelim(opener, delimiters: &delimiters, lastDelim: &lastDelim)
        }
        if closerNumChars == 0 {
            storage.unlinkChild(closerInl)
            let next = delimiters[closer].next
            removeDelim(closer, delimiters: &delimiters, lastDelim: &lastDelim)
            resultCloser = next
        }
        return resultCloser
    }

    private func removeDelim(_ idx: Int, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?) {
        let prev = delimiters[idx].previous
        let next = delimiters[idx].next
        if let prev {
            delimiters[prev].next = next
        }
        if let next {
            delimiters[next].previous = prev
        }
        if idx == lastDelim {
            lastDelim = prev
        }
    }

    private func literalLength(of nodeIdx: DocumentStorage.Index) -> Int {
        if case .literal(let ref) = storage[nodeIdx].data {
            return Int(ref.totalLength)
        }
        return 0
    }

    // MARK: - Smart punctuation

    /// UTF-8 bytes for the smart-punctuation replacement characters.
    static let leftSingleQuote: StaticString = "\u{2018}"
    static let rightSingleQuote: StaticString = "\u{2019}"
    static let leftDoubleQuote: StaticString = "\u{201C}"
    static let rightDoubleQuote: StaticString = "\u{201D}"
    static let enDash: StaticString = "\u{2013}"
    static let emDash: StaticString = "\u{2014}"
    static let ellipsis: StaticString = "\u{2026}"

    /// Append a constant UTF-8 byte sequence into the string arena.
    private mutating func appendSmartConstant(_ s: StaticString) {
        let ptr = s.utf8Start
        for k in 0..<s.utf8CodeUnitCount {
            storage.strings.append(ptr[k])
        }
    }

    /// Append a constant UTF-8 byte sequence into the string arena and intern it as a literal content ref.
    private mutating func internSmartLiteral(_ s: StaticString) -> ContentRef {
        let offset = storage.strings.count
        appendSmartConstant(s)
        let chunk = Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
        return storage.intern(chunk)
    }

    /// Replace a text node's literal with a constant smart-punctuation glyph.
    private mutating func setSmartLiteral(of nodeIdx: DocumentStorage.Index, _ s: StaticString) {
        let ref = internSmartLiteral(s)
        storage[nodeIdx].data = .literal(ref)
    }

    /// Handle a run of `-` under `.smart`. A run of two or more hyphens is decomposed into en/em dashes. A lone hyphen is left in the pending-text region. Returns the offset just past the run.
    private mutating func handleSmartHyphen(start: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, pendingTextStart: inout Int) -> Int {
        var runEnd = start
        while runEnd < end,
              content[runEnd] == UInt8(ascii: "-") {
            runEnd += 1
        }
        let numHyphens = runEnd - start
        if numHyphens < 2 {
            // Lone hyphen: leave it in pending text (identical output, no extra node).
            return runEnd
        }
        var enCount = 0
        var emCount = 0
        if numHyphens % 3 == 0 {
            emCount = numHyphens / 3
        } else if numHyphens % 2 == 0 {
            enCount = numHyphens / 2
        } else if numHyphens % 3 == 2 {
            enCount = 1
            emCount = (numHyphens - 2) / 3
        } else {
            enCount = 2
            emCount = (numHyphens - 4) / 3
        }
        flushPendingText(
            start: pendingTextStart,
            end: start,
            content: content,
            into: parent
        )
        let offset = storage.strings.count
        for _ in 0..<emCount {
            appendSmartConstant(Self.emDash)
        }
        for _ in 0..<enCount {
            appendSmartConstant(Self.enDash)
        }
        let chunk = Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
        let ref = storage.intern(chunk)
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(ref))
        )
        storage.appendChild(textIdx, to: parent)
        // why: the node's content is arena-backed en/em-dash glyphs whose byte length differs from the source hyphen run; stamp the source span of the `-` run (`start..<runEnd`) so the dashes keep their source columns.
        stampInline(textIdx, start, runEnd, content: content)
        pendingTextStart = runEnd
        return runEnd
    }

    /// Handle a `'` or `"` under `.smart`. Emits a text node carrying the initial curly form and, if the quote can open or close, pushes a delimiter so `processEmphasis` can resolve the open/close pairing.
    ///
    /// Returns the offset just past the quote.
    private mutating func handleQuoteDelim(char: UInt8, start: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, pendingTextStart: inout Int) throws (MarkdownDocument.Error) -> Int {
        let chunkStart = content.startOffset
        // Quotes are limited to a single delimiter character (unlike `*`/`_`/`~` runs).
        let runEnd = start + 1
        let beforeChar: UInt8 = if start > chunkStart { content[start - 1] } else { UInt8(ascii: "\n") }
        let afterChar: UInt8 = if runEnd < end { content[runEnd] } else { UInt8(ascii: "\n") }
        let beforeIsNBSP = beforeChar == 0xA0 && start - 2 >= chunkStart && content[start - 2] == 0xC2
        let afterIsNBSP = afterChar == 0xC2 && runEnd + 1 < end && content[runEnd + 1] == 0xA0
        let beforeIsSpace = beforeChar.isASCIISpace || beforeIsNBSP
        let beforeIsPunct = beforeChar.isASCIIPunct
        let afterIsSpace = afterChar.isASCIISpace || afterIsNBSP
        let afterIsPunct = afterChar.isASCIIPunct
        let leftFlanking = !afterIsSpace && (!afterIsPunct || beforeIsSpace || beforeIsPunct)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunct || afterIsSpace || afterIsPunct)
        // Quote-specific flanking rules.
        let canOpen = leftFlanking && !rightFlanking && beforeChar != UInt8(ascii: "]") && beforeChar != UInt8(ascii: ")")
        let canClose = rightFlanking
        // Initial curly form: `'` is always a right single quote (apostrophe); `"` is a closing quote when it can close, otherwise an opening quote.
        let literal: StaticString
        if char == UInt8(ascii: "'") {
            literal = Self.rightSingleQuote
        } else {
            literal = canClose ? Self.rightDoubleQuote : Self.leftDoubleQuote
        }
        flushPendingText(
            start: pendingTextStart,
            end: start,
            content: content,
            into: parent
        )
        let ref = internSmartLiteral(literal)
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(ref))
        )
        storage.appendChild(textIdx, to: parent)
        // why: the node's content is the arena-backed curly glyph (3 UTF-8 bytes), but its source span is the single straight-quote byte at `start`; stamp that 1-byte source range so the quote keeps its column.
        stampInline(textIdx, start, runEnd, content: content)
        if canOpen || canClose {
            let prev = lastDelim
            let newIdx = delimiters.count
            delimiters.append(DelimiterRecord(
                character: char,
                // The curly glyph is 3 UTF-8 bytes; recording that as the delimiter length makes the rule-of-three opener check (`length % 3 == 0`) always admit a quote pairing.
                length: 3,
                canOpen: canOpen,
                canClose: canClose,
                inlText: textIdx,
                virtualStart: start,
                virtualEnd: runEnd,
                previous: prev,
                next: nil
            ))
            if let prev {
                delimiters[prev].next = newIdx
            }
            lastDelim = newIdx
        }
        pendingTextStart = runEnd
        return runEnd
    }

    // MARK: - Code spans

    private struct CodeSpanMatch {
        var content: Chunk      // the code-span literal (with one-space-each-side trimmed if applicable)
        var afterClose: Int     // offset just past the closing backtick run
        var backtickCount: Int  // number of backticks in the opening/closing run
    }

    /// Match a code span starting at `start` (which must point at a backtick). Returns the resulting content chunk and the offset just past the closing backtick run, or `nil` if no closing run of equal length exists in `start..<end`.
    ///
    /// Flag-ON (`.cmarkBugCompatibility`) this reproduces cmark's per-subject backtick-closer cache (`scan_to_closing_backticks`, swift-cmark `src/inlines.c`): a stale "no closer here" record makes cmark MISS some valid later same-length spans after an unmatched longer run has scanned to the end. Flag-OFF the search is spec-correct greedy matching, unchanged - it finds every valid span.
    private mutating func matchCodeSpan(start: Int, end: Int, content: borrowing ContentSpan) -> CodeSpanMatch? {
        let openEnd = scanBacktickRun(start: start, end: end, content: content)
        let runLength = openEnd - start

        let bugCompat = storage.options.contains(.cmarkBugCompatibility)
        if bugCompat {
            // cmark step 1: the closer cache has no slot past MAXBACKTICKS, so a longer run is never an opener.
            if runLength > Self.codeSpanMaxBacktickRun {
                return nil
            }
            // cmark step 2 (early bail): a prior scan already reached the content end for this length, and the latest run start it recorded is at/before this opener - so there is no closer of this length at/after here. Skip the rescan (the stale-cache miss).
            if codeSpanScannedForBackticks && codeSpanBackticks[runLength] <= openEnd {
                return nil
            }
        }

        // Find a matching same-length backtick run after `openEnd`.
        var i = openEnd
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "`") {
                let closeEnd = scanBacktickRun(start: i, end: end, content: content)
                let closeLength = closeEnd - i
                // cmark step 3: record this run's START as the latest known closer position for its length.
                if bugCompat && closeLength <= Self.codeSpanMaxBacktickRun {
                    codeSpanBackticks[closeLength] = i
                }
                if closeLength == runLength {
                    // Return RAW content; the caller normalizes newlines and applies the single-space-strip rule (in that order) since the strip needs the post-normalize bytes to compare against.
                    let contentChunk = content.chunk(
                        offset: openEnd,
                        length: i - openEnd
                    )
                    return CodeSpanMatch(content: contentChunk, afterClose: closeEnd, backtickCount: runLength)
                }
                i = closeEnd
                continue
            }
            i += 1
        }
        // cmark step 4: reached the content end without a closer. Remember it so any later open short-circuits at step 2.
        if bugCompat {
            codeSpanScannedForBackticks = true
        }
        return nil
    }

    /// Scan `start..<end` for the run of backticks beginning at `start`. Returns the offset just past the last consecutive backtick.
    private func scanBacktickRun(start: Int, end: Int, content: borrowing ContentSpan) -> Int {
        var i = start
        while i < end, content[i] == UInt8(ascii: "`") {
            i += 1
        }
        return i
    }

    /// Apply CommonMark's code-span normalization to raw content.
    ///
    /// 1. Replace each `\r\n`, `\r`, or `\n` with a single space.
    /// 2. If the result begins AND ends with a space and isn't all spaces, strip one space from each end.
    ///
    /// Returns either the original chunk (if no changes) or a new chunk pointing at materialized bytes in `storage.strings`.
    private mutating func normalizeCodeSpanContent(_ chunk: Chunk) -> Chunk {
        // Quick scan for newlines.
        var hasNewline = false
        let endOff = chunk.offset + chunk.length
        for i in chunk.offset..<endOff {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") {
                hasNewline = true
                break
            }
        }
        var workChunk: Chunk
        if hasNewline {
            // Materialize with newlines replaced by spaces.
            let outOffset = storage.strings.count
            var i = chunk.offset
            while i < endOff {
                let b = readByte(at: i, in: chunk)
                if b == UInt8(ascii: "\r") {
                    storage.strings.append(UInt8(ascii: " "))
                    i += 1
                    if i < endOff,
                       readByte(at: i, in: chunk) == UInt8(ascii: "\n") {
                        // CRLF: collapse to one space.
                        i += 1
                    }
                    continue
                }
                if b == UInt8(ascii: "\n") {
                    storage.strings.append(UInt8(ascii: " "))
                    i += 1
                    continue
                }
                storage.strings.append(b)
                i += 1
            }
            workChunk = Chunk(
                offset: outOffset,
                length: storage.strings.count - outOffset,
                inSource: false
            )
        } else {
            workChunk = chunk
        }
        // Now apply the single-space-strip rule on the (possibly newline-normalized) chunk.
        return trimSingleSpaces(workChunk)
    }

    /// Apply CommonMark's "code-span single-space-strip" rule.
    ///
    /// If the content is non-empty, begins with a space, ends with a space, and contains at least one non-space byte, strip exactly one space from each end.
    private func trimSingleSpaces(_ chunk: Chunk) -> Chunk {
        let start = chunk.offset
        let end = chunk.range.upperBound
        if start < end,
           readByte(at: start, in: chunk) == UInt8(ascii: " "),
           readByte(at: end - 1, in: chunk) == UInt8(ascii: " ") {
            // Verify there's at least one non-space byte strictly between the two enclosing spaces. For 1- and 2-byte runs there are no inner bytes, so the strip rule doesn't apply.
            let innerStart = start + 1
            let innerEnd = end - 1
            var hasNonSpace = false
            if innerStart < innerEnd {
                for j in innerStart..<innerEnd {
                    let b = readByte(at: j, in: chunk)
                    if b != UInt8(ascii: " ") {
                        hasNonSpace = true
                        break
                    }
                }
            }
            if hasNonSpace {
                return chunk.extracting(1..<(chunk.length - 1))
            }
        }
        return chunk
    }

    // MARK: - Line breaks

    private struct LineBreakInfo {
        var isHard: Bool
        var textEnd: Int  // exclusive end of the pending-text region (excludes the marker bytes)
        var isBackslash: Bool = false  // hard break driven by a trailing `\` (vs 2+ trailing spaces)
    }

    /// Decide whether the `\n` at `newlineOffset` is a soft or hard line break. CommonMark 0.31 §6.6 / §6.7:
    /// - Hard if a `\` immediately precedes the newline (with at least one byte in the pending-text region).
    /// - Hard if 2+ spaces immediately precede the newline.
    /// - Soft otherwise.
    /// Returns the kind plus the offset at which to truncate pending text (excluding the marker bytes - backslash or trailing spaces).
    private func classifyLineBreak(at newlineOffset: Int, pendingTextStart: Int, content: borrowing ContentSpan) -> LineBreakInfo {
        // Backslash hard break.
        if newlineOffset > pendingTextStart {
            let prev = content[newlineOffset - 1]
            if prev == UInt8(ascii: "\\") {
                return LineBreakInfo(isHard: true, textEnd: newlineOffset - 1, isBackslash: true)
            }
        }
        // Trailing-space hard break.
        var i = newlineOffset
        var spaces = 0
        while i > pendingTextStart {
            let prev = content[i - 1]
            if prev == UInt8(ascii: " ") {
                spaces += 1
                i -= 1
            } else {
                break
            }
        }
        if spaces >= 2 {
            return LineBreakInfo(isHard: true, textEnd: i)
        }
        // Soft break: still trim trailing spaces (and tabs) so the rendered output doesn't preserve them.
        var softEnd = newlineOffset
        while softEnd > pendingTextStart {
            let prev = content[softEnd - 1]
            if prev == UInt8(ascii: " ") || prev == UInt8(ascii: "\t") {
                softEnd -= 1
            } else {
                break
            }
        }
        return LineBreakInfo(isHard: false, textEnd: softEnd)
    }

    // MARK: - Autolinks

    private struct AutolinkMatch {
        var interior: Range<Int>  // bytes between `<` and `>` (the visible text)
        var afterClose: Int       // offset just past the closing `>`
        var isEmail: Bool
    }

    /// Try to match an autolink starting at `start` (which points at `<`). CommonMark 0.31 §6.4. URI form first, email form as fallback.
    private func matchAutolink(start: Int, end: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        if let uri = matchURIAutolink(start: start, end: end, content: content) {
            return uri
        }
        return matchEmailAutolink(start: start, end: end, content: content)
    }

    /// URI autolink: `<scheme:rest>` where scheme is `[A-Za-z][A-Za-z0-9+.-]{1,31}` and rest contains no `<`, `>`, ASCII whitespace, or ASCII control characters.
    private func matchURIAutolink(start: Int, end: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        var i = start + 1
        if i >= end {
            return nil
        }
        let first = content[i]
        if !first.isASCIILetter {
            return nil
        }
        i += 1
        var schemeChars = 1
        while i < end, schemeChars < 32 {
            let b = content[i]
            let ok = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: "+")
                || b == UInt8(ascii: ".")
                || b == UInt8(ascii: "-")
            if !ok {
                break
            }
            i += 1
            schemeChars += 1
        }
        // Need at least 2-char scheme and a `:`.
        if schemeChars < 2 || i >= end {
            return nil
        }
        if content[i] != UInt8(ascii: ":") {
            return nil
        }
        i += 1
        // Scan body until `>`.
        let bodyStart = start + 1
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: ">") {
                return AutolinkMatch(
                    interior: bodyStart..<i,
                    afterClose: i + 1,
                    isEmail: false
                )
            }
            if b == UInt8(ascii: "<") || b == UInt8(ascii: " ") || b == UInt8(ascii: "\t")
                || b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") || b < 0x20 || b == 0x7F {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Email autolink: a relaxed approximation of the CommonMark email pattern. `<local@domain>` with `local` from a generous punctuation set and `domain` made of dot-separated labels. We don't enforce the full RFC here - pragmatic matches at the cost of some divergence from the spec.
    private func matchEmailAutolink(start: Int, end: Int, content: borrowing ContentSpan) -> AutolinkMatch? {
        var i = start + 1
        let bodyStart = i
        // Local part: 1+ local-allowed chars, no `@`.
        var localChars = 0
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "@") {
                break
            }
            if !isEmailLocalChar(b) {
                return nil
            }
            i += 1
            localChars += 1
        }
        if localChars == 0 || i >= end {
            return nil
        }
        // `@`
        if content[i] != UInt8(ascii: "@") {
            return nil
        }
        i += 1
        // Domain: 1+ labels separated by `.`. Each label: letter/digit, optional letters/digits/hyphens, ending with letter/digit. Up to 63 chars per label.
        let domainStart = i
        let labelStart = i
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: ">") {
                break
            }
            i += 1
        }
        if i == domainStart || i >= end {
            return nil
        }
        // Validate domain structure.
        if !validateEmailDomain(range: labelStart..<i, content: content) {
            return nil
        }
        _ = labelStart
        return AutolinkMatch(
            interior: bodyStart..<i,
            afterClose: i + 1,
            isEmail: true
        )
    }

    private func isEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "!"), UInt8(ascii: "#"), UInt8(ascii: "$"),
             UInt8(ascii: "%"), UInt8(ascii: "&"), UInt8(ascii: "'"), UInt8(ascii: "*"),
             UInt8(ascii: "+"), UInt8(ascii: "/"), UInt8(ascii: "="), UInt8(ascii: "?"),
             UInt8(ascii: "^"), UInt8(ascii: "_"), UInt8(ascii: "`"), UInt8(ascii: "{"),
             UInt8(ascii: "|"), UInt8(ascii: "}"), UInt8(ascii: "~"), UInt8(ascii: "-"):
            return true
        default:
            return false
        }
    }

    private func validateEmailDomain(range: Range<Int>, content: borrowing ContentSpan) -> Bool {
        if range.isEmpty {
            return false
        }
        var i = range.lowerBound
        var labelStart = i
        var labelLen = 0
        while i <= range.upperBound {
            let atEnd = i == range.upperBound
            let b: UInt8 = atEnd ? UInt8(ascii: ".") : content[i]
            if b == UInt8(ascii: ".") {
                // End of label.
                if labelLen == 0 || labelLen > 63 {
                    return false
                }
                // Label can't start or end with hyphen.
                let firstByte = content[labelStart]
                let lastByte = content[i - 1]
                if firstByte == UInt8(ascii: "-") || lastByte == UInt8(ascii: "-") {
                    return false
                }
                if atEnd {
                    return true
                }
                labelStart = i + 1
                labelLen = 0
            } else {
                if !(b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-")) {
                    return false
                }
                labelLen += 1
            }
            i += 1
        }
        return true
    }

    /// Emit a `.link` node + a single `.text` child for an autolink match.
    ///
    /// For email forms, the URL gets a `mailto:` prefix and is materialized into the string arena. For URI forms, the URL chunk references the original interior bytes directly.
    private mutating func emitAutolink(auto: AutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let urlChunk: Chunk
        if auto.isEmail {
            // Build `mailto:` + interior into the string arena.
            let offset = storage.strings.count
            let prefix: StaticString = "mailto:"
            let prefixLen = prefix.utf8CodeUnitCount
            let prefixPtr = prefix.utf8Start
            for k in 0..<prefixLen {
                storage.strings.append(prefixPtr[k])
            }
            for j in auto.interior {
                storage.strings.append(content[j])
            }
            // Materialized into the arena, so `inSource: false` regardless of `content`'s buffer.
            urlChunk = Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
        } else {
            urlChunk = content.chunk(
                offset: auto.interior.lowerBound,
                length: auto.interior.count
            )
        }
        let textChunk = content.chunk(
            offset: auto.interior.lowerBound,
            length: auto.interior.count
        )
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        let linkIdx = storage.appendNode(
            NodeRecord(
                kind: .link,
                parent: parent,
                data: .link(url: urlRef, title: .empty)
            )
        )
        storage.appendChild(linkIdx, to: parent)
        // The link spans the whole `<…>`; the text child spans just the interior visible bytes.
        stampInline(linkIdx, auto.interior.lowerBound - 1, auto.afterClose, content: content)
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: linkIdx, data: .literal(textRef))
        )
        storage.appendChild(textIdx, to: linkIdx)
        stampInline(textIdx, auto.interior.lowerBound, auto.interior.upperBound, content: content)
    }

    // MARK: - Raw inline HTML

    /// Match raw inline HTML starting at `start` (which points at `<`). Returns the offset just past the closing `>`, or `nil` if the bytes do not form one of the six accepted patterns:
    ///
    /// - open tag: `<name attrs… />` / `<name>`
    /// - close tag: `</name>`
    /// - comment: `<!--…-->` (and the empty forms `<!-->` / `<!--->`)
    /// - processing instruction: `<?…?>`
    /// - declaration: `<!NAME …>`
    /// - CDATA section: `<![CDATA[…]]>`
    ///
    /// CommonMark 0.31 §6.6.
    private func matchInlineHTML(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        let after = start + 1
        if after >= end {
            return nil
        }
        let c = content[after]
        switch c {
        case UInt8(ascii: "!"):
            return matchHTMLBangForm(start: start, end: end, content: content)
        case UInt8(ascii: "?"):
            return matchHTMLProcessingInstruction(start: start, end: end, content: content)
        case UInt8(ascii: "/"):
            return matchHTMLCloseTag(start: start, end: end, content: content)
        default:
            if c.isASCIILetter {
                return matchHTMLOpenTag(start: start, end: end, content: content)
            }
            return nil
        }
    }

    /// Match an HTML open tag starting at `<`.
    ///
    /// Tagname `[A-Za-z][A-Za-z0-9-]*`, then any number of attributes (each preceded by `spacechar+`), then optional trailing whitespace, optional `/`, then `>`.
    private func matchHTMLOpenTag(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        var i = start + 1
        // Tag name.
        guard let afterName = scanTagName(start: i, end: end, content: content) else {
            return nil
        }
        i = afterName
        // Attributes.
        while i < end {
            let saved = i
            // Need at least one spacechar.
            let afterSpaces = skipSpaceChars(start: i, end: end, content: content)
            if afterSpaces == saved {
                break
            }
            // Then the attribute name (or we may just be skipping trailing whitespace before `/>` / `>`).
            guard let afterAttr = scanAttribute(start: afterSpaces, end: end, content: content) else {
                i = afterSpaces
                break
            }
            i = afterAttr
        }
        // Optional trailing whitespace, optional `/`, then `>`.
        i = skipSpaceChars(start: i, end: end, content: content)
        if i < end, content[i] == UInt8(ascii: "/") {
            i += 1
        }
        if i >= end {
            return nil
        }
        if content[i] != UInt8(ascii: ">") {
            return nil
        }
        return i + 1
    }

    /// Match an HTML close tag `</name spacechar* >` starting at `<`.
    private func matchHTMLCloseTag(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // Skip the leading `</`.
        var i = start + 2
        guard let afterName = scanTagName(
            start: i, end: end,
            content: content
        ) else {
            return nil
        }
        i = skipSpaceChars(start: afterName, end: end, content: content)
        if i >= end {
            return nil
        }
        if content[i] != UInt8(ascii: ">") {
            return nil
        }
        return i + 1
    }

    /// Dispatch `<!`-prefixed HTML forms: comment, CDATA, declaration.
    private func matchHTMLBangForm(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // start[0] == '<', start[1] == '!' guaranteed by caller.
        let i = start + 2
        if i >= end {
            return nil
        }
        let next = content[i]
        if next == UInt8(ascii: "-") {
            return matchHTMLComment(start: start, end: end, content: content)
        }
        if next == UInt8(ascii: "[") {
            return matchHTMLCDATA(start: start, end: end, content: content)
        }
        return matchHTMLDeclaration(start: start, end: end, content: content)
    }

    /// Match `<!--…-->`. Accepts the empty forms `<!-->` and `<!--->` per HTML5, then scans for the first `-->` terminator (rejecting NUL bytes in the body).
    private func matchHTMLComment(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // Need at least `<!--`.
        if start + 4 > end {
            return nil
        }
        if content[start + 2] != UInt8(ascii: "-") || content[start + 3] != UInt8(ascii: "-") {
            return nil
        }
        let bodyStart = start + 4
        // <!-->
        if bodyStart < end, content[bodyStart] == UInt8(ascii: ">") {
            return bodyStart + 1
        }
        // <!--->
        if bodyStart + 1 < end, content[bodyStart] == UInt8(ascii: "-"), content[bodyStart + 1] == UInt8(ascii: ">") {
            return bodyStart + 2
        }
        var i = bodyStart
        while i + 3 <= end {
            let b0 = content[i]
            if b0 == 0 {
                return nil
            }
            if b0 == UInt8(ascii: "-") && content[i + 1] == UInt8(ascii: "-") && content[i + 2] == UInt8(ascii: ">") {
                return i + 3
            }
            i += 1
        }
        return nil
    }

    /// Match `<![CDATA[…]]>`.
    private func matchHTMLCDATA(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // Need `<![CDATA[`.
        let prefixLen = 9
        if start + prefixLen > end {
            return nil
        }
        let prefix: StaticString = "<![CDATA["
        let prefixPtr = prefix.utf8Start
        for k in 0..<prefixLen {
            if content[start + k] != prefixPtr[k] {
                return nil
            }
        }
        var i = start + prefixLen
        while i + 3 <= end {
            let b0 = content[i]
            if b0 == 0 {
                return nil
            }
            if b0 == UInt8(ascii: "]")
                && content[i + 1] == UInt8(ascii: "]")
                && content[i + 2] == UInt8(ascii: ">") {
                return i + 3
            }
            i += 1
        }
        return nil
    }

    /// Match `<!NAME …>` where NAME is `[A-Z]+`, followed by at least one spacechar, any non-`>` non-NUL chars, then `>`.
    private func matchHTMLDeclaration(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        var i = start + 2
        var nameLen = 0
        while i < end {
            let b = content[i]
            if b.isUppercaseASCIILetter {
                nameLen += 1
                i += 1
            } else {
                break
            }
        }
        if nameLen == 0 {
            return nil
        }
        let afterSpaces = skipSpaceChars(
            start: i, end: end,
            content: content
        )
        if afterSpaces == i {
            return nil
        }
        i = afterSpaces
        while i < end {
            let b = content[i]
            if b == 0 {
                return nil
            }
            if b == UInt8(ascii: ">") {
                return i + 1
            }
            i += 1
        }
        return nil
    }

    /// Match `<?…?>`. Body may be empty; scans for the first `?>` terminator rejecting NUL bytes.
    private func matchHTMLProcessingInstruction(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        var i = start + 2
        while i + 2 <= end {
            let b0 = content[i]
            if b0 == 0 {
                return nil
            }
            if b0 == UInt8(ascii: "?")
                && content[i + 1] == UInt8(ascii: ">") {
                return i + 2
            }
            i += 1
        }
        return nil
    }

    /// Scan `[A-Za-z][A-Za-z0-9-]*`. Returns the offset just past the last tag-name byte, or `nil` if the first byte isn't a letter.
    private func scanTagName(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        if start >= end {
            return nil
        }
        let first = content[start]
        if !first.isASCIILetter {
            return nil
        }
        var i = start + 1
        while i < end {
            let b = content[i]
            let ok = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: "-")
            if !ok {
                break
            }
            i += 1
        }
        return i
    }

    /// Scan one attribute: `attributename attributevaluespec?` (caller has already consumed the leading `spacechar+`). Returns the offset just past the attribute, or `nil` if no attribute name is present.
    private func scanAttribute(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // attributename = [a-zA-Z_:][a-zA-Z0-9:._-]*
        if start >= end {
            return nil
        }
        let first = content[start]
        let isFirstChar = first.isASCIILetter || first == UInt8(ascii: "_") || first == UInt8(ascii: ":")
        if !isFirstChar {
            return nil
        }
        var i = start + 1
        while i < end {
            let b = content[i]
            let ok = b.isASCIILetter
                || b.isASCIIDigit
                || b == UInt8(ascii: ":")
                || b == UInt8(ascii: ".")
                || b == UInt8(ascii: "_")
                || b == UInt8(ascii: "-")
            if !ok {
                break
            }
            i += 1
        }
        // Optional value spec: spacechar* '=' spacechar* attributevalue
        let savedAfterName = i
        let afterSpace1 = skipSpaceChars(
            start: i, end: end,
            content: content
        )
        if afterSpace1 < end,
           content[afterSpace1] == UInt8(ascii: "=") {
            let afterEq = afterSpace1 + 1
            let afterSpace2 = skipSpaceChars(
                start: afterEq, end: end,
                content: content
            )
            guard let afterValue = scanAttributeValue(
                start: afterSpace2, end: end,
                content: content
            ) else {
                return nil
            }
            return afterValue
        }
        return savedAfterName
    }

    /// Scan an attribute value: unquoted, single-quoted, or double-quoted.
    private func scanAttributeValue(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        if start >= end {
            return nil
        }
        let first = content[start]
        if first == UInt8(ascii: "'") || first == UInt8(ascii: "\"") {
            var i = start + 1
            while i < end {
                let b = content[i]
                if b == 0 {
                    return nil
                }
                if b == first {
                    return i + 1
                }
                i += 1
            }
            return nil
        }
        // Unquoted value: 1+ of [^ \t\r\n\v\f"'=<>`\x00].
        var i = start
        var count = 0
        while i < end {
            let b = content[i]
            if b == 0 {
                break
            }
            if b.isASCIISpace
                || b == UInt8(ascii: "\"")
                || b == UInt8(ascii: "'")
                || b == UInt8(ascii: "=")
                || b == UInt8(ascii: "<")
                || b == UInt8(ascii: ">")
                || b == UInt8(ascii: "`") {
                break
            }
            count += 1
            i += 1
        }
        if count == 0 {
            return nil
        }
        return i
    }

    /// Skip zero or more spacechar bytes. Spacechar = ` `, `\t`, `\n`, `\r`, VT (0x0B), FF (0x0C). Returns the offset just past the run.
    private func skipSpaceChars(start: Int, end: Int, content: borrowing ContentSpan) -> Int {
        var i = start
        while i < end {
            let b = content[i]
            if !b.isASCIISpace {
                break
            }
            i += 1
        }
        return i
    }

    // MARK: - GFM extended autolinks

    /// Form of a matched GFM autolink - affects how the destination URL is built when the node is emitted (`www.` needs a synthetic `http://` prefix; emails need `mailto:`).
    private enum GFMAutolinkForm {
        case uri      // already has http:// or https:// or ftp:// prefix
        case www      // needs http:// synthesized
        case email    // needs mailto: synthesized
    }

    /// Result of a GFM bare-URL / email match. Carries the visible text range (used for the link's child `.text` node) plus the form so the emit step knows whether to synthesize a scheme prefix.
    private struct GFMAutolinkMatch {
        var urlStart: Int
        var urlEnd: Int
        var form: GFMAutolinkForm
    }

    /// Dispatch a GFM autolink trial based on the trigger byte. Returns nil if no autolink starts at / contains `cursor`.
    private func matchGFMAutolink(trigger: UInt8, cursor: Int, end: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        switch trigger {
        case UInt8(ascii: ":"):
            return matchGFMSchemeAutolink(
                colon: cursor, end: end,
                content: content
            )
        case UInt8(ascii: "w"), UInt8(ascii: "W"):
            return matchGFMWWWAutolink(
                start: cursor, end: end,
                content: content
            )
        case UInt8(ascii: "@"):
            return matchGFMEmailAutolink(
                at: cursor, end: end,
                content: content
            )
        default:
            return nil
        }
    }

    /// `:`-triggered: looks back for `http`/`https`/`ftp`, then forward for `//` and a URL body.
    private func matchGFMSchemeAutolink(colon: Int, end: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let chunkStart = content.startOffset
        if colon + 2 >= end {
            return nil
        }
        if content[colon + 1] != UInt8(ascii: "/") || content[colon + 2] != UInt8(ascii: "/") {
            return nil
        }
        guard let schemeStart = matchSchemeBackward(colon: colon, content: content) else {
            return nil
        }
        if schemeStart > chunkStart {
            let pre = content[schemeStart - 1]
            if !isValidGFMPreceding(pre) {
                return nil
            }
        }
        let urlEnd = scanGFMURLBody(start: colon + 3, end: end, content: content)
        let trimmedEnd = trimTrailingPunctuation(urlStart: schemeStart, urlEnd: urlEnd, content: content)
        if trimmedEnd <= colon + 3 {
            return nil
        }
        if !chunkContainsDot(start: colon + 3, end: trimmedEnd, content: content) {
            return nil
        }
        return GFMAutolinkMatch(
            urlStart: schemeStart,
            urlEnd: trimmedEnd,
            form: .uri
        )
    }

    /// Find the start position of `http`, `https`, or `ftp` ending just before `colon`. Returns the scheme's first-byte offset, or nil.
    private func matchSchemeBackward(colon: Int, content: borrowing ContentSpan) -> Int? {
        let chunkStart = content.startOffset
        if colon - 5 >= chunkStart,
           bytesEqual(at: colon - 5, target: "https", content: content) {
            return colon - 5
        }
        if colon - 4 >= chunkStart,
           bytesEqual(at: colon - 4, target: "http", content: content) {
            return colon - 4
        }
        if colon - 3 >= chunkStart,
           bytesEqual(at: colon - 3, target: "ftp", content: content) {
            return colon - 3
        }
        return nil
    }

    /// `w`/`W`-triggered: matches `www.` followed by a URL body.
    private func matchGFMWWWAutolink(start: Int, end: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let chunkStart = content.startOffset
        if start > chunkStart {
            let pre = content[start - 1]
            if !isValidGFMPreceding(pre) {
                return nil
            }
        }
        if start + 4 > end {
            return nil
        }
        if !bytesEqual(at: start, target: "www.", content: content) {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: start + 4, end: end, content: content)
        let trimmedEnd = trimTrailingPunctuation(
            urlStart: start, urlEnd: urlEnd,
            content: content
        )
        if trimmedEnd <= start + 4 {
            return nil
        }
        return GFMAutolinkMatch(urlStart: start, urlEnd: trimmedEnd, form: .www)
    }

    /// `@`-triggered: scans backward for the email local part and forward for the domain.
    private func matchGFMEmailAutolink(at: Int, end: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        let chunkStart = content.startOffset
        var localStart = at
        while localStart > chunkStart {
            let b = content[localStart - 1]
            if isEmailLocalChar(b) {
                localStart -= 1
            } else {
                break
            }
        }
        if localStart == at {
            return nil
        }
        if localStart > chunkStart {
            let pre = content[localStart - 1]
            if !isValidGFMPreceding(pre) {
                return nil
            }
        }
        // Domain: 1+ labels separated by `.`.
        var i = at + 1
        let domainStart = i
        var hasDot = false
        while i < end {
            let b = content[i]
            if b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") {
                i += 1
            } else if b == UInt8(ascii: ".") {
                hasDot = true
                i += 1
            } else {
                break
            }
        }
        // Before any trailing-punct trim, the last char of the scanned domain must be alphanumeric or `.`. This is what rejects `a.b-c_d@a.b_` - the trailing `_` is not alpha/`.`, so the whole match dies before we could trim it off.
        if i <= at + 1 {
            return nil
        }
        let preTrimLast = content[i - 1]
        let preTrimAlnumOrDot = preTrimLast.isASCIILetter || preTrimLast.isASCIIDigit || preTrimLast == UInt8(ascii: ".")
        if !preTrimAlnumOrDot {
            return nil
        }
        let trimmedEnd = trimTrailingPunctuation(urlStart: localStart, urlEnd: i, content: content)
        if !hasDot || domainStart == i || trimmedEnd <= at + 1 {
            return nil
        }
        let last = content[trimmedEnd - 1]
        let lastIsAlnum = last.isASCIILetter || last.isASCIIDigit
        if !lastIsAlnum {
            return nil
        }
        // GFM rule: the last domain label must not contain `_` (#631 case 4). Walk back from `trimmedEnd` to find the start of the last label.
        var labelScan = trimmedEnd
        while labelScan > domainStart {
            let prev = content[labelScan - 1]
            if prev == UInt8(ascii: ".") {
                break
            }
            labelScan -= 1
        }
        for k in labelScan..<trimmedEnd {
            if content[k] == UInt8(ascii: "_") {
                return nil
            }
        }
        return GFMAutolinkMatch(urlStart: localStart, urlEnd: trimmedEnd, form: .email)
    }

    /// Emit a `.link` node + a single `.text` child for a GFM autolink match. `www.` and email forms get a synthetic scheme prefix (`http://` or `mailto:`) materialized into the string arena.
    private mutating func emitGFMAutolink(auto: GFMAutolinkMatch, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        let urlChunk: Chunk
        switch auto.form {
        case .uri:
            urlChunk = content.chunk(
                offset: auto.urlStart,
                length: auto.urlEnd - auto.urlStart
            )
        case .www:
            urlChunk = materializeAutolinkURL(
                prefix: "http://",
                start: auto.urlStart, end: auto.urlEnd,
                content: content
            )
        case .email:
            urlChunk = materializeAutolinkURL(
                prefix: "mailto:",
                start: auto.urlStart, end: auto.urlEnd,
                content: content
            )
        }
        let textChunk = content.chunk(
            offset: auto.urlStart,
            length: auto.urlEnd - auto.urlStart
        )
        let urlRef = storage.intern(urlChunk)
        let textRef = storage.intern(textChunk)
        let linkIdx = storage.appendNode(NodeRecord(
            kind: .link,
            parent: parent,
            data: .link(url: urlRef, title: .empty)
        ))
        storage.appendChild(linkIdx, to: parent)
        let textIdx = storage.appendNode(NodeRecord(
            kind: .text, parent: linkIdx, data: .literal(textRef)
        ))
        storage.appendChild(textIdx, to: linkIdx)
    }

    /// Append `prefix` + the content bytes of `start..<end` into `storage.strings`, returning a chunk pointing at the appended region.
    ///
    /// The bytes are read from `content` (the scratch/source view, independent of `storage.strings`) so the read region doesn't alias the buffer being appended to.
    private mutating func materializeAutolinkURL(prefix: StaticString, start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        let offset = storage.strings.count
        let prefixLen = prefix.utf8CodeUnitCount
        let prefixPtr = prefix.utf8Start
        for k in 0..<prefixLen {
            storage.strings.append(prefixPtr[k])
        }
        for j in start..<end {
            storage.strings.append(content[j])
        }
        return Chunk(
            offset: offset,
            length: storage.strings.count - offset,
            inSource: false
        )
    }

    /// Walk forward accepting non-whitespace, non-`<`, non-`>` bytes.
    private func scanGFMURLBody(
        start: Int,
        end: Int,
        content: borrowing ContentSpan
    ) -> Int {
        var i = start
        while i < end {
            let b = content[i]
            if b.isASCIISpace || b == UInt8(ascii: "<") || b == UInt8(ascii: ">") {
                break
            }
            i += 1
        }
        return i
    }

    /// Peel trailing `.,?:!*_~` and unmatched trailing `)` per the GFM autolink trim rules.
    private func trimTrailingPunctuation(urlStart: Int, urlEnd: Int, content: borrowing ContentSpan) -> Int {
        var i = urlEnd
        var changed = true
        while changed && i > urlStart {
            changed = false
            while i > urlStart {
                let b = content[i - 1]
                switch b {
                case UInt8(ascii: "."), UInt8(ascii: ","), UInt8(ascii: "?"),
                     UInt8(ascii: ":"), UInt8(ascii: "!"), UInt8(ascii: "*"),
                     UInt8(ascii: "_"), UInt8(ascii: "~"):
                    i -= 1
                    changed = true
                default:
                    break
                }
                let stopHere: Bool
                if i <= urlStart {
                    stopHere = true
                } else {
                    let again = content[i - 1]
                    switch again {
                    case UInt8(ascii: "."), UInt8(ascii: ","), UInt8(ascii: "?"),
                         UInt8(ascii: ":"), UInt8(ascii: "!"), UInt8(ascii: "*"),
                         UInt8(ascii: "_"), UInt8(ascii: "~"):
                        stopHere = false
                    default:
                        stopHere = true
                    }
                }
                if stopHere {
                    break
                }
            }
            var open = 0
            var close = 0
            for j in urlStart..<i {
                let b = content[j]
                if b == UInt8(ascii: "(") { open += 1 }
                else if b == UInt8(ascii: ")") { close += 1 }
            }
            while close > open && i > urlStart {
                let b = content[i - 1]
                if b == UInt8(ascii: ")") {
                    i -= 1
                    close -= 1
                    changed = true
                } else {
                    break
                }
            }
            // GFM rule: a trailing `&entity;`-like sequence is treated as separate text. If the URL ends with `;`, scan back for an `&` that delimits an entity candidate (only ASCII letters/digits between them).
            if i > urlStart, content[i - 1] == UInt8(ascii: ";") {
                var k = i - 2
                var ok = true
                while k >= urlStart {
                    let b = content[k]
                    if b == UInt8(ascii: "&") {
                        break
                    }
                    let isAlnum = b.isASCIILetter
                        || b.isASCIIDigit
                    if !isAlnum {
                        ok = false
                        break
                    }
                    k -= 1
                }
                if ok && k >= urlStart,
                   content[k] == UInt8(ascii: "&") {
                    i = k
                    changed = true
                }
            }
        }
        return i
    }

    private func chunkContainsDot(start: Int, end: Int, content: borrowing ContentSpan) -> Bool {
        var i = start
        while i < end {
            if content[i] == UInt8(ascii: ".") {
                return true
            }
            i += 1
        }
        return false
    }

    /// Allowlist of characters that may directly precede a GFM autolink trigger (`http://`, `www.`, `local@host`).
    ///
    /// Only whitespace, `*`, `_`, `~`, `(` count as valid boundaries; everything else (including `<`) disqualifies the autolink so it can't trigger inside an angle-bracket autolink that failed validation.
    private func isValidGFMPreceding(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
             UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "("):
            return true
        default:
            return false
        }
    }

    /// Compare bytes at `start..(start+target.utf8CodeUnitCount)` against the static-string target.
    private func bytesEqual(at start: Int, target: StaticString, content: borrowing ContentSpan) -> Bool {
        let len = target.utf8CodeUnitCount
        let ptr = target.utf8Start
        for k in 0..<len {
            if content[start + k] != ptr[k] {
                return false
            }
        }
        return true
    }

    /// Append a flat UTF-8 byte array to `bytes` and return a chunk pointing at the appended region.
    private static func appendUTF8Bytes(bytes: Bytes8, count: Int, into out: inout UniqueArray<UInt8>) -> Chunk {
        let offset = out.count
        for i in 0..<count {
            out.append(bytes[i])
        }
        return Chunk(offset: offset, length: count, inSource: false)
    }

    // MARK: - Helpers

    /// Emit a `.text` node spanning `start..<end` if non-empty.
    ///
    /// `rangeEnd` defaults to `end` but may be set larger to extend the node's *source range* past its content - e.g. the text node before a soft break or a trailing-space hard break owns the trailing whitespace that was stripped from its content (cmark stamps the text up to the newline), so the content is `[start, end)` while the range is `[start, rangeEnd)`. A backslash hard break is the exception: it passes `rangeEnd: nil`, so the text ends at its content, before the `\` that cmark consumes into the LINEBREAK.
    ///
    /// `emitEmptyStrippedWhitespace` (set by the line-break flush, soft OR trailing-space hard) governs the whitespace-only run, whose stripped content is empty (`end <= start`) but whose raw range `[start, rangeEnd)` still spans the trailing whitespace. Flag-OFF (spec-correct) such a run is dropped. Flag-ON reproduces a cmark quirk (Hyrum's Law): its text-flush path (swift-cmark `src/inlines.c` `parse_inline` ~1683-1694) creates a `.text` node from the run, then `cmark_chunk_rtrim` strips its content to empty at the line-end char but leaves the now-empty node in the tree carrying its pre-strip source range. That flush runs BEFORE `handle_newline` classifies the following break, so cmark emits the empty node identically for soft and trailing-space hard breaks (the `emptytext-*` and `brkhb-*` fuzzer pairs). So emit an empty `.text` node whose range is the raw `[start, rangeEnd)`. This fires whenever the pre-break run is empty: after a non-text inline (link/emphasis/code) the empty node survives standalone (`brkhb-emph`/`code`/`link`), and after a separately-emitted text node - the `emitBracketLiteral` `]`, whose return resets `pendingTextStart` past the bracket so the trailing spaces start a fresh run - `consolidateTextNodes` merges the empty node into that text, extending its end over the stripped spaces (how `brkhb-min`/`brkhb-text` stamp `]` to the newline). It does NOT fire for an ordinary contiguous text run, which absorbs its own trailing whitespace (#22) and stays non-empty (`end > start`).
    private mutating func flushPendingText(start: Int, end: Int, content: borrowing ContentSpan, into parent: DocumentStorage.Index, rangeEnd: Int? = nil, emitEmptyStrippedWhitespace: Bool = false) {
        if end <= start {
            if emitEmptyStrippedWhitespace,
               let rangeEnd, rangeEnd > start,
               storage.options.contains(.cmarkBugCompatibility) {
                let emptyRef = storage.intern(content.chunk(offset: start, length: 0))
                let textIdx = storage.appendNode(
                    NodeRecord(kind: .text, parent: parent, data: .literal(emptyRef))
                )
                storage.appendChild(textIdx, to: parent)
                stampInline(textIdx, start, rangeEnd, content: content)
            }
            return
        }
        let chunk = content.chunk(offset: start, length: end - start)
        let chunkRef = storage.intern(chunk)
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(chunkRef))
        )
        storage.appendChild(textIdx, to: parent)
        stampInline(textIdx, start, rangeEnd ?? end, content: content)
    }

    /// Stamp `node`'s source range from *virtual* content offsets, resolving each through `content.sourceOffset(ofVirtual:)`.
    ///
    /// This is the only stamping path, shared by every inline node (leaf and wrapper - matching cmark, whose `S_insert_emph` derives a wrapper's range from its child columns in the same buffer map): a single-segment source span maps identity (byte offsets pass through unchanged), single-segment arena maps to nil (skipped) unless its arena→source run map resolves it, and a multi-segment span walks its segment list - so a construct inside a multi-line blockquote/list paragraph gets real source positions. `end` is *exclusive* (one past the last byte), so the last content byte `end - 1` is resolved and incremented; this also maps an `end` that lands on the synthetic line-join newline back to just past the preceding source byte.
    @inline(__always)
    mutating func stampInline(_ node: DocumentStorage.Index, _ start: Int, _ end: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, end > start,
              let s = content.sourceOffset(ofVirtual: start),
              let lastByte = content.sourceOffset(ofVirtual: end - 1) else {
            return
        }
        storage.setSourceStart(node, s)
        storage.setSourceEnd(node, lastByte + 1)
        // why: an inline node's range after a backslash hard break is stamped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). The byte-projected start/end above are the spec-correct positions; the explicit override below is the cmark quirk.
        //
        // Flag ON reproduces a cmark quirk (Hyrum's Law): after a backslash hard break, cmark's inline cursor keeps counting columns flat (its `handle_backslash` never resets `subj->line` / `subj->column_offset`, unlike `handle_newline` for soft/space breaks). No source byte projects onto that flat column, so stamp explicit start/end positions from the flat cursor for every node after such a break. The flat cursor is measured in CONTENT offsets (`start` / `end - 1`), not the source offsets `s` / `lastByte`: for single-segment source content the two coincide (identity map), but for a multi-segment continuation the stripped prefix/indent means the content offset - which cmark counted - is what lands on cmark's flat column, while the source offset would double-count the gap.
        //
        // Flag OFF is spec-correct: take no explicit positions, so the node keeps the byte-projected range above - its content projected onto its true physical line:column, which resets at the physical newline exactly like soft and trailing-space breaks do. Covers only `stampInline`'s node population; the strikethrough-zero-width and multi-line-link close-bracket end overrides are separate quirks not compounded here.
        if inlineSawBackslashHardBreak && storage.options.contains(.cmarkBugCompatibility) {
            storage.setExplicitStart(node, flatInlinePosition(ofContent: start, content: content))
            var endPosition = flatInlinePosition(ofContent: end - 1, content: content)
            endPosition.column += 1  // half-open end: one past the last content byte's column
            storage.setExplicitEnd(node, endPosition)
        } else if storage.options.contains(.cmarkBugCompatibility),
                  content.isReindentedRun(ofVirtual: end - 1),
                  let physBase = content.physicalRunBase(ofVirtual: end - 1),
                  sourceLineNumber(ofSource: lastByte + 1) > sourceLineNumber(ofSource: physBase),
                  !runContainsNewline(start, end, content: content) {
            // why: Quirk E's continuation re-indent (see `BlockParser.addLineSegment`) remaps a re-indented continuation line's surviving content to the block's fixed content column, which can push the run's mapped source offsets rightward past its own physical line's byte extent. cmark works in (line, column) space, so it keeps the run on its own physical line at its re-indented column + width; the rewrite's byte-offset end (`lastByte + 1`) instead projects onto a LATER physical line - e.g. `> bar\nbaz\nqux` flag-ON: `baz`'s re-indented last content byte projects to line 3's start byte, so `lastByte + 1` reports `@3:2` for cmark's `@2:6`. Anchor the stamp on the run's PHYSICAL base line (`physBase` = the segment's byte-read offset, via `physicalRunBase`), NOT on the re-indented base (`sourceRunBase`) or the start byte `s`: the physical base is literally where the run's bytes are read from, so it ALWAYS sits on the run's true physical source line - even when the re-indent shift EXCEEDS the continuation line's content width and pushes the re-indented base itself past that line's `\n`. `- e\nc\ng` flag-ON: the 1-char middle line `c` re-indents to content column 3 (line-2 start + the `- ` marker's 2 cols), whose byte is line 3's `g`, so BOTH the re-indented base and `lastByte + 1` land on line 3 - the earlier `sourceRunBase`-anchored guard then collapsed to false (`line(lastByte+1) == line(runBase)`) and fell through to the `@3:1` byte-projected overshoot. `physBase` stays on line 2, so the guard fires and the stamp lands there. The re-indented COLUMN comes from the mapped source offset measured against the PHYSICAL line start (`s - lineStartByte(physBase) + 1` = cmark's block content column), which is correct even when `s` itself sits past the physical line. This also handles the smart-punct / entity split (` - b\n  -- c\n  d`: `--`→`–` then ` c`) where the fragment's own start `s` maps past the line boundary; `physBase` stays on the fragment's physical line and the end lands there at `startColumn + width` (`@2:10`). The `isReindentedRun` guard restricts this correction to a genuinely re-indented run (`seg.sourceOffset != seg.offset`): a multi-line CONTIGUOUS segment (`a\nb`, `sourceOffset == offset`, from a top-level paragraph's source-adjacent lines) spans several physical lines under ONE base on its FIRST line, so an interior-line run's byte projection is already exact and reporting it not-re-indented keeps that exact projection. The `!runContainsNewline` guard restricts this to a single-physical-line TEXT run (a re-indented continuation text run carries no interior newline - the joining soft break is a separate node), so `start` and `end - 1` share one segment and one `physBase`; a genuinely multi-line WRAPPER node whose closer overshoots is handled by the next branch (which anchors on the re-indented base and stays a documented gap when it overshoots). When the re-indented offset does NOT overshoot its physical line (the common re-indented run) this is byte-identical to the byte projection. Flag-OFF keeps the byte-projected end (spec-correct).
            let startLine = sourceLineNumber(ofSource: physBase)
            let startColumn = s - lineStartByte(ofSource: physBase) + 1
            // why: a MULTI-LINE inline (code span / emphasis) preceding this text run on the segment's FIRST physical line consumes that line within the same re-indented segment, so the run's START byte `s` maps past the line boundary too - it overshoots onto a LATER physical line exactly as `lastByte + 1` does (`> `\n`o\nx` flag-ON: after the multi-line `` ` ``…`` ` `` code span, `o`'s re-indented `s` projects to line 3's start byte, so the byte-projected start reports `@3:1` while cmark reports `@2:4`). Anchor the START on `physBase`'s physical line at its own re-indented column - the same flat `startColumn` the end uses - so the run stays whole on its physical line; leaving the start byte-projected while the end is corrected onto `physBase`'s line inverts the range (start `@3:1` > end `@2:5`), which renders position-less. When `s` does NOT overshoot (the common re-indented run, `s` on `physBase`'s line), this explicit start equals the byte projection (byte-identical to before). Flag-OFF keeps the byte-projected start (spec-correct).
            storage.setExplicitStart(node, MarkdownNode.SourcePosition(line: startLine, column: startColumn))
            storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: startLine, column: startColumn + (end - start)))
        } else if storage.options.contains(.cmarkBugCompatibility),
                  content.isReindentedRun(ofVirtual: end - 1),
                  let runBase = content.sourceRunBase(ofVirtual: end - 1),
                  sourceLineNumber(ofSource: lastByte + 1) > sourceLineNumber(ofSource: runBase),
                  runContainsNewline(start, end, content: content) {
            // why: a softbreak-spanning WRAPPER (emphasis/strong/link/image) whose closer sits on a re-indented continuation line has the same Quirk-E overshoot as the single-line text run above, but its start and closer are on DIFFERENT logical lines, so the start-line + width formula can't express its end. The wrapper's byte-projected end (`lastByte + 1`) projects the re-indented closer past its physical line onto a LATER one - e.g. `  Foo *bar\nbaz*\n====` flag-ON: the closer `*`'s re-indented byte lands at or past line 2's newline, so `lastByte + 1` reports `@3:2` for cmark's `@2:7` (the underline line). cmark keeps the closer on its own line at the re-indented column (`closer_inl->end_column`). Anchor the end line on the closer run's base source offset (`runBase`) and take the column arithmetically from the mapped byte (`lastByte`), which stays consistent with `runBase` even when the byte overshoots the line: `endColumn = (lastByte - lineStartByte(runBase) + 1) + 1` (column of the last content byte, then half-open). This is correct only while `runBase` itself is still on the closer's physical line, which the `lastByte + 1` vs `runBase` line comparison enforces: if a large re-indent (`currentContentIndent` exceeding the continuation line's content width) has already pushed `runBase` off its own line, the comparison collapses to false and the node falls through to the plain byte projection - the same deferred divergence the byte path already had (and the deferred nested-container gap `stampCloseBracketEnd` documents), never a wrong-line stamp or a crash. The `isReindentedRun` guard restricts the correction to a genuinely re-indented closer run (`seg.sourceOffset != seg.offset`), for the same reason as the single-line branch above: a wrapper closing inside a multi-line CONTIGUOUS segment (`*a\nb*`, `sourceOffset == offset`) has an exact byte-projected end already, and its `runBase` sits on the segment's FIRST line, so the overshoot comparison would mis-fire and collapse the closer onto line 1 - reporting it not-re-indented keeps the exact byte projection (`*a\nb*` -> `@1:1-2:3`). The `runContainsNewline` guard (evaluated last - it's O(width), off the common path) restricts this to a genuine multi-line wrapper; a single-physical-line run took the branch above. This is the multi-line counterpart of that branch and of `stampCloseBracketEnd`. Flag-OFF keeps the byte-projected end (spec-correct): with the re-indent off, the closer maps to its true byte, whose `+ 1` stays on the closer's own line.
            let endLine = sourceLineNumber(ofSource: runBase)
            let endColumn = (lastByte - lineStartByte(ofSource: runBase) + 1) + 1
            storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: endLine, column: endColumn))
        }
    }

    /// Whether the content run `[start, end)` contains an interior newline byte.
    ///
    /// Distinguishes a re-indented continuation *text* run (no interior newline - the joining soft break is a separate node) from a genuinely multi-line wrapper node (link/emphasis whose content spans a soft break). Only consulted flag-ON when a run's byte-projected end has already been found to cross a physical line, so the O(width) scan is off the common path.
    private func runContainsNewline(_ start: Int, _ end: Int, content: borrowing ContentSpan) -> Bool {
        var i = start
        while i < end {
            if content[i] == UInt8(ascii: "\n") {
                return true
            }
            i += 1
        }
        return false
    }

    /// cmark's flat inline (line, column) for CONTENT offset `off`, counting backslash-hard-break newlines as columns (cmark's inline cursor never resets there) while soft / trailing-space breaks reset it to the next line. Content offsets (not source offsets) are the coordinate: they exclude the stripped prefixes/indents of multi-segment continuation lines, which is exactly what cmark's flat cursor never counted. Every logical line (index 0 and each soft/space-break reset) is based at its own re-indented block-content column via `flatBaseColumn` - cmark's fixed block-content column (`block_offset + 1`) for the block's first line and every *matched* continuation, plus the preserved residual whitespace of a *lazy* continuation (which cmark keeps in its paragraph buffer and counts flat). Valid only while `inlineFlatColumnTracking` is armed and `inlineLogicalLineStarts` is seeded (see `parseInline`).
    private func flatInlinePosition(ofContent off: Int, content: borrowing ContentSpan) -> MarkdownNode.SourcePosition {
        // Largest logical-line-start index `k` with `inlineLogicalLineStarts[k] <= off` (ascending, and [0] == block start <= any node offset). The list is one entry per soft/space break, so this walk is tiny.
        var k = 0
        while k + 1 < inlineLogicalLineStarts.count && inlineLogicalLineStarts[k + 1] <= off {
            k += 1
        }
        let logicalLineStart = inlineLogicalLineStarts[k]
        return MarkdownNode.SourcePosition(
            line: inlineBlockStartLine + k,
            column: (off - logicalLineStart) + flatBaseColumn(ofContent: logicalLineStart, content: content)
        )
    }

    /// The flat-cursor base column for the logical line beginning at CONTENT offset `logicalLineStart`: the column cmark's inline cursor assigns that line's first content byte.
    ///
    /// The block's first line and every *matched* continuation re-indent to the fixed block-content column (`inlineBlockStartColumn` = cmark's `block_offset + 1`), so this returns that. A *lazy* continuation is the exception: cmark's `add_line` copies from the offset where container-prefix matching stopped without advancing to the first non-space (blocks.c ~1408), so its preserved residual leading whitespace survives in cmark's paragraph buffer and shifts every following byte's flat column right by that residual (`- b\n \\\nc`: line 2's 1 leading space is below the list's 2-space content indent, so it stays a lazy continuation and cmark reports the post-break `c` at `@2:6`, one past the residual-free `@2:5`). The rewrite strips that residual from the CONTENT bytes (it lives only in the re-indented source mapping; see `BlockParser.addLineSegment`), so recover the residual from the line-start's own re-indented column: `sourceOffset` maps the byte to its block-content column + residual, and `physicalRunBase` anchors that column on the line's true physical source line even when a large re-indent pushes the mapped offset past the line's byte extent (the same anchor `stampInline`'s Quirk-E branch uses). Not re-indented (single-segment source, or a first line) → the block-content column.
    private func flatBaseColumn(ofContent logicalLineStart: Int, content: borrowing ContentSpan) -> Int {
        guard content.isReindentedRun(ofVirtual: logicalLineStart),
              let mappedSource = content.sourceOffset(ofVirtual: logicalLineStart),
              let physicalBase = content.physicalRunBase(ofVirtual: logicalLineStart) else {
            return inlineBlockStartColumn
        }
        return mappedSource - lineStartByte(ofSource: physicalBase) + 1
    }

    /// Give a matched link/image/attribute the flat close-bracket end column cmark reports when its `(...)` (destination/title/attrs) crosses a newline.
    ///
    /// cmark stamps a matched close-bracket node's `end_column = subj->pos + column_offset + block_offset` (swift-cmark `src/inlines.c` `handle_close_bracket`, ~1462-1491; the attribute form at ~1251-1253) WITHOUT running `handle_newline`'s per-line reset (~1507) while scanning `(...)`. Text softbreaks, code spans and raw HTML all *do* reset, so a newline inside `(...)` advances the buffer cursor past the next line's bytes while `end_column` keeps counting flat from the `]`'s line - overshooting that line's physical width. The rewrite's byte-offset range can't encode this (no source byte projects onto the `]`'s line at that column), so store an explicit end position.
    ///
    /// why: the multi-line link/image/attribute end column is stamped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). The mechanism it uses - an explicit end position (`setExplicitEnd`) that overrides the node's byte-projected end - stays unconditional; only whether this method sets one is gated.
    ///
    /// Flag ON reproduces the cmark quirk (Hyrum's Law): its link/image/attribute end column alone skips the newline reset that every other multi-line inline construct performs, so store the flat close-bracket column as an explicit end.
    ///
    /// Flag OFF is spec-correct: take no explicit end, so the node keeps the byte-projected end from its normal `stampInline(node, linkStart, linkEnd)` stamp - i.e. just past the `)` on the `)`'s own physical line (`[a](\n/u)` -> `Link @1:1-2:4`, the `)` on line 2), like every other construct whose interior newline resets the column.
    ///
    /// Scoped to top-level blocks (`block_offset == 0`, so `blockStartColumn == 1`). A link nested in a blockquote/list has its `(...)` newline in `[closeBracket, linkEnd)` too, so it still takes this path (flag ON) and gets an explicit end - but computed *without* the container's `block_offset`, so its column is short by the container indent and stays divergent (as it already was on the byte path). Threading `block_offset` to retire nested links is the documented Stage-2 gap (`docs/inline-end-column-exploration.md` §4); nested multi-line links are not in the fuzz corpus.
    @inline(__always)
    mutating func stampCloseBracketEnd(_ node: DocumentStorage.Index, closeBracket: Int, linkEnd: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, storage.options.contains(.cmarkBugCompatibility) else { return }
        // Only the non-resetting case diverges: a newline between the `]` and just past the close form. Single-line forms - and newline-in-*text* links, whose newline precedes the `]` - project identically from the end byte, so leave them on the byte path (byte-identical to today).
        var crossedNewline = false
        var i = closeBracket
        while i < linkEnd {
            if content[i] == UInt8(ascii: "\n") {
                crossedNewline = true
                break
            }
            i += 1
        }
        guard crossedNewline else { return }
        // end line: the physical source line of the closing `]` (cmark's `inl->end_line = subj->line`, frozen before the `(...)` scan). Bail to the byte path if the `]` has no source image.
        guard let closeBracketSource = content.sourceOffset(ofVirtual: closeBracket) else { return }
        let endLine = sourceLineNumber(ofSource: closeBracketSource)
        // end column: flat buffer column counted from the start of the `]`'s BUFFER line through just past the close form, without resetting at the interior `(...)` newline. `+ 1` is `blockStartColumn` (top-level `block_offset` 0) and cmark's converter `+1`.
        let lineStart = bufferLineStart(ofBuffer: closeBracket, content: content)
        let endColumn = (linkEnd - lineStart) + 1
        storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: endLine, column: endColumn))
    }

    /// Give a raw inline-HTML span whose token crosses a newline the flat end column cmark reports: its LAST byte's column, one short of the half-open (last-byte + 1) that single-line spans and every other node use.
    ///
    /// cmark stamps a raw-HTML node's end via `make_raw_html` (swift-cmark `src/inlines.c` `handle_pointy_brace`, ~1015) then `adjust_subj_node_newlines` (~304). When the matched token contains a newline, `adjust_subj_node_newlines` OVERWRITES `end_column` with `since_newline` - a raw count of bytes since the last interior newline - WITHOUT the `+ 1 + column_offset + block_offset` that `make_literal` (~106) applies to a single-line node's end column. The result lands on the last content byte's own column (the closing `>`'s column), one short of the half-open end every other multi-line construct reports. The rewrite's byte-offset end (`lastByte + 1`) is that half-open column; drop the `+1` by stamping an explicit end at the last byte's projected line:column.
    ///
    /// why: the multi-line inline-HTML end column is stamped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). The mechanism it uses - an explicit end position (`setExplicitEnd`) that overrides the node's byte-projected end - stays unconditional; only whether this method sets one is gated.
    ///
    /// Flag ON reproduces the cmark quirk (Hyrum's Law): a newline-crossing raw-HTML span reports its last byte's column as the end. A single-line span carries no interior newline, so `adjust_subj_node_newlines` is a no-op and the half-open end stands - this method returns early for it (byte-identical to today).
    ///
    /// Flag OFF is spec-correct: take no explicit end, so the node keeps the byte-projected half-open end from its normal `stampInline(node, cursor, htmlEnd)` stamp.
    ///
    /// Scoped to top-level blocks like `stampCloseBracketEnd`: a raw-HTML span nested in a blockquote/list still takes this path (flag ON), but its column is computed without the container's `block_offset`, so it stays short by the container indent (as it already was on the byte path) - the same documented nested-container gap. Not in the fuzz corpus.
    ///
    /// Does NOT compound with the backslash-hard-break quirk: when `inlineSawBackslashHardBreak` is set, `stampInline` has already stamped this node's start AND end from the flat cursor (that quirk's coordinate frame), and this method then overwrites the end with the physical byte projection - a mixed frame matching neither cmark's flat compound end nor the pre-break byte end. A multi-line raw-HTML span *after* a backslash hard break therefore stays divergent flag-ON (it already was), and reproducing it faithfully needs a flat-frame end column, not this physical one - deferred like the nested-container gap. Not in the fuzz corpus (no `htmlml-*` pair pairs a backslash break with a multi-line span).
    @inline(__always)
    mutating func stampInlineHTMLEnd(_ node: DocumentStorage.Index, start: Int, htmlEnd: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, storage.options.contains(.cmarkBugCompatibility) else { return }
        // Only a span with an interior newline diverges: a single-line span's half-open end projects identically to cmark's un-adjusted end column, so leave it on the byte path (byte-identical to today).
        guard runContainsNewline(start, htmlEnd, content: content) else { return }
        // The last content byte (the closing `>`, or the terminator of a comment/CDATA/PI/declaration) carries cmark's end column. Bail to the byte path if it has no source image.
        guard let lastByte = content.sourceOffset(ofVirtual: htmlEnd - 1) else { return }
        let endLine = sourceLineNumber(ofSource: lastByte)
        let endColumn = lastByte - lineStartByte(ofSource: lastByte) + 1
        storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: endLine, column: endColumn))
    }

    /// Give a code span whose matched extent crosses a newline the end position cmark reports: its end line advanced by the interior newline count, and an end column of the raw bytes since the last interior newline - the same `adjust_subj_node_newlines` mechanism as Quirk G's inline HTML (`stampInlineHTMLEnd`), applied to the other raw-scan construct.
    ///
    /// cmark stamps a code node's end via `make_code` (`make_literal`, swift-cmark `src/inlines.c` ~106) then `adjust_subj_node_newlines` (~304, called from `handle_backticks` ~421). When the matched span contains a newline, `adjust_subj_node_newlines` does `end_line += newlines` and OVERWRITES `end_column = since_newline` - a raw count of buffer bytes after the last interior newline (`count_newlines`, ~281), with NO `+ 1 + column_offset + block_offset` re-added. The reference converter then reports `end_column + 1 + backtick_count` (`CommonMarkConverter.range`), which reduces to `afterClose - lastInteriorNewline` measured in the rewrite's CONTENT-offset space: cmark's paragraph buffer strips each continuation line's leading whitespace (`add_line` copies from `parser->offset`), exactly as the rewrite's multi-segment content joins the stripped source lines, so the two byte counts coincide byte-for-byte.
    ///
    /// This is why the column must come from CONTENT-offset arithmetic, NOT `stampInlineHTMLEnd`'s physical last-byte source projection: with leading whitespace on the closing line (` `\n `x`) the physical column re-includes the stripped indent and overshoots by it (`@2:3` for cmark's `@2:2`), while the flat content count matches. For a *matched* blockquote/list continuation, cmark advances to `first_nonspace` before `add_line` (blocks.c ~1464), so its buffer strips the container prefix exactly as the rewrite's content space does - the counts coincide and there is no `block_offset` gap (unlike `stampInlineHTMLEnd`, whose physical-column basis includes it). A *lazy* continuation is the exception: cmark's `add_line` copies from `parser->offset` with no advance (blocks.c ~1408), preserving the residual leading whitespace in its buffer, while the rewrite always adds continuation content from `firstNonSpace` (stripping it from the content bytes, re-adding it only to the source column map). So a multi-line code span closing on a lazy continuation with leading whitespace is short by that residual flag-ON - the same nested-container residual gap Quirks C/E track, already divergent on the byte path and not in the fuzz corpus.
    ///
    /// why: the multi-line code-span end column is stamped one of two ways depending on `.cmarkBugCompatibility` (adopted only by the differential fuzzer; default off is spec-correct). The mechanism it uses - an explicit end position (`setExplicitEnd`) that overrides the node's byte-projected end - stays unconditional; only whether this method sets one is gated. This is an extension of Quirk G (multi-line raw-inline end via `adjust_subj_node_newlines`) from inline HTML to code spans; both share the flag.
    ///
    /// Flag ON reproduces the cmark quirk (Hyrum's Law): a newline-crossing code span reports `(startLine + newlines, afterClose - lastNewline)`. A single-line span carries no interior newline, so `adjust_subj_node_newlines` is a no-op and the spec-correct byte-projected half-open end (from `stampInline`) stands - this method returns early for it (byte-identical to today).
    ///
    /// Flag OFF is spec-correct: take no explicit end, so the node keeps the precise byte-projected half-open end from its `stampInline(node, cursor, afterClose)` stamp (its closing backtick's real line:column).
    ///
    /// Interaction with `.cmarkFlatRawInlineEnds`: the caller invokes `stampFlatRawInlineEnd` AFTER this method, so with the flat option ON (the differential's `disableSourcePosOpts` combination) the flat sourcepos-OFF end overrides this sourcepos-ON quirk end for code spans, mirroring the inline-HTML call order.
    ///
    /// Does NOT compound with the backslash-hard-break quirk: when `inlineSawBackslashHardBreak` is set, `stampInline` has already stamped an explicit flat-cursor end (that quirk's frame) and this method overwrites it with the content-count end - a mixed frame. A code span after a backslash hard break therefore stays divergent flag-ON (it already was); reproducing it faithfully needs a flat-frame end, deferred like the sibling. Not in the fuzz corpus.
    @inline(__always)
    mutating func stampCodeSpanEnd(_ node: DocumentStorage.Index, start: Int, afterClose: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, storage.options.contains(.cmarkBugCompatibility) else { return }
        // Count interior newlines and remember the last one's content offset. No interior newline = single-line span; leave it on the spec-correct byte path (byte-identical to today).
        var lastNewline = -1
        var newlines = 0
        var i = start
        while i < afterClose {
            if content[i] == UInt8(ascii: "\n") {
                lastNewline = i
                newlines += 1
            }
            i += 1
        }
        guard newlines > 0 else { return }
        // The start line comes from the opening backtick's source projection (cmark's `subj->line` at node creation); bail to the byte path if it has no source image (arena-only content, e.g. a flattened setext heading).
        guard let startSource = content.sourceOffset(ofVirtual: start) else { return }
        let endLine = sourceLineNumber(ofSource: startSource) + newlines
        // End column = bytes since the last interior newline, in CONTENT space (== cmark's `since_newline + 1 + backtick_count`, a flat count with no `block_offset`). See the doc comment for why this must not be a physical source-column projection.
        let endColumn = afterClose - lastNewline
        storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: endLine, column: endColumn))
    }

    /// Give a raw-scan inline (code span or inline HTML) whose token crosses a line break the flat end position cmark reports with `CMARK_OPT_SOURCEPOS` off: `(startLine, startColumn + tokenByteLength)`, ignoring the interior break.
    ///
    /// The reference (old swift-markdown, C path) sets `CMARK_OPT_SOURCEPOS` only when `disableSourcePosOpts` is unset (`CommonMarkConverter.swift`). With sourcepos OFF, cmark never runs `handle_newline`'s per-line reset while scanning a code span or raw HTML, so their `end_column` keeps counting flat from the token's start line - unlike the precise end sourcepos ON (and the rewrite) computes by advancing to the closing byte's real line. cmark's other multi-line inlines (emphasis, links, autolinks, text soft breaks) reset either way, so this flat end is scoped to exactly these two raw-scan constructs.
    ///
    /// why: the multi-line raw-inline end is stamped one of two ways depending on `.cmarkFlatRawInlineEnds` (forwarded only for the differential's flag-ON + `disableSourcePosOpts` combination; default off is spec-correct and tracks the precise end). The mechanism it uses - an explicit end position (`setExplicitEnd`) overriding the node's byte-projected end - is the same machinery Quirk C / G and the setext wrapper use; only whether this method sets one is gated.
    ///
    /// Flag ON reproduces the cmark quirk (Hyrum's Law): the token's flat byte length is added to its start column on its start line. For inline HTML this OVERRIDES Quirk G's sourcepos-ON flat-last-byte end (call the two in order; this writes last). A single-line span carries no line break, so its flat end equals its precise byte-projected end and this method returns early (byte-identical to today). Guards on the last content byte landing on a later source line than the first - which covers `\n`, `\r`, and `\r\n` breaks alike (they all advance `lineStarts`), where a `\n`-only scan would miss a bare `\r`. Bails to the byte path if either end of the token has no source image.
    ///
    /// Scoped to top-level blocks like its sibling helpers (`stampInlineHTMLEnd`, `stampCloseBracketEnd`): `startColumn` here counts from the token's PHYSICAL source line start (`s - lineStartByte(ofSource: s) + 1`), so a raw inline nested in a blockquote/list would include the container prefix in the column - a coordinate basis not verified against cmark's sourcepos-off nested end. Nested multi-line raw inlines are not in the fuzz corpus; a nested raw inline was already precise-vs-flat divergent on the byte path before this change (the same documented nested-container gap the siblings carry), never a wrong-line stamp and never in the deliverable (flag ON only).
    @inline(__always)
    mutating func stampFlatRawInlineEnd(_ node: DocumentStorage.Index, start: Int, end: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, storage.options.contains(.cmarkFlatRawInlineEnds),
              let s = content.sourceOffset(ofVirtual: start),
              let lastByte = content.sourceOffset(ofVirtual: end - 1),
              sourceLineNumber(ofSource: lastByte) > sourceLineNumber(ofSource: s) else {
            return
        }
        let startLine = sourceLineNumber(ofSource: s)
        let startColumn = s - lineStartByte(ofSource: s) + 1
        storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: startLine, column: startColumn + (end - start)))
    }

    /// Buffer offset of the start of the content line containing buffer offset `pos`: just past the previous buffer newline, or the content start. Counts cmark's flat close-bracket end column from the `]`'s line base and resets it at a newline in the link *text* (the softbreak that precedes the `]`).
    private func bufferLineStart(ofBuffer pos: Int, content: borrowing ContentSpan) -> Int {
        let start = content.startOffset
        var i = pos - 1
        while i >= start {
            if content[i] == UInt8(ascii: "\n") {
                return i + 1
            }
            i -= 1
        }
        return start
    }

    /// Stamp an unmatched strikethrough (`~`) run's source range: start at the run's own source offset, end at the START of that run's source line.
    ///
    /// Gated behind `.cmarkBugCompatibility` at the call site (`handleDelimRun`): only invoked flag-ON. Flag-OFF (the shipped default) stamps the run's normal width-bearing range via `stampInline` instead, so this degenerate range is never produced spec-correct.
    ///
    /// cmark-gfm's strikethrough extension (`strikethrough.c` `match`) sets a `~` run's `start_column` but never its `end_column`, leaving `end_column == 0` - which projects to column 1 of the run's line, i.e. the line-start byte. So a `~` at column 1 gets a zero-width `[s, s]` range, while a `~` further into its line gets a start-past-end range that `sourceRange(of:)` reports as no position - reproducing cmark either way. A no-op when positions are off or `start` maps to synthetic/arena content. Relies on `lineStarts` being populated, which holds during the inline-parsing pass (it runs after every line has been read).
    ///
    /// After a backslash hard break the run's line/column come from the flat inline cursor instead of byte projection (see the `inlineSawBackslashHardBreak` branch and `stampInline`). That branch needs no `.cmarkBugCompatibility` gate of its own: this whole method is reachable only flag-ON (call site above), and flag-OFF a post-break unmatched `~` flows through `stampInline`, whose gate - being off - leaves it the spec-correct byte-projected range.
    @inline(__always)
    mutating func stampInlineZeroWidth(_ node: DocumentStorage.Index, at start: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, let s = content.sourceOffset(ofVirtual: start) else {
            return
        }
        storage.setSourceStart(node, s)
        // why: cmark-gfm's strikethrough.c leaves an unmatched `~` run's `end_column` unset (== 0), i.e. column 1 = the start of the run's line, not the run's own column. Stamp the end at that line-start byte so consolidation's last-node end and standalone rendering both reproduce cmark's zero/negative-width range.
        storage.setSourceEnd(node, lineStartByte(ofSource: s))
        // why: two cmark quirks compound here. (1) strikethrough.c's `match` sets the `~` text node's `start_line`/`end_line` to `subj->line` and its `start_column` to the inline cursor's flat column, but leaves `end_column == 0` (which the reference converter maps to column 1). (2) After a backslash hard break, cmark's `handle_backslash` never resets `subj->line` / `subj->column_offset` (unlike `handle_newline` for soft/space breaks), so `subj->line` and the flat column keep counting across the break - no source byte projects onto them. The byte path above resets at the physical newline and so mis-lines the `~`; when a backslash break precedes this run, override start/end from the same flat cursor `stampInline` uses. The start is the flat position; the end is that flat line's column 1 (the `end_column == 0` mapping), so a run past column 1 stays start > end and reports no position (matching cmark), and consolidation carries these explicit positions onto a merged post-break run. Without a preceding backslash break this branch is skipped and the byte path above is byte-identical to before.
        if inlineSawBackslashHardBreak {
            let flatStart = flatInlinePosition(ofContent: start, content: content)
            storage.setExplicitStart(node, flatStart)
            storage.setExplicitEnd(node, MarkdownNode.SourcePosition(line: flatStart.line, column: 1))
        }
    }

    /// The source byte offset of the start of the line containing source offset `s`.
    ///
    /// Binary-searches `storage.lineStarts` (ascending; populated by the block pass that precedes inline parsing) for the largest entry `<= s`, mirroring `StorageView.position(ofByte:)`. Returns 0 when no line starts are recorded.
    private func lineStartByte(ofSource s: Int) -> Int {
        let lo = lineSearch(ofSource: s)
        return lo > 0 ? storage.lineStarts[lo - 1] : 0
    }

    /// The 1-based physical line number of source offset `s`, mirroring `StorageView.position(ofByte:)`.
    private func sourceLineNumber(ofSource s: Int) -> Int {
        max(1, lineSearch(ofSource: s))
    }

    /// Count of recorded line starts `<= s` (binary search of ascending `storage.lineStarts`). The containing line's start byte is `lineStarts[result - 1]` and its 1-based number is `max(1, result)`.
    private func lineSearch(ofSource s: Int) -> Int {
        var lo = 0
        var hi = storage.lineStarts.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if storage.lineStarts[mid] <= s {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        return lo
    }

    /// Merge runs of adjacent `.text` children into single nodes, recursing into containers.
    ///
    /// Smart-punctuation / entity substitutions emit their replacement as a separate text node (e.g. `"Markdown"` + `"’"` + `"s "`); cmark coalesces them into one text run. The merged node's content is the concatenation of the runs' segments and its source range is their union.
    mutating func consolidateTextNodes(_ parent: DocumentStorage.Index) {
        var child = storage[parent].firstChild
        while let current = child {
            if storage[current].kind == .text {
                // Absorb all immediately-following text siblings into `current`. Stop if a pair can't be merged (non-contiguous segment runs) so the loop always makes progress - otherwise the un-merged sibling would be revisited forever.
                while let next = storage[current].next, storage[next].kind == .text {
                    if !mergeTextNode(next, into: current) {
                        break
                    }
                }
            } else {
                consolidateTextNodes(current)
            }
            child = storage[current].next
        }
    }

    /// Merge `source` into the preceding text node `dest`, unioning their source ranges and unlinking `source`.
    ///
    /// When the two runs are pool-contiguous (the common case for adjacent text) this just widens `dest`'s `ContentRef` - no new segments. Otherwise (e.g. a smart-punctuation glyph re-interned at the pool's end sits between them) it appends copies of both runs' segments as a fresh combined run, so consolidation still merges them.
    @discardableResult
    private mutating func mergeTextNode(_ source: DocumentStorage.Index, into dest: DocumentStorage.Index) -> Bool {
        guard case .literal(let destRef) = storage[dest].data,
              case .literal(let srcRef) = storage[source].data else {
            return false
        }
        if destRef.first + destRef.count == srcRef.first {
            // Pool-contiguous: widen the destination's `ContentRef` in place (no new segments, no intern).
            storage[dest].data = .literal(ContentRef(
                first: destRef.first,
                count: destRef.count + srcRef.count,
                totalLength: destRef.totalLength + srcRef.totalLength
            ))
        } else {
            // Non-contiguous: append copies of both runs' segments to the pool end as a new combined run. Each segment is read into a local before appending, so the read access ends before the mutating append - no aliasing of the growing `segments` pool.
            let newFirst = Int32(storage.segments.count)
            for i in 0..<Int(destRef.count) {
                let seg = storage.segments[Int(destRef.first) + i]
                storage.segments.append(seg)
            }
            for i in 0..<Int(srcRef.count) {
                let seg = storage.segments[Int(srcRef.first) + i]
                storage.segments.append(seg)
            }
            storage[dest].data = .literal(ContentRef(
                first: newFirst,
                count: destRef.count + srcRef.count,
                totalLength: destRef.totalLength + srcRef.totalLength
            ))
        }
        if positionsEnabled {
            let a = storage.sourceRanges[dest]
            let b = storage.sourceRanges[source]
            if a.start >= 0, b.start >= 0 {
                // why: cmark's `cmark_consolidate_text_nodes` (swift-cmark `src/iterator.c`) sets the merged run's range from the FIRST node's start and the LAST node's end (`cur->end_column = tmp->end_column` on every iteration; `cur`'s start is never touched) - not a min/max union. In this pairwise left-to-right merge `dest` is the running-first node and `source` the next (last-so-far) sibling, so first-start = `dest.start` and last-end = `source.end`. This differs from a union only when a non-final node ends further right than the final node (the zero-width trailing-`~` quirk), where cmark collapses the run to the final node's end. Carry the first node's `explicitStart` and the last node's `explicitEnd` (backslash-hard-break flat columns) so a merged post-break run keeps its flat positions.
                storage.sourceRanges[dest] = DocumentStorage.SourceByteRange(
                    start: a.start,
                    end: b.end,
                    explicitStart: a.explicitStart,
                    explicitEnd: b.explicitEnd
                )
            } else if a.start < 0 {
                storage.sourceRanges[dest] = b
            }
        }
        storage.unlinkChild(source)
        return true
    }
}
