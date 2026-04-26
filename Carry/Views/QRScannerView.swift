import SwiftUI
import AVFoundation

/// Fullscreen camera sheet that detects QR codes and hands the raw string
/// to `onDetect`. The caller is responsible for parsing (via
/// `GroupInviteParser`) and routing. View automatically stops the capture
/// session when dismissed.
///
/// Usage:
///     .sheet(isPresented: $showScanner) {
///         QRScannerView { payload in
///             // handle payload…
///             showScanner = false
///         }
///     }
struct QRScannerView: View {
    /// Called on the main actor with the detected QR string. Caller is
    /// responsible for dismissing the sheet once routing completes.
    let onDetect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var cameraAuthorized: Bool? = nil
    @State private var hasDelivered = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraAuthorized == true {
                CameraPreview { payload in
                    guard !hasDelivered else { return }
                    hasDelivered = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onDetect(payload)
                }
                .ignoresSafeArea()

                scannerOverlay
            } else if cameraAuthorized == false {
                deniedState
            }
            // cameraAuthorized == nil: permission is still resolving; keep
            // the screen black until AVCaptureDevice answers.
        }
        .task {
            cameraAuthorized = await Self.requestCameraAccess()
        }
    }

    // MARK: - Overlay

    private var scannerOverlay: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height) * 0.7

            // Single reference frame for dim + cutout + brackets so all
            // three share the same center. Previously the dim rectangle used
            // `.ignoresSafeArea()` while the brackets laid out inside the
            // GeometryReader's safe-area-clipped space, which visibly offset
            // the brackets from the cutout.
            ZStack {
                Rectangle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24)
                            .frame(width: side, height: side)
                            .blendMode(.destinationOut)
                    )
                    .compositingGroup()

                ReticleBrackets()
                    .stroke(Color.white, lineWidth: 4)
                    .frame(width: side, height: side)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.black.opacity(0.45)))
            }
            .accessibilityLabel("Close scanner")
            .padding(.trailing, 20)
            .padding(.top, 8)
        }
        .overlay(alignment: .bottom) {
            Text("Point at your friend's QR code")
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .padding(.bottom, 48)
        }
    }

    private var deniedState: some View {
        VStack(spacing: 20) {
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundColor(.white.opacity(0.7))

            Text("Camera access needed")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.white)

            Text("Enable camera access in Settings to scan invite QR codes.")
                .font(.system(size: 15))
                .foregroundColor(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.system(size: 16, weight: .semibold))
            .foregroundColor(.black)
            .padding(.horizontal, 24)
            .frame(height: 48)
            .background(Capsule().fill(Color.white))
            .padding(.top, 8)

            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white.opacity(0.75))
                .padding(.top, 4)
        }
    }

    // MARK: - Camera access

    private static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted: return false
        @unknown default: return false
        }
    }
}

// MARK: - Reticle brackets

private struct ReticleBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let len = min(rect.width, rect.height) * 0.18
        var p = Path()

        // Top-left
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + len))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + len, y: rect.minY))

        // Top-right
        p.move(to: CGPoint(x: rect.maxX - len, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + len))

        // Bottom-right
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - len))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - len, y: rect.maxY))

        // Bottom-left
        p.move(to: CGPoint(x: rect.minX + len, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - len))

        return p
    }
}

// MARK: - Camera preview (UIViewRepresentable)

private struct CameraPreview: UIViewRepresentable {
    let onDetect: (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onDetect: onDetect) }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    static func dismantleUIView(_ uiView: PreviewView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        private let onDetect: (String) -> Void
        private let session = AVCaptureSession()
        private let sessionQueue = DispatchQueue(label: "carry.qrscanner.session")

        init(onDetect: @escaping (String) -> Void) {
            self.onDetect = onDetect
        }

        func attach(to view: PreviewView) {
            view.previewLayer.session = session
            view.previewLayer.videoGravity = .resizeAspectFill

            sessionQueue.async { [weak self] in
                self?.configureAndStart()
            }
        }

        private func configureAndStart() {
            guard
                let device = AVCaptureDevice.default(for: .video),
                let input = try? AVCaptureDeviceInput(device: device)
            else { return }

            session.beginConfiguration()
            if session.canAddInput(input) { session.addInput(input) }

            let output = AVCaptureMetadataOutput()
            if session.canAddOutput(output) {
                session.addOutput(output)
                // Delegate calls dispatched on main so onDetect is main-actor safe.
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
            }
            session.commitConfiguration()
            session.startRunning()
        }

        func stop() {
            sessionQueue.async { [weak self] in
                guard let self, self.session.isRunning else { return }
                self.session.stopRunning()
            }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard
                let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                let str = obj.stringValue
            else { return }
            onDetect(str)
        }
    }
}
