import AVFoundation
import ScreenCaptureKit

public enum RecorderError: Error {
    case writerFailed
    case noMicrophone
    case notRecording
}

/// SCStream → AVAssetWriter MP4 recording engine. Video + optional system-audio
/// track (SCK) + optional microphone track (MicCapturer). All sample appends run
/// on `sampleQueue`; start/stop are called from the main actor.
public final class ScreenRecorder: NSObject, SCStreamOutput, SCStreamDelegate {
    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var systemAudioInput: AVAssetWriterInput?
    private var micInput: AVAssetWriterInput?
    private var micCapturer: MicCapturer?
    private let sampleQueue = DispatchQueue(label: "betterscreenshot.recorder.samples")
    private var sessionStarted = false
    private var outputURL: URL?

    /// Stream died underneath us (display unplugged, etc.). Fired on sampleQueue.
    public var onStreamError: ((Error) -> Void)?

    public override init() { super.init() }

    private static let audioSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 48_000,
        AVNumberOfChannelsKey: 2,
        AVEncoderBitRateKey: 128_000,
    ]

    /// Begin recording `filter` at `pixelSize` to `outputURL`.
    /// `sourceRect` (display-relative, top-left-origin, points) crops the display.
    public func start(filter: SCContentFilter, pixelSize: CGSize, sourceRect: CGRect?,
                      config: RecordingConfig, outputURL: URL) async throws {
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let pure = config.videoSettings(width: Int(pixelSize.width), height: Int(pixelSize.height))
        // Map the pure-model dictionary onto the real AVFoundation constants.
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pure[AVKey.width] as? Int ?? Int(pixelSize.width),
            AVVideoHeightKey: pure[AVKey.height] as? Int ?? Int(pixelSize.height),
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey:
                    (pure[AVKey.compression] as? [String: Any])?[AVKey.bitRate] as? Int ?? 8_000_000,
            ],
        ]
        let vInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        vInput.expectsMediaDataInRealTime = true
        guard writer.canAdd(vInput) else { throw RecorderError.writerFailed }
        writer.add(vInput)

        var sysInput: AVAssetWriterInput?
        if config.systemAudio {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); sysInput = a }
        }
        var micInput: AVAssetWriterInput?
        if config.microphone {
            let a = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.audioSettings)
            a.expectsMediaDataInRealTime = true
            if writer.canAdd(a) { writer.add(a); micInput = a }
        }

        let sc = SCStreamConfiguration()
        sc.width = Int(pixelSize.width)
        sc.height = Int(pixelSize.height)
        if let sourceRect { sc.sourceRect = sourceRect }
        sc.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(config.fps))
        sc.showsCursor = true
        sc.capturesAudio = config.systemAudio
        sc.pixelFormat = kCVPixelFormatType_32BGRA
        sc.queueDepth = 6

        let stream = SCStream(filter: filter, configuration: sc, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        if config.systemAudio {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
        }

        guard writer.startWriting() else { throw writer.error ?? RecorderError.writerFailed }

        self.writer = writer
        self.videoInput = vInput
        self.systemAudioInput = sysInput
        self.micInput = micInput
        self.outputURL = outputURL
        self.sessionStarted = false
        self.stream = stream

        if config.microphone, micInput != nil {
            let capturer = MicCapturer()
            self.micCapturer = capturer
            try? capturer.start(queue: sampleQueue) { [weak self] buffer in
                self?.appendMic(buffer)
            }
        }

        try await stream.startCapture()
    }

    /// Stop and finalize; returns the finished file URL.
    public func stop() async throws -> URL {
        guard let writer, let outputURL else { throw RecorderError.notRecording }
        if let stream { try? await stream.stopCapture() }
        micCapturer?.stop()
        // Let in-flight appends drain before finishing.
        sampleQueue.sync {}
        videoInput?.markAsFinished()
        systemAudioInput?.markAsFinished()
        micInput?.markAsFinished()
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            writer.finishWriting { cont.resume() }
        }
        defer { reset() }
        if writer.status == .failed { throw writer.error ?? RecorderError.writerFailed }
        return outputURL
    }

    private func reset() {
        stream = nil; writer = nil; videoInput = nil
        systemAudioInput = nil; micInput = nil; micCapturer = nil
        outputURL = nil; sessionStarted = false
    }

    // MARK: - SCStreamOutput (called on sampleQueue)

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                       of type: SCStreamOutputType) {
        guard sampleBuffer.isValid else { return }
        switch type {
        case .screen:
            // Only complete frames carry image data.
            guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
                      sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
                  let statusRaw = attachments.first?[.status] as? Int,
                  SCFrameStatus(rawValue: statusRaw) == .complete else { return }
            if !sessionStarted {
                writer?.startSession(atSourceTime: sampleBuffer.presentationTimeStamp)
                sessionStarted = true
            }
            if let videoInput, videoInput.isReadyForMoreMediaData {
                videoInput.append(sampleBuffer)
            }
        case .audio:
            guard sessionStarted, let systemAudioInput,
                  systemAudioInput.isReadyForMoreMediaData else { return }
            systemAudioInput.append(sampleBuffer)
        default:
            break
        }
    }

    private func appendMic(_ buffer: CMSampleBuffer) {
        guard sessionStarted, let micInput, micInput.isReadyForMoreMediaData else { return }
        micInput.append(buffer)
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        onStreamError?(error)
    }
}
