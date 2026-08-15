import AppKit

private let strokeWidthOptions: [CGFloat] = [2, 4, 8, 14]

@MainActor
private func screenMarkerOverlayFrame(for screen: NSScreen) -> NSRect {
    // Keep the macOS menu bar reachable because all controls now live there.
    screen.visibleFrame
}

@MainActor
func runLogicSelfTest() {
    let store = AnnotationStore()
    let view = OverlayView(store: store)

    view.beginAnnotation(at: CGPoint(x: 10, y: 10))
    view.updateAnnotation(at: CGPoint(x: 20, y: 20))
    view.finishAnnotation(at: CGPoint(x: 30, y: 30))
    precondition(store.annotations.isEmpty, "默认待机状态不应该生成标记")

    store.isDrawingEnabled = true
    store.currentTool = .line
    view.beginAnnotation(at: CGPoint(x: 10, y: 10))
    view.updateAnnotation(at: CGPoint(x: 100, y: 100))
    view.finishAnnotation(at: CGPoint(x: 100, y: 100))
    precondition(store.annotations.count == 1, "选择工具后应该可以生成标记")

    view.undo()
    precondition(store.annotations.isEmpty, "撤回应删除最后一个标记")

    store.isDrawingEnabled = true
    view.beginAnnotation(at: CGPoint(x: 10, y: 10))
    view.finishAnnotation(at: CGPoint(x: 20, y: 20))
    view.clear()
    precondition(store.annotations.isEmpty, "清空应删除全部标记")

    if let mainScreen = NSScreen.main {
        let overlayFrame = screenMarkerOverlayFrame(for: mainScreen)
        precondition(overlayFrame.maxY <= mainScreen.visibleFrame.maxY + 0.5, "绘图层不能覆盖菜单栏")
    }

    print("PASS: 逻辑自检通过")
}

if CommandLine.arguments.contains("--logic-self-test") {
    MainActor.assumeIsolated {
        runLogicSelfTest()
    }
    exit(0)
}

enum AnnotationTool: String, CaseIterable {
    case pen = "画笔"
    case line = "直线"
    case arrow = "箭头"
    case rectangle = "矩形"
    case oval = "圆形"
}

final class Annotation: NSObject {
    let tool: AnnotationTool
    let color: NSColor
    let lineWidth: CGFloat
    var points: [CGPoint]

    init(tool: AnnotationTool, color: NSColor, lineWidth: CGFloat, points: [CGPoint]) {
        self.tool = tool
        self.color = color
        self.lineWidth = lineWidth
        self.points = points
    }
}

@MainActor
final class AnnotationStore {
    var currentTool: AnnotationTool = .pen
    var currentColor: NSColor = .systemRed
    var lineWidth: CGFloat = 4
    var annotations: [Annotation] = []
    var isDrawingEnabled = false

    func adjustLineWidth(by step: Int) {
        let currentIndex = strokeWidthOptions
            .enumerated()
            .min(by: { abs($0.element - lineWidth) < abs($1.element - lineWidth) })?
            .offset ?? 1
        let nextIndex = min(max(currentIndex + step, 0), strokeWidthOptions.count - 1)
        lineWidth = strokeWidthOptions[nextIndex]
    }
}

@MainActor
final class OverlayView: NSView {
    private let store: AnnotationStore
    private var currentAnnotation: Annotation?
    private lazy var penCursor = makePenCursor()
    private var trackingArea: NSTrackingArea?

    init(store: AnnotationStore) {
        self.store = store
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea {
            removeTrackingArea(trackingArea)
        }

        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeAlways, .mouseMoved, .cursorUpdate, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
        self.trackingArea = trackingArea
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: store.isDrawingEnabled ? penCursor : .arrow)
    }

    override func cursorUpdate(with event: NSEvent) {
        updateActiveCursor()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            NSApp.terminate(nil)
        } else if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "z" {
            undo()
        } else {
            super.keyDown(with: event)
        }
    }

    func beginAnnotation(at point: CGPoint) {
        guard store.isDrawingEnabled else { return }
        currentAnnotation = Annotation(
            tool: store.currentTool,
            color: store.currentColor,
            lineWidth: store.lineWidth,
            points: [point]
        )
        needsDisplay = true
    }

    func updateAnnotation(at point: CGPoint) {
        guard store.isDrawingEnabled else { return }
        guard let currentAnnotation else { return }

        if currentAnnotation.tool == .pen {
            currentAnnotation.points.append(point)
        } else if currentAnnotation.points.count == 1 {
            currentAnnotation.points.append(point)
        } else {
            currentAnnotation.points[1] = point
        }

        needsDisplay = true
    }

    func finishAnnotation(at point: CGPoint) {
        guard store.isDrawingEnabled else { return }
        guard let currentAnnotation else { return }

        if currentAnnotation.tool != .pen {
            if currentAnnotation.points.count == 1 {
                currentAnnotation.points.append(point)
            } else {
                currentAnnotation.points[1] = point
            }
        }

        store.annotations.append(currentAnnotation)
        self.currentAnnotation = nil
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        updateActiveCursor()
        beginAnnotation(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseMoved(with event: NSEvent) {
        updateActiveCursor()
    }

    override func mouseDragged(with event: NSEvent) {
        updateActiveCursor()
        updateAnnotation(at: convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        finishAnnotation(at: convert(event.locationInWindow, from: nil))
    }

    override func rightMouseDown(with event: NSEvent) {
        guard store.isDrawingEnabled else { return }
        clear()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.clear.setFill()
        dirtyRect.fill()

        for annotation in store.annotations {
            draw(annotation)
        }

        if let currentAnnotation {
            draw(currentAnnotation)
        }
    }

    func undo() {
        _ = store.annotations.popLast()
        needsDisplay = true
    }

    func clear() {
        store.annotations.removeAll()
        currentAnnotation = nil
        needsDisplay = true
    }

    func refreshCursor() {
        window?.discardCursorRects()
        window?.invalidateCursorRects(for: self)
        updateActiveCursor()
    }

    private func updateActiveCursor() {
        if store.isDrawingEnabled {
            penCursor.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func draw(_ annotation: Annotation) {
        guard let first = annotation.points.first else { return }

        annotation.color.setStroke()
        annotation.color.withAlphaComponent(0.12).setFill()

        let path = NSBezierPath()
        path.lineWidth = annotation.lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        switch annotation.tool {
        case .pen:
            path.move(to: first)
            for point in annotation.points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()

        case .line:
            guard let last = annotation.points.last else { return }
            path.move(to: first)
            path.line(to: last)
            path.stroke()

        case .arrow:
            guard let last = annotation.points.last else { return }
            drawArrow(from: first, to: last, color: annotation.color, lineWidth: annotation.lineWidth)

        case .rectangle:
            guard let last = annotation.points.last else { return }
            path.appendRect(rect(from: first, to: last))
            path.fill()
            path.stroke()

        case .oval:
            guard let last = annotation.points.last else { return }
            path.appendOval(in: rect(from: first, to: last))
            path.fill()
            path.stroke()
        }
    }

    private func rect(from start: CGPoint, to end: CGPoint) -> CGRect {
        CGRect(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }

    private func drawArrow(from start: CGPoint, to end: CGPoint, color: NSColor, lineWidth: CGFloat) {
        color.setStroke()

        let body = NSBezierPath()
        body.lineWidth = lineWidth
        body.lineCapStyle = .round
        body.move(to: start)
        body.line(to: end)
        body.stroke()

        let angle = atan2(end.y - start.y, end.x - start.x)
        let headLength: CGFloat = 18
        let headAngle: CGFloat = .pi / 7

        let p1 = CGPoint(
            x: end.x - headLength * cos(angle - headAngle),
            y: end.y - headLength * sin(angle - headAngle)
        )
        let p2 = CGPoint(
            x: end.x - headLength * cos(angle + headAngle),
            y: end.y - headLength * sin(angle + headAngle)
        )

        let head = NSBezierPath()
        head.lineWidth = lineWidth
        head.lineCapStyle = .round
        head.move(to: end)
        head.line(to: p1)
        head.move(to: end)
        head.line(to: p2)
        head.stroke()
    }

    private func makePenCursor() -> NSCursor {
        let size = NSSize(width: 24, height: 24)
        let image = NSImage(size: size)
        image.lockFocus()

        NSColor.white.setStroke()
        let outer = NSBezierPath()
        outer.lineWidth = 5
        outer.lineCapStyle = .round
        outer.lineJoinStyle = .round
        outer.move(to: NSPoint(x: 5, y: 5))
        outer.line(to: NSPoint(x: 18, y: 18))
        outer.stroke()

        NSColor.black.setStroke()
        let body = NSBezierPath()
        body.lineWidth = 3
        body.lineCapStyle = .round
        body.lineJoinStyle = .round
        body.move(to: NSPoint(x: 5, y: 5))
        body.line(to: NSPoint(x: 18, y: 18))
        body.stroke()

        let tip = NSBezierPath()
        tip.lineWidth = 2.4
        tip.lineCapStyle = .round
        tip.lineJoinStyle = .round
        tip.move(to: NSPoint(x: 3, y: 3))
        tip.line(to: NSPoint(x: 5, y: 5))
        tip.line(to: NSPoint(x: 7.5, y: 3.8))
        tip.stroke()

        image.unlockFocus()
        return NSCursor(image: image, hotSpot: NSPoint(x: 5, y: 19))
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = AnnotationStore()
    private var overlayWindows: [NSWindow] = []
    private var overlayViews: [OverlayView] = []
    private var statusController: StatusBarController?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        installSafetyKeyMonitor()
        createOverlayWindows()
        statusController = StatusBarController(store: store, overlayWindows: overlayWindows, overlayViews: overlayViews)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
    }

    private func installSafetyKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 {
                self.setDrawingEnabled(false)
                return nil
            }

            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "q" {
                NSApp.terminate(nil)
                return nil
            }

            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "z" {
                self.overlayViews.forEach { $0.undo() }
                return nil
            }

            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "k" {
                self.overlayViews.forEach { $0.clear() }
                return nil
            }

            if event.charactersIgnoringModifiers == "[" {
                self.store.adjustLineWidth(by: -1)
                self.statusController?.refresh()
                return nil
            }

            if event.charactersIgnoringModifiers == "]" {
                self.store.adjustLineWidth(by: 1)
                self.statusController?.refresh()
                return nil
            }

            if let character = event.charactersIgnoringModifiers, let tool = self.tool(forShortcut: character) {
                self.store.currentTool = tool
                self.setDrawingEnabled(true)
                self.statusController?.refresh()
                return nil
            }

            return event
        }
    }

    private func createOverlayWindows() {
        for screen in NSScreen.screens {
            let view = OverlayView(store: store)
            let frame = screenMarkerOverlayFrame(for: screen)
            let window = NSWindow(
                contentRect: frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )

            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.ignoresMouseEvents = true
            window.acceptsMouseMovedEvents = true
            window.contentView = view
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(view)

            overlayWindows.append(window)
            overlayViews.append(view)
        }
    }

    private func setDrawingEnabled(_ enabled: Bool) {
        store.isDrawingEnabled = enabled
        overlayWindows.forEach { $0.ignoresMouseEvents = !enabled }
        overlayViews.forEach { $0.refreshCursor() }
        statusController?.refresh()
    }

    private func tool(forShortcut shortcut: String) -> AnnotationTool? {
        switch shortcut {
        case "1": .pen
        case "2": .line
        case "3": .arrow
        case "4": .rectangle
        case "5": .oval
        default: nil
        }
    }
}

@MainActor
final class StatusBarController: NSObject {
    private let store: AnnotationStore
    private let overlayWindows: [NSWindow]
    private let overlayViews: [OverlayView]
    private let statusItem: NSStatusItem
    private var toolItems: [AnnotationTool: NSMenuItem] = [:]
    private var strokeWidthItems: [CGFloat: NSMenuItem] = [:]
    private var enabledItem: NSMenuItem?

    init(store: AnnotationStore, overlayWindows: [NSWindow], overlayViews: [OverlayView]) {
        self.store = store
        self.overlayWindows = overlayWindows
        self.overlayViews = overlayViews
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        configure()
    }

    private func configure() {
        statusItem.button?.title = ""
        statusItem.button?.image = makeStatusBarIcon()
        statusItem.button?.toolTip = "边记正在运行"

        let menu = NSMenu()
        let enabledItem = NSMenuItem(title: "状态：待机", action: nil, keyEquivalent: "")
        self.enabledItem = enabledItem
        menu.addItem(enabledItem)
        menu.addItem(NSMenuItem.separator())

        for (index, tool) in AnnotationTool.allCases.enumerated() {
            let item = NSMenuItem(title: "\(tool.rawValue)  \(index + 1)", action: #selector(selectTool(_:)), keyEquivalent: "\(index + 1)")
            item.representedObject = tool.rawValue
            item.target = self
            toolItems[tool] = item
            menu.addItem(item)
        }

        menu.addItem(NSMenuItem.separator())
        for width in strokeWidthOptions {
            let item = NSMenuItem(title: lineWidthTitle(width), action: #selector(selectLineWidth(_:)), keyEquivalent: "")
            item.representedObject = width
            item.target = self
            strokeWidthItems[width] = item
            menu.addItem(item)
        }
        menu.addItem(NSMenuItem(title: "变细  [", action: #selector(decreaseLineWidth), keyEquivalent: "["))
        menu.addItem(NSMenuItem(title: "变粗  ]", action: #selector(increaseLineWidth), keyEquivalent: "]"))
        menu.addItem(NSMenuItem.separator())
        addColorItem("红色", color: .systemRed, to: menu)
        addColorItem("黄色", color: .systemYellow, to: menu)
        addColorItem("蓝色", color: .systemBlue, to: menu)
        addColorItem("绿色", color: .systemGreen, to: menu)
        addColorItem("白色", color: .white, to: menu)
        menu.addItem(NSMenuItem(title: "打开色盘", action: #selector(openColorPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem(title: "暂停标记  Esc", action: #selector(pauseDrawing), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "撤回", action: #selector(undo), keyEquivalent: "z"))
        menu.addItem(NSMenuItem(title: "清空", action: #selector(clear), keyEquivalent: "k"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出边记", action: #selector(quit), keyEquivalent: "q"))

        for item in menu.items where item.action != nil {
            item.target = self
        }

        statusItem.menu = menu
        refresh()
    }

    private func makeStatusBarIcon() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        NSColor.black.setStroke()

        let cursor = NSBezierPath()
        cursor.lineWidth = 1.8
        cursor.lineCapStyle = .round
        cursor.lineJoinStyle = .round
        cursor.move(to: NSPoint(x: 3.5, y: 15))
        cursor.line(to: NSPoint(x: 3.8, y: 4.2))
        cursor.line(to: NSPoint(x: 7.1, y: 7.0))
        cursor.line(to: NSPoint(x: 9.1, y: 2.8))
        cursor.line(to: NSPoint(x: 11.0, y: 3.8))
        cursor.line(to: NSPoint(x: 8.9, y: 8.1))
        cursor.line(to: NSPoint(x: 13.0, y: 8.0))
        cursor.close()
        cursor.stroke()

        let line = NSBezierPath()
        line.lineWidth = 2.1
        line.lineCapStyle = .round
        line.lineJoinStyle = .round
        line.move(to: NSPoint(x: 9.0, y: 8.0))
        line.curve(
            to: NSPoint(x: 16.0, y: 8.9),
            controlPoint1: NSPoint(x: 11.0, y: 12.3),
            controlPoint2: NSPoint(x: 13.4, y: 5.6)
        )
        line.stroke()

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func lineWidthTitle(_ width: CGFloat) -> String {
        switch width {
        case 2:
            return "粗细：细"
        case 4:
            return "粗细：标准"
        case 8:
            return "粗细：粗"
        case 14:
            return "粗细：很粗"
        default:
            return "粗细：\(Int(width))"
        }
    }

    private func addColorItem(_ title: String, color: NSColor, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: #selector(selectPresetColor(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = color
        menu.addItem(item)
    }

    func refresh() {
        enabledItem?.title = store.isDrawingEnabled ? "状态：正在标记 \(store.currentTool.rawValue)" : "状态：待机"

        for (tool, item) in toolItems {
            item.state = tool == store.currentTool && store.isDrawingEnabled ? .on : .off
        }

        for (width, item) in strokeWidthItems {
            item.state = width == store.lineWidth ? .on : .off
        }
    }

    private func setDrawingEnabled(_ enabled: Bool) {
        store.isDrawingEnabled = enabled
        overlayWindows.forEach { $0.ignoresMouseEvents = !enabled }
        overlayViews.forEach { $0.refreshCursor() }
        refresh()
    }

    @objc private func selectTool(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let tool = AnnotationTool(rawValue: rawValue)
        else {
            return
        }

        store.currentTool = tool
        setDrawingEnabled(true)
    }

    @objc private func selectPresetColor(_ sender: NSMenuItem) {
        guard let color = sender.representedObject as? NSColor else { return }
        store.currentColor = color
    }

    @objc private func selectLineWidth(_ sender: NSMenuItem) {
        guard let width = sender.representedObject as? CGFloat else { return }
        store.lineWidth = width
        refresh()
    }

    @objc private func decreaseLineWidth() {
        store.adjustLineWidth(by: -1)
        refresh()
    }

    @objc private func increaseLineWidth() {
        store.adjustLineWidth(by: 1)
        refresh()
    }

    @objc private func openColorPanel() {
        let colorPanel = NSColorPanel.shared
        colorPanel.color = store.currentColor
        colorPanel.setTarget(self)
        colorPanel.setAction(#selector(selectPanelColor(_:)))
        colorPanel.orderFrontRegardless()
    }

    @objc private func selectPanelColor(_ sender: NSColorPanel) {
        store.currentColor = sender.color
    }

    @objc private func undo() {
        overlayViews.forEach { $0.undo() }
    }

    @objc private func clear() {
        overlayViews.forEach { $0.clear() }
    }

    @objc private func pauseDrawing() {
        setDrawingEnabled(false)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
