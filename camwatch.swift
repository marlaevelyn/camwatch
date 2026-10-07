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

    static func now() -> Snapshot { Snapshot(cameras: activeCameras(), micApps: activeMicApps()) }

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

func runHook(_ snapshot: Snapshot) {
    let dir = Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
        ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let hook = dir.appendingPathComponent("on-change.sh")
    guard FileManager.default.isExecutableFile(atPath: hook.path) else { return }
    let process = Process()
    process.executableURL = hook
    process.arguments = [snapshot.state.rawValue, snapshot.details]
    do { try process.run() } catch { print("hook failed: \(error)") }
}

// MARK: - watch mode

var lastReported: State?
var pending: DispatchWorkItem?
var listenedCameras = Set<CMIOObjectID>()
var listenedProcesses = Set<AudioObjectID>()

func scheduleCheck() {
    pending?.cancel()
    let work = DispatchWorkItem {
        let snapshot = Snapshot.now()
        guard snapshot.state != lastReported else { return }
        lastReported = snapshot.state
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

func watch() -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)  // line-buffer so logs appear promptly under launchd

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

    let snapshot = Snapshot.now()
    lastReported = snapshot.state
    report(snapshot)
    runHook(snapshot)  // sync lights/notifications with the current state on startup

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
