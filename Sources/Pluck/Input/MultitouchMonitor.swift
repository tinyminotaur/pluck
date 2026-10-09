import Foundation

/// EXPERIMENTAL — counts fingers on the trackpad via Apple's private MultitouchSupport framework
/// (the same route BetterTouchTool-style utilities use). A listen-only `NSEvent` monitor cannot see
/// raw touches, so this is the only way to implement a "three fingers down" trigger.
///
/// Private API: it can disappear or change in any macOS release. Everything is looked up with
/// `dlopen`/`dlsym`, so if anything is missing Pluck simply reports `isAvailable == false` and
/// carries on. Off by default (see `PluckConfig.threeFingerEnabled`).
final class MultitouchMonitor: @unchecked Sendable {
    static let shared = MultitouchMonitor()

    private typealias DeviceRef = UnsafeMutableRawPointer
    private typealias FrameCallback = @convention(c) (
        UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, Int32, Double, Int32
    ) -> Int32
    private typealias CreateListFn = @convention(c) () -> Unmanaged<CFArray>?
    private typealias RegisterFn = @convention(c) (DeviceRef, FrameCallback) -> Void
    private typealias StartFn = @convention(c) (DeviceRef, Int32) -> Void
    private typealias StopFn = @convention(c) (DeviceRef) -> Void

    private let lock = NSLock()
    private var devices: [DeviceRef] = []
    private var stopFn: StopFn?
    private var running = false

    /// Touch count callback, invoked on a private Multitouch thread. Hop to main yourself.
    fileprivate static var onCount: ((Int) -> Void)?
    fileprivate static var lastCount = -1

    private(set) var isAvailable = false

    func start(onCount: @escaping (Int) -> Void) {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }
        guard let handle = dlopen(
            "/System/Library/PrivateFrameworks/MultitouchSupport.framework/MultitouchSupport", RTLD_NOW
        ),
        let createSym = dlsym(handle, "MTDeviceCreateList"),
        let registerSym = dlsym(handle, "MTRegisterContactFrameCallback"),
        let startSym = dlsym(handle, "MTDeviceStart"),
        let stopSym = dlsym(handle, "MTDeviceStop") else {
            NSLog("Pluck: MultitouchSupport unavailable; three-finger trigger disabled")
            isAvailable = false
            return
        }
        let create = unsafeBitCast(createSym, to: CreateListFn.self)
        let register = unsafeBitCast(registerSym, to: RegisterFn.self)
        let startDevice = unsafeBitCast(startSym, to: StartFn.self)
        stopFn = unsafeBitCast(stopSym, to: StopFn.self)

        guard let list = create()?.takeRetainedValue(), CFArrayGetCount(list) > 0 else {
            NSLog("Pluck: no multitouch devices found")
            isAvailable = false
            return
        }

        Self.onCount = onCount
        Self.lastCount = -1
        let callback: FrameCallback = { _, _, count, _, _ in
            let n = Int(count)
            if n != MultitouchMonitor.lastCount {
                MultitouchMonitor.lastCount = n
                MultitouchMonitor.onCount?(n)
            }
            return 0
        }

        devices = []
        for i in 0..<CFArrayGetCount(list) {
            guard let raw = CFArrayGetValueAtIndex(list, i) else { continue }
            let device = UnsafeMutableRawPointer(mutating: raw)
            register(device, callback)
            startDevice(device, 0)
            devices.append(device)
        }
        isAvailable = !devices.isEmpty
        running = isAvailable
        // The CFArray (and so the device refs) must stay alive while running.
        retainedList = list
    }

    private var retainedList: CFArray?

    func stop() {
        lock.lock(); defer { lock.unlock() }
        guard running else { return }
        if let stopFn { for d in devices { stopFn(d) } }
        devices = []
        retainedList = nil
        Self.onCount = nil
        running = false
    }
}
