import AppKit
import GuardCore

enum BrandAssets {
    static func resource(_ name: String, ext: String) -> URL {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) { return url }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Resources/\(name).\(ext)")
    }
    static func mark(size: CGFloat = 20) -> NSImage? {
        guard let image = NSImage(contentsOf: resource("BrandMark", ext: "svg")) else { return nil }
        image.size = NSSize(width: size, height: size); image.isTemplate = true; return image
    }
    static func icon(size: CGFloat = 80) -> NSImage? {
        guard let image = NSImage(contentsOf: resource("AppIcon", ext: "svg")) else { return nil }
        image.size = NSSize(width: size, height: size); return image
    }
}

final class NativeSurface: NSView {
    var color: NSColor = .windowBackgroundColor
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) { color.setFill(); bounds.fill() }
}

enum UI {
    static func label(_ text: String, size: CGFloat = 13, weight: NSFont.Weight = .regular,
                      color: NSColor = .labelColor, centered: Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString: text)
        field.font = .systemFont(ofSize: size, weight: weight); field.textColor = color
        field.alignment = centered ? .center : .left
        field.maximumNumberOfLines = 0; field.setContentCompressionResistancePriority(.required, for: .vertical)
        return field
    }
    static func stack(_ views: [NSView], vertical: Bool = true, spacing: CGFloat = 10,
                      centered: Bool = false) -> NSStackView {
        let stack = NSStackView(views: views); stack.orientation = vertical ? .vertical : .horizontal
        stack.alignment = vertical ? (centered ? .centerX : .leading) : .centerY
        stack.spacing = spacing; return stack
    }
    static func image(_ image: NSImage?, size: CGFloat) -> NSImageView {
        let view = NSImageView(); view.image = image
        view.widthAnchor.constraint(equalToConstant: size).isActive = true
        view.heightAnchor.constraint(equalToConstant: size).isActive = true
        return view
    }
    static func pin(_ content: NSView, in parent: NSView, padding: CGFloat = 18) {
        content.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: padding),
            content.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -padding),
            content.topAnchor.constraint(equalTo: parent.topAnchor, constant: padding),
            content.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -padding)
        ])
    }
    static func row(title: String, detail: String? = nil, control: NSView) -> NSView {
        var labels: [NSView] = [label(title, size: 13, weight: .medium)]
        if let detail { labels.append(label(detail, size: 12, color: .secondaryLabelColor)) }
        let words = stack(labels, spacing: 4)
        let row = NSView()
        words.translatesAutoresizingMaskIntoConstraints = false; control.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(words); row.addSubview(control)
        NSLayoutConstraint.activate([
            words.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            words.topAnchor.constraint(equalTo: row.topAnchor, constant: 2),
            words.bottomAnchor.constraint(equalTo: row.bottomAnchor, constant: -2),
            words.trailingAnchor.constraint(lessThanOrEqualTo: control.leadingAnchor, constant: -20),
            control.trailingAnchor.constraint(equalTo: row.trailingAnchor),
            control.centerYAnchor.constraint(equalTo: row.centerYAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 36)
        ])
        return row
    }
    static func group(_ rows: [NSView], width: CGFloat = 524) -> NSView {
        let panel = NSBox(); panel.boxType = .custom
        panel.cornerRadius = 10; panel.borderWidth = 0.5
        panel.borderColor = .separatorColor; panel.fillColor = .controlBackgroundColor
        panel.contentViewMargins = .zero
        let container = NSView(); panel.contentView = container
        var content: [NSView] = []
        for (index, row) in rows.enumerated() {
            if index > 0 { let line = NSBox(); line.boxType = .separator; content.append(line) }
            content.append(row)
        }
        let column = stack(content, spacing: 11)
        for view in content { view.widthAnchor.constraint(equalTo: column.widthAnchor).isActive = true }
        pin(column, in: container, padding: 14)
        column.widthAnchor.constraint(equalToConstant: width - 28).isActive = true
        panel.heightAnchor.constraint(equalTo: column.heightAnchor, constant: 28).isActive = true
        panel.widthAnchor.constraint(equalToConstant: width).isActive = true
        return panel
    }
    static func section(_ title: String) -> NSTextField { label(title, size: 12, weight: .semibold, color: .secondaryLabelColor) }
    static func link(_ title: String, target: AnyObject, action: Selector) -> NSButton {
        let button = NSButton(title: title, target: target, action: action)
        button.isBordered = false; button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = .linkColor; return button
    }
    static func menuHeader(headline: String, detail: String, volume: String? = nil) -> NSView {
        let header = NSView(frame: NSRect(x: 0, y: 0, width: 316, height: 84))
        header.widthAnchor.constraint(equalToConstant: 316).isActive = true
        header.heightAnchor.constraint(equalToConstant: 84).isActive = true
        let name = stack([image(BrandAssets.mark(size: 14), size: 14), label("声音守卫", size: 12, weight: .medium, color: .secondaryLabelColor)], vertical: false, spacing: 6)
        let title = label(headline, size: 14, weight: .medium)
        let info = label(detail, size: 12, color: .secondaryLabelColor)
        let value = label(volume ?? "", size: 12, color: .secondaryLabelColor)
        value.alignment = .right
        value.widthAnchor.constraint(equalToConstant: volume == nil ? 0 : 42).isActive = true
        name.widthAnchor.constraint(equalToConstant: 110).isActive = true
        name.detachesHiddenViews = false
        value.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        value.setContentCompressionResistancePriority(.required, for: .horizontal)
        for field in [title, info] {
            field.maximumNumberOfLines = 1; field.lineBreakMode = .byTruncatingTail
            field.toolTip = field.stringValue
            field.setAccessibilityLabel(field.stringValue)
            field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }
        value.setAccessibilityLabel(volume.map { "输出音量 " + $0 } ?? "")
        for view in [name, title, info, value] {
            view.translatesAutoresizingMaskIntoConstraints = false; header.addSubview(view)
        }
        NSLayoutConstraint.activate([
            name.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            name.topAnchor.constraint(equalTo: header.topAnchor, constant: 10),
            title.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            title.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 5),
            title.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            info.leadingAnchor.constraint(equalTo: name.leadingAnchor),
            info.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 5),
            value.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            value.firstBaselineAnchor.constraint(equalTo: info.firstBaselineAnchor),
            info.trailingAnchor.constraint(equalTo: value.leadingAnchor, constant: -12)
        ])
        return header
    }
}
