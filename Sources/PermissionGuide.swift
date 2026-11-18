import AppKit
import ApplicationServices
import PermissionFlow

/// The three system permissions Jit needs, as last read from macOS.
struct PermissionState: Equatable {
    var accessibility: Bool
    var inputMonitoring: Bool
    var postEvents: Bool

    static func current() -> PermissionState {
        PermissionState(
            accessibility: AXIsProcessTrusted(),
            inputMonitoring: CGPreflightListenEventAccess(),
            postEvents: CGPreflightPostEventAccess()
        )
    }

    var allGranted: Bool { accessibility && inputMonitoring && postEvents }

    /// The next System Settings pane that still needs Jit. Post Events is
    /// granted from the Accessibility list, so it shares that pane.
    var nextPane: PermissionFlowPane? {
        if !accessibility || !postEvents { return .accessibility }
        if !inputMonitoring { return .inputMonitoring }
        return nil
    }
}

/// Walks the user through the missing permissions: opens the right
/// System Settings pane with a floating Jit tile to drag into the list, and
/// watches for the grant so it can move on to the next pane by itself.
///
/// macOS sends no notification when a permission changes, so the guide polls
/// once a second while it runs.
@MainActor
final class PermissionGuide {
    /// Called whenever any of the three permissions changes.
    var onChange: ((PermissionState) -> Void)?
    /// Called once every permission is granted.
    var onFinished: (() -> Void)?

    private var flow: PermissionFlowController?
    private var timer: Timer?
    private var currentPane: PermissionFlowPane?
    private var lastState = PermissionState.current()
    private var startedAt = Date()
    private static let pollLimit: TimeInterval = 15 * 60

    var isRunning: Bool { timer != nil }

    /// Starts with `pane`, or with the first missing permission when nil.
    /// `sourceFrame` (screen coordinates) is where the tile flies from.
    func start(pane: PermissionFlowPane? = nil, from sourceFrame: CGRect? = nil) {
        let state = PermissionState.current()
        lastState = state
        guard let target = pane ?? state.nextPane else {
            finish()
            return
        }
        open(target, from: sourceFrame)
        startedAt = Date()
        if timer == nil {
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        currentPane = nil
        flow?.closePanel()
    }

    private func open(_ pane: PermissionFlowPane, from sourceFrame: CGRect?) {
        currentPane = pane
        let flow = self.flow ?? PermissionFlow.makeController(
            configuration: .init(requiredAppURLs: [Bundle.main.bundleURL])
        )
        self.flow = flow
        flow.authorize(pane: pane, suggestedAppURLs: [Bundle.main.bundleURL], sourceFrameInScreen: sourceFrame)
    }

    private func poll() {
        let state = PermissionState.current()
        if state != lastState {
            lastState = state
            onChange?(state)
        }
        if state.allGranted {
            finish()
            return
        }
        if let next = state.nextPane, next != currentPane {
            // The pane we were guiding is done; move on to the next one.
            open(next, from: nil)
            return
        }
        if Date().timeIntervalSince(startedAt) > Self.pollLimit {
            stop()
        }
    }

    private func finish() {
        stop()
        onFinished?()
    }
}
