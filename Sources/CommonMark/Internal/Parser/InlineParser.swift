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
/// Backed by the first 15 lanes of a `SIMD16<Int>` (row-major, lane `row * 5 + col`), so it back-deploys and stack-allocates (a nested `InlineArray` would be value-generic and require the anyAppleOS 26 runtime). The 16th lane is unused.
internal struct OpenersBottom {
    private var storage: SIMD16<Int>

    internal init(fill: Int) {
        storage = SIMD16(repeating: fill)
    }

    internal subscript(_ row: Int, _ col: Int) -> Int {
        get { storage[row * 5 + col] }
        set { storage[row * 5 + col] = newValue }
    }
}

/// Per-kind stretch of scan-start offsets from which a spec (first-closer) raw-HTML closer scan is known to
/// fail in the current `parseInline` pass. A scan that fails from `p` reached the content end, so it rules
/// out every start at or after `p`.
/// Without it, every unclosed opener of a kind rescans to the content end. Reset per `parseInline` pass.
internal struct HTMLCloserMisses {
    var comment: Range<Int> = 0..<0
    var cdata: Range<Int> = 0..<0
    var declaration: Range<Int> = 0..<0
    var processingInstruction: Range<Int> = 0..<0
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
    ) {
        if content.isEmpty {
            return
        }
        // The delimiter and bracket stacks are caller-owned scratch buffers, reused across every paragraph in the document. Reset them to empty rather than allocating per call.
        delimiters.removeSubrange(0..<delimiters.count)
        brackets.removeSubrange(0..<brackets.count)
        
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

        htmlCloserMisses = HTMLCloserMisses()
        characterReferenceSources.removeAll(keepingCapacity: true)

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
                    // Per Code spans, line endings become spaces before one leading and trailing space is stripped.
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
                let info: LineBreakInfo
                if preserveWhitespace {
                    // Preserving whitespace, a line ending is literal text rather than a soft line break or a trailing-space hard line break. A backslash before it forms a hard line break (Hard line breaks).
                    guard cursor > pendingTextStart, content[cursor - 1] == UInt8(ascii: "\\") else {
                        cursor += 1
                        continue
                    }
                    info = LineBreakInfo(isHard: true, textEnd: cursor - 1, isBackslash: true)
                } else {
                    info = classifyLineBreak(
                        at: cursor,
                        pendingTextStart: pendingTextStart,
                        content: content
                    )
                }
                flushPendingText(
                    start: pendingTextStart,
                    end: info.textEnd,
                    content: content,
                    into: parent
                )
                let kind: MarkdownNode.Kind = info.isHard ? .lineBreak : .softBreak
                let breakIdx = storage.appendNode(NodeRecord(kind: kind, parent: parent))
                storage.appendChild(breakIdx, to: parent)
                cursor += 1
                pendingTextStart = cursor

            case UInt8(ascii: "&"):
                // Entity matching reads a flat buffer by raw offset, so scan through a contiguous
                // window (see `contiguousChunk`): identity for single-segment content, the single
                // source segment's slice for multi-segment content (whose virtual offsets index no
                // single buffer). The line ending at a segment join terminates any entity name or
                // number, so a window from `&` to the segment end is sufficient.
                let contiguous = content.contiguousChunk(fromVirtual: cursor, limit: endOffset)
                precondition(contiguous != nil, "an `&` lies in a source segment: the only synthetic segment is the line join")
                let window = contiguous!
                // Match in an expression of its own so the borrowed `source` span (lifetime-dependent) stays scoped to the call and can't escape into the body.
                let entity: EntityParser.EntityMatch? = if window.inSource {
                    EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: sourceBytes)
                } else {
                    EntityParser.matchEntity(start: window.offset, end: window.offset + window.length, source: storage.strings.span)
                }
                if let entity {
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
                    if positionsEnabled {
                        let source = storage.sourceRanges[textIdx]
                        characterReferenceSources.append((decoded.range, Int(source.start)..<Int(source.end)))
                    }
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
                    // Links may not contain other links (Links), and an autolink binds more tightly
                    // than link text brackets, so the link openers before it cannot form links.
                    markLinkOpenersInactive(brackets: &brackets, lastBracket: lastBracket)
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
                    // The literal is the tag's raw bytes, zero-copy when they lie in one segment. A tag
                    // spanning a line ending in a non-contiguous paragraph has its bytes in separate
                    // segments, so the joined literal is materialized into the arena.
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
                    cursor = htmlEnd
                    pendingTextStart = cursor
                    continue
                }
                cursor += 1
                
            case UInt8(ascii: "*"), UInt8(ascii: "_"):
                cursor = handleDelimRun(
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
                    cursor = handleDelimRun(
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
                pushBracket(
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
                // `![^` opens no image: the `!` is literal text and the `[` opens a bracket, so `![^a]`
                // is `!` followed by a footnote reference, link or literal text.
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
                    // An opener whose image never resolves survives as literal `![` text; stamp its full 2-byte span so it keeps its start column when it consolidates with neighbors (a matched image unlinks this node first).
                    stampInline(textIdx, cursor, cursor + 2, content: content)
                    pushBracket(
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
                // Without `.attributes`, `^` is ordinary text and a following `[` opens a link bracket.
                if storage.options.contains(.attributes),
                   cursor + 1 < endOffset,
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
                    // An opener whose attribute never resolves survives as literal `^[` text; stamp it so it keeps its columns when it consolidates with neighbors.
                    stampInline(textIdx, cursor, cursor + 2, content: content)
                    pushBracket(
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
                // Backslash escape: `\<ASCII punct>` emits the punct as a single-byte text node. The line ending case handles `\<line ending>`. Anything else leaves the backslash as literal text.
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
                // `://` and `www.` extended autolinks are detected in this pass. Extended email autolinks
                // are detected by `gfmEmailAutolinkPass` after emphasis resolution, so a `_` or `*` beside
                // an email resolves as emphasis (or not) before the email's boundaries are decided.
                // The parser forms no `://` or `www.` extended autolink while a `[` or `![` opener is on
                // the bracket stack, so `[a http://t.t` is text. An `^[` opener does not suppress one.
                let insideLinkOrImageBracket = lastBracket.map { brackets[$0].insideLinkOrImage } ?? false
                if storage.options.contains(.gfmAutolink),
                   !insideLinkOrImageBracket,
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
                    cursor = handleQuoteDelim(
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
                    // The ellipsis glyph is arena-backed and its byte length differs from the `...` it replaces; stamp the three dots' source span so it keeps their columns.
                    stampInline(textIdx, cursor, cursor + 3, content: content)
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

    /// Bracket-stack entry recording an open `[` (LINK), `![` (IMAGE), or `^[` (ATTRIBUTE, the inline-attribute syntax). Like the delimiter stack, it's a linked list embedded in an array; `previous` is an index into `brackets` (or `nil`).
    internal struct BracketRecord {
        var kind: BracketKind
        var inlText: DocumentStorage.Index
        /// Virtual content offset of the opening `[` / `![` / `^[` byte. `buildLinkOrImage` / `handleCloseBracketAttribute` derive the wrapper's start from this so the map-aware stamp resolves arena/multi-segment content (the opener text node's stored chunk offset is already a source offset and would double-map).
        var virtualStart: Int
        /// Delimiter-stack index at time of push. Passed to `processEmphasis` as `stackBottom` after a successful link match so emphasis inside the link text gets resolved without leaking out.
        var delimPosition: Int
        /// `true` once any later bracket has been pushed on top of this one; an outer bracket that contains nested ones cannot take the shortcut reference form.
        var bracketAfter: Bool
        /// `true` when this bracket, or any bracket enclosing it, is a `.link` or `.image` opener. `://` and `www.` extended autolinks don't form while such a bracket is open; an `.attribute`-only chain does not suppress them.
        var insideLinkOrImage: Bool
        /// `true` once a link or autolink formed after this opener, which then cannot form a link: links may not
        /// contain other links (Links).
        var linkFormedAfter: Bool = false
        var previous: Int?
    }

    /// Marks every open link opener as unable to form a link, because a link or autolink formed after it.
    private func markLinkOpenersInactive(brackets: inout UniqueArray<BracketRecord>, lastBracket: Int?) {
        var idx = lastBracket
        while let i = idx {
            if brackets[i].kind == .link {
                brackets[i].linkFormedAfter = true
            }
            idx = brackets[i].previous
        }
    }

    private func pushBracket(kind: BracketKind, inlText: DocumentStorage.Index, virtualStart: Int, delimPosition: Int, brackets: inout UniqueArray<BracketRecord>, lastBracket: inout Int?, noLinkOpeners: inout Bool) {
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
        if !isImage && (noLinkOpeners || brackets[openerIdx].linkFormedAfter) {
            popBracket(brackets: &brackets, lastBracket: &lastBracket)
            emitBracketLiteral(at: cursor, content: content, parent: parent)
            return pos
        }
        // Virtual arithmetic below uses `brackets[openerIdx].virtualStart` (correct for multi-segment content), not the opener text node's stored source offset.
        var url: Chunk = .empty
        var title: Chunk = .empty
        var matched = false
        // Try inline link: `(url "title")`.
        if pos < end,
           content[pos] == UInt8(ascii: "(") {
            let afterParen = pos + 1
            let afterSpaces1 = skipSpaceChars(start: afterParen, end: end, content: content)
            // Scan the destination and title over virtual offsets: either may span a line ending in
            // multi-segment content (`<a\` LF `b>`, `'\'` LF `'`), which a one-segment contiguous window
            // would cut short.
            if let dest = matchLinkDestination(from: afterSpaces1, end: end, in: content) {
                let afterDest = dest.afterEnd
                let afterSpaces2 = skipSpaceChars(start: afterDest, end: end, content: content)
                var titleEnd = afterDest
                var titleInterior: Range<Int> = afterDest..<afterDest
                if afterSpaces2 > afterDest,
                   let t = matchLinkTitle(from: afterSpaces2, end: end, in: content) {
                    titleInterior = t.interior
                    titleEnd = t.afterEnd
                }
                let afterTitleSpaces = skipSpaceChars(start: titleEnd, end: end, content: content)
                if afterTitleSpaces < end,
                   content[afterTitleSpaces] == UInt8(ascii: ")") {
                    pos = afterTitleSpaces + 1
                    // The destination is trimmed, then unescaped and entity-decoded; the title is unescaped and entity-decoded without trimming. Inside arena content (a non-contiguous setext heading, a table cell with `\|`) either can be arena-backed, and either may span a line ending, so both are materialized (zero-copy within one segment).
                    url = cleanURLChunk(materializedChunk(start: dest.destination.lowerBound, end: dest.destination.upperBound, content: content))
                    title = unescapeURLChunk(materializedChunk(start: titleInterior.lowerBound, end: titleInterior.upperBound, content: content))
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
                // The full-reference label spans a line ending (`[text][la\nbel]`), which the contiguous
                // window can't image; carry the interior's virtual range and normalize it across the
                // join for lookup.
                labelRange = lab.interior
                afterRefForm = lab.afterEnd
            }
            // A collapsed `[]`, a whitespace-only `[   ]` or no label falls back to the shortcut form,
            // whose label is the bracket text, when no bracket is nested under this opener.
            var shortcutRange: Range<Int>?
            let labelIsBlank: Bool
            if let lc = labelChunk {
                labelIsBlank = lc.trimming(using: self).isEmpty
            } else if let lr = labelRange {
                labelIsBlank = normalizeLabel(virtualRange: lr, in: content).isEmpty
            } else {
                labelIsBlank = true
            }
            // A whitespace-only `[ ]` is neither a link label nor `[]` (Links: a link label holds a
            // non-whitespace character), so a shortcut reference before it leaves it as text.
            let labelIsWhitespace = labelIsBlank && (labelChunk.map { $0.length > 0 } ?? (labelRange.map { !$0.isEmpty } ?? false))
            if labelIsWhitespace {
                afterRefForm = pos
            }
            if labelIsBlank && !openerBracketAfter {
                // The shortcut label runs from just past the opener to the `]` at `cursor`. Within one segment it resolves from a contiguous chunk; a label spanning a line ending (`[foo\nbar]`) carries its virtual range and normalizes across the join.
                let openerContentStart = brackets[openerIdx].virtualStart + (isImage ? 2 : 1)
                let shortcutLen = cursor - openerContentStart
                // A link label has at most 999 characters inside its brackets (Links), so a longer shortcut stays literal.
                if shortcutLen > 0,
                   linkLabelFitsLengthCap(virtualRange: openerContentStart..<cursor, in: content) {
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
            if let key, !key.isEmpty,
               let ref = storage.referenceMap[key] {
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
                markLinkOpenersInactive(brackets: &brackets, lastBracket: lastBracket)
            }
            return pos
        }
        // With no link form matched, a `[^label]` whose label names a footnote definition is a footnote
        // reference. Any other bracket stays literal text through the no-match handling below; the
        // footnote map is complete before inline parsing.
        let footnoteBracketStart = brackets[openerIdx].virtualStart + (isImage ? 1 : 0)
        // When an inner `^[…](…)` or `^[…][ref]` formed an attribute, the node after the opener is that
        // attribute rather than text, and the bracket stays literal (`[^[]()]` is `[`, an attribute and `]`).
        let footnoteAfterOpenerIsText = storage[openerInl].next.map { storage[$0].kind == .text } ?? false
        if storage.options.contains(.footnotes),
           footnoteAfterOpenerIsText,
           let defIdx = footnoteDefinition(referencedFrom: footnoteBracketStart, closeBracket: cursor, in: content) {
            // Resolve emphasis inside the bracket first (clearing its delimiters from the stack) so
            // removing the inner nodes below doesn't leave stale delimiters for `processEmphasis`.
            processEmphasis(stackBottom: openerDelimPos, content: content, delimiters: &delimiters, lastDelim: &lastDelim)
            emitFootnoteReference(openerInl: openerInl, definition: defIdx, span: footnoteBracketStart..<(cursor + 1), content: content)
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

    /// The footnote definition the footnote-shaped bracket from `open` to `closeBracket` references, or `nil`.
    /// Its label - everything after the `^` - matches a definition's label after the normalization link labels
    /// get (Links: case-folded, with runs of whitespace, line endings included, collapsed to one
    /// space and leading and trailing whitespace removed), so it may span a line ending.
    private func footnoteDefinition(referencedFrom open: Int, closeBracket: Int, in content: borrowing ContentSpan) -> DocumentStorage.Index? {
        let labelStart = open + 2
        guard labelStart < closeBracket, content[open + 1] == UInt8(ascii: "^"),
              linkLabelFitsLengthCap(virtualRange: labelStart..<closeBracket, in: content) else {
            return nil
        }
        return storage.footnoteMap[normalizeLabel(virtualRange: labelStart..<closeBracket, in: content)]
    }

    /// Splice a `.footnoteReference` node in place of the opener's bracket text node and any inner-content text nodes.
    ///
    /// Only called with the `definition` the reference's label resolved to (`footnoteDefinition`). The reference's index (and the
    /// definition's `referenceCount`) is assigned later, by the footnote post-processing pass over the
    /// finalized tree, because an enclosing bracket can discard this reference; until then it
    /// carries a placeholder index of 0. The emitted reference carries the *definition's* raw label, so
    /// `[^Foo]` resolving to `[^foo]` displays `foo`.
    ///
    /// The opener node is removed whole: a `[` (`![^a]` never opens an image bracket, see the `!` dispatch,
    /// so it reaches here as a literal `!` followed by a `[` opener).
    ///
    /// The reference's source range is `span`, the virtual range of `content` it replaces: from its opener to just past its `]`.
    private mutating func emitFootnoteReference(openerInl: DocumentStorage.Index, definition defIdx: DocumentStorage.Index, span: Range<Int>, content: borrowing ContentSpan) {
        guard case .footnoteDefinition(let defLabel, _) = storage[defIdx].data else {
            preconditionFailure("footnoteMap holds only footnote definitions")
        }
        let parentIdx = storage[openerInl].parent
        let fnRefIdx = storage.appendNode(NodeRecord(
            kind: .footnoteReference(index: 0),
            parent: parentIdx,
            data: .footnoteReference(label: defLabel)
        ))
        storage.insertChildBefore(fnRefIdx, before: openerInl)
        stampInline(fnRefIdx, span.lowerBound, span.upperBound, content: content)
        storage.unlinkChild(openerInl)
        // Detach inner-content text nodes (the `^label` part) that follow the reference. They aren't part of the reference's emitted text - the reference is rendered by the consumer based on its label and index.
        var sib = storage[fnRefIdx].next
        while let sib_ = sib {
            let nextSib = storage[sib_].next
            storage.unlinkChild(sib_)
            sib = nextSib
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
        // Otherwise try the reference form `[label]`, whose label must name an entry in
        // `attributeReferenceMap`.
        var labelKey: String?
        // The inline form completes the construct; what follows it is not part of it.
        if !matched, let labelWindow = content.contiguousChunk(fromVirtual: pos, limit: end),
           let lab = matchLinkLabel(labelWindow) {
            // Contiguous window (see `contiguousChunk`): `lab.interior` is a real buffer chunk and
            // `lab.afterEnd` a buffer offset converted back to virtual via the window base.
            pos = pos + (lab.afterEnd - labelWindow.offset)
            if lab.interior.length > 0 {
                labelKey = normalizeLabel(chunk: lab.interior)
            }
        } else if !matched, let lab = matchLinkLabel(from: pos, end: end, in: content) {
            // The label spans a line ending (`^[x][la\nbel]`), past the end of the contiguous window;
            // normalize the interior across the join for lookup.
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
            // Fail: pop bracket, emit `]` as text and resume just past it. The `^[` text node stays as
            // text. A label naming no attribute definition is not part of the construct, so it is parsed
            // again as text.
            pos = cursor + 1
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
    /// Zero-copy when the range lies in one segment. An interior spanning a line ending in a
    /// non-contiguous paragraph (e.g. ` ^[](\n)`) lies in separate segments, so its joined bytes are
    /// materialized into the arena; the line ending is ordinary attribute content. An empty `()` is a
    /// zero-length chunk.
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

    /// One node in the delimiter stack of the emphasis-resolution algorithm (Appendix: A parsing strategy). Each record points at a `.text` node whose literal contains a delimiter run scanned during the forward pass.
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

    /// Classify a delimiter run as left- and/or right-flanking (Emphasis and strong emphasis).
    ///
    /// With strikethrough enabled, a `*`, `_` or quote run reads its bordering characters past any
    /// adjacent `~` run, so the closing `*` in `*-*~a` borders `a`, is left-flanking only, and closes
    /// no emphasis. A `~` run reads its immediate neighbours.
    private func classifyFlanking(char: UInt8, start: Int, runEnd: Int, end: Int, content: borrowing ContentSpan) -> Flanking {
        let chunkStart = content.startOffset
        let tilde = UInt8(ascii: "~")
        let skipTilde = char != tilde && storage.options.contains(.strikethrough)
        // "Before" character - the start of the content counts as a line ending; skip a leading `~` run.
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
        // Flanking is defined over characters, so a non-ASCII Unicode whitespace character or
        // punctuation character neighbour (e.g. U+00A0, U+2014) counts as one. `beforeChar` keeps the
        // raw byte for the quote `]`/`)` rule; a multi-byte scalar never equals those.
        let beforeScalar: Int32 = beforeIdx >= chunkStart
            ? Self.flankingScalarBefore(endingAt: beforeIdx, lowerBound: chunkStart, content: content)
            : 0x0A
        let afterScalar: Int32 = afterIdx < end
            ? Self.flankingScalarAfter(startingAt: afterIdx, content: content)
            : 0x0A
        let beforeIsSpace = Self.isUnicodeWhitespace(beforeScalar)
        let beforeIsPunct = Self.isUnicodePunctuation(beforeScalar)
        let afterIsSpace = Self.isUnicodeWhitespace(afterScalar)
        let afterIsPunct = Self.isUnicodePunctuation(afterScalar)
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
    /// `lowerBound`) to the lead byte and decode.
    @inline(__always)
    private static func flankingScalarBefore(endingAt endIdx: Int, lowerBound: Int, content: borrowing ContentSpan) -> Int32 {
        let last = content[endIdx]
        if last < 0x80 { return Int32(last) }
        var lead = endIdx
        while lead > lowerBound, content[lead] & 0xC0 == 0x80 { lead -= 1 }
        return decodeUTF8Scalar(at: lead, content: content)
    }

    /// The Unicode scalar just after a delimiter run, beginning at `idx`.
    @inline(__always)
    private static func flankingScalarAfter(startingAt idx: Int, content: borrowing ContentSpan) -> Int32 {
        let first = content[idx]
        if first < 0x80 { return Int32(first) }
        return decodeUTF8Scalar(at: idx, content: content)
    }

    /// Decode the multi-byte UTF-8 scalar whose lead byte is at `idx`. Inline content is valid UTF-8 cut only on
    /// ASCII bytes, so the whole sequence lies inside the content.
    private static func decodeUTF8Scalar(at idx: Int, content: borrowing ContentSpan) -> Int32 {
        let b0 = content[idx]
        precondition(b0 >= 0xC2 && b0 <= 0xF4, "inline content is valid UTF-8, so a decoded scalar starts at a multi-byte lead byte")
        if b0 < 0xE0 {
            return (Int32(b0 & 0x1F) << 6) | Int32(content[idx + 1] & 0x3F)
        }
        if b0 < 0xF0 {
            return (Int32(b0 & 0x0F) << 12) | (Int32(content[idx + 1] & 0x3F) << 6) | Int32(content[idx + 2] & 0x3F)
        }
        return (Int32(b0 & 0x07) << 18) | (Int32(content[idx + 1] & 0x3F) << 12) | (Int32(content[idx + 2] & 0x3F) << 6) | Int32(content[idx + 3] & 0x3F)
    }

    /// Whether `uc` is a Unicode whitespace character (Characters and lines): the Zs general category
    /// plus tab, line feed, form feed and carriage return.
    @inline(__always)
    private static func isUnicodeWhitespace(_ uc: Int32) -> Bool {
        if uc < 0x80 { return UInt8(uc).isFlankingSpace }
        switch uc {
        case 160, 5760, 8192...8202, 8239, 8287, 12288:
            return true
        default:
            return false
        }
    }

    /// Whether `uc` is a punctuation character (Characters and lines): an ASCII punctuation character or
    /// a member of the Pc, Pd, Pe, Pf, Pi, Po or Ps general categories.
    @inline(__always)
    private static func isUnicodePunctuation(_ uc: Int32) -> Bool {
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

    /// Scan a maximal delimiter run of `char` starting at `start`, decide whether it can open and close (Emphasis and strong emphasis), emit a `.text` node for the run, and (if it can open or close) push a delimiter record onto the stack. Returns the offset just past the run.
    ///
    /// The start of the content counts as a line ending before the run.
    private mutating func handleDelimRun(char: UInt8, start: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, pendingTextStart: inout Int) -> Int {
        var runEnd = start
        while runEnd < end, content[runEnd] == char {
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
        // A run that can neither open nor close stays in the pending text, so the extended email
        // autolink pass sees an unbroken local part (`a.b-c_d@a.b`). A `~` run always emits its own
        // text node; a non-flanking `~` run is surrounded by whitespace, so it never falls inside an
        // autolink.
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
        // A delimiter that forms no emphasis stays literal text, and this range keeps its columns when it consolidates with adjacent text.
        stampInline(textIdx, start, runEnd, content: content)
        if canOpen || canClose {
            // Strikethrough (extension) wraps text in two tildes. The parser also accepts a single tilde
            // unless `.strikethroughDoubleTilde` is set; a `~` run of any other length stays literal text.
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
                    // The parser applies the multiple-of-3 test of rules 9 and 10 (Emphasis and strong
                    // emphasis) to `~` as well as `*` and `_`. A `~` opener is accepted whatever its length:
                    // `insertEmph` discards a mismatched pair, so a closer never reaches past the nearest
                    // `~` opener to a farther one of equal length.
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
            // Strikethrough forms only between runs of equal length. On a mismatch both runs stay
            // literal text, and every delimiter from the closer back through the opener is removed,
            // so a farther opener can't pair with this closer.
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
        // The delimiter records' `length` stays the original run length: the multiple-of-3 test of
        // rules 9 and 10 sums the lengths of the delimiter runs, and `processEmphasis` indexes
        // `openersBottom` by it. A closer reduced from 4 to 2 must keep its original slot, or a floor
        // lowered by an unpairable interior run would suppress the leftover pairing (`****a**o****`
        // nests as Strong>Strong>Text "a**o"). The remaining count, which governs how many characters
        // this pairing consumes, is the text literal's length (`literalLength` above).
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
        guard case .literal(let ref) = storage[nodeIdx].data else {
            preconditionFailure("a delimiter run's text node holds a literal")
        }
        return Int(ref.totalLength)
    }

    // MARK: - Smart punctuation

    /// UTF-8 bytes for the smart-punctuation replacement characters.
    static let leftSingleQuote = "\u{2018}"
    static let rightSingleQuote = "\u{2019}"
    static let leftDoubleQuote = "\u{201C}"
    static let rightDoubleQuote = "\u{201D}"
    static let enDash = "\u{2013}"
    static let emDash = "\u{2014}"
    static let ellipsis = "\u{2026}"

    /// Append a constant UTF-8 byte sequence into the string arena.
    private mutating func appendSmartConstant(_ s: String) {
        for b in s.utf8 {
            storage.strings.append(b)
        }
    }

    /// Append a constant UTF-8 byte sequence into the string arena and intern it as a literal content ref.
    private mutating func internSmartLiteral(_ s: String) -> ContentRef {
        let offset = storage.strings.count
        appendSmartConstant(s)
        let chunk = Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
        return storage.intern(chunk)
    }

    /// Replace a text node's literal with a constant smart-punctuation glyph.
    private mutating func setSmartLiteral(of nodeIdx: DocumentStorage.Index, _ s: String) {
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
    private mutating func handleQuoteDelim(char: UInt8, start: Int, end: Int, content: borrowing ContentSpan, parent: DocumentStorage.Index, delimiters: inout UniqueArray<DelimiterRecord>, lastDelim: inout Int?, pendingTextStart: inout Int) -> Int {
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
        let literal: String
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
    private mutating func matchCodeSpan(start: Int, end: Int, content: borrowing ContentSpan) -> CodeSpanMatch? {
        let openEnd = scanBacktickRun(start: start, end: end, content: content)
        let runLength = openEnd - start

        // Find a matching same-length backtick run after `openEnd`.
        var i = openEnd
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: "`") {
                let closeEnd = scanBacktickRun(start: i, end: end, content: content)
                let closeLength = closeEnd - i
                if closeLength == runLength {
                    // Return the raw content `[openEnd, i)`; the caller converts line endings to spaces before
                    // the one-space strip, which compares the converted bytes. A span crossing a line ending in
                    // a non-contiguous paragraph lies in separate segments, which `materializedChunk` joins
                    // (zero-copy within one segment). Each continuation line, lazy or not, begins at its first
                    // non-space character, so its leading whitespace is not part of the content (Paragraphs).
                    let contentChunk = materializedChunk(start: openEnd, end: i, content: content)
                    return CodeSpanMatch(content: contentChunk, afterClose: closeEnd, backtickCount: runLength)
                }
                i = closeEnd
                continue
            }
            i += 1
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

    /// Apply code span normalization (Code spans) to raw content.
    ///
    /// 1. Replace each line ending with a single space. (Inline content joins lines with `\n` alone.)
    /// 2. If the result begins AND ends with a space and isn't all spaces, strip one space from each end.
    ///
    /// Returns either the original chunk (if no changes) or a new chunk pointing at materialized bytes in `storage.strings`.
    private mutating func normalizeCodeSpanContent(_ chunk: Chunk) -> Chunk {
        var hasNewline = false
        let endOff = chunk.offset + chunk.length
        for i in chunk.offset..<endOff {
            let b = readByte(at: i, in: chunk)
            if b == UInt8(ascii: "\n") {
                hasNewline = true
                break
            }
        }
        var workChunk: Chunk
        if hasNewline {
            // Materialize with line endings replaced by spaces.
            let outOffset = storage.strings.count
            var i = chunk.offset
            while i < endOff {
                let b = readByte(at: i, in: chunk)
                assert(b != UInt8(ascii: "\r"), "inline content holds no carriage return: lines split on CR and join with LF")
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
        return trimSingleSpaces(workChunk)
    }

    /// Apply the code span one-space strip (Code spans).
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

    /// Decide whether the line ending at `newlineOffset` is a soft or hard line break (Hard line breaks):
    /// - Hard if a `\` immediately precedes the line ending (with at least one byte in the pending-text region).
    /// - Hard if 2+ spaces immediately precede the line ending.
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
        // Spaces and tabs before a line ending are not part of the text, whatever the break kind; a
        // line tabulation or form feed is (`a\f\t  \n` keeps `a\f`). The break is hard when the two
        // characters immediately before the line ending are spaces, so `a  \t\n` is soft.
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

    /// Try to match an autolink (Autolinks) starting at `start` (which points at `<`). URI form first, email form as fallback.
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
        // Scan body until `>`. An absolute URI excludes ASCII control characters, DEL (0x7F) included.
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
                || b == 0x7F {
                return nil
            }
            i += 1
        }
        return nil
    }

    /// Email autolink: `<local@domain>` where `local@domain` is an email address as Autolinks defines it, with `domain` made of dot-separated labels.
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
        // The local-part loop stopped on the `@`.
        i += 1
        // Domain: 1+ labels separated by `.`. Each label: letter/digit, optional letters/digits/hyphens, ending with letter/digit. Up to 63 chars per label.
        let domainStart = i
        let labelStart = i
        while i < end {
            let b = content[i]
            if b == UInt8(ascii: ">") {
                break
            }
            // Stop at the first byte no domain can contain: scanning on to a distant `>` or the block's
            // end would make each unclosed `<local@` cost O(block length).
            if !(b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: ".")) {
                return nil
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

    /// Whether `b` may appear in the local part of an extended email autolink (Autolinks (extension)):
    /// alphanumeric, `.`, `-`, `_` or `+`.
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
        precondition(!range.isEmpty, "an email autolink's domain holds at least one byte")
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
                assert(b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-"), "the domain scan admits only letters, digits, `-` and `.`")
                labelLen += 1
            }
            i += 1
        }
        return true
    }

    /// Emit a `.link` node + a single `.text` child for an autolink match.
    ///
    /// The text is the interior with entity and numeric character references decoded, materialized into the string arena only when a `&` is present; backslash escapes do not work in autolinks (Backslash escapes). For email forms, the URL gets a `mailto:` prefix and is materialized into the string arena; an email address admits no `;`, so its interior holds no reference to decode. For URI forms, the URL is the decoded text.
    private mutating func emitAutolink(auto: AutolinkMatch, into parent: DocumentStorage.Index, content: borrowing ContentSpan) {
        let textChunk = unescapeURLChunk(
            content.chunk(offset: auto.interior.lowerBound, length: auto.interior.count),
            backslashEscapes: false
        )
        let urlChunk: Chunk
        if auto.isEmail {
            // Build `mailto:` + interior into the string arena.
            let offset = storage.strings.count
            for b in "mailto:".utf8 {
                storage.strings.append(b)
            }
            for j in auto.interior {
                storage.strings.append(content[j])
            }
            // Materialized into the arena, so `inSource: false` regardless of `content`'s buffer.
            urlChunk = Chunk(offset: offset, length: storage.strings.count - offset, inSource: false)
        } else {
            urlChunk = textChunk
        }
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
    /// (Raw HTML)
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
        let afterName = scanTagName(start: i, end: end, content: content)
        precondition(afterName != nil, "an open tag is matched only when its `<` is followed by a letter")
        i = afterName!
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
        return Self.scanRawHTMLCloser("-->", from: bodyStart, end: end, content: content, misses: &htmlCloserMisses.comment)
    }

    /// Match `<![CDATA[…]]>`. Per the CDATA section definition (Raw HTML) the content is any run not
    /// containing `]]>`, closed by the first `]]>`.
    private mutating func matchHTMLCDATA(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        // Need `<![CDATA[`, with `CDATA` matched case-sensitively.
        let prefixLen = 9
        if start + prefixLen > end {
            return nil
        }
        let prefix = "<![CDATA["
        for (k, prefixByte) in prefix.utf8.enumerated() {
            if content[start + k] != prefixByte {
                return nil
            }
        }
        return Self.scanRawHTMLCloser("]]>", from: start + prefixLen, end: end, content: content, misses: &htmlCloserMisses.cdata)
    }

    /// Match `<!NAME …>` where NAME is `[A-Z]+`, followed by at least one spacechar, any non-`>` non-NUL chars, then `>`.
    private mutating func matchHTMLDeclaration(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
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
        return Self.scanRawHTMLCloser(">", from: afterSpaces, end: end, content: content, misses: &htmlCloserMisses.declaration)
    }

    /// Match `<?…?>`. Body may be empty; scans for the first `?>` terminator rejecting NUL bytes.
    ///
    /// Per the processing instruction definition (Raw HTML) the body is any string of characters not
    /// including `?>`, so this stops at the first `?>`.
    private mutating func matchHTMLProcessingInstruction(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        return Self.scanRawHTMLCloser("?>", from: start + 2, end: end, content: content, misses: &htmlCloserMisses.processingInstruction)
    }

    /// Scan for the first `closer` starting at or after `start`. Returns the offset just past it, or `nil` if the end of the content comes first.
    ///
    /// `misses` is the kind's stretch of scan starts already known to fail (`HTMLCloserMisses`): a `start` inside it returns `nil` without rescanning, and a failing scan replaces it with the stretch that scan rules out. Both are exact: a scan from any later start inside that stretch sees a subset of the same bytes, none of which begins `closer`, and then the same content end.
    private static func scanRawHTMLCloser(
        _ closer: String, from start: Int, end: Int, content: borrowing ContentSpan, misses: inout Range<Int>
    ) -> Int? {
        if misses.contains(start) {
            return nil
        }
        let width = closer.utf8.count
        var i = start
        while i + width <= end {
            assert(content[i] != 0, "inline content holds no NUL: the block parser replaces it with U+FFFD")
            var matched = 0
            for closerByte in closer.utf8 {
                if content[i + matched] != closerByte {
                    break
                }
                matched += 1
            }
            if matched == width {
                return i + width
            }
            i += 1
        }
        misses = start..<Int.max
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
                assert(b != 0, "inline content holds no NUL: the block parser replaces it with U+FFFD")
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
            assert(b != 0, "inline content holds no NUL: the block parser replaces it with U+FFFD")
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

    // MARK: - Extended autolinks

    /// Form of a matched extended autolink - affects how the destination URL is built when the node is emitted (`www.` needs a synthetic `http://` prefix; emails need `mailto:`).
    private enum GFMAutolinkForm {
        case uri      // already has http:// or https:// or ftp:// prefix
        case www      // needs http:// synthesized
        case email    // needs mailto: synthesized
    }

    /// Result of an extended autolink match. Carries the visible text range (used for the link's child `.text` node) plus the form so the emit step knows whether to synthesize a scheme prefix.
    ///
    /// `emailSchemeFolded` is set only for the email form when `[urlStart, urlEnd)` begins with a folded
    /// `mailto:`/`xmpp:` scheme. The destination is then the folded run itself, with no synthetic
    /// `mailto:` prefix, so `xmpp:` keeps its own scheme.
    private struct GFMAutolinkMatch {
        var urlStart: Int
        var urlEnd: Int
        var form: GFMAutolinkForm
        var emailSchemeFolded: Bool = false
    }

    /// Dispatch a `://` or `www.` extended autolink trial based on the trigger byte. Returns nil if no autolink starts at / contains `cursor`. The `@`-triggered email form is handled separately in `gfmEmailAutolinkPass`, not here.
    private func matchGFMAutolink(trigger: UInt8, cursor: Int, end: Int, content: borrowing ContentSpan) -> GFMAutolinkMatch? {
        if trigger == UInt8(ascii: ":") {
            return matchGFMSchemeAutolink(
                colon: cursor, end: end,
                content: content
            )
        }
        precondition(trigger == UInt8(ascii: "w") || trigger == UInt8(ascii: "W"), "a GFM autolink trial is dispatched only on `:`, `w` or `W`")
        return matchGFMWWWAutolink(
            start: cursor, end: end,
            content: content
        )
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
            // The scheme is the maximal run of ASCII letters before `://`, so a letter before `http`
            // makes the scheme something else (`xhttp://a.b` is text). Any other preceding byte, unlike
            // the `www.` form's `isValidGFMPreceding` set, is allowed.
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
        let domainAccepted = validDomainEnd(start: colon + 3, end: trimmedEnd, content: content) != nil
        if !domainAccepted {
            return nil
        }
        return GFMAutolinkMatch(
            urlStart: schemeStart,
            urlEnd: trimmedEnd,
            form: .uri
        )
    }

    /// Find the start position of `http`, `https`, or `ftp` (matched case-insensitively) ending just
    /// before `colon`. Returns the scheme's first-byte offset, or nil.
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
        let urlEnd = scanGFMURLBody(start: start + 4, end: end, content: content)
        let trimmedEnd = trimTrailingPunctuation(
            urlStart: start, urlEnd: urlEnd,
            content: content
        )
        // The trailing punctuation removed above is not part of the autolink, so neither is it part of
        // its domain.
        guard validDomainEnd(start: start + 4, end: trimmedEnd, content: content) != nil else {
            return nil
        }
        return GFMAutolinkMatch(urlStart: start, urlEnd: trimmedEnd, form: .www)
    }

    /// Decide whether the `:` at `colon` completes the given lowercase scheme literal (`mailto:` /
    /// `xmpp:`, `:` included) sitting at a boundary, so the scheme folds into an extended email autolink.
    /// Returns the scheme's byte length, or nil.
    ///
    /// A scheme qualifies when its bytes lie fully within the scan window `[localBound, colon]`, match the
    /// literal case-sensitively (`MAILTO:` does not match), and either begin exactly at `localBound` or are
    /// preceded by a non-alphanumeric byte (`amailto:` fails).
    private func matchEmailScheme(_ scheme: String, colon: Int, localBound: Int, content: borrowing ContentSpan) -> Int? {
        let len = scheme.utf8.count
        let schemeStart = colon + 1 - len
        if schemeStart < localBound {
            return nil
        }
        for (k, schemeByte) in scheme.utf8.enumerated() where content[schemeStart + k] != schemeByte {
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
    /// domain, restarting from a second `@` met mid-domain (see the loop).
    ///
    /// `localBound` is the earliest offset the backward local-part scan may reach - the content start for a
    /// fresh scan, or the end of the previous email when scanning a text node with several `@`s.
    ///
    /// On a non-match the function returns nil and sets `resumeAt` to the offset just past everything it
    /// scanned (`> at` always). Every `@` in `[at, resumeAt)` - the trial `@` plus any `@`s the restart
    /// walked over - provably cannot start an email (a restart that reaches those `@`s fresh
    /// carries no more periods than this scan did, so it fails identically), so the caller skips straight to
    /// `resumeAt`. This keeps the whole pass O(content length) even on `@`-dense input.
    private func matchGFMEmailAutolink(at: Int, localBound: Int, end: Int, content: borrowing ContentSpan, resumeAt: inout Int) -> GFMAutolinkMatch? {
        // `atSign` is the `@` under trial. A second `@` met during the domain scan abandons the current
        // candidate and restarts from that `@`, the run between the two becoming the new local part.
        // The scheme state below carries across the restart; `localStart` and the domain cursor are
        // recomputed from `atSign`.
        var atSign = at
        var schemeFolded = false
        var isXmpp = false
        while true {
            // The local part stops at the first character an extended email autolink's local part can't
            // hold (`isGFMEmailLocalChar`). A `:` completing a lowercase `mailto:` or `xmpp:` scheme at a
            // boundary is instead folded into the link text and destination; an `xmpp:` destination keeps
            // that scheme.
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
            // No local part and no folded scheme: not an email at this `@`; resume just past it. A folded
            // scheme moves `localStart` back even when the local part is empty, so `mailto:@a.b` is accepted
            // here.
            if localStart == atSign {
                resumeAt = atSign + 1
                return nil
            }
            // Unlike the `www.` form, an email has no preceding-character restriction: whatever precedes
            // the local part stays text, so `<o@a.b` is `<` followed by a link.
            // The domain is one or more segments of alphanumerics, `-` and `_` separated by periods, with
            // at least one period, ending in neither `-` nor `_` (Autolinks (extension)). A period no
            // segment follows ends the address before it.
            var i = atSign + 1
            var periods = 0
            while true {
                let segmentStart = i
                while i < end, isEmailDomainByte(content[i], isXmpp: isXmpp) {
                    i += 1
                }
                guard i > segmentStart, i + 1 < end, content[i] == UInt8(ascii: "."),
                      isEmailDomainByte(content[i + 1], isXmpp: isXmpp) else {
                    break
                }
                periods += 1
                i += 1
            }
            if i < end, content[i] == UInt8(ascii: "@") {
                atSign = i
                continue
            }
            resumeAt = max(i, atSign + 1)
            guard periods > 0, content[i - 1] != UInt8(ascii: "-"), content[i - 1] != UInt8(ascii: "_") else {
                return nil
            }
            return GFMAutolinkMatch(urlStart: localStart, urlEnd: i, form: .email, emailSchemeFolded: schemeFolded)
        }
    }

    /// Whether `b` may appear in an extended email autolink's domain segment: an ASCII alphanumeric, `-`
    /// or `_`, or `/` after a folded `xmpp:` scheme.
    private func isEmailDomainByte(_ b: UInt8, isXmpp: Bool) -> Bool {
        b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "-") || b == UInt8(ascii: "_")
            || (isXmpp && b == UInt8(ascii: "/"))
    }

    /// Emit a `.link` node + a single `.text` child for an extended autolink match. `www.` and email forms get a synthetic scheme prefix (`http://` or `mailto:`) materialized into the string arena.
    private mutating func emitGFMAutolink(auto: GFMAutolinkMatch, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        precondition(auto.form != .email, "email autolinks are emitted by gfmEmailAutolinkPass")
        let urlChunk: Chunk
        if auto.form == .uri {
            urlChunk = content.chunk(
                offset: auto.urlStart,
                length: auto.urlEnd - auto.urlStart
            )
        } else {
            urlChunk = materializeAutolinkURL(
                prefix: "http://",
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
        stampInline(linkIdx, auto.urlStart, auto.urlEnd, content: content)
        stampInline(textIdx, auto.urlStart, auto.urlEnd, content: content)
    }

    /// Append `prefix` + the content bytes of `start..<end` into `storage.strings`, returning a chunk pointing at the appended region.
    ///
    /// The bytes are read from `content` (the scratch/source view, independent of `storage.strings`) so the read region doesn't alias the buffer being appended to.
    private mutating func materializeAutolinkURL(prefix: String, start: Int, end: Int, content: borrowing ContentSpan) -> Chunk {
        let offset = storage.strings.count
        for b in prefix.utf8 {
            storage.strings.append(b)
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

    /// Walk forward until a URL boundary: space, tab, line feed, carriage return or `<`.
    ///
    /// `>`, line tabulation and form feed are ordinary URL bytes, hence `isSpaceTabOrNewline` rather than
    /// `isASCIISpace`.
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

    /// Trailing-boundary trim for an extended autolink URL (extended autolink path validation, Autolinks
    /// (extension)), as a single pass from the end of the `[urlStart, urlEnd)` run that `scanGFMURLBody`
    /// produced:
    ///
    /// - a trailing `? ! . , : * _ ~ ' "` is peeled, one character at a time;
    /// - a trailing `)` is peeled only when the run holds more `)` than `(`, so balanced parentheses
    ///   (`…/Pikachu_(Electric)`) are kept while a stray closing paren is dropped. The `(`/`)` totals are
    ///   counted once over the whole run; `closing` is decremented as each unbalanced `)` is removed;
    /// - a trailing `;` peels a whole `&…;` entity tail when one precedes it (`&`, then one or more ASCII
    ///   letters, not digits, then `;`), otherwise it peels just the `;`.
    ///
    /// These `)`, punctuation, and `;` cases are interleaved in one loop, so a mixed tail like `');` peels
    /// right-to-left. A `<` never appears in the run: `scanGFMURLBody` stops at it.
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
                // letters + `;`. Requiring at least one letter (`entityStart < i - 2`) makes `&;` and a
                // bare `;` peel only the `;`.
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

    /// The end of the valid domain starting at `start` (Autolinks (extension): segments of
    /// alphanumeric characters, underscores and hyphens separated by periods, with at least one period
    /// and no underscore in the last two segments), or `nil` when none starts there. A period that no
    /// segment follows ends the domain before it.
    private func validDomainEnd(start: Int, end: Int, content: borrowing ContentSpan) -> Int? {
        var i = start
        var periods = 0
        var underscoreInPreviousSegment = false
        var underscoreInSegment = false
        while true {
            let segmentStart = i
            underscoreInPreviousSegment = underscoreInSegment
            underscoreInSegment = false
            while i < end, let width = domainCharacterWidth(at: i, content: content) {
                if content[i] == UInt8(ascii: "_") {
                    underscoreInSegment = true
                }
                i += width
            }
            if i == segmentStart {
                return nil
            }
            guard i + 1 < end, content[i] == UInt8(ascii: "."),
                  domainCharacterWidth(at: i + 1, content: content) != nil else {
                break
            }
            periods += 1
            i += 1
        }
        if periods == 0 || underscoreInSegment || underscoreInPreviousSegment {
            return nil
        }
        return i
    }

    /// The byte width of the domain-segment character at `i` - an alphanumeric character (a Unicode letter or
    /// number), `_` or `-` - or `nil` when another character is there.
    private func domainCharacterWidth(at i: Int, content: borrowing ContentSpan) -> Int? {
        let b = content[i]
        if b < 0x80 {
            return b.isASCIILetter || b.isASCIIDigit || b == UInt8(ascii: "_") || b == UInt8(ascii: "-") ? 1 : nil
        }
        let decoded = Unicode.Scalar(UInt32(Self.decodeUTF8Scalar(at: i, content: content)))
        precondition(decoded != nil, "inline content is valid UTF-8, so a decoded scalar is a Unicode scalar value")
        let scalar = decoded!
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber, .letterNumber, .otherNumber:
            return scalar.utf8.count
        default:
            return nil
        }
    }

    /// Characters that may directly precede a `www.` extended autolink: whitespace, `*`, `_`, `~` and `(`.
    /// Anything else, `<` included, disqualifies it. The `://` form only rejects a preceding ASCII letter
    /// (see `matchGFMSchemeAutolink`), and the email form has no restriction (see `matchGFMEmailAutolink`).
    private func isValidGFMPreceding(_ b: UInt8) -> Bool {
        switch b {
        case UInt8(ascii: " "), UInt8(ascii: "\t"), UInt8(ascii: "\n"), UInt8(ascii: "\r"),
             UInt8(ascii: "*"), UInt8(ascii: "_"), UInt8(ascii: "~"), UInt8(ascii: "("):
            return true
        default:
            return false
        }
    }

    /// Compare bytes at `start..(start+target.utf8.count)` against the string target.
    /// `ignoringASCIICase` folds ASCII case on both sides (`| 0x20`), for the case-insensitive `://`
    /// scheme literals; the `www.` form compares exactly. Only the comparison folds, so the matched
    /// destination and text keep the source case.
    private func bytesEqual(at start: Int, target: String, content: borrowing ContentSpan, ignoringASCIICase: Bool = false) -> Bool {
        let mask: UInt8 = ignoringASCIICase ? 0x20 : 0
        for (k, targetByte) in target.utf8.enumerated() {
            if (content[start + k] | mask) != (targetByte | mask) {
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
    /// A text run never holds a line join - every line ending flushes the run before it - so it lies within one line, which
    /// a single segment of multi-segment content holds.
    private mutating func flushPendingText(start: Int, end: Int, content: borrowing ContentSpan, into parent: DocumentStorage.Index) {
        if end <= start {
            return
        }
        precondition(content.contiguousChunk(fromVirtual: start, limit: end)?.length == end - start, "a text run lies within one segment")
        let chunkRef = storage.intern(content.chunk(offset: start, length: end - start))
        let textIdx = storage.appendNode(
            NodeRecord(kind: .text, parent: parent, data: .literal(chunkRef))
        )
        storage.appendChild(textIdx, to: parent)
        stampInline(textIdx, start, end, content: content)
    }

    /// Build a `Chunk` for the virtual range `[start, end)`, materializing into the arena ONLY when the
    /// range straddles a segment boundary (multi-segment content whose bytes don't lie in one contiguous
    /// buffer region). Single-segment content and any range confined to one segment stay zero-copy - the
    /// contiguous slice is returned unchanged. Code spans and link destinations and titles can straddle a
    /// line join.
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
    /// This is the only stamping path, shared by every inline node, leaf and wrapper: a single-segment source span maps identity (byte offsets pass through unchanged), single-segment arena content resolves through its arena→source run map, and a multi-segment span walks its segment list - so a construct inside a multi-line block quote or list paragraph gets real source positions. `end` is *exclusive* (one past the last byte), so the last content byte `end - 1` is resolved and incremented; this also maps an `end` that lands on the line ending at a segment join back to just past the preceding source byte.
    @inline(__always)
    mutating func stampInline(_ node: DocumentStorage.Index, _ start: Int, _ end: Int, content: borrowing ContentSpan) {
        guard positionsEnabled, end > start else {
            return
        }
        storage.setSourceStart(node, content.sourceOffset(ofVirtual: start))
        storage.setSourceEnd(node, content.sourceOffset(ofVirtual: end - 1) + 1)
    }

    /// Merge runs of adjacent `.text` children into single nodes, recursing into containers.
    ///
    /// Smart-punctuation and entity substitutions emit their replacement as a separate text node (e.g. `"Markdown"` + `"’"` + `"s "`), which this merges into one text run. The merged node's content is the concatenation of the runs' segments and its source range runs from the first run's start to the last run's end.
    mutating func consolidateTextNodes(_ parent: DocumentStorage.Index) {
        var child = storage[parent].firstChild
        while let current = child {
            if storage[current].kind == .text {
                // Absorb all immediately-following text siblings into `current`.
                while let next = storage[current].next, storage[next].kind == .text {
                    mergeTextNode(next, into: current)
                }
            } else {
                consolidateTextNodes(current)
            }
            child = storage[current].next
        }
    }

    /// Merge `source` into the preceding text node `dest`, giving `dest` its own start and `source`'s end, and unlink `source`.
    ///
    /// When the two runs are pool-contiguous (the common case for adjacent text) this just widens `dest`'s `ContentRef` - no new segments. Otherwise (e.g. a smart-punctuation glyph re-interned at the pool's end sits between them) it appends copies of both runs' segments as a fresh combined run.
    private mutating func mergeTextNode(_ source: DocumentStorage.Index, into dest: DocumentStorage.Index) {
        guard case .literal(let destRef) = storage[dest].data,
              case .literal(let srcRef) = storage[source].data else {
            preconditionFailure("a text node holds a literal")
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
            precondition(a.start >= 0 && b.start >= 0, "with positions tracked, every text node is stamped before it consolidates")
            // The merged run spans from the first node's start to the last node's end rather than the union of their ranges; the two differ only when an earlier node ends past the last one.
            storage.sourceRanges[dest] = DocumentStorage.SourceByteRange(
                start: a.start,
                end: b.end
            )
        }
        storage.unlinkChild(source)
    }

    // MARK: - Extended email autolink pass

    /// Detect extended email autolinks in a pass over the consolidated inline tree.
    ///
    /// Runs after emphasis resolution and `consolidateTextNodes`, splitting every text node outside a link
    /// into `[before, link, after]` at each email match. A `_` or `*` beside an email is therefore already
    /// resolved as emphasis, or left as literal text in the local part, before the email's boundaries are
    /// decided.
    ///
    /// Every non-link container (emphasis, strong, image, …) is recursed into.
    ///
    /// A link may not contain another link, so the pass never autolinks inside a link and skips its subtree.
    /// `image` maps the leaf's arena content back to source, when its content is a single arena chunk with a source image.
    mutating func gfmEmailAutolinkPass(_ parent: DocumentStorage.Index, image: ContentImage?) {
        var child = storage[parent].firstChild
        while let current = child {
            // Capture the next sibling BEFORE splitting: `splitEmailsInTextNode` inserts the link/after
            // nodes between `current` and this sibling (and may unlink `current`), and resuming here skips
            // over everything it produced.
            let next = storage[current].next
            switch storage[current].kind {
            case .text:
                splitEmailsInTextNode(current, parent: parent, image: image)
            case .link:
                break
            default:
                gfmEmailAutolinkPass(current, image: image)
            }
            child = next
        }
    }

    /// Split one text node into `[before, link, after]` at each extended email autolink it contains.
    ///
    /// The node content is materialized into a scratch buffer once and scanned left-to-right in a single
    /// pass (each backward local-part scan is bounded by the previous match's end), so cost is O(content
    /// length). `before`/`after`/link text are carved zero-copy from the node's existing segments
    /// (`subContentRef`); only the `mailto:` URL is materialized into the arena.
    ///
    /// The link and its text span the address's source bytes. Each text run keeps the part of the split node's range
    /// on its side of the address, so a run whose bytes aren't all source bytes (a smart quote, a NUL's U+FFFD)
    /// has a source range.
    private mutating func splitEmailsInTextNode(_ node: DocumentStorage.Index, parent: DocumentStorage.Index, image: ContentImage?) {
        guard case .literal(let ref) = storage[node].data else {
            preconditionFailure("a text node holds a literal")
        }
        // Cheap early-out: a text node with no `@` is left untouched (no allocation). This is the
        // overwhelmingly common case.
        if !contentRefContains(ref, byte: UInt8(ascii: "@")) {
            return
        }
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
        // The split node's end, which the last text run keeps.
        let nodeEnd = positionsEnabled ? storage.sourceRanges[node].end : -1
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
                // The backward-scan floor `cursor` advances with `i`, so the next `@`'s local part can't
                // reach into the abandoned candidate. Otherwise a character the domain scan stops at but a
                // local part accepts (`+`, or a `.` not followed by an alphanumeric) would pull preceding
                // text into the next email's local part.
                cursor = resumeAt
                i = resumeAt
                continue
            }
            // `current` becomes the text run before this email.
            let beforeRef = subContentRef(of: ref, from: segStart, to: auto.urlStart)
            storage[current].data = .literal(beforeRef)
            let emailRef = subContentRef(of: ref, from: auto.urlStart, to: auto.urlEnd)
            let email = positionsEnabled ? sourceSpan(of: emailRef, image: image) : nil
            if let email {
                let currentStart = Int(storage.sourceRanges[current].start)
                precondition(currentStart >= 0, "a text run is placed before an address splits it")
                storage.setSourceStart(current, min(currentStart, email.start))
                storage.setSourceEnd(current, email.start)
            }

            // The link node and its single text child (the visible email address).
            // A folded `mailto:`/`xmpp:` scheme means the destination is the visible run, so reuse its ref
            // for the URL. A plain email gets `mailto:` synthesized into the arena.
            let urlRef = auto.emailSchemeFolded ? emailRef : materializeMailtoURL(for: emailRef)
            let linkIdx = storage.appendNode(NodeRecord(
                kind: .link, parent: parent, data: .link(url: urlRef, title: .empty)))
            let childIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: linkIdx, data: .literal(emailRef)))
            storage.appendChild(childIdx, to: linkIdx)
            storage.insertChildAfter(linkIdx, after: current)
            if let email {
                for idx in [linkIdx, childIdx] {
                    storage.setSourceStart(idx, email.start)
                    storage.setSourceEnd(idx, email.end)
                }
            }

            // A fresh text node spanning the remaining tail; it becomes the running run and is trimmed to
            // the next `between` segment on a further match, or kept as the final `after` run.
            let tailRef = subContentRef(of: ref, from: auto.urlEnd, to: total)
            let tailIdx = storage.appendNode(NodeRecord(
                kind: .text, parent: parent, data: .literal(tailRef)))
            storage.insertChildAfter(tailIdx, after: linkIdx)
            if let email {
                storage.setSourceStart(tailIdx, email.end)
                storage.setSourceEnd(tailIdx, max(nodeEnd, email.end))
            }

            // An empty `before` / `between` run is not a real text node, so drop it.
            if beforeRef.totalLength == 0 {
                storage.unlinkChild(current)
            }
            current = tailIdx
            segStart = auto.urlEnd
            cursor = auto.urlEnd
            i = auto.urlEnd
            didSplit = true
        }
        // Drop the final tail run if the split left it empty. Only ever a residual this pass
        // produced (`didSplit`), never a pre-existing `@`-free node.
        if didSplit, case .literal(let last) = storage[current].data, last.totalLength == 0 {
            storage.unlinkChild(current)
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
    /// Zero-copy: the carved segments point into the same source / arena bytes (with `offset` shifted for
    /// a partial leading segment); only new `Segment` entries are appended.
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
                inSource: seg.inSource
            ))
            count += 1
            total += pieceLen
        }
        precondition(count > 0, "a non-empty sub-range of a text node overlaps at least one of its segments")
        return ContentRef(first: newFirst, count: count, totalLength: total)
    }

    /// Materialize `"mailto:"` + the content bytes of `emailRef` into the string arena and intern them.
    ///
    /// The email bytes are copied into an independent local buffer first (they may live in the arena, and
    /// reading the arena while appending to it would alias the growing buffer), then flushed to the arena.
    private mutating func materializeMailtoURL(for emailRef: ContentRef) -> ContentRef {
        var buf = UniqueArray<UInt8>()
        for b in "mailto:".utf8 {
            buf.append(b)
        }
        materialize(emailRef, into: &buf)
        let offset = storage.strings.count
        for k in 0..<buf.count {
            storage.strings.append(buf[k])
        }
        return storage.intern(Chunk(offset: offset, length: buf.count, inSource: false))
    }

    /// The source extent of the non-empty `ref`'s bytes: from the start of the source its first byte stands for to
    /// the end of the source its last byte stands for (`sourceRange(of:local:image:)`).
    private func sourceSpan(of ref: ContentRef, image: ContentImage?) -> (start: Int, end: Int) {
        precondition(ref.count > 0 && ref.totalLength > 0, "an email address holds at least one byte")
        let firstSeg = storage.segments[Int(ref.first)]
        let lastSeg = storage.segments[Int(ref.first) + Int(ref.count) - 1]
        let first = sourceRange(of: firstSeg, local: 0, image: image)
        let last = sourceRange(of: lastSeg, local: Int(lastSeg.length) - 1, image: image)
        return (first.lowerBound, last.upperBound)
    }

    /// The source bytes that byte `local` of an address's segment `seg` stands for: a source segment's own byte, an
    /// arena byte of the leaf's content imaged by `image`, or the whole character reference a decoded byte comes from.
    /// Every other arena text is punctuation no address holds.
    private func sourceRange(of seg: Segment, local: Int, image: ContentImage?) -> Range<Int> {
        if seg.inSource {
            let offset = Int(seg.offset) + local
            return offset..<(offset + 1)
        }
        let arena = Int(seg.offset) + local
        if let offset = image?.sourceOffset(ofArenaByte: arena) {
            return offset..<(offset + 1)
        }
        return characterReferenceSource(ofArenaByte: arena)
    }

    /// The source range of the character reference decoded into arena byte `offset` in this pass.
    private func characterReferenceSource(ofArenaByte offset: Int) -> Range<Int> {
        var lo = 0
        var hi = characterReferenceSources.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if characterReferenceSources[mid].arena.upperBound > offset {
                hi = mid
            } else {
                lo = mid + 1
            }
        }
        precondition(lo < characterReferenceSources.count && characterReferenceSources[lo].arena.contains(offset), "an address's arena byte outside the leaf's content comes from a character reference")
        return characterReferenceSources[lo].source
    }
}
