// OpenClaw.app — macOS menu-bar launcher for the OpenClaw gateway.
//
// The deliberately minimal sibling of 大肥鱼.app:
//   · left click  → open the Control UI (raising the tab you already have)
//   · right click → 开启/关闭网关  +  退出
// No restart item, no billing, no status line — the icon itself carries the state
// (full colour = running, dimmed = stopped).
//
// The gateway is a LaunchAgent on macOS, so starting it is silent: launchd runs it
// in the background with no terminal window. All real work lives in
// openclaw-ctl.sh, which this app just shells out to — see resolveCtlPath() for
// where that script is looked up.
import Cocoa

let PORT: UInt16 = 18789
let HOME = NSHomeDirectory()
let CONFIG = "\(HOME)/.openclaw/openclaw.json"

// MARK: - locating the service-layer script

/// Optional config, so the script location can be overridden without recompiling.
///
/// `~/.config/openclaw-menubar/config.json`
/// ```json
/// { "ctlPath": "~/bin/openclaw-ctl.sh" }
/// ```
func configuredCtlPath() -> String? {
    let path = "\(HOME)/.config/openclaw-menubar/config.json"
    guard let data = FileManager.default.contents(atPath: path),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let ctl = obj["ctlPath"] as? String, !ctl.isEmpty
    else { return nil }
    return (ctl as NSString).expandingTildeInPath
}

/// Find `openclaw-ctl.sh`. First executable path wins:
///
///   1. `$OPENCLAW_MENUBAR_CTL`
///   2. `ctlPath` in `~/.config/openclaw-menubar/config.json`
///   3. **bundled inside the app** (`Contents/Resources/openclaw-ctl.sh`)
///   4. `~/.local/bin/openclaw-ctl.sh`
///   5. `~/DeepSeekHarness/bin/openclaw-ctl.sh` — where earlier builds expected it
///
/// Step 3 is what makes a downloaded copy work out of the box; earlier builds
/// hardcoded step 5, which is the author's own machine and nobody else's.
func resolveCtlPath() -> String? {
    var candidates: [String] = []

    if let env = ProcessInfo.processInfo.environment["OPENCLAW_MENUBAR_CTL"], !env.isEmpty {
        candidates.append((env as NSString).expandingTildeInPath)
    }
    if let configured = configuredCtlPath() {
        candidates.append(configured)
    }
    if let bundled = Bundle.main.path(forResource: "openclaw-ctl", ofType: "sh") {
        candidates.append(bundled)
    }
    candidates.append("\(HOME)/.local/bin/openclaw-ctl.sh")
    candidates.append("\(HOME)/DeepSeekHarness/bin/openclaw-ctl.sh")

    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
}

/// nil when nothing was found — surfaced to the user instead of failing silently.
let CTL = resolveCtlPath()

// MARK: - helpers

/// Cheap liveness probe: TCP connect to the gateway port. Fast enough to run on a
/// 3-second timer, and it does not care whether launchd or a detached process owns it.
func gatewayIsRunning() -> Bool {
    let sock = socket(AF_INET, SOCK_STREAM, 0)
    if sock < 0 { return false }
    defer { close(sock) }

    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = PORT.bigEndian
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)

    let rc = withUnsafePointer(to: &addr) { ptr in
        ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
            connect(sock, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    return rc == 0
}

/// Run a shell command with a PATH that can find node/openclaw.
@discardableResult
func shell(_ args: [String]) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/zsh")
    p.arguments = ["-lc", args.joined(separator: " ")]
    var env = ProcessInfo.processInfo.environment
    env["PATH"] = "\(HOME)/.local/node/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
    p.environment = env
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "error: \(error.localizedDescription)" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

func ctl(_ arg: String) -> String {
    // shell() joins the arguments into one `zsh -lc` line, so the path needs quoting —
    // an app dragged into a folder with a space would otherwise split into two words.
    guard let path = CTL else {
        return "找不到 openclaw-ctl.sh。请把仓库里的它放到 ~/.local/bin/,"
             + "或设置 OPENCLAW_MENUBAR_CTL —— 详见 README「服务层脚本放哪」。"
    }
    return shell(["'\(path)'", arg])
}

/// Run an AppleScript snippet through osascript and return its stdout.
func runOsascript(_ script: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    p.arguments = ["-e", script]
    let pipe = Pipe()
    p.standardOutput = pipe
    p.standardError = pipe
    do { try p.run() } catch { return "" }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
}

/// The Control UI refuses to talk to the gateway without its token; the config's
/// `gateway.auth.token` is what `openclaw dashboard` folds into the URL fragment.
/// Read it live so a rotated token keeps working without rebuilding the app.
func gatewayToken() -> String {
    guard let data = FileManager.default.contents(atPath: CONFIG),
          let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let gw = root["gateway"] as? [String: Any],
          let auth = gw["auth"] as? [String: Any],
          let token = auth["token"] as? String,
          !token.isEmpty
    else { return "" }
    return token
}

func controlUIURL() -> URL {
    let token = gatewayToken()
    let s = token.isEmpty
        ? "http://127.0.0.1:\(PORT)/"
        : "http://127.0.0.1:\(PORT)/#token=\(token)"
    return URL(string: s)!
}

/// Raise an already-open Control UI tab instead of piling up duplicates.
///
/// Chromium browsers expose their tabs to AppleScript, so this needs no helper
/// extension (the Windows launcher needed a poll server on port 9335 — macOS
/// doesn't). Uses numeric window/tab indices: `repeat with t in tabs` yields
/// references whose `index of t` fails to coerce.
/// Returns true when an existing tab was raised.
func raiseExistingTab(browser: String) -> Bool {
    let script = """
    tell application "\(browser)"
        set wc to count of windows
        repeat with i from 1 to wc
            set tc to count of tabs of window i
            repeat with j from 1 to tc
                set u to URL of tab j of window i
                if u starts with "http://127.0.0.1:\(PORT)" then
                    set active tab index of window i to j
                    set index of window i to 1
                    activate
                    return "raised"
                end if
            end repeat
        end repeat
    end tell
    return "absent"
    """
    // Empty output means the browser isn't running or Automation permission was
    // refused — both are "no tab raised" for our purposes.
    return runOsascript(script).contains("raised")
}

// MARK: - app delegate

final class ClawDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var refreshTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = lobsterIcon()
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(handleClick(_:))
            // Receive both buttons. We deliberately do NOT set statusItem.menu below:
            // attaching a menu makes AppKit swallow every click and open the menu,
            // so the action decides and we pop the menu up by hand.
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        menu = NSMenu()
        menu.delegate = self

        refreshTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            self?.updateIconState()
        }
        updateIconState()
    }

    /// Quitting also stops the gateway, matching 大肥鱼.app — leaving the menu bar
    /// must not leave an orphan service behind. Covers every exit path (menu item,
    /// Cmd+Q, logout). Change this to a no-op if the gateway should outlive the icon.
    func applicationWillTerminate(_ notification: Notification) {
        _ = ctl("stop")
    }

    /// Left click = jump to the Control UI (the common case).
    /// Right click (or control-click) = the two-item menu.
    @objc func handleClick(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        let isRightClick = event?.type == .rightMouseUp
            || (event?.modifierFlags.contains(.control) ?? false)

        if isRightClick {
            // Attach the menu only for this click so AppKit positions it exactly like
            // a native status-bar menu, then detach it again — otherwise every later
            // left click would open the menu instead of running our action.
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            openControlUI()
        }
    }

    /// Load the lobster PNGs shipped in the bundle; fall back to an SF Symbol.
    /// Both 1x and 2x reps are added explicitly — NSImage(contentsOfFile:) does not
    /// pick up an @2x sibling on its own, so a single-rep icon would go soft on Retina.
    func lobsterIcon() -> NSImage? {
        let img = NSImage(size: NSSize(width: 18, height: 18))
        var found = false
        for name in ["claw", "claw@2x"] {
            if let path = Bundle.main.path(forResource: name, ofType: "png"),
               let rep = NSImage(contentsOfFile: path),
               let best = rep.representations.first {
                img.addRepresentation(best)
                found = true
            }
        }
        guard found else {
            let fallback = NSImage(systemSymbolName: "ant.fill", accessibilityDescription: "OpenClaw")
            fallback?.size = NSSize(width: 18, height: 18)
            fallback?.isTemplate = true
            return fallback
        }
        img.isTemplate = false   // keep the lobster red
        return img
    }

    /// Running = full colour; stopped = dimmed, so state reads at a glance.
    func updateIconState() {
        let running = gatewayIsRunning()
        statusItem.button?.alphaValue = running ? 1.0 : 0.35
        statusItem.button?.toolTip = running
            ? "OpenClaw 运行中  ·  http://127.0.0.1:\(PORT)"
            : "OpenClaw 已停止  ·  点击启动"
    }

    // Rebuilt each time it opens so it always reflects live state.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let running = gatewayIsRunning()

        let toggle = NSMenuItem(
            title: running ? "关闭网关" : "开启网关",
            action: #selector(toggleGateway), keyEquivalent: "t")
        toggle.target = self
        menu.addItem(toggle)

        let quit = NSMenuItem(title: "退出", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    // MARK: actions

    @objc func toggleGateway() {
        let running = gatewayIsRunning()
        _ = ctl(running ? "stop" : "start")
        updateIconState()
    }

    @objc func openControlUI() {
        if !gatewayIsRunning() { _ = ctl("start") }
        updateIconState()
        // Prefer raising the tab the user already has; fall back to opening one.
        for browser in ["Microsoft Edge", "Google Chrome"] {
            if raiseExistingTab(browser: browser) { return }
        }
        NSWorkspace.shared.open(controlUIURL())
    }

    @objc func quitApp() {
        NSApp.terminate(nil)
    }
}

// MARK: - entry point

let app = NSApplication.shared
let delegate = ClawDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // no Dock icon
app.run()
