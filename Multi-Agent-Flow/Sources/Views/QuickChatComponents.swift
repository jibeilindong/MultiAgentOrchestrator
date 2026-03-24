import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct QuickChatImageLightboxItem: Identifiable {
    let id = UUID()
    let title: String
    let image: NSImage
}

struct QuickChatMessageBubbleView: View {
    let message: QuickChatStore.Message
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    @State private var isHovered = false

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .top) {
            if isUser {
                Spacer(minLength: 56)
            }

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    roleBadge
                    if message.isStreaming {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Spacer(minLength: 0)
                    Text(timestampLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                if !message.attachments.isEmpty {
                    QuickChatAttachmentGridView(
                        attachments: message.attachments,
                        onOpenImage: onOpenImage
                    )
                }

                if message.blocks.isEmpty && message.isStreaming {
                    Text("正在生成内容...")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(message.blocks) { block in
                        QuickChatMessageBlockView(
                            block: block,
                            onOpenImage: onOpenImage
                        )
                    }
                }
            }
            .padding(14)
            .background(bubbleBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
            .shadow(color: shadowColor, radius: 8, y: 2)
            .frame(maxWidth: 820, alignment: isUser ? .trailing : .leading)
            .overlay(alignment: .topTrailing) {
                if isHovered && !message.plainText.isEmpty {
                    HStack(spacing: 6) {
                        QuickChatMiniActionButton(
                            title: "复制",
                            systemImage: "doc.on.doc"
                        ) {
                            copyToPasteboard(message.plainText)
                        }
                    }
                    .padding(10)
                }
            }
            .onHover { hovered in
                isHovered = hovered
            }

            if !isUser {
                Spacer(minLength: 56)
            }
        }
    }

    private var roleBadge: some View {
        HStack(spacing: 8) {
            Image(systemName: roleIconName)
                .font(.caption)
            Text(message.role.title)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(roleAccent)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            Capsule(style: .continuous)
                .fill(roleAccent.opacity(0.11))
        )
    }

    private var bubbleBackground: some ShapeStyle {
        switch message.role {
        case .user:
            return AnyShapeStyle(Color.accentColor.opacity(0.13))
        case .toolResult:
            return AnyShapeStyle(Color.orange.opacity(0.07))
        case .assistant, .system:
            return AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var borderColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.22)
        case .toolResult:
            return Color.orange.opacity(0.2)
        case .assistant, .system:
            return Color.primary.opacity(0.07)
        }
    }

    private var roleAccent: Color {
        switch message.role {
        case .user:
            return .accentColor
        case .assistant:
            return .primary
        case .toolResult:
            return .orange
        case .system:
            return .secondary
        }
    }

    private var roleIconName: String {
        switch message.role {
        case .user:
            return "person.fill"
        case .assistant:
            return "sparkles"
        case .toolResult:
            return "shippingbox.fill"
        case .system:
            return "gearshape.fill"
        }
    }

    private var shadowColor: Color {
        switch message.role {
        case .user:
            return Color.accentColor.opacity(0.08)
        case .toolResult:
            return Color.orange.opacity(0.06)
        case .assistant, .system:
            return Color.black.opacity(0.05)
        }
    }

    private var timestampLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: message.createdAt)
    }
}

struct QuickChatAttachmentGridView: View {
    let attachments: [QuickChatStore.AttachmentSnapshot]
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 128, maximum: 180), spacing: 10)
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(attachments) { attachment in
                if attachment.isImage {
                    QuickChatAttachmentImageCard(
                        attachment: attachment,
                        onOpenImage: onOpenImage
                    )
                } else {
                    QuickChatAttachmentFileCard(
                        title: attachment.fileName,
                        subtitle: attachment.mimeType,
                        detail: ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file)
                    )
                }
            }
        }
    }
}

struct QuickChatComposerAttachmentRow: View {
    let attachments: [QuickChatStore.Attachment]
    let onRemove: (UUID) -> Void
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(attachments) { attachment in
                    QuickChatComposerAttachmentCard(
                        attachment: attachment,
                        onRemove: onRemove,
                        onOpenImage: onOpenImage
                    )
                }
            }
            .padding(.vertical, 2)
        }
    }
}

private struct QuickChatComposerAttachmentCard: View {
    let attachment: QuickChatStore.Attachment
    let onRemove: (UUID) -> Void
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if attachment.isImage,
               let image = image(from: attachment.previewData, fileURL: attachment.stagedURL)
            {
                Button {
                    onOpenImage(
                        QuickChatImageLightboxItem(
                            title: attachment.fileName,
                            image: image
                        )
                    )
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 132, height: 92)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                QuickChatAttachmentFileCard(
                    title: attachment.fileName,
                    subtitle: attachment.mimeType,
                    detail: ByteCountFormatter.string(fromByteCount: attachment.fileSize, countStyle: .file)
                )
            }

            HStack(spacing: 8) {
                Text(attachment.stageStatusText)
                    .font(.caption2)
                    .foregroundColor(stageColor)
                Spacer(minLength: 8)
                Button {
                    onRemove(attachment.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            if let errorDescription = attachment.errorDescription {
                Text(errorDescription)
                    .font(.caption2)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(stageColor.opacity(0.22), lineWidth: 1)
        )
        .frame(width: 152, alignment: .leading)
    }

    private var stageColor: Color {
        switch attachment.stageState {
        case .staging:
            return .orange
        case .ready:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct QuickChatAttachmentImageCard: View {
    let attachment: QuickChatStore.AttachmentSnapshot
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    var body: some View {
        if let image = image(from: attachment.previewData, fileURL: attachment.stagedURL) {
            Button {
                onOpenImage(
                    QuickChatImageLightboxItem(
                        title: attachment.fileName,
                        image: image
                    )
                )
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 108)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Text(attachment.fileName)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundColor(.primary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
            }
            .buttonStyle(.plain)
        }
    }
}

private struct QuickChatAttachmentFileCard: View {
    let title: String
    let subtitle: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(nsImage: fileIcon)
                .resizable()
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var fileIcon: NSImage {
        if let contentType = UTType(mimeType: subtitle) {
            return NSWorkspace.shared.icon(for: contentType)
        }
        return NSWorkspace.shared.icon(for: .data)
    }
}

struct QuickChatMessageBlockView: View {
    let block: QuickChatStore.MessageContentBlock
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    var body: some View {
        switch block.kind {
        case .text:
            if let text = block.text {
                QuickChatMarkdownContentView(markdown: text)
            }

        case .thinking:
            if let text = block.text {
                QuickChatDisclosureCard(
                    title: "思考过程",
                    systemImage: "brain.head.profile",
                    tint: .orange,
                    initialExpanded: false
                ) {
                    QuickChatMarkdownContentView(markdown: text)
                }
            }

        case .image:
            QuickChatImageBlockView(
                block: block,
                onOpenImage: onOpenImage
            )

        case .toolUse:
            QuickChatDisclosureCard(
                title: block.toolName ?? "tool",
                systemImage: "hammer.fill",
                tint: .blue,
                initialExpanded: false
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    if let text = block.text, !text.isEmpty {
                        QuickChatLabeledSection(title: "说明", copyText: text) {
                            QuickChatMarkdownContentView(markdown: text)
                        }
                    }
                    if let arguments = block.toolArguments, !arguments.isEmpty {
                        QuickChatLabeledSection(title: "参数", copyText: arguments) {
                            QuickChatCodeBlockView(
                                code: arguments,
                                language: "json"
                            )
                        }
                    }
                }
            }

        case .toolResult:
            QuickChatDisclosureCard(
                title: block.toolName ?? "Tool Result",
                systemImage: "shippingbox.fill",
                tint: .green,
                initialExpanded: true
            ) {
                if let output = block.toolOutput ?? block.text {
                    QuickChatLabeledSection(title: "输出", copyText: output) {
                        QuickChatMarkdownContentView(markdown: output)
                    }
                }
            }
        }
    }
}

private struct QuickChatImageBlockView: View {
    let block: QuickChatStore.MessageContentBlock
    let onOpenImage: (QuickChatImageLightboxItem) -> Void

    var body: some View {
        let previewImage = image(from: block.imagePreviewData, fileURL: block.imageURL)

        VStack(alignment: .leading, spacing: 8) {
            if let previewImage {
                Button {
                    onOpenImage(
                        QuickChatImageLightboxItem(
                            title: block.text ?? "图片",
                            image: previewImage
                        )
                    )
                } label: {
                    Image(nsImage: previewImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 280)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "photo")
                        .foregroundColor(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(block.text ?? "图片")
                            .foregroundColor(.primary)
                        Text(imageDetailText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color(nsColor: .windowBackgroundColor))
                )
            }

            if let text = block.text, previewImage != nil {
                Text(text)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var imageDetailText: String {
        var parts: [String] = []
        if let imageMimeType = block.imageMimeType {
            parts.append(imageMimeType)
        }
        if let imageByteCount = block.imageByteCount {
            parts.append(ByteCountFormatter.string(fromByteCount: Int64(imageByteCount), countStyle: .file))
        }
        if block.imageDataOmitted {
            parts.append("历史数据已省略")
        }
        return parts.isEmpty ? "图片预览不可用" : parts.joined(separator: " · ")
    }
}

private struct QuickChatDisclosureCard<Content: View>: View {
    let title: String
    let systemImage: String
    let tint: Color
    let initialExpanded: Bool
    @ViewBuilder let content: Content

    @State private var isExpanded: Bool

    init(
        title: String,
        systemImage: String,
        tint: Color,
        initialExpanded: Bool,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.initialExpanded = initialExpanded
        self._isExpanded = State(initialValue: initialExpanded)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: systemImage)
                        .font(.caption)
                        .foregroundColor(tint)
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(tint.opacity(0.12))
                        )

                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 10) {
                    Divider()
                        .overlay(tint.opacity(0.14))
                    content
                }
                .padding(.top, 12)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(tint.opacity(0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(tint.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct QuickChatLabeledSection<Content: View>: View {
    let title: String
    let copyText: String?
    @ViewBuilder let content: Content

    init(
        title: String,
        copyText: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.copyText = copyText
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                    .tracking(0.6)

                Spacer(minLength: 8)

                if let copyText, !copyText.isEmpty {
                    QuickChatMiniActionButton(
                        title: "复制",
                        systemImage: "doc.on.doc"
                    ) {
                        copyToPasteboard(copyText)
                    }
                }
            }

            content
        }
    }
}

struct QuickChatMarkdownContentView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(QuickChatMarkdownSegment.parse(markdown), id: \.id) { segment in
                switch segment.kind {
                case .prose:
                    QuickChatMarkdownProseView(markdown: segment.content)
                case .code(let language):
                    QuickChatCodeBlockView(
                        code: segment.content,
                        language: language
                    )
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct QuickChatMarkdownProseView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(QuickChatMarkdownProseBlock.parse(markdown)) { block in
                QuickChatMarkdownProseBlockView(block: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct QuickChatCodeBlockView: View {
    let code: String
    let language: String?
    @State private var isExpanded: Bool

    init(code: String, language: String?) {
        self.code = code
        self.language = language
        self._isExpanded = State(initialValue: Self.lineCount(for: code) <= Self.collapsedLineLimit)
    }

    private static let collapsedLineLimit = 18

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(displayLanguageLabel)
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                Spacer(minLength: 8)

                if isCollapsible {
                    QuickChatMiniActionButton(
                        title: isExpanded ? "收起" : "展开",
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    ) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    }
                }

                QuickChatMiniActionButton(
                    title: "复制",
                    systemImage: "doc.on.doc"
                ) {
                    copyToPasteboard(code)
                }
            }

            ScrollView(.horizontal, showsIndicators: true) {
                QuickChatAttributedTextView(
                    attributedString: QuickChatCodeHighlighter.highlight(
                        code: visibleCode,
                        language: language
                    )
                )
                .frame(minHeight: 22)
            }

            if isCollapsible {
                HStack {
                    Text(isExpanded ? "共 \(lineCount) 行代码" : "已折叠，仅显示前 \(Self.collapsedLineLimit) 行")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    Button(isExpanded ? "收起代码" : "展开全部") {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            isExpanded.toggle()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .textBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var displayLanguageLabel: String {
        let normalizedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalizedLanguage, !normalizedLanguage.isEmpty {
            return normalizedLanguage.uppercased()
        }
        return "PLAIN"
    }

    private var visibleCode: String {
        guard isCollapsible, !isExpanded else { return code }
        let prefix = code.components(separatedBy: .newlines).prefix(Self.collapsedLineLimit)
        return prefix.joined(separator: "\n")
    }

    private var lineCount: Int {
        Self.lineCount(for: code)
    }

    private var isCollapsible: Bool {
        lineCount > Self.collapsedLineLimit
    }

    private static func lineCount(for code: String) -> Int {
        code.components(separatedBy: .newlines).count
    }
}

private struct QuickChatAttributedTextView: NSViewRepresentable {
    let attributedString: NSAttributedString

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        textView.textStorage?.setAttributedString(attributedString)
        textView.sizeToFit()
    }
}

private struct QuickChatSelectableMarkdownTextView: NSViewRepresentable {
    let markdown: String
    var baseFont: NSFont = .systemFont(ofSize: 14)
    var textColor: NSColor = .labelColor

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(wrappingLabelWithString: "")
        textField.isEditable = false
        textField.isSelectable = true
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.allowsEditingTextAttributes = true
        textField.maximumNumberOfLines = 0
        textField.lineBreakMode = .byWordWrapping
        textField.usesSingleLineMode = false
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        nsView.attributedStringValue = makeAttributedMarkdown(markdown)
    }

    private func makeAttributedMarkdown(_ markdown: String) -> NSAttributedString {
        let attributed: NSAttributedString
        if let parsed = try? AttributedString(
            markdown: markdown,
            options: AttributedString.MarkdownParsingOptions(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        ) {
            attributed = NSAttributedString(parsed)
        } else {
            attributed = NSAttributedString(
                string: markdown,
                attributes: [
                    .font: baseFont,
                    .foregroundColor: textColor
                ]
            )
        }

        let mutable = NSMutableAttributedString(attributedString: attributed)
        let fullRange = NSRange(location: 0, length: mutable.length)
        guard fullRange.length > 0 else { return mutable }

        mutable.addAttribute(.foregroundColor, value: textColor, range: fullRange)
        mutable.enumerateAttribute(.paragraphStyle, in: fullRange) { value, range, _ in
            let style = (value as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()
            style.lineSpacing = max(style.lineSpacing, 4)
            style.paragraphSpacing = max(style.paragraphSpacing, 6)
            style.lineBreakMode = .byWordWrapping
            mutable.addAttribute(.paragraphStyle, value: style, range: range)
        }

        return mutable
    }
}

private enum QuickChatCodeHighlighter {
    static func highlight(code: String, language: String?) -> NSAttributedString {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let attributed = NSMutableAttributedString(
            string: code,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )

        apply(pattern: #"(?m)^\s*(//|#).*$"#, color: .secondaryLabelColor, in: attributed)
        apply(pattern: #"(?s)/\*.*?\*/"#, color: .secondaryLabelColor, in: attributed)
        apply(pattern: #""([^"\\]|\\.)*"|'([^'\\]|\\.)*'"#, color: .systemRed, in: attributed)
        apply(pattern: #"\b\d+(\.\d+)?\b"#, color: .systemOrange, in: attributed)
        apply(pattern: keywordPattern(for: language), color: .systemBlue, in: attributed)

        return attributed
    }

    private static func apply(pattern: String, color: NSColor, in attributed: NSMutableAttributedString) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let range = NSRange(location: 0, length: attributed.string.utf16.count)
        regex.enumerateMatches(in: attributed.string, range: range) { result, _, _ in
            guard let result else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: result.range)
        }
    }

    private static func keywordPattern(for language: String?) -> String {
        let normalized = language?.lowercased() ?? ""
        let keywords: [String]
        switch normalized {
        case "swift":
            keywords = ["func", "let", "var", "if", "else", "guard", "return", "struct", "class", "enum", "switch", "case", "import", "extension", "async", "await", "throw", "throws", "try"]
        case "python", "py":
            keywords = ["def", "class", "import", "from", "if", "elif", "else", "return", "for", "while", "try", "except", "with", "async", "await", "lambda"]
        case "json":
            keywords = ["true", "false", "null"]
        default:
            keywords = ["function", "const", "let", "var", "if", "else", "return", "async", "await", "class", "import", "export", "try", "catch", "throw", "for", "while"]
        }

        let pattern = keywords
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return #"\b(\#(pattern))\b"#
    }
}

private struct QuickChatMarkdownProseBlock: Identifiable {
    enum Kind {
        case heading(level: Int)
        case bullet(indent: Int, marker: String)
        case quote
        case divider
        case table
        case paragraph
    }

    let id = UUID()
    let kind: Kind
    let content: String

    static func parse(_ markdown: String) -> [QuickChatMarkdownProseBlock] {
        let normalized = markdown
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized.components(separatedBy: "\n")
        var blocks: [QuickChatMarkdownProseBlock] = []
        var paragraphLines: [String] = []
        var quoteLines: [String] = []
        var tableLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                paragraphLines.removeAll()
                return
            }
            blocks.append(.init(kind: .paragraph, content: text))
            paragraphLines.removeAll()
        }

        func flushQuote() {
            let text = quoteLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                quoteLines.removeAll()
                return
            }
            blocks.append(.init(kind: .quote, content: text))
            quoteLines.removeAll()
        }

        func flushTable() {
            let lines = tableLines
            defer { tableLines.removeAll() }

            guard lines.count >= 2, isTableSeparator(lines[1]) else {
                for line in lines where !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.init(kind: .paragraph, content: line))
                }
                return
            }

            let content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return }
            blocks.append(.init(kind: .table, content: content))
        }

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                flushQuote()
                flushTable()
                continue
            }

            if isPotentialTableRow(trimmed) {
                flushParagraph()
                flushQuote()
                tableLines.append(trimmed)
                continue
            } else if !tableLines.isEmpty {
                flushTable()
            }

            if isDivider(trimmed) {
                flushParagraph()
                flushQuote()
                blocks.append(.init(kind: .divider, content: ""))
                continue
            }

            if let heading = parseHeading(from: trimmed) {
                flushParagraph()
                flushQuote()
                blocks.append(.init(kind: .heading(level: heading.level), content: heading.content))
                continue
            }

            if let bullet = parseBullet(from: line) {
                flushParagraph()
                flushQuote()
                blocks.append(.init(kind: .bullet(indent: bullet.indent, marker: bullet.marker), content: bullet.content))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                let quoteContent = trimmed
                    .dropFirst()
                    .trimmingCharacters(in: .whitespaces)
                quoteLines.append(quoteContent)
                continue
            }

            flushQuote()
            paragraphLines.append(line)
        }

        flushParagraph()
        flushQuote()
        flushTable()
        return blocks.isEmpty ? [.init(kind: .paragraph, content: normalized)] : blocks
    }

    private static func isDivider(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == "*" || $0 == "_" }
    }

    private static func parseHeading(from line: String) -> (level: Int, content: String)? {
        let hashes = line.prefix { $0 == "#" }
        guard !hashes.isEmpty, hashes.count <= 6 else { return nil }
        let content = line.dropFirst(hashes.count).trimmingCharacters(in: .whitespaces)
        guard !content.isEmpty else { return nil }
        return (min(hashes.count, 3), content)
    }

    private static func parseBullet(from line: String) -> (indent: Int, marker: String, content: String)? {
        let pattern = #"^(\s*)([-*+•]|\d+[.)])\s+(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange),
              let indentRange = Range(match.range(at: 1), in: line),
              let markerRange = Range(match.range(at: 2), in: line),
              let contentRange = Range(match.range(at: 3), in: line) else {
            return nil
        }

        let indentWidth = line[indentRange].count / 2
        let marker = String(line[markerRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let content = String(line[contentRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        return (min(indentWidth, 4), marker, content)
    }

    private static func isPotentialTableRow(_ line: String) -> Bool {
        line.hasPrefix("|") && line.hasSuffix("|") && line.contains("|")
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|"), trimmed.hasSuffix("|") else { return false }
        let cells = splitTableRow(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let normalized = cell.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "")
            return normalized.trimmingCharacters(in: .whitespaces).isEmpty && cell.contains("-")
        }
    }

    private static func splitTableRow(_ row: String) -> [String] {
        row
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct QuickChatMarkdownProseBlockView: View {
    let block: QuickChatMarkdownProseBlock

    var body: some View {
        switch block.kind {
        case .heading(let level):
            VStack(alignment: .leading, spacing: 6) {
                Text(block.content)
                    .font(headingFont(level: level))
                    .fontWeight(.semibold)
                    .foregroundColor(level == 1 ? .accentColor : .primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if level == 1 {
                    Capsule(style: .continuous)
                        .fill(Color.accentColor.opacity(0.18))
                        .frame(width: 56, height: 4)
                }
            }

        case .bullet(let indent, let marker):
            HStack(alignment: .top, spacing: 10) {
                bulletMarker(marker)
                    .padding(.top, marker.first?.isNumber == true ? 1 : 7)

                QuickChatSelectableMarkdownTextView(markdown: block.content)
            }
            .padding(.leading, CGFloat(indent) * 14)

        case .quote:
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 4)

                QuickChatSelectableMarkdownTextView(markdown: block.content, textColor: .secondaryLabelColor)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.orange.opacity(0.06))
            )

        case .divider:
            Divider()
                .padding(.vertical, 2)

        case .table:
            QuickChatMarkdownTableView(markdown: block.content)

        case .paragraph:
            QuickChatSelectableMarkdownTextView(markdown: block.content)
        }
    }

    private func headingFont(level: Int) -> Font {
        switch level {
        case 1:
            return .title3
        case 2:
            return .headline
        default:
            return .subheadline
        }
    }

    @ViewBuilder
    private func bulletMarker(_ marker: String) -> some View {
        if marker.first?.isNumber == true {
            Text(marker)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(minWidth: 18, alignment: .trailing)
        } else {
            Circle()
                .fill(Color.accentColor.opacity(0.85))
                .frame(width: 6, height: 6)
        }
    }
}

private struct QuickChatMarkdownTableView: View {
    let markdown: String

    var body: some View {
        let table = parseTable(markdown)

        if let table {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text("\(table.headers.count) 列 / \(table.rows.count) 行")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 8)
                    QuickChatMiniActionButton(
                        title: "复制表格",
                        systemImage: "tablecells.badge.ellipsis"
                    ) {
                        copyToPasteboard(tableTSV(from: table))
                    }
                }

                ScrollView(.horizontal, showsIndicators: true) {
                    Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                        GridRow {
                            ForEach(Array(table.headers.enumerated()), id: \.offset) { index, cell in
                                tableCell(cell, isHeader: true, showsTrailingBorder: index < table.headers.count - 1)
                            }
                        }

                        ForEach(Array(table.rows.enumerated()), id: \.offset) { rowIndex, row in
                            GridRow {
                                ForEach(Array(row.enumerated()), id: \.offset) { cellIndex, cell in
                                    tableCell(
                                        cell,
                                        isHeader: false,
                                        isStriped: rowIndex.isMultiple(of: 2),
                                        alignTrailing: cellIndex > 0 && isNumeric(cell),
                                        showsTrailingBorder: cellIndex < row.count - 1,
                                        showsBottomBorder: rowIndex < table.rows.count - 1
                                    )
                                }
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.58))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private func tableTSV(from table: (headers: [String], rows: [[String]])) -> String {
        let headerLine = table.headers.joined(separator: "\t")
        let bodyLines = table.rows.map { row in
            row.joined(separator: "\t")
        }
        return ([headerLine] + bodyLines).joined(separator: "\n")
    }

    @ViewBuilder
    private func tableCell(
        _ text: String,
        isHeader: Bool,
        isStriped: Bool = false,
        alignTrailing: Bool = false,
        showsTrailingBorder: Bool = true,
        showsBottomBorder: Bool = true
    ) -> some View {
        QuickChatSelectableMarkdownTextView(
            markdown: text,
            baseFont: isHeader ? .systemFont(ofSize: 13, weight: .semibold) : .systemFont(ofSize: 13),
            textColor: isHeader ? .labelColor : .secondaryLabelColor
        )
        .frame(minWidth: 140, maxWidth: 260, alignment: alignTrailing ? .trailing : .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            Group {
                if isHeader {
                    Color.primary.opacity(0.05)
                } else if isStriped {
                    Color.primary.opacity(0.025)
                } else {
                    Color.clear
                }
            }
        )
        .overlay(alignment: .bottom) {
            if showsBottomBorder {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 1)
            }
        }
        .overlay(alignment: .trailing) {
            if showsTrailingBorder {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: 1)
            }
        }
    }

    private func parseTable(_ markdown: String) -> (headers: [String], rows: [[String]])? {
        let lines = markdown
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }
        let headers = splitTableRow(lines[0])
        guard !headers.isEmpty else { return nil }

        let rows = lines.dropFirst(2).map { row in
            normalizeCells(splitTableRow(row), count: headers.count)
        }
        return (normalizeCells(headers, count: headers.count), rows)
    }

    private func splitTableRow(_ row: String) -> [String] {
        row
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }

    private func normalizeCells(_ cells: [String], count: Int) -> [String] {
        if cells.count >= count {
            return Array(cells.prefix(count))
        }
        return cells + Array(repeating: "", count: count - cells.count)
    }

    private func isNumeric(_ text: String) -> Bool {
        let candidate = text.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespaces)
        return Double(candidate) != nil
    }
}

private struct QuickChatMiniActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption2)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.primary.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct QuickChatMarkdownSegment: Identifiable {
    enum Kind {
        case prose
        case code(language: String?)
    }

    let id = UUID()
    let kind: Kind
    let content: String

    static func parse(_ markdown: String) -> [QuickChatMarkdownSegment] {
        let pattern = #"(?s)```([A-Za-z0-9_+\-]*)\n(.*?)```"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [.init(kind: .prose, content: markdown)]
        }

        let fullRange = NSRange(location: 0, length: markdown.utf16.count)
        let matches = regex.matches(in: markdown, range: fullRange)
        guard !matches.isEmpty else {
            return [.init(kind: .prose, content: markdown)]
        }

        var segments: [QuickChatMarkdownSegment] = []
        var currentLocation = 0

        for match in matches {
            let matchRange = match.range(at: 0)
            if matchRange.location > currentLocation,
               let proseRange = Range(NSRange(location: currentLocation, length: matchRange.location - currentLocation), in: markdown)
            {
                let prose = String(markdown[proseRange])
                if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    segments.append(.init(kind: .prose, content: prose))
                }
            }

            let language = Range(match.range(at: 1), in: markdown).map { String(markdown[$0]) }
            let code = Range(match.range(at: 2), in: markdown).map { String(markdown[$0]) } ?? ""
            let normalizedCode = code.trimmingCharacters(in: .newlines)
            if !normalizedCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(
                    .init(
                        kind: .code(language: language?.isEmpty == true ? nil : language),
                        content: normalizedCode
                    )
                )
            }

            currentLocation = matchRange.location + matchRange.length
        }

        if currentLocation < markdown.utf16.count,
           let tailRange = Range(NSRange(location: currentLocation, length: markdown.utf16.count - currentLocation), in: markdown)
        {
            let prose = String(markdown[tailRange])
            if !prose.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                segments.append(.init(kind: .prose, content: prose))
            }
        }

        return segments.isEmpty ? [.init(kind: .prose, content: markdown)] : segments
    }
}

struct QuickChatGrowingTextEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var dynamicHeight: CGFloat
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.automaticallyAdjustsContentInsets = false

        let textView = QuickChatInputTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.drawsBackground = false
        textView.font = .systemFont(ofSize: 14)
        textView.textContainerInset = NSSize(width: 0, height: 8)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.minSize = NSSize(width: 0, height: 0)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.string = text
        scrollView.documentView = textView

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? QuickChatInputTextView else { return }

        context.coordinator.parent = self

        if textView.string != text {
            textView.string = text
        }

        DispatchQueue.main.async {
            context.coordinator.recalculateHeight(for: textView)
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: QuickChatGrowingTextEditor

        init(_ parent: QuickChatGrowingTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight(for: textView)
        }

        func textView(
            _ textView: NSTextView,
            doCommandBy commandSelector: Selector
        ) -> Bool {
            guard commandSelector == #selector(NSResponder.insertNewline(_:)) else {
                return false
            }

            if NSApp.currentEvent?.modifierFlags.contains(.shift) == true {
                return false
            }

            parent.onSubmit()
            return true
        }

        func recalculateHeight(for textView: NSTextView) {
            guard let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else {
                return
            }

            layoutManager.ensureLayout(for: textContainer)
            let usedHeight = layoutManager.usedRect(for: textContainer).height
            let newHeight = min(max(usedHeight + 20, 52), 180)

            if abs(parent.dynamicHeight - newHeight) > 0.5 {
                parent.dynamicHeight = newHeight
            }
        }
    }
}

private final class QuickChatInputTextView: NSTextView {}

private func image(from data: Data?, fileURL: URL?) -> NSImage? {
    if let data, let image = NSImage(data: data) {
        return image
    }

    if let fileURL {
        if fileURL.isFileURL {
            return NSImage(contentsOf: fileURL)
        }
        if let data = try? Data(contentsOf: fileURL) {
            return NSImage(data: data)
        }
    }

    return nil
}

func copyToPasteboard(_ text: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
}
