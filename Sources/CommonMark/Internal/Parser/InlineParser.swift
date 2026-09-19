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

/// Per-text-run record of which inline raw-HTML scan kinds have overrun to end-of-input and must not be
/// re-attempted for the rest of the run - cmark's per-subject `FLAG_SKIP_HTML_*` bits (`src/inlines.c`
/// `handle_pointy_brace`). Meaningful only flag-ON (`.cmarkBugCompatibility`); reset per `parseInline` pass.
internal struct HTMLScanSkip: OptionSet {
    let rawValue: UInt8

    static let comment = HTMLScanSkip(rawValue: 1 << 0)
    static let cdata = HTMLScanSkip(rawValue: 1 << 1)
    static let declaration = HTMLScanSkip(rawValue: 1 << 2)
    static let processingInstruction = HTMLScanSkip(rawValue: 1 << 3)
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
        // Record newlines swallowed by a code span / raw HTML only when reproducing cmark's
        // source-positions-off column behavior (`footnoteColumnResets`); otherwise leave the set inert.
        // Also require `.cmarkBugCompatibility` so this write-gate matches the reset-gate below (the set is
        // cleared per pass only in that block) - the Markdown layer always forwards them together.
        let recordSwallowedNewlines = storage.options.contains(.cmarkSourcePositionsDisabled)
            && storage.options.contains(.cmarkBugCompatibility)

        // Reset cmark's per-subject backtick-closer cache (`matchCodeSpan`, flag-ON only). Flag-OFF the cache is never consulted, so leave it untouched - inert.
        if storage.options.contains(.cmarkBugCompatibility) {
            codeSpanScannedForBackticks = false
            for i in codeSpanBackticks.indices {
                codeSpanBackticks[i] = 0
            }
            // cmark's per-subject `FLAG_SKIP_HTML_*` bits start clear for each new inline subject.
            htmlScanSkip = []
            codeSpanSwallowedNewlines.removeAll(keepingCapacity: true)
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
                    if recordSwallowedNewlines {
                        recordRawInlineSwallowedNewlines(from: cursor, to: span.afterClose, content: content)
                    }
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
                cursor += 1
                pendingTextStart = cursor
                // why: after a soft or trailing-space break cmark's inline `handle_newline` (inlines.c ~1499) advances past the spaces/tabs that begin the next line before resuming text, so a LAZY continuation's residual leading whitespace - which flag-ON the block parser keeps in the buffer (see `BlockParser.addLineSegment`) - never reaches a TEXT node, mirroring cmark stripping it from text flow while a code span still captures it straight from the raw buffer. Gated on `.cmarkBugCompatibility`: flag-OFF (and for every matched continuation) the block parser begins each continuation at its first non-space, so no residual follows a break and this loop finds none. EXCLUDES a backslash hard break (`!info.isBackslash`): cmark's `handle_backslash` builds the LINEBREAK and does NOT advance past the next line's leading whitespace, so after a `\`-break a lazy continuation's residual stays literal text (`- \<nl> r` -> Text " r"); skipping it here diverged from cmark (a fuzzer-found residual, previously mis-noted as out-of-corpus).
                if storage.options.contains(.cmarkBugCompatibility), !info.isBackslash {
                    while cursor < endOffset,
                          content[cursor] == UInt8(ascii: " ") || content[cursor] == UInt8(ascii: "\t") {
                        cursor += 1
                    }
                    pendingTextStart = cursor
                }

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
                        EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: sourceBytes, bugCompat: storage.options.contains(.cmarkBugCompatibility))
                    } else {
                        EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: storage.strings.span, bugCompat: storage.options.contains(.cmarkBugCompatibility))
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
                    if recordSwallowedNewlines {
                        recordRawInlineSwallowedNewlines(from: cursor, to: htmlEnd, content: content)
                    }
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
                // cmark opens an image only for `![` NOT followed by `^` (src/inlines.c: "specifically
                // check for '![' not followed by '^'"). `![^…` leaves the `!` as literal text and lets
                // the `[` open a link/footnote bracket, so `![^a]` is `!` + a footnote (or, with
                // footnotes off, `!` + a link/literal), never an image.
                if cursor + 1 < endOffset,
                   content[cursor + 1] == UInt8(ascii: "["),
                   !(cursor + 2 < endOffset && content[cursor + 2] == UInt8(ascii: "^")) {
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
                
            case UInt8(ascii: ":"), UInt8(ascii: "w"), UInt8(ascii: "W"):
                // Bare-URL autolinks (`://`-scheme and `www.`) are detected here, in the forward pass.
                // The `@`-triggered EMAIL form is NOT: cmark-gfm detects it in a post-pass over the
                // finished text nodes, AFTER emphasis resolution and `cmark_consolidate_text_nodes`
                // (`postprocess`, `extensions/autolink.c`). The rewrite mirrors that in
                // `gfmEmailAutolinkPass`, run after `consolidateTextNodes`, so a flanking `_`/`*` next to
                // an email is resolved as emphasis (or not) before the email boundaries are decided.
                // why: cmark's autolink extension declines to match a bare-URL autolink while an unclosed
                // `[`/`![` (LINK/IMAGE) opener is on the bracket stack - `match` (`extensions/autolink.c`)
                // bails when `cmark_inline_parser_in_bracket` reports LINK or IMAGE - so e.g. `[http://t`
                // stays plain text. An `^[` (ATTRIBUTE-only) opener does not suppress. The email post-pass
                // is unaffected: it runs after brackets have collapsed to literal text.
                let insideLinkOrImageBracket = lastBracket.map { brackets[$0].insideLinkOrImage } ?? false
                if storage.options.contains(.gfmAutolink),
                   !insideLinkOrImageBracket,
                   let auto = matchGFMAutolink(
                    trigger: byte,
                    cursor: cursor,
                    end: endOffset,
                    content: content
                   ) {
                    let emptyBefore = pendingTextStart == auto.urlStart
                    flushPendingText(
                        start: pendingTextStart,
                        end: auto.urlStart,
                        content: content,
                        into: parent
                    )
                    // why: cmark-gfm's autolink extension splits the text flow into `[before, link, after]` and leaves an EMPTY text node where the rewrite emits none. Flag-ON (`.cmarkBugCompatibility`) reproduce those empties; flag-OFF the tree stays clean (spec-correct deliverable). A `://`-scheme URL (`url_match` + `cmark_node_unput`) leaves an empty `before` only when the scheme-only preceding text node is fully rewound, and never an `after`; a `www.` match rewinds nothing and its trigger fires before any text is emitted, so it gets neither. (The EMAIL form's empty siblings are handled in `gfmEmailAutolinkPass`, not here.) `consolidateTextNodes` later folds an empty node into an adjacent real text run (mirroring cmark's `cmark_consolidate_text_nodes`), leaving it standalone only where cmark does.
                    if storage.options.contains(.cmarkBugCompatibility),
                       emptyBefore, auto.form != .www {
                        emitEmptyText(at: auto.urlStart, content: content, into: parent)
                    }
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
        /// `true` when this bracket, or any bracket enclosing it, is a `.link` or `.image` opener - the cumulative union cmark keeps in `bracket.in_bracket[LINK|IMAGE]` (see `push_bracket` in `src/inlines.c`). GFM bare-URL autolinks (`://`-scheme, `www.`) are suppressed while such a bracket is open, matching `match` in `extensions/autolink.c` (`cmark_inline_parser_in_bracket`). An `.attribute`-only chain does not suppress them.
        var insideLinkOrImage: Bool
        var previous: Int?
    }

    private func pushBracket(kind: BracketKind, inlText: DocumentStorage.Index, virtualStart: Int, delimPosition: Int, brackets: inout UniqueArray<BracketRecord>, lastBracket: inout Int?, noLinkOpeners: inout Bool) throws (MarkdownDocument.Error) {
        if let lastBracket {
            brackets[lastBracket].bracketAfter = true
        }
        let prev = lastBracket
        let newIdx = brackets.count
        let insideLinkOrImage = (prev.map { brackets[$0].insideLinkOrImage } ?? false)
            || kind == .link || kind == .image
        brackets.append(BracketRecord(
            kind: kind,
            inlText: inlText,
            virtualStart: virtualStart,
            delimPosition: delimPosition,
            bracketAfter: false,
            insideLinkOrImage: insideLinkOrImage,
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
                if afterSpaces2 > afterDest {
                    if let titleWindow = content.contiguousChunk(fromVirtual: afterSpaces2, limit: end),
                       let t = matchLinkTitle(titleWindow) {
                        maybeTitle = t.chunk
                        titleEnd = afterSpaces2 + (t.afterEnd - titleWindow.offset)
                    } else if let t = matchLinkTitle(from: afterSpaces2, end: end, in: content) {
                        // The `"…"` / `'…'` / `(…)` title straddles a soft-break join (`[](f (\n))`),
                        // which the contiguous window can't image within one source segment. cmark's
                        // `scan_link_title` scans a flat buffer, so it crosses the join to the closer
                        // (like the cross-line link-label scan below). Materialize the interior — it may
                        // straddle the join — then clean it exactly like the contiguous title.
                        maybeTitle = materializedChunk(start: t.interior.lowerBound, end: t.interior.upperBound, content: content)
                        titleEnd = t.afterEnd
                    }
                }
                let afterTitleSpaces = skipSpaceChars(start: titleEnd, end: end, content: content)
                if afterTitleSpaces < end,
                   content[afterTitleSpaces] == UInt8(ascii: ")") {
                    pos = afterTitleSpaces + 1
                    // Clean the destination like cmark's `cmark_clean_url` (trim surrounding whitespace, then remove escapes / decode entities); the title uses `unescapeURLChunk` alone, since cmark's `cmark_clean_title` does not trim. Both read via the buffer-aware accessor (selects `sourceBytes` vs the arena per `chunk.inSource`): a link inside flattened/arena content (a non-contiguous setext heading, a `\|`-unescaped table cell) has an arena-backed destination/title, so reading must not index the source buffer at an arena offset.
                    url = cleanURLChunk(dest.chunk)
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
            var labelRange: Range<Int>?
            var afterRefForm = pos
            // Scan the reference label through a contiguous window (see `contiguousChunk`); `lab.interior` is already a real buffer chunk and `lab.afterEnd` a buffer offset converted back to virtual via the window base.
            if let labelWindow = content.contiguousChunk(fromVirtual: pos, limit: end),
               let lab = matchLinkLabel(labelWindow) {
                labelChunk = lab.interior
                afterRefForm = pos + (lab.afterEnd - labelWindow.offset)
            } else if let lab = matchLinkLabel(from: pos, end: end, in: content) {
                // The full-reference label straddles a soft-break join (`[text][la\nbel]`), which the
                // contiguous window can't image. cmark's `link_label` scans a flat buffer, so it crosses
                // the join to the `]`; carry the interior's virtual range and normalize it across the
                // join for lookup, exactly like the shortcut fallback below.
                labelRange = lab.interior
                afterRefForm = lab.afterEnd
            }
            // Collapsed `[]`, a whitespace-only `[   ]`, or absent - fall back to shortcut form (the
            // bracket text itself becomes the label) when no inner brackets were nested under this
            // opener. cmark trims the scanned label (`cmark_chunk_trim`) before testing it for empty,
            // so a whitespace-only full-reference label triggers the same shortcut fallback (`[x][ ]`
            // resolves `[x]`).
            var shortcutRange: Range<Int>?
            let labelIsBlank: Bool
            if let lc = labelChunk {
                labelIsBlank = lc.trimming(using: self).isEmpty
            } else if let lr = labelRange {
                labelIsBlank = normalizeLabel(virtualRange: lr, in: content).isEmpty
            } else {
                labelIsBlank = true
            }
            if labelIsBlank && !openerBracketAfter {
                // Virtual offsets: the opener's `[` / `![` sits at `virtualStart`; the shortcut label runs from just past it to the `]` (`cursor`). `contiguousChunk` maps that virtual range to a real buffer chunk only when it lies within a single source segment. When it does, resolve from that chunk. When it straddles a multi-segment join (a soft break inside the label, `[foo\nbar]`), `contiguousChunk` can't image the whole label, so carry the virtual range and normalize across the join instead — cmark resolves such a multi-line label, so giving up here would leave the reference literal.
                let openerContentStart = brackets[openerIdx].virtualStart + (isImage ? 2 : 1)
                let shortcutLen = cursor - openerContentStart
                if shortcutLen > 0 {
                    if let sc = content.contiguousChunk(fromVirtual: openerContentStart, limit: cursor),
                       sc.length == shortcutLen {
                        labelChunk = sc
                    } else {
                        shortcutRange = openerContentStart..<cursor
                    }
                }
            }
            let key: String?
            if let lc = labelChunk, lc.length > 0 {
                key = normalizeLabel(chunk: lc)
            } else if let sr = shortcutRange {
                key = normalizeLabel(virtualRange: sr, in: content)
            } else if let lr = labelRange, !lr.isEmpty {
                key = normalizeLabel(virtualRange: lr, in: content)
            } else {
                key = nil
            }
            if let key, !key.isEmpty, let ref = storage.referenceMap[key] {
                url = ref.destination
                title = ref.title
                pos = afterRefForm
                matched = true
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
        // GFM footnote reference: when no link form matches but the bracket contents start with `^` (and have at least one more byte), treat the whole `[^label]` as a `.footnoteReference` — but only when the label resolves to a known definition. cmark turns an unresolved `[^x]` back into literal `[^x]` text (and then consolidates it with neighbours), which the normal no-match bracket handling below reproduces, since the footnote map is fully populated before inline parsing. An image-shaped opener `![^label]` is a footnote too (cmark ignores the image flag here): its `[` sits one past the opener's `!`.
        let footnoteBracketStart = brackets[openerIdx].virtualStart + (isImage ? 1 : 0)
        // cmark gates ALL footnote handling below — the resolved reference and every
        // `.cmarkBugCompatibility` collapse — on the node immediately after the opener being a TEXT
        // node (`handle_close_bracket`, src/inlines.c: `opener->inl_text->next->type ==
        // CMARK_NODE_TEXT`). When the inner `^[…](…)` / `^[…][ref]` was consumed as an inline
        // attribute, that node is the ATTRIBUTE node instead, so no footnote path applies and the
        // bracket falls through to the literal `]` below (`[^[]()]` → `[` + attributes + `]`). The
        // `[^[` collapse still fires when the inner `^[` did NOT form an attribute, because then the
        // `^[` text node remains (`[[^[]]]()` → `Link[Text "[^["]`).
        let footnoteAfterOpenerIsText = storage[openerInl].next.map { storage[$0].kind == .text } ?? false
        if storage.options.contains(.footnotes),
           footnoteAfterOpenerIsText,
           let labelChunk = footnoteRefLabel(
               openerVirtualStart: footnoteBracketStart,
               closeBracket: cursor,
               content: content
           ),
           storage.footnoteMap[normalizeLabel(chunk: labelChunk)] != nil {
            // Resolve emphasis inside the bracket first (clearing its delimiters from the stack) so
            // removing the inner nodes below doesn't leave stale delimiters for `processEmphasis`.
            processEmphasis(stackBottom: openerDelimPos, content: content, delimiters: &delimiters, lastDelim: &lastDelim)
            emitFootnoteReference(
                openerInl: openerInl,
                isImage: isImage,
                openerVirtualStart: brackets[openerIdx].virtualStart,
                content: content,
                labelChunk: labelChunk
            )
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            return initialPos
        }
        // cmark BUG (bug-compat only): a footnote-shaped opener whose caret is immediately followed by
        // another `[` (`[^[…`) has its inline footnote branch capture the label from the static `"^["`
        // string, over-reading past the inner `[` into that string's NUL terminator (FINDINGS #146). The
        // unresolved reference reconstructs to `[^[` (`![^[` for an image opener) followed by a NUL, so
        // reading its consolidated run as a C-string truncates there. Emit the `[^[` text and mark it as
        // run-truncating (its invisible tail is dropped in `dropRunTruncatedTails`, after the autolink pass
        // so a trailing email still links), then continue parsing so an enclosing bracket can still close
        // (`[[^[]]]()` -> `Link[Text "[^["]`).
        // Checked before the cross-line case because a `[^[…` opener takes this shape even across lines.
        if storage.options.contains(.footnotes),
           storage.options.contains(.cmarkBugCompatibility),
           footnoteAfterOpenerIsText,
           footnoteBracketStart + 2 < end,
           content[footnoteBracketStart + 1] == UInt8(ascii: "^"),
           content[footnoteBracketStart + 2] == UInt8(ascii: "["),
           caretBracketCollapses(content, open: footnoteBracketStart, outerClose: cursor) {
            processEmphasis(stackBottom: openerDelimPos, content: content, delimiters: &delimiters, lastDelim: &lastDelim)
            collapseCaretBracket(
                openerInl: openerInl,
                isImage: isImage,
                footnoteBracketStart: footnoteBracketStart,
                content: content
            )
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            return initialPos
        }
        // cmark BUG (bug-compat only): a footnote-shaped opener `[^…]` / `![^…]` whose `]` is on a
        // later line than its `[` collapses to literal `[^]` / `![^]`, dropping the inner content and
        // the soft break (empty label from a column-length underflow across the break). The
        // spec-correct default falls through to normal bracket handling, keeping the break. See
        // FINDINGS #146.
        if storage.options.contains(.footnotes),
           storage.options.contains(.cmarkBugCompatibility),
           footnoteAfterOpenerIsText,
           footnoteBracketStart + 1 < end,
           footnoteBracketStart + 2 < cursor,
           content[footnoteBracketStart + 1] == UInt8(ascii: "^"),
           footnoteSpanCrossesLine(content, from: footnoteBracketStart + 2, to: cursor) {
            processEmphasis(stackBottom: openerDelimPos, content: content, delimiters: &delimiters, lastDelim: &lastDelim)
            collapseMultilineFootnote(
                openerInl: openerInl,
                isImage: isImage,
                footnoteBracketStart: footnoteBracketStart,
                closeBracket: cursor,
                content: content
            )
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            return initialPos
        }
        // cmark BUG (bug-compat only): any other unresolved footnote-shaped bracket with a same-line
        // label reconstructs to the RAW `[^label]` source span. cmark synthesizes the unresolved
        // reference's text from raw bytes in `process_footnotes`, bypassing the smart punctuation,
        // backslash escapes, and entity decoding that the spec-correct literal path applies.
        if storage.options.contains(.footnotes),
           storage.options.contains(.cmarkBugCompatibility),
           footnoteAfterOpenerIsText,
           footnoteBracketStart + 1 < end,
           content[footnoteBracketStart + 1] == UInt8(ascii: "^"),
           let labelChunk = footnoteRefLabel(openerVirtualStart: footnoteBracketStart, closeBracket: cursor, content: content),
           storage.footnoteMap[normalizeLabel(chunk: labelChunk)] == nil {
            processEmphasis(stackBottom: openerDelimPos, content: content, delimiters: &delimiters, lastDelim: &lastDelim)
            emitRawFootnoteLiteral(openerInl: openerInl, openerVirtualStart: brackets[openerIdx].virtualStart, closeBracket: cursor, content: content)
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            return initialPos
        }
        // cmark BUG (bug-compat only): a footnote-shaped bracket whose caret is backslash-escaped
        // (`[\^…]` / `![\^…]`). cmark still treats it as a footnote — the text node after `[` is the
        // escaped `^` — but measures the reference-label length in *columns* from the opener's start
        // (the `[`, or the `!` of an image opener) spanning the backslash, while reading the label bytes
        // from just past the `^`. Counting the backslash column runs the read one byte past the label:
        //   - a `[` opener captures the closing `]` (`[\^x]` -> `[^x]]`);
        //   - an image `![` opener, whose start column sits one further left, over-reads a *second* byte
        //     past the `]` into the paragraph's trailing newline, and drops the `!` (`![\^x]` -> `[^x]\n]`);
        //   - a cross-line span resets the per-line column at the soft break, underflowing the length to
        //     an empty label (`[\^\nx]` -> `[^]`).
        // The unresolved reference reconstructs as `[^` + captured bytes + `]`. The spec-correct default
        // processes the escape and keeps a single `]` (`[^x]`).
        if storage.options.contains(.footnotes),
           storage.options.contains(.cmarkBugCompatibility),
           footnoteAfterOpenerIsText,
           footnoteBracketStart + 3 < cursor,
           content[footnoteBracketStart + 1] == UInt8(ascii: "\\"),
           content[footnoteBracketStart + 2] == UInt8(ascii: "^") {
            processEmphasis(stackBottom: openerDelimPos, content: content, delimiters: &delimiters, lastDelim: &lastDelim)
            emitEscapedCaretFootnoteLiteral(
                openerInl: openerInl,
                isImage: isImage,
                footnoteBracketStart: footnoteBracketStart,
                closeBracket: cursor,
                content: content
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
        // A footnote reference is same-line only. Unlike a link reference (whose multi-line label
        // cmark resolves after normalization), cmark never resolves a footnote-shaped bracket whose
        // label spans a soft break — such a bracket takes the cross-line collapse instead. So reject a
        // label containing a newline here; the cross-line branch handles it.
        var i = labelStart
        while i < closeBracket {
            if content[i] == UInt8(ascii: "\n") {
                return nil
            }
            i += 1
        }
        return chunk
    }

    /// Splice a `.footnoteReference` node in place of the opener's bracket text node and any inner-content text nodes.
    ///
    /// Only called for a label that resolves to a registered definition. Assigns or reuses the 1-based
    /// index for this label (in first-reference order), records the definition on first reference (so the
    /// post-processing pass can move it to the document end in index order), and increments the
    /// definition's `referenceCount`. The emitted reference carries the *definition's* raw label (cmark
    /// discards the reference's own text and links back to the definition), so `[^Foo]` resolving to
    /// `[^foo]` displays `foo`.
    ///
    /// cmark treats an image-shaped opener `![^a]` as a literal `!` followed by the footnote reference
    /// (its footnote branch ignores the bracket's image flag), so for an image opener the opener node's
    /// `![` is shrunk to a `!` text node kept before the reference; for a link opener the `[` node is removed.
    private mutating func emitFootnoteReference(openerInl: DocumentStorage.Index, isImage: Bool, openerVirtualStart: Int, content: borrowing ContentSpan, labelChunk: Chunk) {
        let key = normalizeLabel(chunk: labelChunk)
        guard let defIdx = storage.footnoteMap[key],
              case .footnoteDefinition(let defLabel, let count) = storage[defIdx].data else {
            return
        }
        let index: Int32
        if let existing = storage.footnoteIndices[key] {
            index = existing
        } else {
            storage.nextFootnoteIndex += 1
            index = storage.nextFootnoteIndex
            storage.footnoteIndices[key] = index
            storage.footnoteReferencedDefs.append(defIdx)
        }
        storage[defIdx].data = .footnoteDefinition(
            label: defLabel,
            referenceCount: count + 1
        )
        let parentIdx = storage[openerInl].parent
        let fnRefIdx = storage.appendNode(NodeRecord(
            kind: .footnoteReference(index: Int(index)),
            parent: parentIdx,
            data: .footnoteReference(label: defLabel)
        ))
        if isImage {
            // The opener node holds `![`; keep the `!` as a literal text node before the reference.
            let bang = content.chunk(offset: openerVirtualStart, length: 1)
            storage[openerInl].data = .literal(storage.intern(bang))
            stampInline(openerInl, openerVirtualStart, openerVirtualStart + 1, content: content)
            storage.insertChildAfter(fnRefIdx, after: openerInl)
        } else {
            storage.insertChildBefore(fnRefIdx, before: openerInl)
            storage.unlinkChild(openerInl)
        }
        // Detach inner-content text nodes (the `^label` part) that follow the reference. They aren't part of the reference's emitted text - the reference is rendered by the consumer based on its label and index.
        var sib = storage[fnRefIdx].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            sib = nextSib
        }
    }

    /// Whether the virtual content range `[from, to)` contains a line break (`\n`), i.e. a
    /// footnote-shaped bracket's `]` lands on a later line than its `[`. Soft breaks appear as `\n`
    /// bytes whether the paragraph content is one contiguous source chunk or a multi-segment join.
    private func footnoteSpanCrossesLine(_ content: borrowing ContentSpan, from: Int, to: Int) -> Bool {
        var i = from
        while i < to {
            if content[i] == UInt8(ascii: "\n") {
                return true
            }
            i += 1
        }
        return false
    }

    /// The byte length of the label cmark captures for a footnote-shaped bracket, `colOf(]) -
    /// colOf([) - 2`, with each column measured from its own line's start (cmark's `handle_newline`
    /// resets `column_offset` at each *bare* line ending). Negative/zero means an empty captured label.
    ///
    /// Only a bare `\n` resets: cmark's `handle_newline` (soft break, or the trailing-space hard break)
    /// runs `column_offset = -subj->pos` unconditionally, but a `\n` consumed by a preceding backslash
    /// hard break (`handle_backslash`'s `make_linebreak`) never touches `column_offset`. A `\n` is
    /// backslash-consumed exactly when an *odd* run of backslashes immediately precedes it, so those
    /// bytes must not reset the per-line column (see FINDINGS #154).
    private func footnoteCapturedLabelLength(_ content: borrowing ContentSpan, open: Int, close: Int) -> Int {
        var afterNLOpen = content.base
        var i = content.base
        while i < open {
            if content[i] == UInt8(ascii: "\n"), footnoteColumnResets(content, at: i) {
                afterNLOpen = i + 1
            }
            i += 1
        }
        var afterNLClose = afterNLOpen
        i = open
        while i < close {
            if content[i] == UInt8(ascii: "\n"), footnoteColumnResets(content, at: i) {
                afterNLClose = i + 1
            }
            i += 1
        }
        return (close - afterNLClose) - (open - afterNLOpen) - 2
    }

    /// Whether the `\n` at `i` is a *bare* line ending — one that cmark's `handle_newline` processes
    /// (resetting `column_offset`) rather than one consumed by a preceding backslash hard break. The
    /// last of an odd run of backslashes immediately before the `\n` consumes it (CommonMark's
    /// backslash line-break rule), so the newline is bare exactly when that run has even length.
    private func bareLineEnding(_ content: borrowing ContentSpan, at i: Int) -> Bool {
        var backslashes = 0
        var j = i - 1
        while j >= content.base, content[j] == UInt8(ascii: "\\") {
            backslashes += 1
            j -= 1
        }
        return backslashes % 2 == 0
    }

    /// Whether the `\n` at `i` resets cmark's per-line column cursor when measuring a footnote
    /// reference's captured label length (`footnoteCapturedLabelLength`). A backslash hard break's
    /// newline never resets (`bareLineEnding`). Additionally, when the reference was parsed with source
    /// positions off (`.cmarkSourcePositionsDisabled`), a newline swallowed by a code span or raw HTML
    /// does not reset either: cmark runs its `adjust_subj_node_newlines` cursor reset only under
    /// `CMARK_OPT_SOURCEPOS`, whereas `handle_newline` (soft/space breaks) always resets. So with source
    /// positions off the swallowed newline stays part of the raw byte capture (`` [^`\n`] `` verbatim),
    /// while with them on it collapses the label like a soft break (`[^]`). See FINDINGS Quirk I (#35/#74).
    private func footnoteColumnResets(_ content: borrowing ContentSpan, at i: Int) -> Bool {
        guard bareLineEnding(content, at: i) else {
            return false
        }
        if storage.options.contains(.cmarkSourcePositionsDisabled), codeSpanSwallowedNewlines.contains(i) {
            return false
        }
        return true
    }

    /// Record every newline byte in `[from, to)` as one consumed inside a raw-scan inline (a code span
    /// or raw HTML). Called at those two handlers only when reproducing cmark's source-positions-off
    /// column behavior; the recorded offsets suppress that newline's column reset in
    /// `footnoteColumnResets`.
    private mutating func recordRawInlineSwallowedNewlines(from: Int, to: Int, content: borrowing ContentSpan) {
        var i = from
        while i < to {
            if content[i] == UInt8(ascii: "\n") {
                codeSpanSwallowedNewlines.insert(i)
            }
            i += 1
        }
    }

    /// Whether a footnote-shaped `[^[…` opener takes cmark's `[^[` collapse (literal `[^[`, dropping
    /// the rest of the line) rather than the cross-line label reconstruction. The captured label starts
    /// with the inner `[`; cmark produces the `[^[` garbage once that label is >= 2 bytes (the inner `[`
    /// plus more). A length of 1 (just the inner `[`) reconstructs to `[^[]`, and <= 0 to `[^]`, both
    /// handled by the cross-line branch.
    private func caretBracketCollapses(_ content: borrowing ContentSpan, open: Int, outerClose: Int) -> Bool {
        return footnoteCapturedLabelLength(content, open: open, close: outerClose) >= 2
    }

    /// Replace an unresolved same-line footnote-shaped bracket with its RAW `[^label]` (or `![^label]`)
    /// source span as a single text node, reproducing cmark's `process_footnotes` reconstruction which
    /// works from raw bytes — so smart punctuation, backslash escapes, and entity references inside the
    /// bracket stay verbatim, unlike the spec-correct literal path.
    private mutating func emitRawFootnoteLiteral(openerInl: DocumentStorage.Index, openerVirtualStart: Int, closeBracket: Int, content: borrowing ContentSpan) {
        let parentIdx = storage[openerInl].parent
        let chunk = content.chunk(offset: openerVirtualStart, length: closeBracket + 1 - openerVirtualStart)
        let ref = storage.intern(chunk)
        let textIdx = storage.appendNode(NodeRecord(kind: .text, parent: parentIdx, data: .literal(ref)))
        storage.insertChildBefore(textIdx, before: openerInl)
        stampInline(textIdx, openerVirtualStart, closeBracket + 1, content: content)
        var sib: DocumentStorage.Index? = openerInl
        while let s = sib {
            let next = storage[s].next
            storage.unlinkChild(s)
            sib = next
        }
    }

    /// Collapse a footnote-shaped bracket whose caret is *immediately* followed by another `[`
    /// (`[^[…`) once its outer `]` closes, reproducing cmark's `.cmarkBugCompatibility` behavior:
    /// cmark's inline footnote branch captures the label from the static `"^["` string, over-reading
    /// past the inner `[` into its NUL terminator, so the unresolved reference reconstructs to `[^[`
    /// (`![^[` for an image opener) followed by a NUL. Emit that `[^[` literal in place of the opener
    /// and its inner content, and mark it run-truncating so `dropRunTruncatedTails` (run after the autolink
    /// pass) drops the invisible tail the NUL would hide - while an email in that tail still links. The
    /// caller returns `initialPos` so parsing continues - an enclosing bracket can still form a link
    /// around the `[^[`.
    private mutating func collapseCaretBracket(openerInl: DocumentStorage.Index, isImage: Bool, footnoteBracketStart: Int, content: borrowing ContentSpan) {
        let parentIdx = storage[openerInl].parent
        var literal: [UInt8] = []
        if isImage {
            literal.append(UInt8(ascii: "!"))
        }
        literal.append(UInt8(ascii: "["))
        literal.append(UInt8(ascii: "^"))
        literal.append(UInt8(ascii: "["))
        let startOff = storage.strings.count
        for b in literal {
            storage.strings.append(b)
        }
        let ref = storage.intern(Chunk(offset: startOff, length: literal.count, inSource: false))
        let textIdx = storage.appendNode(NodeRecord(kind: .text, parent: parentIdx, data: .literal(ref)))
        storage.insertChildBefore(textIdx, before: openerInl)
        stampInline(textIdx, footnoteBracketStart - (isImage ? 1 : 0), footnoteBracketStart + 3, content: content)
        storage.runTruncatingTextNodes.insert(textIdx)
        var sib: DocumentStorage.Index? = openerInl
        while let s = sib {
            let next = storage[s].next
            storage.unlinkChild(s)
            sib = next
        }
    }

    /// The byte length of the UTF-8 sequence led by `b0` (1/2/3/4 per the lead-byte bit pattern, mirroring
    /// the same tests `decodeUTF8Scalar` uses). The source is already known-valid UTF-8, so this is only
    /// used to tell whether a raw byte cut (`capturedLabelBytes`) lands mid-sequence, never to validate
    /// the sequence itself.
    private static func utf8SequenceLength(_ b0: UInt8) -> Int {
        if b0 & 0xE0 == 0xC0 { return 2 }
        if b0 & 0xF0 == 0xE0 { return 3 }
        if b0 & 0xF8 == 0xF0 { return 4 }
        return 1
    }

    /// Build the byte-captured label for a raw byte-length cut `[start, cutEnd)`, reproducing cmark's
    /// `cmark_chunk` truncation: the cut is a length-bounded slice oblivious to UTF-8 boundaries, so a
    /// scalar split by the cut is replaced by a single U+FFFD (the reference's later `String(cString:)`
    /// bridge repairing the truncated tail) instead of reading past the cut to complete it. Shared by both
    /// footnote-shaped-bracket label captures (`collapseMultilineFootnote`, `emitEscapedCaretFootnoteLiteral`).
    /// `overreadByte`, when non-nil, stands in for content at/past `content.endOffset` — the
    /// escaped-caret image form's one-byte over-read into the paragraph's synthetic trailing newline;
    /// callers that don't over-read never pass a `cutEnd` past `content.endOffset`, so it's never forced.
    private static func capturedLabelBytes(content: borrowing ContentSpan, start: Int, cutEnd: Int, overreadByte: UInt8? = nil) -> [UInt8] {
        let contentEnd = content.endOffset
        var bytes: [UInt8] = []
        var j = start
        while j < cutEnd {
            let b0 = j < contentEnd ? content[j] : overreadByte!
            let sequenceLength = utf8SequenceLength(b0)
            if j + sequenceLength <= cutEnd {
                for k in j..<(j + sequenceLength) {
                    bytes.append(k < contentEnd ? content[k] : overreadByte!)
                }
                j += sequenceLength
            } else {
                // The cut lands inside this scalar's continuation bytes: cmark's raw slice ends here, so
                // nothing beyond `cutEnd` is part of the capture. Emit the one U+FFFD the reference's
                // later UTF-8 repair produces for the truncated tail, and stop.
                bytes.append(contentsOf: [0xEF, 0xBF, 0xBD])
                break
            }
        }
        return bytes
    }

    /// Handle a footnote-shaped bracket whose `]` lands on a later line than its opener, reproducing
    /// cmark's `.cmarkBugCompatibility` behavior. cmark's inline footnote branch captures the label as
    /// `cmark_chunk_dup(caretNode, 1, end_col - start_col - 2)`, reading raw bytes from just after the
    /// `^` across the soft break; its column arithmetic resets at each newline (`handle_newline` sets
    /// `column_offset = -pos`), so the captured byte length is `colOf(]) - colOf([) - 2` with per-line
    /// columns (`footnoteCapturedLabelLength`). That raw byte cut can land mid-character: cmark's
    /// `cmark_chunk` is just a length-bounded slice, so the copy is oblivious to UTF-8 boundaries and can
    /// truncate a multi-byte scalar to its lead byte(s) alone. The reference's Swift bridge later turns
    /// that raw C chunk into a `String` via `String(cString:)`, whose own UTF-8 decoding repairs the
    /// truncated tail to a single U+FFFD (Unicode's maximal-subpart replacement) — so a captured lead
    /// byte with no continuation bytes becomes `�`, not the rest of the (unrelated) character that
    /// happened to follow it in the buffer. Materialize that same replacement here rather than reading
    /// past the cut to complete the scalar. cmark then RESOLVES that captured label if it matches a
    /// definition (so a cross-line `[^a<nl>x]` resolves to `a`); otherwise the whole span reconstructs as
    /// `[^` + the captured bytes + `]` (`[^]` for an empty capture). The spec-correct default keeps the
    /// bracket literal with its soft break; see FINDINGS #146.
    private mutating func collapseMultilineFootnote(openerInl: DocumentStorage.Index, isImage: Bool, footnoteBracketStart open: Int, closeBracket close: Int, content: borrowing ContentSpan) {
        let labelStart = open + 2
        let x = footnoteCapturedLabelLength(content, open: open, close: close)
        var labelBytes: [UInt8] = []
        if x > 0 {
            labelBytes = Self.capturedLabelBytes(content: content, start: labelStart, cutEnd: min(labelStart + x, close))
        }
        // cmark resolves the reference by its byte-captured label; a match emits a footnote reference.
        if !labelBytes.isEmpty {
            let capStart = storage.strings.count
            for b in labelBytes {
                storage.strings.append(b)
            }
            let capturedChunk = Chunk(offset: capStart, length: labelBytes.count, inSource: false)
            if !normalizeLabel(chunk: capturedChunk).isEmpty,
               storage.footnoteMap[normalizeLabel(chunk: capturedChunk)] != nil {
                emitFootnoteReference(openerInl: openerInl, isImage: isImage, openerVirtualStart: open - (isImage ? 1 : 0), content: content, labelChunk: capturedChunk)
                return
            }
        }
        // Unresolved: reconstruct `[^` (or `![^`) + captured bytes + `]`.
        var literal: [UInt8] = []
        if isImage {
            literal.append(UInt8(ascii: "!"))
        }
        literal.append(UInt8(ascii: "["))
        literal.append(UInt8(ascii: "^"))
        literal.append(contentsOf: labelBytes)
        literal.append(UInt8(ascii: "]"))

        let parentIdx = storage[openerInl].parent
        let start = storage.strings.count
        for b in literal {
            storage.strings.append(b)
        }
        let ref = storage.intern(Chunk(offset: start, length: literal.count, inSource: false))
        let textIdx = storage.appendNode(NodeRecord(kind: .text, parent: parentIdx, data: .literal(ref)))
        storage.insertChildBefore(textIdx, before: openerInl)
        stampInline(textIdx, open - (isImage ? 1 : 0), close + 1, content: content)
        // Remove the opener and every inner-content sibling (the `^…` up to the `]`).
        var sib: DocumentStorage.Index? = openerInl
        while let s = sib {
            let next = storage[s].next
            storage.unlinkChild(s)
            sib = next
        }
    }

    /// Reconstruct a footnote-shaped bracket `[\^…]` / `![\^…]` (backslash-escaped caret) under
    /// `.cmarkBugCompatibility`. cmark reads the reference label from just past the `^` (`open + 3`, one
    /// byte after the escaped caret) for its column-measured length `colOf(]) - colOf(opener) - 2`, where
    /// the opener column is the `[`'s for a `[` opener and the `!`'s for an image opener (one further
    /// left, so an image captures one extra byte). Counting the backslash runs the read one byte past the
    /// label: a `[` opener captures the closing `]` (`[\^x]` -> `[^x]]`); an image opener over-reads a
    /// second byte into the paragraph's trailing newline and drops the `!` (`![\^x]` -> `[^x]\n]`). A
    /// cross-line span resets the per-line column at the soft break, underflowing the length to an empty
    /// label (`[\^\nx]` -> `[^]`). That raw byte cut can land mid-character the same way the plain
    /// `[^…]` capture does (`collapseMultilineFootnote`): cmark's `cmark_chunk` slice is UTF-8-oblivious,
    /// and its Swift bridge's later `String(cString:)` repairs a truncated tail to a single U+FFFD
    /// (`capturedLabelBytes`), rather than reading past the cut to complete the scalar. The unresolved
    /// reference reconstructs as `[^` + captured bytes + `]`.
    private mutating func emitEscapedCaretFootnoteLiteral(openerInl: DocumentStorage.Index, isImage: Bool, footnoteBracketStart open: Int, closeBracket close: Int, content: borrowing ContentSpan) {
        // cmark's byte-length label is `colOf(]) - colOf(opener) - 2` (per-line columns); an image
        // opener's `![` shifts the start one byte left, so it captures one extra byte. A cross-line reset
        // can drive it negative — cmark's underflow guard clamps that to an empty label.
        let labelLength = max(0, footnoteCapturedLabelLength(content, open: open, close: close) + (isImage ? 1 : 0))
        // The label runs from just past the escaped `^` (`open + 3`). cmark reads from the paragraph
        // buffer, which carries a trailing newline the zero-copy span omits; the image over-read is the
        // only read that reaches the content end, where that synthetic `\n` stands in.
        let labelStart = open + 3
        let labelBytes = Self.capturedLabelBytes(
            content: content, start: labelStart, cutEnd: labelStart + labelLength, overreadByte: UInt8(ascii: "\n"))

        var literal: [UInt8] = []
        literal.append(UInt8(ascii: "["))
        literal.append(UInt8(ascii: "^"))
        literal.append(contentsOf: labelBytes)
        literal.append(UInt8(ascii: "]"))

        let parentIdx = storage[openerInl].parent
        let start = storage.strings.count
        for b in literal {
            storage.strings.append(b)
        }
        let ref = storage.intern(Chunk(offset: start, length: literal.count, inSource: false))
        let textIdx = storage.appendNode(NodeRecord(kind: .text, parent: parentIdx, data: .literal(ref)))
        storage.insertChildBefore(textIdx, before: openerInl)
        // The reconstructed span runs from the opener (the `!` for an image, else the `[`) to just past
        // the closing `]`.
        stampInline(textIdx, open - (isImage ? 1 : 0), close + 1, content: content)
        // Remove the opener and every inner-content sibling (the `\^…` up to the `]`).
        var sib: DocumentStorage.Index? = openerInl
        while let s = sib {
            let next = storage[s].next
            storage.unlinkChild(s)
            sib = next
        }
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
        // Try reference form `[label]` looking up in attribute refmap. cmark's
        // `handle_close_bracket_attribute` (swift-cmark `src/inlines.c`) calls `link_label`
        // unconditionally: it ADVANCES past a well-formed following `[…]` - even an empty `[]`, or one
        // whose label resolves to no attribute reference - and only rewinds when no closing `]` is found.
        // A resolved reference supplies the attributes; an unresolved one is still consumed. Unlike the
        // link path, the failure branch does NOT rewind (`handle_close_bracket` resets
        // `subj->pos = initial_pos`; the attribute path never does), so the consumed `[…]` does not
        // re-parse - `^[][]` drops the trailing `[]`, leaving literal `^[]`.
        var labelKey: String?
        if let labelWindow = content.contiguousChunk(fromVirtual: pos, limit: end),
           let lab = matchLinkLabel(labelWindow) {
            // Contiguous window (see `contiguousChunk`): `lab.interior` is a real buffer chunk and
            // `lab.afterEnd` a buffer offset converted back to virtual via the window base.
            pos = pos + (lab.afterEnd - labelWindow.offset)
            if lab.interior.length > 0 {
                labelKey = normalizeLabel(chunk: lab.interior)
            }
        } else if let lab = matchLinkLabel(from: pos, end: end, in: content) {
            // The following `[…]` straddles a soft-break join (`^[](x)[la\nbel]`), which the contiguous
            // window can't image - it stops at the segment boundary, leaving the closing `]` on the next
            // line unseen. cmark's `link_label` scans a flat buffer, so it crosses the join to the `]` and
            // consumes it without rewinding; normalize the interior across the join for lookup.
            pos = lab.afterEnd
            if !lab.interior.isEmpty {
                labelKey = normalizeLabel(virtualRange: lab.interior, in: content)
            }
        }
        if let key = labelKey, !key.isEmpty,
           let storedAttrs = storage.attributeReferenceMap[key] {
            attrs = storedAttrs
            matched = true
        }
        if !matched {
            // Fail: pop bracket, emit a single `]` text at the (possibly label-advanced) close position
            // and resume there. The `^[` text node stays as regular text in the tree, matching cmark.
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            emitBracketLiteral(at: pos - 1, content: content, parent: parent)
            return pos
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
    private mutating func matchAttributeAttributes(start: Int, end: Int, content: borrowing ContentSpan) -> AttributeAttributesMatch? {
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
                    return AttributeAttributesMatch(chunk: attributeContentChunk(start: start, end: i, content: content), afterEnd: i)
                }
                nbParen -= 1
                i += 1
                continue
            }
            i += 1
        }
        return nil
    }

    /// The attribute interior `[start, end)` as a single readable chunk.
    ///
    /// Zero-copy when the range lies in one contiguous buffer region - every single-line attribute, and
    /// any multi-segment one that stays within a single source segment. A multi-line attribute straddles
    /// a soft-break segment boundary: its `(…)` content spans a paragraph line join (e.g. ` ^[](\n)`,
    /// which the block parser keeps as non-contiguous segments once a positive content indent suppresses
    /// the source-contiguity collapse), so the interior bytes live in separate source segments joined by
    /// the interned `\n` and no single buffer holds them. Materialize the joined bytes into the arena
    /// through the segment-aware subscript - the code-span / tab-expansion pattern - and hand back an
    /// arena chunk. cmark reads its flattened paragraph buffer, so the interior newline is ordinary
    /// attribute content (`manual_scan_attribute_attributes`, swift-cmark `src/inlines.c`). An empty `()`
    /// is a zero-length chunk.
    private mutating func attributeContentChunk(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if start == end {
            return content.chunk(offset: start, length: 0)
        }
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end),
           contiguous.length == end - start {
            return contiguous
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            storage.strings.append(content[k])
        }
        return Chunk(offset: outOffset, length: storage.strings.count - outOffset, inSource: false)
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

    /// The flanking classification of a `*`/`_`/`~`/quote delimiter run, computed against the
    /// characters bordering the run.
    private struct Flanking {
        var leftFlanking: Bool
        var rightFlanking: Bool
        /// The (skip-adjusted) character immediately before the run, used by the quote `]`/`)` rule.
        var beforeChar: UInt8
        /// Whether that before/after character is ASCII punctuation, used by the `_` intraword rule.
        var beforeIsPunct: Bool
        var afterIsPunct: Bool
    }

    /// Classify a delimiter run's left/right flanking, matching cmark-gfm's `scan_delims`.
    ///
    /// cmark-gfm skips over emphasis "special" characters (`skip_chars`) when it reads the before
    /// and after character for flanking. The only such character in this build is the GFM
    /// strikethrough `~`: its extension declares itself an emphasis extension, which registers `~`
    /// in `skip_chars`. The skip runs *before* cmark's per-delimiter-char branch, so it applies to
    /// `*`/`_` runs and smart quotes (`'`/`"`) alike — but NOT to a `~` run itself, which cmark
    /// scans through the extension's own delimiter scan that never consults `skip_chars`. With
    /// strikethrough disabled, `~` is ordinary text and nothing is skipped, matching cmark-gfm with
    /// the extension detached. So a `*`/`_`/quote run adjacent to a `~` is classified against the
    /// character past the `~`, e.g. the closing `*` in `*-*~a` sees `a` (a letter) and is
    /// left-flanking only, so it cannot close and no emphasis forms.
    private func classifyFlanking(char: UInt8, start: Int, runEnd: Int, end: Int, content: borrowing ContentSpan) -> Flanking {
        let chunkStart = content.startOffset
        let tilde = UInt8(ascii: "~")
        let skipTilde = char != tilde && storage.options.contains(.strikethrough)
        // "Before" character - treat content boundaries as a line break; skip a leading `~` run.
        var beforeIdx = start - 1
        if skipTilde {
            while beforeIdx >= chunkStart, content[beforeIdx] == tilde { beforeIdx -= 1 }
        }
        let beforeChar: UInt8 = beforeIdx >= chunkStart ? content[beforeIdx] : UInt8(ascii: "\n")
        // "After" character - same convention at end of content; skip a trailing `~` run.
        var afterIdx = runEnd
        if skipTilde {
            while afterIdx < end, content[afterIdx] == tilde { afterIdx += 1 }
        }
        // Classify the full Unicode scalar bordering the run, as cmark's `scan_delims` does via
        // `cmark_utf8proc_is_space` / `cmark_utf8proc_is_punctuation` over the decoded codepoint (not the
        // raw byte): a non-ASCII Unicode whitespace or punctuation neighbour (e.g. U+00A0 NBSP, the
        // U+055E Armenian question mark, the U+2014 em dash) must count as such for flanking. The
        // (skip-adjusted) neighbour byte is the LAST byte of the before scalar and the FIRST byte of the
        // after scalar; an ASCII byte is its own scalar (the common fast path), otherwise the multi-byte
        // scalar is decoded - the before scalar by walking back over continuation bytes to its lead.
        // `beforeChar` keeps the raw byte for the quote `]`/`)` rule below (a multi-byte before scalar
        // never equals those ASCII bytes), so only the space/punct classification changes here.
        let beforeScalar: Int32 = beforeIdx >= chunkStart
            ? Self.flankingScalarBefore(endingAt: beforeIdx, lowerBound: chunkStart, content: content)
            : 0x0A
        let afterScalar: Int32 = afterIdx < end
            ? Self.flankingScalarAfter(startingAt: afterIdx, upperBound: end, content: content)
            : 0x0A
        let beforeIsSpace = Self.isFlankingWhitespace(beforeScalar)
        let beforeIsPunct = Self.isFlankingPunctuation(beforeScalar)
        let afterIsSpace = Self.isFlankingWhitespace(afterScalar)
        let afterIsPunct = Self.isFlankingPunctuation(afterScalar)
        let leftFlanking = !afterIsSpace && (!afterIsPunct || beforeIsSpace || beforeIsPunct)
        let rightFlanking = !beforeIsSpace && (!beforeIsPunct || afterIsSpace || afterIsPunct)
        return Flanking(
            leftFlanking: leftFlanking,
            rightFlanking: rightFlanking,
            beforeChar: beforeChar,
            beforeIsPunct: beforeIsPunct,
            afterIsPunct: afterIsPunct
        )
    }

    /// The Unicode scalar just before a delimiter run, whose last byte is at `endIdx`. An ASCII byte is
    /// its own scalar (the common fast path); otherwise walk back over UTF-8 continuation bytes (not past
    /// `lowerBound`) to the lead byte and decode. A malformed sequence reads as U+000A, matching cmark's
    /// `scan_delims` (a `cmark_utf8proc_iterate` failure leaves `before_char` at the newline sentinel 10).
    @inline(__always)
    private static func flankingScalarBefore(endingAt endIdx: Int, lowerBound: Int, content: borrowing ContentSpan) -> Int32 {
        let last = content[endIdx]
        if last < 0x80 { return Int32(last) }
        var lead = endIdx
        while lead > lowerBound, content[lead] & 0xC0 == 0x80 { lead -= 1 }
        return decodeUTF8Scalar(at: lead, upperBound: endIdx + 1, content: content) ?? 0x0A
    }

    /// The Unicode scalar just after a delimiter run, beginning at `idx`. A malformed sequence reads as
    /// U+000A, matching cmark's `scan_delims` (see `flankingScalarBefore`).
    @inline(__always)
    private static func flankingScalarAfter(startingAt idx: Int, upperBound: Int, content: borrowing ContentSpan) -> Int32 {
        let first = content[idx]
        if first < 0x80 { return Int32(first) }
        return decodeUTF8Scalar(at: idx, upperBound: upperBound, content: content) ?? 0x0A
    }

    /// Decode the UTF-8 scalar beginning at `idx` (its lead byte), reading no further than `upperBound`.
    /// Returns `nil` for a malformed, truncated, overlong, surrogate, or out-of-range sequence, mirroring
    /// `cmark_utf8proc_iterate` (`src/utf8.c`) returning -1.
    private static func decodeUTF8Scalar(at idx: Int, upperBound: Int, content: borrowing ContentSpan) -> Int32? {
        let b0 = content[idx]
        if b0 < 0x80 { return Int32(b0) }
        let length: Int
        if b0 & 0xE0 == 0xC0 {
            length = 2
        } else if b0 & 0xF0 == 0xE0 {
            length = 3
        } else if b0 & 0xF8 == 0xF0 {
            length = 4
        } else {
            return nil
        }
        guard idx + length <= upperBound else { return nil }
        switch length {
        case 2:
            let b1 = content[idx + 1]
            guard b1 & 0xC0 == 0x80 else { return nil }
            let uc = (Int32(b0 & 0x1F) << 6) | Int32(b1 & 0x3F)
            return uc < 0x80 ? nil : uc
        case 3:
            let b1 = content[idx + 1]
            let b2 = content[idx + 2]
            guard b1 & 0xC0 == 0x80, b2 & 0xC0 == 0x80 else { return nil }
            let uc = (Int32(b0 & 0x0F) << 12) | (Int32(b1 & 0x3F) << 6) | Int32(b2 & 0x3F)
            return (uc < 0x800 || (uc >= 0xD800 && uc < 0xE000)) ? nil : uc
        default:
            let b1 = content[idx + 1]
            let b2 = content[idx + 2]
            let b3 = content[idx + 3]
            guard b1 & 0xC0 == 0x80, b2 & 0xC0 == 0x80, b3 & 0xC0 == 0x80 else { return nil }
            let uc = (Int32(b0 & 0x07) << 18) | (Int32(b1 & 0x3F) << 12) | (Int32(b2 & 0x3F) << 6) | Int32(b3 & 0x3F)
            return (uc < 0x10000 || uc >= 0x110000) ? nil : uc
        }
    }

    /// Whether `uc` is "Unicode whitespace" for flanking - cmark's `cmark_utf8proc_is_space` (`src/utf8.c`):
    /// the Zs general category plus TAB/LF/FF/CR. The ASCII subset ({9,10,12,13,32}) routes through the
    /// `isFlankingSpace` byte predicate.
    @inline(__always)
    private static func isFlankingWhitespace(_ uc: Int32) -> Bool {
        if uc < 0x80 { return UInt8(uc).isFlankingSpace }
        switch uc {
        case 160, 5760, 8192...8202, 8239, 8287, 12288:
            return true
        default:
            return false
        }
    }

    /// Whether `uc` is a "Unicode punctuation character" for flanking - cmark's
    /// `cmark_utf8proc_is_punctuation` (`src/utf8.c`): the P[cdefios] general categories. The ASCII subset
    /// routes through the `isASCIIPunct` byte predicate (which mirrors cmark's `cmark_ispunct` ctype table).
    @inline(__always)
    private static func isFlankingPunctuation(_ uc: Int32) -> Bool {
        if uc < 0x80 { return UInt8(uc).isASCIIPunct }
        switch uc {
        case 161, 167, 171, 182, 183, 187, 191, 894, 903,
            1370...1375, 1417, 1418, 1470, 1472, 1475, 1478, 1523, 1524,
            1545, 1546, 1548, 1549, 1563, 1566, 1567, 1642...1645, 1748,
            1792...1805, 2039...2041, 2096...2110, 2142, 2404, 2405, 2416,
            2800, 3572, 3663, 3674, 3675, 3844...3858, 3860, 3898...3901,
            3973, 4048...4052, 4057, 4058, 4170...4175, 4347, 4960...4968,
            5120, 5741, 5742, 5787, 5788, 5867...5869, 5941, 5942,
            6100...6102, 6104...6106, 6144...6154, 6468, 6469, 6686, 6687,
            6816...6822, 6824...6829, 7002...7008, 7164...7167, 7227...7231,
            7294, 7295, 7360...7367, 7379, 8208...8231, 8240...8259,
            8261...8273, 8275...8286, 8317, 8318, 8333, 8334, 8968...8971,
            9001, 9002, 10088...10101, 10181, 10182, 10214...10223,
            10627...10648, 10712...10715, 10748, 10749, 11513...11516,
            11518, 11519, 11632, 11776...11822, 11824...11842, 12289...12291,
            12296...12305, 12308...12319, 12336, 12349, 12448, 12539,
            42238, 42239, 42509...42511, 42611, 42622, 42738...42743,
            43124...43127, 43214, 43215, 43256...43258, 43310, 43311,
            43359, 43457...43469, 43486, 43487, 43612...43615, 43742, 43743,
            43760, 43761, 44011, 64830, 64831, 65040...65049, 65072...65106,
            65108...65121, 65123, 65128, 65130, 65131, 65281...65283,
            65285...65290, 65292...65295, 65306, 65307, 65311, 65312,
            65339...65341, 65343, 65371, 65373, 65375...65381, 65792...65794,
            66463, 66512, 66927, 67671, 67871, 67903, 68176...68184, 68223,
            68336...68342, 68409...68415, 68505...68508, 69703...69709,
            69819, 69820, 69822...69825, 69952...69955, 70004, 70005,
            70085...70088, 70093, 70200...70205, 70854, 71105...71113,
            71233...71235, 74864...74868, 92782, 92783, 92917, 92983...92987,
            92996, 113823:
            return true
        default:
            return false
        }
    }

    /// Scan a maximal run of `c` (`*` or `_`) starting at `start`, classify its left/right-flanking + can_open/can_close per CommonMark 0.31 §6.2, emit a `.text` node for the run, and (if it can open or close) push a delimiter record onto the stack. Returns the offset just past the run.
    ///
    /// The start of the content (`content.startOffset`) determines whether `start - 1` is a real "before" character or implicitly a newline (start of inline content acts like a line break).
    private mutating func handleDelimRun(char: UInt8, start: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, pendingTextStart: inout Int) throws (MarkdownDocument.Error) -> Int {
        // why: cmark-gfm's strikethrough `match` (`extensions/strikethrough.c`) scans a `~` run into a
        // fixed `char buffer[101]` via `cmark_inline_parser_scan_delimiters(inline_parser,
        // sizeof(buffer) - 1, '~', …)`, so it reads at most 100 consecutive `~` per delimiter token. A
        // longer run is thereby chunked into 100-length tokens (never a valid strikethrough delimiter -
        // only lengths 1 and 2 are - so each stays literal text) plus a final `N mod 100` token that can
        // pair. Cap the scan at 100 under `.cmarkBugCompatibility`; the outer loop re-enters here for the
        // next chunk, reproducing the chunking. Flag-OFF stays spec-correct (a run of length ≥ 3 is
        // simply not a valid delimiter), and `*`/`_` are never capped - cmark's own `scan_delims`
        // (`src/inlines.c`) has no such fixed buffer, only the strikethrough extension does.
        let scanLimit =
            char == UInt8(ascii: "~") && storage.options.contains(.cmarkBugCompatibility)
            ? min(end, start + 100)
            : end
        var runEnd = start
        while runEnd < scanLimit, content[runEnd] == char {
            runEnd += 1
        }

        let count = runEnd - start
        let flanking = classifyFlanking(char: char, start: start, runEnd: runEnd, end: end, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeIsPunct = flanking.beforeIsPunct
        let afterIsPunct = flanking.afterIsPunct
        
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
        // Stamp the run's own source span. A delimiter that never forms emphasis stays as literal text, and this range lets it keep its columns when it consolidates with adjacent text; a matched delimiter's text node is unlinked before it can matter. The reference stamps this node at creation for the same reason. The run is ordinary literal text and gets a normal, width-bearing range over its own `[start, runEnd)` span, exactly like emphasis (`*`/`_`) delimiters and every other text run stamped via `stampInline`.
        stampInline(textIdx, start, runEnd, content: content)
        // Push a delimiter record only when the run can open or close. A non-flanking `~` (emitted above to mirror cmark-gfm) can do neither, so it contributes no delimiter and stays literal text.
        if canOpen || canClose {
            // cmark-gfm's strikethrough `match` (`strikethrough.c`) pushes a `~` delimiter only for a
            // run of exactly length 2, or length 1 when the double-tilde option is off. Longer runs
            // (and length-1 runs under doubleTilde) still surface as literal text — emitted above —
            // but never become delimiters, so they can't pair into a strikethrough the way cmark's
            // generic delimiter walk would otherwise let an equal-length neighbour do. `*`/`_` runs
            // are pushed regardless of length.
            let pushDelim: Bool
            if isStrikethrough {
                let doubleTilde = storage.options.contains(.strikethroughDoubleTilde)
                pushDelim = count == 2 || (!doubleTilde && count == 1)
            } else {
                pushDelim = true
            }
            if pushDelim {
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
        }
        pendingTextStart = runEnd
        return runEnd
    }

    /// Resolve emphasis pairs. Walks forward from the first delimiter above `stackBottom` (use `-1` to process the entire stack). For each closer, looks back for the most recent compatible opener and pairs them via `insertEmph`.
    ///
    /// `openersBottom` is the per-(length%3, char) search-floor optimization: once we fail to find an opener for a closer of a given (length%3, char), no later closer of the same shape needs to look behind that point.
    private mutating func processEmphasis(stackBottom: Int, content: borrowing ContentSpan, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?) {
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
                    // The rule-of-three opener-acceptance test cmark applies to EVERY delimiter in
                    // `S_process_emphasis` — `*`/`_` and, through the generic driver, GFM `~` too. For
                    // `~`, the run-length match is deliberately NOT checked here; `insertEmph` forms a
                    // strikethrough only when the runs are equal-length and otherwise discards both
                    // delimiters (its `goto done` path). Checking length here would instead let a
                    // closer skip a mismatched-length opener and pair a farther equal-length one, which
                    // cmark never does — it selects the nearest flanking opener, then discards it on
                    // mismatch, so the farther opener can no longer reach this closer. That divergence
                    // is only observable across a softbreak, where an intervening `~~` is can-open-only.
                    if !(cl.canOpen || op.canClose)
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
            // cmark-gfm's strikethrough `insert` (`strikethrough.c`) forms a node only when the opener
            // and closer text runs have equal length. On a mismatch it takes the `goto done` path:
            // no node is built, but it still removes every delimiter from the closer back through the
            // opener, so a farther equal-length opener can no longer pair with this closer. The runs
            // survive as literal text. (`processEmphasis` selects the nearest flanking opener via the
            // generic rule, so this is where the length constraint is actually enforced.)
            if openerNumChars != closerNumChars {
                let next = delimiters[closer].next
                var d: Int? = closer
                while let dd = d, dd != opener {
                    let prev = delimiters[dd].previous
                    removeDelim(dd, delimiters: &delimiters, lastDelim: &lastDelim)
                    d = prev
                }
                removeDelim(opener, delimiters: &delimiters, lastDelim: &lastDelim)
                return next
            }
            // Equal run lengths: consume the entire run from each side.
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
        // The emph/strong range covers only the consumed delimiters plus content and never overlaps the leftover text: advance the start past the opener's leftover delimiters and pull the end back before the closer's (`**o*` → `Emphasis @1:2-1:5`). For balanced runs both counts are zero. Both offsets are VIRTUAL content offsets so the map-aware `content:` overload resolves them through the arena/segment map (identity for source-backed content).
        let start = delimiters[opener].virtualStart + openerNumChars
        let end = delimiters[closer].virtualEnd - closerNumChars
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
        // Quotes are limited to a single delimiter character (unlike `*`/`_`/`~` runs).
        let runEnd = start + 1
        let flanking = classifyFlanking(char: char, start: start, runEnd: runEnd, end: end, content: content)
        let leftFlanking = flanking.leftFlanking
        let rightFlanking = flanking.rightFlanking
        let beforeChar = flanking.beforeChar
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
                    //
                    // The raw content is `[openEnd, i)`. When that whole range lies in one contiguous buffer
                    // region - every single-line span, and any multi-segment span that stays within one source
                    // segment - it is returned zero-copy, byte-identical to the old `content.chunk` fast path. A
                    // multi-line span straddles a soft-break segment boundary (its interior newline joined the
                    // paragraph's non-contiguous lines): the content bytes live in separate source segments joined
                    // by the interned `\n` (and, flag-ON, a synthetic split-tab residual segment), so no single
                    // buffer holds them and a straddling `content.chunk` would read the wrong bytes - dropping the
                    // tail and keeping the continuation line's stripped leading whitespace. `materializedChunk`
                    // joins them through the segment-aware subscript, then hands them to the unchanged normalizer.
                    // This is the `ef14606` inline-HTML sibling.
                    //
                    // The joined bytes equal cmark's paragraph buffer for a MATCHED continuation, whose leading
                    // whitespace the block parser strips just as cmark does (blocks.c:1465). A LAZY continuation
                    // (block quote / list) is the case cmark treats differently: it preserves that line's residual
                    // leading whitespace (blocks.c:1408), and flag-ON the block parser now keeps that residual in
                    // the segment content too (`BlockParser.addLineSegment` begins the lazy segment at the
                    // prefix-match stop, or emits a synthetic-space segment for a split tab), so the join here
                    // captures it and the code-span literal reproduces cmark (`> `x\n y`` -> `x  y`; the
                    // `lazyres-*` pairs). Flag-OFF the block parser begins every continuation at its first
                    // non-space, so the residual never enters the join - spec-correct.
                    let contentChunk = materializedChunk(start: openEnd, end: i, content: content)
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
        // Trailing whitespace before the newline. cmark's inline text flush rtrims the preceding text
        // of `cmark_isspace` bytes - space and tab - regardless of the break kind (`cmark_chunk_rtrim`,
        // src/inlines.c), so the content always ends at the first non-space/tab. VT (0x0b) / FF (0x0c)
        // are NOT in `cmark_isspace`, so a trailing VT/FF is preserved (a\f\t  \n keeps "a\f"). The
        // break is HARD when the two bytes immediately before the newline were both spaces (§6.7), SOFT
        // otherwise; an intervening tab ends the "immediately before" run, so `a  \t\n` is soft.
        var textEnd = newlineOffset
        var leadingSpaces = 0
        var inSpaceRun = true
        while textEnd > pendingTextStart {
            let prev = content[textEnd - 1]
            if prev == UInt8(ascii: " ") {
                if inSpaceRun { leadingSpaces += 1 }
            } else if prev == UInt8(ascii: "\t") {
                inSpaceRun = false
            } else {
                break
            }
            textEnd -= 1
        }
        return LineBreakInfo(isHard: leadingSpaces >= 2, textEnd: textEnd)
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
        // why: cmark's `_scan_autolink_uri` (swift-cmark `src/scanners.re`) matches the URI body with the
        // class `[^\x00-\x20<>]*`, which excludes 0x00–0x20 and `<`/`>` but NOT DEL (0x7F). DEL is an ASCII
        // control character, so the spec excludes it and the deliverable (flag OFF) rejects it; cmark
        // wrongly admits it. Under `.cmarkBugCompatibility` (adopted only by the differential fuzzer) admit
        // DEL to match cmark. The email form's explicit char classes never include 0x7F, so only this URI
        // form diverges.
        let admitDEL = storage.options.contains(.cmarkBugCompatibility)
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
                || b == UInt8(ascii: "\n") || b == UInt8(ascii: "\r") || b < 0x20
                || (b == 0x7F && !admitDEL) {
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

    /// Local-part char for a GFM *extended* email autolink (the `@`-triggered form).
    ///
    /// cmark-gfm's `postprocess_text` backward scan (`extensions/autolink.c`) accepts only alnum and
    /// `.+-_`; it breaks at anything else. This is narrower than `isEmailLocalChar` (the CommonMark §6.4
    /// angle-`<...>` email set, which also admits `!#$%&'*/=?^\`{|}~`). The `mailto:`/`xmpp:` protocol
    /// prefixes cmark additionally recognizes via `validate_protocol` are a separate concern not handled here.
    private func isGFMEmailLocalChar(_ b: UInt8) -> Bool {
        if b.isASCIILetter || b.isASCIIDigit {
            return true
        }
        switch b {
        case UInt8(ascii: "."), UInt8(ascii: "+"), UInt8(ascii: "-"), UInt8(ascii: "_"):
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
    private mutating func matchInlineHTML(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
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
    private mutating func matchHTMLBangForm(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // start[0] == '<', start[1] == '!' guaranteed by caller.
        // why: cmark-gfm guards the ENTIRE `<!` dispatch on the comment skip flag
        // (`src/inlines.c` `handle_pointy_brace`: `if (c == '!' && (subj->flags & FLAG_SKIP_HTML_COMMENT) == 0)`),
        // so once a comment scan has overrun to end-of-input in this run, later CDATA and declaration
        // matches are suppressed too. Flag-ON only; flag-OFF each bang form is attempted independently.
        if storage.options.contains(.cmarkBugCompatibility), htmlScanSkip.contains(.comment) {
            return nil
        }
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

    /// Match `<!--…-->`. Accepts the empty forms `<!-->` and `<!--->` per HTML5, then scans for the first `-->` terminator (rejecting NUL bytes in the body). Under `.cmarkBugCompatibility` the body+closer is matched by cmark-gfm's stricter grammar instead (`matchHTMLCommentBodyStrict`), which rejects some forms the first-`-->` rule accepts (e.g. `<!----->`).
    private mutating func matchHTMLComment(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
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
        // why: cmark-gfm scans comment bodies with the stricter grammar in swift-cmark `src/scanners.re`
        // (`htmlcomment`, via `_scan_html_comment`), which rejects forms the CommonMark 0.31 first-`-->`
        // rule accepts (e.g. `<!----->`). Flag-ON (`.cmarkBugCompatibility`, adopted only by the
        // differential fuzzer) reproduces that rejection; flag-OFF the deliverable stays spec-correct
        // (0.31), matching the first `-->` below.
        if storage.options.contains(.cmarkBugCompatibility) {
            if let match = matchHTMLCommentBodyStrict(bodyStart: bodyStart, end: end, content: content) {
                return match
            }
            // why: `scan_html_comment` returning 0 (no closer reachable) is exactly where cmark sets
            // `subj->flags |= FLAG_SKIP_HTML_COMMENT` (`src/inlines.c` `handle_pointy_brace`), so no later
            // `<!` form is reparsed in this run. The empty forms above match before this, mirroring cmark's
            // `matchlen = 4/5` shortcuts, so they never set the flag.
            htmlScanSkip.insert(.comment)
            return nil
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

    /// Match a comment body + `-->` closer under cmark-gfm's stricter grammar (swift-cmark `src/scanners.re`: `([^\x00-]+ | "-" [^\x00-] | "--" [^\x00>])* "-->"`, scanned by `_scan_html_comment` after the `<!--` opener). Returns the offset just past `-->`, or `nil` if no closer is reachable. Dashes are admitted only in runs of one or two before a non-dash / non-`>` char, so a body element can never leave a lone `-->` closer — which is why `<!----->` is rejected (its three interior dashes are absorbed as `--` + `-`, then `>` no longer follows a `--`). A NUL byte, or reaching `end` without a closer, fails.
    private func matchHTMLCommentBodyStrict(bodyStart: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // Unabsorbed dashes since the last body char, capped at two (cmark DFA states yy226/yy228/yy236);
        // a third dash is the `[^\x00>]` completing a `--` run, so the run resets.
        var pendingDashes = 0
        var i = bodyStart
        while i < end {
            let b = content[i]
            if b == 0 {
                return nil
            }
            if b == UInt8(ascii: "-") {
                pendingDashes = pendingDashes == 2 ? 0 : pendingDashes + 1
            } else if b == UInt8(ascii: ">"), pendingDashes == 2 {
                return i + 1
            } else {
                // Any other char (including `>` after fewer than two dashes) absorbs the pending run.
                pendingDashes = 0
            }
            i += 1
        }
        return nil
    }

    /// Match `<![CDATA[…]]>`. Flag-OFF (spec-correct, CommonMark 0.31 §6.6) the content is any run not
    /// containing `]]>`, closed by the first `]]>`. Under `.cmarkBugCompatibility` the content is scanned
    /// by cmark-gfm's stricter grammar instead (`scanCDATAContentEnd`), which rejects some forms the
    /// first-`]]>` rule accepts (e.g. a content run ending in a lone `]`, `<![CDATA[…]]]>`).
    private mutating func matchHTMLCDATA(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // why: cmark checks (and, on overrun, sets) `FLAG_SKIP_HTML_CDATA` around the CDATA scan
        // (`src/inlines.c` `handle_pointy_brace`). Flag-ON only.
        let bugCompat = storage.options.contains(.cmarkBugCompatibility)
        if bugCompat, htmlScanSkip.contains(.cdata) {
            return nil
        }
        // Need `<![CDATA[`. The two brackets are literal; the letters `CDATA` are matched
        // case-SENSITIVELY per CommonMark start condition 5 (spec-correct, flag OFF). Under
        // `.cmarkBugCompatibility` they are matched case-INSENSITIVELY to reproduce cmark-gfm.
        // why: cmark-gfm's `inlines.c` `handle_pointy_brace` matches the leading `<![` with literal
        // byte compares, then hands the rest to `_scan_html_cdata` (`src/scanners.re`'s
        // `cdata = "CDATA[" (...)*` production). `scanners.re` is compiled with `re2c --case-insensitive`
        // (swift-cmark `Makefile`, the `scanners.c` build rule), so the generated DFA accepts either case
        // at each of the five `CDATA` letter states (`scanners.c`: `if (yych == 'C') ... if (yych == 'c')
        // ...`, and likewise D/A/T/A) while the literal brackets are unaffected.
        let prefixLen = 9
        if start + prefixLen > end {
            return nil
        }
        let prefix: StaticString = "<![CDATA["
        let prefixPtr = prefix.utf8Start
        let letters = 3..<8
        for k in 0..<prefixLen {
            var actual = content[start + k]
            var expected = prefixPtr[k]
            if bugCompat, letters.contains(k) {
                if actual.isUppercaseASCIILetter {
                    actual += 32
                }
                if expected.isUppercaseASCIILetter {
                    expected += 32
                }
            }
            if actual != expected {
                return nil
            }
        }
        // why: cmark-gfm scans the CDATA body with the grammar in swift-cmark `src/scanners.re` (`cdata`,
        // via `_scan_html_cdata`), then in `src/inlines.c` `handle_pointy_brace` ASSUMES a `]]>` closer
        // follows the matched content WITHOUT verifying it (`matchlen += 5` for `![` + `]]>`), rejecting
        // only when that assumed closer overruns the buffer (`subj->pos + matchlen > input.len`, which
        // sets `FLAG_SKIP_HTML_CDATA`). The grammar's `"]]" [^>\x00]` token absorbs a content run ending
        // in a lone `]` right before the real closer (`…]]]>` reads as `]]` + `]` content, then `>`
        // content), carrying the match past where the closer would begin so the assumed `]]>` overruns
        // and the `<` stays literal. Flag-ON (`.cmarkBugCompatibility`, adopted only by the differential
        // fuzzer) reproduces that rejection; flag-OFF the deliverable stays spec-correct (0.31), matching
        // the first `]]>` below.
        if bugCompat {
            let contentEnd = scanCDATAContentEnd(bodyStart: start + prefixLen, end: end, content: content)
            if contentEnd + 3 <= end {
                return contentEnd + 3
            }
            htmlScanSkip.insert(.cdata)
            return nil
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

    /// Scan a CDATA body under cmark-gfm's grammar (swift-cmark `src/scanners.re`:
    /// `([^\]\x00]+ | "]" [^\]\x00] | "]]" [^>\x00])*`, the tail of the `cdata` production that
    /// `_scan_html_cdata` matches after `CDATA[`). Returns the offset just past the longest content match
    /// starting at `bodyStart`. Content bytes are admitted as `[^\]\x00]` runs; a `]` is admitted only
    /// when a non-`]` byte follows (`] [^\]\x00]`) and `]]` only when a non-`>` byte follows
    /// (`]] [^>\x00]`), so a run halts just before a `]]>` closer — but a lone `]` (or `]]`) whose
    /// following bytes are themselves the closer's brackets (`…]]]>`) is absorbed as content, carrying the
    /// match past the closer. A NUL byte or reaching `end` halts the run; a trailing `]`/`]]` with no
    /// completing byte is excluded (its token never closed). The caller adds the assumed `]]>` and
    /// bounds-checks, mirroring cmark. Operates byte-wise: valid multibyte UTF-8 (every byte ≠ `]`, `>`,
    /// NUL) is consumed as content exactly as the grammar's codepoint classes intend (input is repaired to
    /// U+FFFD upstream, so no invalid sequence reaches here).
    private func scanCDATAContentEnd(bodyStart: Int, end: Int, content: borrowing ContentSpan) -> Int {
        let bracket = UInt8(ascii: "]")
        let gt = UInt8(ascii: ">")
        // Furthest offset ending a complete token sequence (cmark's re2c backtrack marker); a `]` or `]]`
        // still awaiting the byte that completes its token is not yet part of the match.
        var lastComplete = bodyStart
        var i = bodyStart
        while i < end {
            let b = content[i]
            if b == 0 {
                break
            }
            if b != bracket {
                // Ordinary content byte: `[^\]\x00]+`, or the trailing byte of a `] X` / `]] X` token.
                i += 1
                lastComplete = i
                continue
            }
            // A `]`. Consume it and look for the byte completing `] [^\]\x00]` or `]] [^>\x00]`.
            i += 1
            if i < end, content[i] == bracket {
                // `]]`: needs a following non-`>`, non-NUL byte to complete `]] [^>\x00]`.
                i += 1
                if i < end, content[i] != 0, content[i] != gt {
                    i += 1
                    lastComplete = i
                } else {
                    break
                }
            } else if i < end, content[i] != 0 {
                // `] [^\]\x00]`: the following byte is non-`]` (checked above) and non-NUL.
                i += 1
                lastComplete = i
            } else {
                break
            }
        }
        return lastComplete
    }

    /// Match `<!NAME …>` where NAME is `[A-Z]+`, followed by at least one spacechar, any non-`>` non-NUL chars, then `>`.
    private mutating func matchHTMLDeclaration(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // why: cmark checks (and, on overrun, sets) `FLAG_SKIP_HTML_DECLARATION` around the declaration
        // scan (`src/inlines.c` `handle_pointy_brace`). Flag-ON only.
        let bugCompat = storage.options.contains(.cmarkBugCompatibility)
        if bugCompat, htmlScanSkip.contains(.declaration) {
            return nil
        }
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
        // Matched name + spaces but no closing `>` through end-of-input: cmark's framed match overruns
        // (`subj->pos + matchlen > input.len`), which sets `FLAG_SKIP_HTML_DECLARATION`.
        if bugCompat {
            htmlScanSkip.insert(.declaration)
        }
        return nil
    }

    /// Match `<?…?>`. Body may be empty; scans for the first `?>` terminator rejecting NUL bytes.
    ///
    /// Flag-OFF (the spec-correct deliverable, CommonMark 0.31 §6.6) the body is any string of
    /// characters not including `?>`, so this stops at the FIRST `?>`. Under `.cmarkBugCompatibility`
    /// the scan follows cmark-gfm's inline PI grammar instead (`matchHTMLProcessingInstructionCmark`),
    /// which over-consumes and rejects some PIs the spec accepts (e.g. `<???>`).
    private mutating func matchHTMLProcessingInstruction(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        if storage.options.contains(.cmarkBugCompatibility) {
            return matchHTMLProcessingInstructionCmark(start: start, end: end, content: content)
        }
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

    /// Match `<?…?>` under cmark-gfm's inline processing-instruction grammar (swift-cmark
    /// `src/inlines.c` `handle_pointy_brace` + `src/scanners.re` `_scan_html_pi`), reproduced only
    /// under `.cmarkBugCompatibility`.
    ///
    /// cmark scans the body with `processinginstruction = ([^?>\x00]+ | [?][^>\x00] | [>])+` starting
    /// at the byte AFTER the opening `?` (`start + 2` here, since `start` is `<`), then frames the
    /// match with `<?`…`?>` (`matchlen += 3`) and rejects the PI when that framing overruns the input
    /// (`subj->pos + matchlen > input.len`). The regex never verifies a real `?>` follows; it just
    /// requires two bytes of room for it. Because the regex admits a lone `>` and pairs each `?` with
    /// its FOLLOWING byte, a body beginning with `?` can swallow the closing `?>` — for `<???>` the
    /// scan of `??>` eats `??` (a `[?][^>\x00]` pair) then `>` (a lone `[>]`), consuming through the
    /// input with no room left for the closer, so cmark rejects it. `<?x?>` matches only `x`, stops
    /// before `?>`, and is accepted. The body ends at the first NUL, the first `?` immediately before
    /// `>` (or at input end), whichever comes first.
    private mutating func matchHTMLProcessingInstructionCmark(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // why: cmark checks `FLAG_SKIP_HTML_PI` before attempting the PI (`src/inlines.c`
        // `handle_pointy_brace`); once set, the `<` stays literal. Reached only flag-ON.
        if htmlScanSkip.contains(.processingInstruction) {
            return nil
        }
        var i = start + 2
        while i < end {
            let b = content[i]
            if b == 0 {
                // NUL is excluded from every alternative of `processinginstruction`.
                break
            }
            if b == UInt8(ascii: ">") {
                // `[>]`: a lone `>` is consumed into the body.
                i += 1
                continue
            }
            if b == UInt8(ascii: "?") {
                // `[?][^>\x00]`: a `?` is consumed only when paired with a following non-`>`,
                // non-NUL byte. A `?` at input end, or immediately before `>` or NUL, cannot be
                // consumed and ends the body — this is where cmark stops before a real `?>`.
                if i + 1 < end {
                    let next = content[i + 1]
                    if next != UInt8(ascii: ">") && next != 0 {
                        i += 2
                        continue
                    }
                }
                break
            }
            // `[^?>\x00]`: any other byte is consumed.
            i += 1
        }
        // cmark: matchlen = (body length) + 3, reject when subj->pos (start + 1) + matchlen > end.
        // Body length = i - (start + 2), so the offset just past the framed `?>` is i + 2.
        let piEnd = i + 2
        if piEnd > end {
            // Framing overruns the input: cmark sets `FLAG_SKIP_HTML_PI`, so no later `<?` is reparsed
            // in this run.
            htmlScanSkip.insert(.processingInstruction)
            return nil
        }
        return piEnd
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
    ///
    /// `emailSchemeFolded` is set only for the email form when a recognized `mailto:`/`xmpp:` scheme was
    /// absorbed into `[urlStart, urlEnd)` (cmark's `validate_protocol`). In that case the destination is
    /// the folded run itself - no synthetic `mailto:` prefix - so `xmpp:` keeps its own scheme.
    private struct GFMAutolinkMatch {
        var urlStart: Int
        var urlEnd: Int
        var form: GFMAutolinkForm
        var emailSchemeFolded: Bool = false
    }

    /// Dispatch a GFM bare-URL autolink trial based on the trigger byte. Returns nil if no autolink starts at / contains `cursor`. The `@`-triggered email form is handled separately in `gfmEmailAutolinkPass`, not here.
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
            // why: cmark's `url_match` (`extensions/autolink.c`) rewinds over the maximal ASCII-alpha run
            // before `://` and then validates that run as a safe scheme (`sd_autolink_issafe`), so the scheme
            // is simply delimited by the first non-alpha byte. The char before the scheme may therefore be
            // ANY non-alpha byte (a digit, punctuation, or a byte of a non-ASCII character), or the content
            // start; only an ASCII letter blocks the match, because it would extend the rewind into an unsafe
            // scheme. This is looser than the `www.` form's `isValidGFMPreceding` allowlist - `www_match` DOES
            // restrict its preceding char, `url_match` does not.
            let pre = content[schemeStart - 1]
            if pre.isASCIILetter {
                return nil
            }
        }
        let urlEnd = scanGFMURLBody(start: colon + 3, end: end, content: content)
        let trimmedEnd = trimTrailingPunctuation(urlStart: schemeStart, urlEnd: urlEnd, content: content)
        if trimmedEnd <= colon + 3 {
            return nil
        }
        if !schemeURLDomainAccepted(afterSlashes: colon + 3, end: end, content: content) {
            return nil
        }
        return GFMAutolinkMatch(
            urlStart: schemeStart,
            urlEnd: trimmedEnd,
            form: .uri
        )
    }

    /// Find the start position of `http`, `https`, or `ftp` (matched case-insensitively, per cmark's
    /// `strncasecmp` in `sd_autolink_issafe`) ending just before `colon`. Returns the scheme's first-byte
    /// offset, or nil.
    private func matchSchemeBackward(colon: Int, content: borrowing ContentSpan) -> Int? {
        let chunkStart = content.startOffset
        if colon - 5 >= chunkStart,
           bytesEqual(at: colon - 5, target: "https", content: content, ignoringASCIICase: true) {
            return colon - 5
        }
        if colon - 4 >= chunkStart,
           bytesEqual(at: colon - 4, target: "http", content: content, ignoringASCIICase: true) {
            return colon - 4
        }
        if colon - 3 >= chunkStart,
           bytesEqual(at: colon - 3, target: "ftp", content: content, ignoringASCIICase: true) {
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
        // cmark's `www_match` (`extensions/autolink.c`) gates on `check_domain(data, size, allow_short: 0)`
        // before scanning the URL body and returns NULL on failure, so a domain bearing an underscore in
        // either of its last two `.`-separated labels (a host name may not) is never linked. The rejection
        // is GFM-spec-correct, so it applies in both modes - unlike the bare-`www` over-trim below.
        guard checkDomainAccepted(base: start, end: end, requireDot: true, content: content) else {
            return nil
        }
        let urlEnd = scanGFMURLBody(start: start + 4, end: end, content: content)
        let trimmedEnd = trimTrailingPunctuation(
            urlStart: start, urlEnd: urlEnd,
            content: content
        )
        if trimmedEnd <= start + 4 {
            // why: nothing survives the trailing-punctuation trim past `www.`, so there is no real domain.
            // Flag-OFF (spec-correct) this is not a www autolink. Flag-ON reproduce cmark's `www_match`
            // over-trim: its `check_domain` (the gate above) counts the dot inside `www.` as the domain's
            // required period whenever the chunk holds at least one byte past `www.` (its `i < size - 1`
            // bound reaches that dot only then), so cmark links a bare `www` once `autolink_delim` peels the
            // trailing `.`. `www.` at end-of-input (nothing after) never reaches that dot, so the gate above
            // already returned nil in both modes.
            guard storage.options.contains(.cmarkBugCompatibility) else {
                return nil
            }
        }
        return GFMAutolinkMatch(urlStart: start, urlEnd: trimmedEnd, form: .www)
    }

    /// One arm of cmark-gfm's `validate_protocol` (`extensions/autolink.c`): decide whether the `:` at
    /// `colon` completes the given lowercase scheme literal (`mailto:` / `xmpp:`, `:` included) sitting at
    /// a boundary, so the scheme should be folded into an email autolink. Returns the scheme's byte length,
    /// or nil.
    ///
    /// A scheme qualifies when its bytes lie fully within the scan window `[localBound, colon]`, match the
    /// literal case-sensitively (cmark uses `memcmp`, so `MAILTO:` does NOT match), and either begin exactly
    /// at `localBound` or are preceded by a non-alphanumeric byte (`amailto:` - preceded by `a` - fails).
    private func matchEmailScheme(_ scheme: StaticString, colon: Int, localBound: Int, content: borrowing ContentSpan) -> Int? {
        let len = scheme.utf8CodeUnitCount
        let schemeStart = colon + 1 - len
        if schemeStart < localBound {
            return nil
        }
        let ptr = scheme.utf8Start
        for k in 0..<len where content[schemeStart + k] != ptr[k] {
            return nil
        }
        if schemeStart == localBound {
            return len
        }
        let prev = content[schemeStart - 1]
        if prev.isASCIILetter || prev.isASCIIDigit {
            return nil
        }
        return len
    }

    /// `@`-triggered: scans backward (bounded by `localBound`) for the email local part and forward for the
    /// domain, restarting from a second `@` met mid-domain the way cmark's `goto found_at` does (see the loop).
    ///
    /// `localBound` is the earliest offset the backward local-part scan may reach - the content start for a
    /// fresh scan, or the end of the previous email when scanning a text node with several `@`s. It matches
    /// cmark's `max_rewind` bound (`postprocess_text`, `extensions/autolink.c`): since `@` is never a
    /// local-part char, the scan stops at any preceding `@` regardless, so the two agree.
    ///
    /// On a non-match the function returns nil and sets `resumeAt` to the offset just past everything it
    /// scanned (`> at` always). Every `@` in `[at, resumeAt)` was examined - the trial `@` plus any `@`s the
    /// restart walked over - and provably cannot start an email (a restart that reaches those `@`s fresh
    /// carries no MORE dots than this scan did, so it fails identically), so the caller skips straight to
    /// `resumeAt`. This mirrors cmark advancing its `offset` past the failed region rather than re-examining
    /// it, keeping the whole pass O(content length) even on adversarial `@`-dense input (the anti-quadratic
    /// guard cmark maintains; see `check_domain`'s GHSA note).
    private func matchGFMEmailAutolink(at: Int, localBound: Int, end: Int, content: borrowing ContentSpan, resumeAt: inout Int) -> GFMAutolinkMatch? {
        // `atSign` is the `@` currently under trial. cmark's `postprocess_text` (`extensions/autolink.c`)
        // RESTARTS the match from a SECOND `@` met during the forward domain scan (`goto found_at`): it
        // abandons the current `local@domain` candidate - never emitting it - and re-scans from that second
        // `@` (the run between the two `@`s becomes the new local part). The `goto` jumps past the
        // initializers of the state below, so these values CARRY across the restart while `localStart` and
        // the domain cursor are recomputed from `atSign`.
        var atSign = at
        var schemeFolded = false
        var isXmpp = false
        // cmark's `np`: the count of domain dots each immediately followed by an alphanumeric, gating "the
        // domain must contain a dot". It carries across the restart (declared before the loop), so a dot
        // counted while scanning the first candidate's domain still satisfies the gate for the restarted
        // email - `o@.e@b` links `.e@b` (the dot in `.e` was counted) though standalone `.e@b` does not (its
        // only dot is in the local part). Likewise `a@b.c@d` links `b.c@d` off the dot counted in `b.c`.
        var hasDotFollowedByAlnum = false
        while true {
            // Local part: cmark-gfm's `postprocess_text` backward scan (`extensions/autolink.c`) accepts a
            // NARROWER set than the CommonMark §6.4 angle-email form - only alnum + `.+-_` - and STOPS at any
            // other char (`isGFMEmailLocalChar`, not `isEmailLocalChar`). Using the broad §6.4 set here would
            // swallow chars cmark stops at (e.g. `x!@.e` -> cmark rejects; the broad set would link `mailto:x!@.e`).
            // A `:` that completes a recognized lowercase `mailto:`/`xmpp:` scheme at a boundary is FOLDED into
            // the link rather than stopping the scan (cmark's `validate_protocol`): the scheme becomes part of
            // the link text and destination, and for `xmpp:` the destination keeps that scheme (see below).
            var localStart = atSign
            while localStart > localBound {
                let b = content[localStart - 1]
                if isGFMEmailLocalChar(b) {
                    localStart -= 1
                    continue
                }
                if b == UInt8(ascii: ":") {
                    if let len = matchEmailScheme("mailto:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        localStart -= len
                        continue
                    }
                    if let len = matchEmailScheme("xmpp:", colon: localStart - 1, localBound: localBound, content: content) {
                        schemeFolded = true
                        isXmpp = true
                        localStart -= len
                        continue
                    }
                }
                break
            }
            // No local part AND no folded scheme (cmark's `rewind == 0`): not an email at this `@`. Resume
            // just past it and return nil - matching cmark, which on `rewind == 0` advances its offset past
            // the `@` (`offset += max_rewind + 1`) rather than emitting anything or re-examining it. A folded
            // scheme moves `localStart` back even when the local part is empty, so `mailto:@a.b` is accepted
            // here.
            if localStart == atSign {
                resumeAt = atSign + 1
                return nil
            }
            // why: unlike the `www.`/`://`-scheme forms (`www_match`/`url_match`, which restrict the char
            // before the match), cmark-gfm's email detection runs in `postprocess_text` (`extensions/autolink.c`)
            // as a pass over the finished text node: it scans backward from `@` over local-part chars and simply
            // STOPS at the first non-local char, leaving whatever precedes as ordinary "before" text with no
            // validity check. So a leading `<` (that already failed as an angle autolink / inline HTML) doesn't
            // block the email - `<o@.e` -> Text "<" + Link(mailto:o@.e). Applying a preceding-char restriction
            // here would reject those, so the email form has none.
            // Domain: cmark's `postprocess_text` requires the domain's dot count `np >= 1`, but a dot counts
            // toward `np` only when it is immediately followed by an alphanumeric. A trailing dot yields an
            // empty last label and does not count, so `o@b.` is not a valid domain (whereas `o@b.c` and the
            // empty-FIRST-label `o@.e` are - their dot is followed by an alphanumeric). The scan itself also
            // ENDS at a `.` not immediately followed by an alphanumeric (cmark breaks the domain there rather
            // than consuming the dot): `a@x.y.-5` scans the domain as `x.y` and leaves `.-5` as after-text.
            var i = atSign + 1
            let domainStart = i
            var sawSecondAt = false
            while i < end {
                let b = content[i]
                if b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: "_") {
                    i += 1
                } else if b == UInt8(ascii: ".") {
                    if i + 1 < end, content[i + 1].isASCIILetter || content[i + 1].isASCIIDigit {
                        hasDotFollowedByAlnum = true
                        i += 1
                    } else {
                        break
                    }
                } else if b == UInt8(ascii: "/"), isXmpp {
                    // why: cmark's `postprocess_text` forward domain scan admits `/` only for a folded `xmpp:`
                    // (`c == '/' && is_xmpp`); for every other form a `/` ends the domain.
                    i += 1
                } else if b == UInt8(ascii: "@") {
                    // why: cmark's forward domain scan does `goto found_at` on a second `@` - it does NOT emit
                    // the current pre-`@` candidate; it restarts the match from this `@`. Restart the loop with
                    // `atSign` at this `@`, carrying `hasDotFollowedByAlnum` / `schemeFolded` / `isXmpp` (which
                    // cmark's `goto` preserves), so the restarted email is gated exactly as cmark gates it.
                    sawSecondAt = true
                    break
                } else {
                    break
                }
            }
            if sawSecondAt {
                atSign = i
                continue
            }
            // The domain scan settled at `i` (a non-`@` terminator or `end`): every gate failure below is a
            // non-match for the whole `[at, i)` region, so resume there and skip the interior `@`s already
            // walked. (On the success path this is overwritten by the caller's use of `urlEnd`.)
            resumeAt = i
            // Before any trailing-punct trim, the last char of the scanned domain must be a LETTER or `.`
            // (cmark's `postprocess_text` gate: `cmark_isalpha(c) || c == '.'`). A digit there fails, so `f@.0`
            // / `a@b.c9` are rejected even though digits are allowed in the domain interior. This also rejects
            // `a.b-c_d@a.b_` - the trailing `_` is neither a letter nor `.`.
            if i <= atSign + 1 {
                return nil
            }
            let preTrimLast = content[i - 1]
            let preTrimAlphaOrDot = preTrimLast.isASCIILetter || preTrimLast == UInt8(ascii: ".")
            if !preTrimAlphaOrDot {
                return nil
            }
            let trimmedEnd = trimTrailingPunctuation(urlStart: localStart, urlEnd: i, content: content)
            if !hasDotFollowedByAlnum || domainStart == i || trimmedEnd <= atSign + 1 {
                return nil
            }
            let last = content[trimmedEnd - 1]
            let lastIsAlnum = last.isASCIILetter || last.isASCIIDigit
            if !lastIsAlnum {
                return nil
            }
            // why: unlike the `://`-scheme URL form (`schemeURLDomainAccepted`, cmark's `check_domain`), the
            // email path does NOT reject an underscore in the domain's last (or any) label. cmark's
            // `postprocess_text` (`extensions/autolink.c`) accepts `_` anywhere in the domain - its forward scan
            // treats `_` like `-` (`c != '-' && c != '_'` never breaks) and it never calls `check_domain`. So
            // `a@b.c_d`, `a@.b_o`, and `-@.b_o` all link, gated only by the letter-or-dot pre-trim check and the
            // trailing-alnum check above.
            return GFMAutolinkMatch(urlStart: localStart, urlEnd: trimmedEnd, form: .email, emailSchemeFolded: schemeFolded)
        }
    }

    /// Emit a zero-length `.text` node at virtual offset `offset` as a child of `parent`.
    ///
    /// Used flag-ON to reproduce the empty `before`/`after` siblings cmark-gfm's autolink extension leaves around a GFM autolink. The node carries no source range (its content is empty, so `stampInline` is a no-op) and positions are not part of the differential compare surface.
    private mutating func emitEmptyText(at offset: Int, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        let emptyRef = storage.intern(content.chunk(offset: offset, length: 0))
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(emptyRef))
        )
        storage.appendChild(textIdx, to: parent)
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

    /// Walk forward until a URL boundary: cmark whitespace (`cmark_isspace` - space, tab, LF, CR) or `<`.
    ///
    /// Mirrors cmark-gfm's URL body scan in `url_match` / `www_match` (`extensions/autolink.c`):
    /// `while (link_end < size && !cmark_isspace(data[link_end]) && data[link_end] != '<')`. `>` is NOT a
    /// boundary - it is an ordinary URL byte - and VT/FF are not `cmark_isspace` (they are HTML `spacechar`
    /// but class-0 here), so both stay in the URL. Hence `isSpaceTabOrNewline` (exactly `cmark_isspace`),
    /// not `isASCIISpace` (which also matches VT/FF).
    private func scanGFMURLBody(
        start: Int,
        end: Int,
        content: borrowing ContentSpan
    ) -> Int {
        var i = start
        while i < end {
            let b = content[i]
            if b.isSpaceTabOrNewline || b == UInt8(ascii: "<") {
                break
            }
            i += 1
        }
        return i
    }

    /// Trailing-boundary trim for a GFM autolink URL, mirroring cmark-gfm's `autolink_delim`
    /// (`extensions/autolink.c`) as a single pass from the end of the `[urlStart, urlEnd)` run that
    /// `scanGFMURLBody` (or the email domain scan) produced:
    ///
    /// - a trailing `? ! . , : * _ ~ ' "` is peeled, one character at a time;
    /// - a trailing `)` is peeled only when the run holds more `)` than `(`, so balanced parentheses
    ///   (`…/Pikachu_(Electric)`) are kept while a stray closing paren is dropped. The `(`/`)` totals are
    ///   counted once over the whole run; `closing` is decremented as each unbalanced `)` is removed;
    /// - a trailing `;` peels a whole `&…;` entity tail when one precedes it (`&`, then one or more ASCII
    ///   letters - `cmark_isalpha`, which excludes digits - then `;`), otherwise it peels just the `;`.
    ///
    /// These `)`, punctuation, and `;` cases are interleaved in one loop (as cmark does), so a mixed tail
    /// like `');` peels right-to-left correctly. A `<` never appears in the run (`scanGFMURLBody` and the
    /// email domain scan both stop at it), so cmark's `<`-truncation pass is a no-op and is omitted.
    private func trimTrailingPunctuation(urlStart: Int, urlEnd: Int, content: borrowing ContentSpan) -> Int {
        var opening = 0
        var closing = 0
        for j in urlStart..<urlEnd {
            switch content[j] {
            case UInt8(ascii: "("): opening += 1
            case UInt8(ascii: ")"): closing += 1
            default: break
            }
        }

        var i = urlEnd
        trim: while i > urlStart {
            switch content[i - 1] {
            case UInt8(ascii: ")"):
                if closing <= opening {
                    break trim
                }
                closing -= 1
                i -= 1
            case UInt8(ascii: "?"), UInt8(ascii: "!"), UInt8(ascii: "."), UInt8(ascii: ","),
                 UInt8(ascii: ":"), UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"),
                 UInt8(ascii: "'"), UInt8(ascii: "\""):
                i -= 1
            case UInt8(ascii: ";"):
                // Scan ASCII letters back from the char before the `;`; an entity tail is `&` + those
                // letters + `;`. Requiring at least one letter (`entityStart < i - 2`) matches cmark's
                // `new_end < link_end - 2` guard, so `&;` and a bare `;` peel only the `;`.
                var entityStart = i - 2
                while entityStart > urlStart, content[entityStart].isASCIILetter {
                    entityStart -= 1
                }
                if entityStart < i - 2, content[entityStart] == UInt8(ascii: "&") {
                    i = entityStart
                } else {
                    i -= 1
                }
            default:
                break trim
            }
        }
        return i
    }

    /// cmark-gfm's `check_domain` (`extensions/autolink.c`) domain-acceptance test, shared by the `www.` and
    /// `://`-scheme autolink forms. Scanning from the second domain byte and never examining the final content
    /// byte (`i < size - 1`), it rejects a domain that bears an underscore in either of its last two
    /// `.`-separated labels - a host-name restriction (`www.xxx.yyy._zzz` is not a host) waived only once the
    /// domain has more than ten labels, to bound cost (cmark's GHSA anti-quadratic guard). `requireDot` is
    /// cmark's `!allow_short`: the `www.` form (`allow_short: 0`) additionally demands at least one period the
    /// scan reaches, while the `://`-scheme form (`allow_short: 1`) accepts any non-empty domain of valid host
    /// chars. `base` is the first domain byte; `end` is the inline-content boundary (cmark scans to the chunk
    /// end, not to the trimmed URL), so a trailing `_` is left to the trailing-punctuation trim rather than
    /// failing the whole domain.
    private func checkDomainAccepted(base: Int, end: Int, requireDot: Bool, content: borrowing ContentSpan) -> Bool {
        let size = end - base
        var dotCount = 0
        var underscoresInPrevLabel = 0
        var underscoresInLastLabel = 0
        var i = 1
        while i < size - 1 {
            var b = content[base + i]
            if b == UInt8(ascii: "\\"), i < size - 2 {
                i += 1
                b = content[base + i]
            }
            if b == UInt8(ascii: "_") {
                underscoresInLastLabel += 1
            } else if b == UInt8(ascii: ".") {
                underscoresInPrevLabel = underscoresInLastLabel
                underscoresInLastLabel = 0
                dotCount += 1
            } else if !isValidGFMHostByte(b) && b != UInt8(ascii: "-") {
                break
            }
            i += 1
        }
        if (underscoresInPrevLabel > 0 || underscoresInLastLabel > 0) && dotCount <= 10 {
            return false
        }
        return requireDot ? dotCount > 0 : true
    }

    /// cmark-gfm's `://`-scheme domain acceptance (`sd_autolink_issafe` + `check_domain(..., allow_short: 1)`,
    /// `extensions/autolink.c`). Unlike the `www.` / email forms, a scheme URL does NOT require a dot: any
    /// non-empty domain whose first character is a valid host char is accepted, EXCEPT one bearing an
    /// underscore in either of its last two `.`-separated labels (deferred to `checkDomainAccepted`).
    /// `afterSlashes` is the first byte after `://`; `end` is the inline-content boundary.
    private func schemeURLDomainAccepted(afterSlashes: Int, end: Int, content: borrowing ContentSpan) -> Bool {
        // `sd_autolink_issafe`: the char immediately after `://` must be a valid host char.
        if !isValidGFMHostByte(content[afterSlashes]) {
            return false
        }
        return checkDomainAccepted(base: afterSlashes, end: end, requireDot: false, content: content)
    }

    /// Approximates cmark-gfm's `is_valid_hostchar` (`extensions/autolink.c`) for a single byte: a host char
    /// is neither whitespace nor punctuation (`cmark_utf8proc_is_space` / `cmark_utf8proc_is_punctuation`,
    /// `src/utf8.c`). For ASCII, `is_punctuation` routes through cmark's ctype table, so `isASCIIPunct` mirrors
    /// it exactly; `isASCIISpace` mirrors `is_space` for every byte the harness admits (the two differ only on
    /// VT (0x0B), which the harness filters and which `scanGFMURLBody` also treats as a boundary). The
    /// predicate thus admits ASCII alphanumerics - and, matching cmark, non-whitespace control bytes.
    ///
    /// A UTF-8 continuation byte (0x80-0xBF) is NOT a valid host byte: cmark's `is_valid_hostchar` runs
    /// `cmark_utf8proc_iterate` and returns 0 when it fails (`r < 0`), which it does on a byte that cannot
    /// START a codepoint. `check_domain` advances one byte at a time, so at the LEADING byte of a multibyte
    /// codepoint iterate succeeds and reports the codepoint's category (a non-space/non-punct char is valid),
    /// but the very next byte is a continuation byte where iterate fails and the scan breaks. The domain scan
    /// therefore stops inside the first multibyte codepoint and never advances past it. Rejecting continuation
    /// bytes reproduces that break: without it, the scan runs past a `�` (U+FFFD, whose repaired bytes are the
    /// input `String`'s own - the harness decodes invalid UTF-8 to U+FFFD before parsing) into a trailing
    /// `_`/`.` and spuriously triggers `checkDomainAccepted`'s underscore-in-last-label rejection.
    private func isValidGFMHostByte(_ b: UInt8) -> Bool {
        if b & 0b1100_0000 == 0b1000_0000 {
            return false
        }
        return !b.isASCIISpace && !b.isASCIIPunct
    }

    /// Allowlist of characters that may directly precede a GFM `www.` autolink.
    ///
    /// Only whitespace, `*`, `_`, `~`, `(` count as valid boundaries; everything else (including `<`)
    /// disqualifies the autolink, mirroring `www_match` in `extensions/autolink.c`. The `://`-scheme form
    /// (`url_match`) uses a looser rule - any non-ASCII-alpha preceding byte is fine (see
    /// `matchGFMSchemeAutolink`) - and the `@`-triggered email form imposes no such restriction at all
    /// (cmark's `postprocess_text`; see `matchGFMEmailAutolink`).
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
    /// `ignoringASCIICase` folds ASCII case on both sides (`| 0x20`) so a comparison mirrors cmark's
    /// `strncasecmp` — used for the `://`-scheme literals, which cmark validates case-insensitively
    /// (`sd_autolink_issafe`, `extensions/autolink.c`). The `www.` form stays exact (`memcmp` in cmark's
    /// `www_match`). Case-folding never touches the source bytes: only this comparison folds, so the
    /// matched destination/text keep the source case.
    private func bytesEqual(at start: Int, target: StaticString, content: borrowing ContentSpan, ignoringASCIICase: Bool = false) -> Bool {
        let len = target.utf8CodeUnitCount
        let ptr = target.utf8Start
        let mask: UInt8 = ignoringASCIICase ? 0x20 : 0
        for k in 0..<len {
            if (content[start + k] | mask) != (ptr[k] | mask) {
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
        // A text run can straddle a segment boundary when a lazy split-tab residual keeps a synthetic
        // arena segment in text flow (flag-ON, after a backslash hard break where the residual-skip does
        // not fire): `[start, end)` then spans the synthetic spaces and the following source line, which no
        // single buffer holds. Materialize such a run into the arena; a run within one segment stays
        // zero-copy. (An ordinary run never straddles - soft/hard breaks bound text at the newline.)
        let chunk = materializedChunk(start: start, end: end, content: content)
        let chunkRef = storage.intern(chunk)
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(chunkRef))
        )
        storage.appendChild(textIdx, to: parent)
        stampInline(textIdx, start, rangeEnd ?? end, content: content)
    }

    /// Build a `Chunk` for the virtual range `[start, end)`, materializing into the arena ONLY when the
    /// range straddles a segment boundary (multi-segment content whose bytes don't lie in one contiguous
    /// buffer region). Single-segment content and any range confined to one segment stay zero-copy - the
    /// contiguous slice is returned unchanged. This is the shared form of the join used by code spans and
    /// straddling text runs.
    private mutating func materializedChunk(start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        if let contiguous = content.contiguousChunk(fromVirtual: start, limit: end),
           contiguous.length == end - start {
            return contiguous
        }
        let outOffset = storage.strings.count
        for k in start..<end {
            storage.strings.append(content[k])
        }
        return Chunk(offset: outOffset, length: storage.strings.count - outOffset, inSource: false)
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
    }

    /// Merge runs of adjacent `.text` children into single nodes, recursing into containers.
    ///
    /// Smart-punctuation / entity substitutions emit their replacement as a separate text node (e.g. `"Markdown"` + `"’"` + `"s "`); cmark coalesces them into one text run. The merged node's content is the concatenation of the runs' segments and its source range is their union.
    mutating func consolidateTextNodes(_ parent: DocumentStorage.Index) {
        var child = storage[parent].firstChild
        while let current = child {
            if storage[current].kind == .text {
                // A `[^[` footnote-collapse node (bug-compat) stands in for cmark's embedded NUL, which ends
                // the consolidation run when it is read as a C-string. Merge preceding text INTO the run so
                // `x[^[` becomes one node (as cmark does), but do NOT absorb the following text: its invisible
                // tail is dropped in `dropRunTruncatedTails`, run AFTER the autolink pass so an email hiding
                // in that tail is linked first.
                if !storage.runTruncatingTextNodes.contains(current) {
                    // Absorb all immediately-following text siblings into `current`. Stop if a pair can't be merged (non-contiguous segment runs) so the loop always makes progress - otherwise the un-merged sibling would be revisited forever.
                    while let next = storage[current].next, storage[next].kind == .text {
                        let nextTruncates = storage.runTruncatingTextNodes.contains(next)
                        if !mergeTextNode(next, into: current) {
                            break
                        }
                        if nextTruncates {
                            // The `[^[` node folded into this run; the merged node inherits the mark and the
                            // run stops here (its tail is dropped later, not now).
                            storage.runTruncatingTextNodes.remove(next)
                            storage.runTruncatingTextNodes.insert(current)
                            break
                        }
                    }
                }
            } else {
                consolidateTextNodes(current)
            }
            child = storage[current].next
        }
    }

    /// Drop the invisible tail a `[^[` footnote-collapse node (bug-compat) leaves behind, after the autolink
    /// pass has run.
    ///
    /// A run-truncating node stands in for cmark's embedded NUL: at render cmark reads the consolidated run as
    /// a C-string and stops at the NUL, so the reconstructed node's own tail and any text merged after it in
    /// the run vanish. Reproduce that by unlinking the marked node's following text siblings - but only AFTER
    /// `gfmEmailAutolinkPass`, so an email in that tail is already carved into a `Link` (a non-text node that
    /// ends the run and survives, along with the empty text the split leaves after it). Recurses into
    /// containers like the autolink pass, since the collapse can sit inside a link or emphasis.
    mutating func dropRunTruncatedTails(_ parent: DocumentStorage.Index) {
        var child = storage[parent].firstChild
        while let current = child {
            if storage.runTruncatingTextNodes.contains(current) {
                storage.runTruncatingTextNodes.remove(current)
                var sib = storage[current].next
                while let s = sib, storage[s].kind == .text {
                    let after = storage[s].next
                    // A following text sibling may itself be run-truncating (two `[^[` collapses in a row);
                    // it is dropped here, so clear its mark too rather than leave a stale index in the set.
                    storage.runTruncatingTextNodes.remove(s)
                    storage.unlinkChild(s)
                    sib = after
                }
                child = storage[current].next
            } else {
                if storage[current].kind != .text {
                    dropRunTruncatedTails(current)
                }
                child = storage[current].next
            }
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
                // why: cmark's `cmark_consolidate_text_nodes` (swift-cmark `src/iterator.c`) sets the merged run's range from the FIRST node's start and the LAST node's end (`cur->end_column = tmp->end_column` on every iteration; `cur`'s start is never touched) - not a min/max union. In this pairwise left-to-right merge `dest` is the running-first node and `source` the next (last-so-far) sibling, so first-start = `dest.start` and last-end = `source.end`. This differs from a union only when a non-final node ends further right than the final node, where cmark collapses the run to the final node's end.
                storage.sourceRanges[dest] = DocumentStorage.SourceByteRange(
                    start: a.start,
                    end: b.end
                )
            } else if a.start < 0 {
                storage.sourceRanges[dest] = b
            }
        }
        storage.unlinkChild(source)
        return true
    }

    // MARK: - GFM email autolink post-pass

    /// Detect GFM `@`-triggered email autolinks in a post-pass over the consolidated inline tree.
    ///
    /// cmark-gfm runs autolink detection in `postprocess` (`extensions/autolink.c`) AFTER emphasis
    /// resolution and `cmark_consolidate_text_nodes`: it walks the finished tree and, for every text node
    /// that is not inside a link, splits it into `[before, link, after]` at each email match. The rewrite
    /// mirrors that here (run from the block/table/inline-only paths right after `consolidateTextNodes`),
    /// so a flanking `_`/`*` next to an email is already resolved as emphasis - or left as literal text
    /// folded into the local part - before the email boundaries are decided.
    ///
    /// Every non-link container (emphasis, strong, image, …) is recursed into, matching cmark iterating
    /// the whole tree; a link's own text - including a bare URL / email link just emitted - is never
    /// re-scanned as more link text.
    ///
    /// cmark's autolink `postprocess` (`extensions/autolink.c`) tracks link context with a single `in_link`
    /// BOOLEAN, not a nesting depth: entering a link arms it and exiting ANY link clears it. So a link
    /// nested in another link's text - e.g. an angle autolink `<a@b>` inside `[…]` link text - clears
    /// `in_link` when it closes, and the OUTER link's remaining text then gets autolinked. Flag-ON
    /// (`.cmarkBugCompatibility`) reproduces that boolean. Flag-OFF, since a link nested in a link is
    /// invalid HTML/CommonMark, the spec-correct deliverable never autolinks inside a link and skips its
    /// subtree.
    mutating func gfmEmailAutolinkPass(_ parent: DocumentStorage.Index) {
        var inLink = false
        gfmEmailAutolinkPass(parent, inLink: &inLink)
    }

    private mutating func gfmEmailAutolinkPass(_ parent: DocumentStorage.Index, inLink: inout Bool) {
        let bugCompat = storage.options.contains(.cmarkBugCompatibility)
        var child = storage[parent].firstChild
        while let current = child {
            // Capture the next sibling BEFORE splitting: `splitEmailsInTextNode` inserts the link/after
            // nodes between `current` and this sibling (and may unlink `current`), and resuming here skips
            // over everything it produced.
            let next = storage[current].next
            switch storage[current].kind {
            case .text:
                // Skip text inside a link (cmark's `!in_link`).
                if !inLink {
                    splitEmailsInTextNode(current, parent: parent)
                }
            case .link:
                // why: flag-ON reproduce cmark's `in_link` boolean by walking the link subtree with the
                // flag set - a nested link's exit clears it, so the outer link's later text is scanned.
                // Flag-OFF skip the subtree outright (never re-scan link text), matching the old behavior.
                if bugCompat {
                    inLink = true
                    gfmEmailAutolinkPass(current, inLink: &inLink)
                    inLink = false
                }
            default:
                gfmEmailAutolinkPass(current, inLink: &inLink)
            }
            child = next
        }
    }

    /// Split one text node into `[before, link, after]` at each GFM email autolink it contains.
    ///
    /// Reuses `matchGFMEmailAutolink` (the locked matcher) so the match/reject decisions are identical to
    /// the former inline path; only the emission moves to insertion-in-place. The node content is
    /// materialized into a scratch buffer ONCE and scanned left-to-right in a single pass (each backward
    /// local-part scan is bounded by the previous match's end), so cost is O(content length) - matching
    /// cmark's `postprocess_text`, not the quadratic re-scan its authors guard against. `before`/`after`/
    /// link-text are carved zero-copy from the node's existing segments (`subContentRef`); only the
    /// `mailto:` URL is materialized into the arena. Under `.cmarkBugCompatibility` an empty `before`/`after`
    /// is kept as an empty `Text` sibling (Quirk M); flag-OFF drops it for the spec-correct clean tree.
    private mutating func splitEmailsInTextNode(_ node: DocumentStorage.Index, parent: DocumentStorage.Index) {
        guard case .literal(let ref) = storage[node].data else {
            return
        }
        // Cheap early-out: a text node with no `@` is left exactly as it was (no allocation), matching
        // cmark returning it untouched. This is the overwhelmingly common case.
        if !contentRefContains(ref, byte: UInt8(ascii: "@")) {
            return
        }
        let keepEmpties = storage.options.contains(.cmarkBugCompatibility)
        var scratch = UniqueArray<UInt8>()
        materialize(ref, into: &scratch)
        let total = scratch.count
        // `content` addresses the whole node content by logical offset (0-based); it borrows `scratch`
        // only - storage mutations below don't touch it.
        let content = ContentSpan(span: scratch.span, base: 0, inSource: false)

        // `current` is the text node we are filling as the running `before`/`between` run; `segStart` is
        // where its text begins (in logical content offsets). `cursor` is the scan position and also the
        // floor for the next backward local-part scan (so a later `@` can't reach into a prior email).
        var current = node
        var segStart = 0
        var cursor = 0
        var didSplit = false
        var i = 0
        var resumeAt = 0
        while i < total {
            guard scratch[i] == UInt8(ascii: "@") else {
                i += 1
                continue
            }
            guard let auto = matchGFMEmailAutolink(
                at: i, localBound: cursor, end: total, content: content, resumeAt: &resumeAt
            ) else {
                // `matchGFMEmailAutolink` guarantees `resumeAt > i`, so this always advances (and skips any
                // `@`s the restart already settled - see its doc). O(content length) overall.
                //
                // why: cmark's `postprocess_text` (`extensions/autolink.c`) runs a single monotonic cursor
                // `start + offset`; a failed candidate advances it past the region scanned (`offset +=
                // max_rewind + link_end`), so the NEXT `@`'s backward local-part scan is bounded there
                // (`max_rewind = at - (data + start + offset)`) and cannot rewind into the abandoned
                // candidate. The rewrite splits that cursor into the forward scan `i` and the backward-scan
                // floor `cursor`; advancing both on failure preserves the bound. Otherwise a char the forward
                // domain scan breaks on but the backward scan accepts as a local-part char - `+`, or a `.`
                // not immediately followed by an alnum - is rewound through, pulling preceding text into the
                // next email's local part.
                cursor = resumeAt
                i = resumeAt
                continue
            }
            // `current` becomes the text run before this email.
            let beforeRef = subContentRef(of: ref, from: segStart, to: auto.urlStart)
            storage[current].data = .literal(beforeRef)
            if positionsEnabled {
                storage.sourceRanges[current] = .unset
            }
            stampFromContentRef(current, beforeRef)

            // The link node and its single text child (the visible email address).
            let emailRef = subContentRef(of: ref, from: auto.urlStart, to: auto.urlEnd)
            // A folded `mailto:`/`xmpp:` scheme means the destination IS the visible run (cmark suppresses
            // the synthetic `mailto:` and keeps `xmpp:`), so reuse the source-backed ref for the URL. A
            // plain email still gets `mailto:` synthesized into the arena.
            let urlRef = auto.emailSchemeFolded ? emailRef : materializeMailtoURL(for: emailRef)
            let linkIdx = storage.appendNode(NodeRecord(
                kind: .link, parent: parent, data: .link(url: urlRef, title: .empty)))
            let childIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: linkIdx, data: .literal(emailRef)))
            storage.appendChild(childIdx, to: linkIdx)
            storage.insertChildAfter(linkIdx, after: current)

            // A fresh text node spanning the remaining tail; it becomes the running run and is trimmed to
            // the next `between` segment on a further match, or kept as the final `after` run.
            let tailRef = subContentRef(of: ref, from: auto.urlEnd, to: total)
            let tailIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: parent, data: .literal(tailRef)))
            storage.insertChildAfter(tailIdx, after: linkIdx)
            stampFromContentRef(tailIdx, tailRef)

            // Flag-OFF: an empty `before` / `between` run is not a real text node, so drop it.
            if beforeRef.totalLength == 0, !keepEmpties {
                storage.unlinkChild(current)
            }
            current = tailIdx
            segStart = auto.urlEnd
            cursor = auto.urlEnd
            i = auto.urlEnd
            didSplit = true
        }
        // Flag-OFF: drop the final tail run if the split left it empty. Only ever a residual this pass
        // produced (`didSplit`), never a pre-existing `@`-free node.
        if didSplit, !keepEmpties, case .literal(let last) = storage[current].data, last.totalLength == 0 {
            storage.unlinkChild(current)
        }
        // A `[^[` footnote-collapse node (bug-compat) that also carried an email (the email precedes the
        // collapse, e.g. `f@.f[^[]]…`) has just been split: the split reuses `node` for the `before` run and
        // carves the `[^[` residual into the tail `current`. cmark's embedded NUL sits at the end of that
        // reconstructed prefix, so the run-truncating mark belongs on the tail - move it there so
        // `dropRunTruncatedTails` drops the tail's following siblings, not the `before` node's.
        if didSplit, storage.runTruncatingTextNodes.contains(node) {
            storage.runTruncatingTextNodes.remove(node)
            storage.runTruncatingTextNodes.insert(current)
        }
    }

    /// `true` if any byte of `ref`'s content equals `target`. Reads the source / arena buffers directly (no copy).
    private func contentRefContains(_ ref: ContentRef, byte target: UInt8) -> Bool {
        for s in 0..<Int(ref.count) {
            let seg = storage.segments[Int(ref.first) + s]
            let base = Int(seg.offset)
            let end = base + Int(seg.length)
            if seg.inSource {
                for k in base..<end where sourceBytes[k] == target { return true }
            } else {
                for k in base..<end where storage.strings[k] == target { return true }
            }
        }
        return false
    }

    /// Copy `ref`'s content bytes (across all its segments) into `out`. Reads the source / arena buffers.
    private func materialize(_ ref: ContentRef, into out: inout UniqueArray<UInt8>) {
        for s in 0..<Int(ref.count) {
            let seg = storage.segments[Int(ref.first) + s]
            let base = Int(seg.offset)
            let end = base + Int(seg.length)
            if seg.inSource {
                for k in base..<end { out.append(sourceBytes[k]) }
            } else {
                for k in base..<end { out.append(storage.strings[k]) }
            }
        }
    }

    /// Carve the logical sub-range `[lo, hi)` of `ref`'s content into a fresh `ContentRef`.
    ///
    /// Zero-copy: the carved segments still point into the same source / arena bytes (with `offset` and
    /// `sourceOffset` shifted for a partial leading segment); only new `Segment` entries are appended.
    private mutating func subContentRef(of ref: ContentRef, from lo: Int, to hi: Int) -> ContentRef {
        if hi <= lo {
            return .empty
        }
        let refFirst = Int(ref.first)
        let refCount = Int(ref.count)
        let newFirst = Int32(storage.segments.count)
        var count: Int32 = 0
        var total: Int32 = 0
        var v = 0
        for s in 0..<refCount {
            // Read the source segment into a local before appending, so the read ends before the append (no
            // aliasing of the growing pool). Original segments keep their indices; appends only grow the end.
            let seg = storage.segments[refFirst + s]
            let segLen = Int(seg.length)
            let segStart = v
            v += segLen
            let pieceLo = max(lo, segStart)
            let pieceHi = min(hi, v)
            if pieceHi <= pieceLo {
                continue
            }
            let localOffset = Int32(pieceLo - segStart)
            let pieceLen = Int32(pieceHi - pieceLo)
            storage.segments.append(Segment(
                offset: seg.offset + localOffset,
                length: pieceLen,
                inSource: seg.inSource,
                sourceOffset: seg.sourceOffset + localOffset
            ))
            count += 1
            total += pieceLen
        }
        if count == 0 {
            return .empty
        }
        return ContentRef(first: newFirst, count: count, totalLength: total)
    }

    /// Materialize `"mailto:"` + the content bytes of `emailRef` into the string arena and intern them.
    ///
    /// The email bytes are copied into an independent local buffer first (they may live in the arena, and
    /// reading the arena while appending to it would alias the growing buffer), then flushed to the arena.
    private mutating func materializeMailtoURL(for emailRef: ContentRef) -> ContentRef {
        var buf = UniqueArray<UInt8>()
        let prefix: StaticString = "mailto:"
        let prefixPtr = prefix.utf8Start
        for k in 0..<prefix.utf8CodeUnitCount {
            buf.append(prefixPtr[k])
        }
        materialize(emailRef, into: &buf)
        let offset = storage.strings.count
        for k in 0..<buf.count {
            storage.strings.append(buf[k])
        }
        return storage.intern(Chunk(offset: offset, length: buf.count, inSource: false))
    }

    /// Stamp `node`'s source range from a source-backed `ContentRef`, mirroring `stampInline`.
    ///
    /// Stamps only when both the first and last content bytes map to source (the carved segments are
    /// `inSource`); an empty or arena-backed piece is left position-less, exactly as `stampInline` would.
    private mutating func stampFromContentRef(_ node: DocumentStorage.Index, _ ref: ContentRef) {
        guard positionsEnabled, ref.count > 0 else {
            return
        }
        let firstSeg = storage.segments[Int(ref.first)]
        let lastSeg = storage.segments[Int(ref.first) + Int(ref.count) - 1]
        guard firstSeg.inSource, lastSeg.inSource else {
            return
        }
        storage.setSourceStart(node, Int(firstSeg.sourceOffset))
        storage.setSourceEnd(node, Int(lastSeg.sourceOffset) + Int(lastSeg.length))
    }
}
