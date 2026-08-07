@preconcurrency import AVFoundation
import SwiftUI

struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCode: (String) -> Void
    @State private var manualCode = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if AVCaptureDevice.default(for: .video) != nil {
                    BarcodeScannerView(onCode: onCode)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 18)
                                .stroke(.white.opacity(0.9), lineWidth: 3)
                                .frame(width: 260, height: 150)
                        }
                        .padding()
                } else {
                    ContentUnavailableView(
                        "Camera unavailable",
                        systemImage: "camera.fill",
                        description: Text("Use a physical device to scan, or enter a supported set number below.")
                    )
                }

                HStack {
                    TextField("Set number", text: $manualCode)
                        .textFieldStyle(.roundedBorder)
                        .keyboardType(.numberPad)
                    Button("Use") { onCode(manualCode) }
                        .buttonStyle(.borderedProminent)
                        .disabled(manualCode.isEmpty)
                }
                .padding(.horizontal)
            }
            .navigationTitle("Scan Set")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

private struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

private final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCode: ((String) -> Void)?
    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasDeliveredCode = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        hasDeliveredCode = false
        if !session.isRunning { session.startRunning() }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        Task { @MainActor in
            guard !hasDeliveredCode else { return }
            hasDeliveredCode = true
            session.stopRunning()
            onCode?(code)
        }
    }
}
