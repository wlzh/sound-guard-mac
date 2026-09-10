import AppKit
import GuardCore

extension AppDelegate {
    @objc func showAbout() {
        if about == nil {
            about = window("关于声音守卫", width: 440, height: 520)
            about!.styleMask.insert(.fullSizeContentView)
            about!.titlebarAppearsTransparent = true; about!.titleVisibility = .hidden
            let root = NativeSurface(); about!.contentView = root
            let identity = UI.stack([
                UI.label("声音守卫", size: 28, weight: .semibold, centered: true),
                UI.label("Sound Guard", size: 14, color: .secondaryLabelColor, centered: true),
                UI.label("版本 \(AppVersion.current) · Build \(AppVersion.build)", size: 12, color: .secondaryLabelColor, centered: true),
                UI.label("开发预览", size: 12, color: .systemOrange, centered: true)
            ], spacing: 4, centered: true)
            let author = UI.stack([UI.label("作者", size: 12, color: .secondaryLabelColor), UI.link("X @wlzh", target: self, action: #selector(openAuthor))], vertical: false, spacing: 6)
            let credits = UI.stack([author, UI.link("869hr.uk", target: self, action: #selector(openWebsite))], spacing: 5, centered: true)
            let divider = NSBox(); divider.boxType = .separator; divider.widthAnchor.constraint(equalToConstant: 310).isActive = true
            let links = UI.stack([
                UI.link("GitHub", target: self, action: #selector(openRepository)),
                UI.link("使用文档", target: self, action: #selector(openGuide)),
                UI.link("版本记录", target: self, action: #selector(openReleases))
            ], vertical: false, spacing: 24)
            let footer = UI.stack([UI.link("MIT License", target: self, action: #selector(showLicense)), UI.label("© 2026 wlzh", size: 12, color: .tertiaryLabelColor)], vertical: false, spacing: 10)
            let body = UI.stack([
                UI.image(BrandAssets.icon(), size: 80), identity,
                UI.label("闲置自动归零，开启由你决定。", size: 13, color: .secondaryLabelColor, centered: true),
                credits, divider, links,
                UI.label("不使用麦克风 · 不保存音频 · 无遥测", size: 12, color: .secondaryLabelColor, centered: true), footer
            ], spacing: 13, centered: true)
            body.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(body)
            NSLayoutConstraint.activate([
                body.centerXAnchor.constraint(equalTo: root.centerXAnchor), body.centerYAnchor.constraint(equalTo: root.centerYAnchor, constant: 6),
                body.widthAnchor.constraint(equalToConstant: 376),
                body.topAnchor.constraint(greaterThanOrEqualTo: root.topAnchor, constant: 32),
                body.bottomAnchor.constraint(lessThanOrEqualTo: root.bottomAnchor, constant: -20)
            ])
        }
        present(about!)
    }
    @objc func showLicense() {
        let local = Bundle.main.resourceURL?.appendingPathComponent("LICENSE")
        let source = BrandAssets.resource("BrandMark", ext: "svg").deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("LICENSE")
        let license = (local.flatMap { try? String(contentsOf: $0, encoding: .utf8) }) ?? (try? String(contentsOf: source, encoding: .utf8)) ?? "完整 MIT 协议请查看 GitHub 仓库中的 LICENSE。"
        let alert = NSAlert(); alert.messageText = "MIT License"; alert.informativeText = "Copyright © 2026 wlzh"
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 400, height: 240)); scroll.hasVerticalScroller = true
        let view = NSTextView(frame: scroll.bounds); view.isEditable = false; view.string = license
        view.font = .monospacedSystemFont(ofSize: 11, weight: .regular); view.textContainerInset = NSSize(width: 8, height: 8)
        view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]
        view.textContainer?.widthTracksTextView = true; scroll.documentView = view
        alert.accessoryView = scroll; alert.addButton(withTitle: "完成")
        if let about { alert.beginSheetModal(for: about) } else { alert.runModal() }
    }
}
