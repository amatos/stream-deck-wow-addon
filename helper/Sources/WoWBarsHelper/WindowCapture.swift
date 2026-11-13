import CoreMedia
import CoreVideo
import Foundation
import QuartzCore
import ScreenCaptureKit
import StripKit

/// What the capture pipeline currently sees. Delivered on the main queue.
struct CaptureSnapshot {
    enum Source: Equatable {
        case noPermission
        case noWindow
        case capturing(title: String, width: Int, height: Int)
        case failed(String)
    }

    var source: Source = .noWindow
    var status: StripTracker.Status = .searching
    var frame: StripFrame?
    var geometry: StripGeometry?
    var framesPerSecond: Double = 0
    var lastFailure: StripDecoder.Failure?
}

/// Captures the World of Warcraft window with ScreenCaptureKit and decodes the strip.
final class WindowCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    static let wowBundleID = "com.blizzard.worldofwarcraft"
    static let framesPerSecond: Int32 = 20

    /// Called on the main queue, at most 10 times a second and on every new frame.
    var onUpdate: ((CaptureSnapshot) -> Void)?

    private let queue = DispatchQueue(label: "WoWBarsHelper.capture")
    private let tracker = StripTracker()
    private var stream: SCStream?
    private var windowID: CGWindowID?
    private var pixelSize: (Int, Int) = (0, 0)
    private var title = ""
    private var pollTimer: Timer?
    private var source: CaptureSnapshot.Source = .noWindow

    // Capture-queue state.
    private var frameTimes: [Double] = []
    private var lastDelivery = 0.0

    func start() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }

    /// Finds the WoW window and (re)starts the stream when it appears, changes or closes.
    func refresh() {
        guard CGPreflightScreenCaptureAccess() else {
            stopStream()
            publish(source: .noPermission)
            return
        }
        SCShareableContent.getExcludingDesktopWindows(true, onScreenWindowsOnly: false) { [weak self] content, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let content {
                    self.choose(from: content.windows)
                } else {
                    self.publish(source: .failed(error?.localizedDescription ?? "no shareable content"))
                }
            }
        }
    }

    private func choose(from windows: [SCWindow]) {
        let wow = windows
            .filter { $0.owningApplication?.bundleIdentifier == Self.wowBundleID && $0.windowLayer == 0 }
            .filter { $0.frame.width >= 200 && $0.frame.height >= 150 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let window = wow else {
            stopStream()
            publish(source: .noWindow)
            return
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let scale = CGFloat(filter.pointPixelScale)
        let size = (Int(filter.contentRect.width * scale), Int(filter.contentRect.height * scale))
        if window.windowID == windowID, size == pixelSize, stream != nil { return }

        let config = SCStreamConfiguration()
        config.width = size.0
        config.height = size.1
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: Self.framesPerSecond)
        config.queueDepth = 3
        config.showsCursor = false

        title = window.title ?? "World of Warcraft"
        pixelSize = size
        if let stream, window.windowID == windowID {
            stream.updateConfiguration(config) { [weak self] error in
                DispatchQueue.main.async {
                    if error == nil { self?.publishCapturing() } else { self?.restart() }
                }
            }
            return
        }
        stopStream()
        windowID = window.windowID
        let newStream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        } catch {
            publish(source: .failed(error.localizedDescription))
            return
        }
        stream = newStream
        newStream.startCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let error {
                    self.stream = nil
                    self.windowID = nil
                    self.publish(source: .failed(error.localizedDescription))
                } else {
                    self.publishCapturing()
                }
            }
        }
    }

    private func restart() {
        stopStream()
        refresh()
    }

    private func stopStream() {
        stream?.stopCapture { _ in }
        stream = nil
        windowID = nil
        pixelSize = (0, 0)
    }

    private func publishCapturing() {
        publish(source: .capturing(title: title, width: pixelSize.0, height: pixelSize.1))
    }

    private func publish(source: CaptureSnapshot.Source) {
        self.source = source
        queue.async { [weak self] in self?.deliver(force: true) }
    }

    // MARK: SCStreamOutput / SCStreamDelegate (capture queue)

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, sampleBuffer.isValid, Self.isComplete(sampleBuffer),
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let pixels = BGRAPixels(
            base: UnsafePointer(base.assumingMemoryBound(to: UInt8.self)),
            width: CVPixelBufferGetWidth(pixelBuffer),
            height: CVPixelBufferGetHeight(pixelBuffer),
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer)
        )
        let now = CACurrentMediaTime()
        frameTimes.append(now)
        frameTimes.removeAll { now - $0 > 1 }
        let isNew = tracker.process(pixels, now: now)
        deliver(force: isNew)
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.stream = nil
            self.windowID = nil
            self.refresh()
        }
    }

    static func isComplete(_ sampleBuffer: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw) else { return false }
        return status == .complete
    }

    /// Runs on the capture queue.
    private func deliver(force: Bool) {
        let now = CACurrentMediaTime()
        guard force || now - lastDelivery >= 0.1 else { return }
        lastDelivery = now
        let snapshot = CaptureSnapshot(
            source: source,
            status: tracker.status(at: now),
            frame: tracker.frame,
            geometry: tracker.geometry,
            framesPerSecond: Double(frameTimes.count),
            lastFailure: tracker.lastFailure
        )
        DispatchQueue.main.async { [weak self] in self?.onUpdate?(snapshot) }
    }
}
