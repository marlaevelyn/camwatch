// camwatch — report whether the camera and/or microphone on this Mac are in use.
//
// Camera: CoreMediaIO's kCMIODevicePropertyDeviceIsRunningSomewhere, true while
// any process streams from a camera (green light).
// Mic: CoreAudio's per-process kAudioProcessPropertyIsRunningInput (macOS 14.2+),
// true while a process records audio (orange dot). Per-process rather than
// per-device so headphones playing music don't count as "mic on".
// Event-driven; never opens the camera or mic.
//
// States: video (camera on, mic either way), mic (mic on, camera off), off.
// Either trigger can be disabled with ./set-trigger; a disabled one counts as off.
//
// Usage:
//   camwatch status   print state once; exit 0 = video, 2 = mic only, 1 = off
//   camwatch watch    print state now and on every (debounced) change, and run
//                     <dir of binary>/on-change.sh <video|mic|off> "<details>"
//
// Build: swiftc -O camwatch.swift -o camwatch -framework CoreMediaIO -framework CoreAudio

import CoreAudio
import CoreMediaIO
import Foundation

let debounceSeconds = 2.0

// MARK: - camera (CoreMediaIO)

func cameraAddress(_ selector: Int, scope: Int = kCMIOObjectPropertyScopeGlobal) -> CMIOObjectPropertyAddress {
    CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(selector),
        mScope: CMIOObjectPropertyScope(scope),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
}

let cameraSystem = CMIOObjectID(kCMIOObjectSystemObject)

func videoDevices() -> [CMIOObjectID] {
    var addr = cameraAddress(kCMIOHardwarePropertyDevices)
    var size: UInt32 = 0
    guard CMIOObjectGetPropertyDataSize(cameraSystem, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(cameraSystem, &addr, 0, nil, size, &used, &ids) == noErr else { return [] }
    return ids.filter(hasInputStreams)
}

func hasInputStreams(_ device: CMIOObjectID) -> Bool {
    var addr = cameraAddress(kCMIODevicePropertyStreams, scope: kCMIODevicePropertyScopeInput)
    var size: UInt32 = 0
    return CMIOObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr && size > 0
}

func name(of device: CMIOObjectID) -> String {
    var addr = cameraAddress(kCMIOObjectPropertyName)
    var value: Unmanaged<CFString>?
    var used: UInt32 = 0
    let size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &used, &value) == noErr,
          let name = value?.takeRetainedValue() else { return "device \(device)" }
    return name as String
}

func isRunning(_ device: CMIOObjectID) -> Bool {
    var addr = cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
    var running: UInt32 = 0
    var used: UInt32 = 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    guard CMIOObjectGetPropertyData(device, &addr, 0, nil, size, &used, &running) == noErr else { return false }
    return running != 0
}

/// Names of cameras currently in use.
func activeCameras() -> [String] {
    videoDevices().filter(isRunning).map(name(of:))
}

// MARK: - microphone (CoreAudio process objects)

func audioAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
        mSelector: selector,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
}

let audioSystem = AudioObjectID(kAudioObjectSystemObject)

func audioProcesses() -> [AudioObjectID] {
    var addr = audioAddress(kAudioHardwarePropertyProcessObjectList)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(audioSystem, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(audioSystem, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func isRecording(_ process: AudioObjectID) -> Bool {
    var addr = audioAddress(kAudioProcessPropertyIsRunningInput)
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
}

func appName(of process: AudioObjectID) -> String {
    var addr = audioAddress(kAudioProcessPropertyBundleID)
    var value: Unmanaged<CFString>?
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    if AudioObjectGetPropertyData(process, &addr, 0, nil, &size, &value) == noErr,
       let bundleID = value?.takeRetainedValue() as String?, !bundleID.isEmpty {
        return bundleID
    }
    var pidAddr = audioAddress(kAudioProcessPropertyPID)
    var pid: pid_t = 0
    size = UInt32(MemoryLayout<pid_t>.size)
    AudioObjectGetPropertyData(process, &pidAddr, 0, nil, &size, &pid)
    return "pid \(pid)"
}

/// Audio devices that have input streams (microphones).
func micDevices() -> [AudioObjectID] {
    var addr = audioAddress(kAudioHardwarePropertyDevices)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(audioSystem, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(audioSystem, &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids.filter { device in
        var streams = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: kAudioObjectPropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
        var streamsSize: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &streams, 0, nil, &streamsSize) == noErr && streamsSize > 0
    }
}

/// Apps currently recording from any microphone.
func activeMicApps() -> [String] {
    Array(Set(audioProcesses().filter(isRecording).map(appName(of:)))).sorted()
}

// MARK: - combined state

enum State: String {
    case video, mic, off

    var label: String {
        switch self {
        case .video: "VIDEO  camera on"
        case .mic: "MIC    mic on, camera off"
        case .off: "OFF    camera and mic off"
        }
    }
}

struct Snapshot {
    let cameras: [String]
    let micApps: [String]

    /// A disabled trigger (see ./set-trigger) is not read, so it never counts as on.
    static func now() -> Snapshot {
        Snapshot(cameras: triggerEnabled("video") ? activeCameras() : [],
                 micApps: triggerEnabled("mic") ? activeMicApps() : [])
    }

    var state: State { !cameras.isEmpty ? .video : !micApps.isEmpty ? .mic : .off }

    var details: String {
        var parts: [String] = []
        if !cameras.isEmpty { parts.append("camera: \(cameras.joined(separator: ", "))") }
        if !micApps.isEmpty { parts.append("mic: \(micApps.joined(separator: ", "))") }
        return parts.joined(separator: "; ")
    }
}

func timestamp() -> String {
    ISO8601DateFormatter.string(from: Date(), timeZone: .current, formatOptions: [.withInternetDateTime])
}

func report(_ snapshot: Snapshot) {
    let details = snapshot.details.isEmpty ? "" : "  (\(snapshot.details))"
    print("\(timestamp())  \(snapshot.state.label)\(details)")
}

let projectDir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

/// A trigger ("video" or "mic") is ignored while <project dir>/<trigger>.disabled
/// exists. Checked on every state read, so ./set-trigger needs no rebuild.
func triggerEnabled(_ trigger: String) -> Bool {
    !FileManager.default.fileExists(atPath: projectDir.appendingPathComponent("\(trigger).disabled").path)
}

var hookProcess: Process?

/// Run on-change.sh for a state change, or with `refresh` to re-send an
/// unchanged state (catches bulbs that missed an update or were power-cycled).
func runHook(_ snapshot: Snapshot, refresh: Bool = false) {
    let hook = projectDir.appendingPathComponent("on-change.sh")
    guard FileManager.default.isExecutableFile(atPath: hook.path) else { return }
    if let previous = hookProcess, previous.isRunning {
        // A refresh never interrupts a hook that is still retrying.
        if refresh { return }
        // Stop a still-running hook for an older state so its sends can't land
        // after the new state's and leave the bulb showing the old color.
        previous.terminate()
    }
    let process = Process()
    process.executableURL = hook
    process.arguments = [snapshot.state.rawValue, snapshot.details] + (refresh ? ["refresh"] : [])
    do { try process.run(); hookProcess = process } catch { print("hook failed: \(error)") }
}

// MARK: - log pruning

let logURL = projectDir.appendingPathComponent("camwatch.log")
let logMaxAge: TimeInterval = 24 * 60 * 60
let logMaxLines = 2000

/// Drop log entries older than 24 hours (an entry is a timestamped line plus the
/// untimestamped hook lines after it) and cap the log at its last 2000 lines.
/// Truncates in place rather than replacing the file, because launchd keeps it
/// open for appending.
func pruneLog() {
    guard let text = try? String(contentsOf: logURL, encoding: .utf8) else { return }
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).dropLast()  // trailing newline
    let parser = ISO8601DateFormatter()
    let cutoff = Date().addingTimeInterval(-logMaxAge)
    var keep = false
    var kept: [Substring] = []
    for line in lines {
        if let date = parser.date(from: String(line.prefix(while: { $0 != " " }))) { keep = date >= cutoff }
        if keep { kept.append(line) }
    }
    kept = Array(kept.suffix(logMaxLines))
    guard kept.count != lines.count, let handle = try? FileHandle(forWritingTo: logURL) else { return }
    defer { try? handle.close() }
    try? handle.truncate(atOffset: 0)
    try? handle.write(contentsOf: Data(kept.map { $0 + "\n" }.joined().utf8))
}

// MARK: - watch mode

let refreshSeconds = 5.0 * 60

var lastReported: State?
var lastSnapshot: Snapshot?
var pending: DispatchWorkItem?
var listenedCameras = Set<CMIOObjectID>()
var listenedProcesses = Set<AudioObjectID>()
var listenedMics = Set<AudioObjectID>()

func scheduleCheck() {
    pending?.cancel()
    let work = DispatchWorkItem {
        let snapshot = Snapshot.now()
        guard snapshot.state != lastReported else { return }
        lastReported = snapshot.state
        lastSnapshot = snapshot
        report(snapshot)
        runHook(snapshot)
    }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + debounceSeconds, execute: work)
}

func listenToCameras() {
    for device in videoDevices() where !listenedCameras.contains(device) {
        var addr = cameraAddress(kCMIODevicePropertyDeviceIsRunningSomewhere)
        let status = CMIOObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main) { _, _ in scheduleCheck() }
        if status == noErr { listenedCameras.insert(device) }
    }
}

func listenToAudioProcesses() {
    let current = audioProcesses()
    listenedProcesses.formIntersection(current)  // forget processes that exited
    for process in current where !listenedProcesses.contains(process) {
        var addr = audioAddress(kAudioProcessPropertyIsRunningInput)
        let status = AudioObjectAddPropertyListenerBlock(process, &addr, DispatchQueue.main) { _, _ in scheduleCheck() }
        if status == noErr { listenedProcesses.insert(process) }
    }
}

// Per-process IsRunningInput changes don't reliably notify (on macOS 15 a Voice
// Memos recording fired no process listener at all), so also wake on any mic
// device starting or stopping and re-read the per-process state then.
func listenToMics() {
    for device in micDevices() where !listenedMics.contains(device) {
        var addr = audioAddress(kAudioDevicePropertyDeviceIsRunningSomewhere)
        let status = AudioObjectAddPropertyListenerBlock(device, &addr, DispatchQueue.main) { _, _ in scheduleCheck() }
        if status == noErr { listenedMics.insert(device) }
    }
}

func watch() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)  // line-buffer so logs appear promptly under launchd

    pruneLog()
    let pruneTimer = DispatchSource.makeTimerSource(queue: .main)
    pruneTimer.schedule(deadline: .now() + 3600, repeating: 3600)
    pruneTimer.setEventHandler(handler: pruneLog)
    pruneTimer.resume()

    listenToCameras()
    var camerasAddr = cameraAddress(kCMIOHardwarePropertyDevices)
    CMIOObjectAddPropertyListenerBlock(cameraSystem, &camerasAddr, DispatchQueue.main) { _, _ in
        listenToCameras()
        scheduleCheck()
    }

    listenToAudioProcesses()
    var processesAddr = audioAddress(kAudioHardwarePropertyProcessObjectList)
    AudioObjectAddPropertyListenerBlock(audioSystem, &processesAddr, DispatchQueue.main) { _, _ in
        listenToAudioProcesses()
        scheduleCheck()
    }

    listenToMics()
    var micsAddr = audioAddress(kAudioHardwarePropertyDevices)
    AudioObjectAddPropertyListenerBlock(audioSystem, &micsAddr, DispatchQueue.main) { _, _ in
        listenToMics()
        scheduleCheck()
    }

    let snapshot = Snapshot.now()
    lastReported = snapshot.state
    lastSnapshot = snapshot
    report(snapshot)
    runHook(snapshot)  // sync lights/notifications with the current state on startup

    let refreshTimer = DispatchSource.makeTimerSource(queue: .main)
    refreshTimer.schedule(deadline: .now() + refreshSeconds, repeating: refreshSeconds)
    refreshTimer.setEventHandler {
        if let snapshot = lastSnapshot { runHook(snapshot, refresh: true) }
    }
    refreshTimer.resume()

    dispatchMain()
}

// MARK: - main

switch CommandLine.arguments.dropFirst().first ?? "status" {
case "status":
    let snapshot = Snapshot.now()
    report(snapshot)
    let code: Int32 = switch snapshot.state { case .video: 0; case .mic: 2; case .off: 1 }
    exit(code)
case "watch":
    watch()
default:
    FileHandle.standardError.write("usage: camwatch [status|watch]\n".data(using: .utf8)!)
    exit(64)
}
