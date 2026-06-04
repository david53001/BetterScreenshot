import AVFoundation

/// Microphone capture on macOS 14 (SCK mic capture is macOS 15+): a tiny
/// AVCaptureSession forwarding audio sample buffers to the recording writer.
public final class MicCapturer: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate {
    private let session = AVCaptureSession()
    private var onBuffer: ((CMSampleBuffer) -> Void)?

    /// Requests mic permission if needed; false when denied.
    public static func ensurePermission() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default: return false
        }
    }

    /// Starts delivering mic buffers on `queue`. Throws when no mic is available.
    public func start(queue: DispatchQueue,
                      onBuffer: @escaping (CMSampleBuffer) -> Void) throws {
        guard let device = AVCaptureDevice.default(for: .audio) else {
            throw RecorderError.noMicrophone
        }
        self.onBuffer = onBuffer
        let input = try AVCaptureDeviceInput(device: device)
        let output = AVCaptureAudioDataOutput()
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            throw RecorderError.noMicrophone
        }
        session.addInput(input)
        session.addOutput(output)
        session.startRunning()
    }

    public func stop() {
        session.stopRunning()
        onBuffer = nil
    }

    public func captureOutput(_ output: AVCaptureOutput,
                              didOutput sampleBuffer: CMSampleBuffer,
                              from connection: AVCaptureConnection) {
        onBuffer?(sampleBuffer)
    }
}
