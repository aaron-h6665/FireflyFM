import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Observation
import SwiftUI
import UIKit

enum AttendanceQRPayload {
    static func token(from value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              components.scheme?.lowercased() == "fireflyfm",
              components.host?.lowercased() == "attendance",
              components.path.lowercased() == "/v1",
              let token = components.queryItems?.first(where: { $0.name == "token" })?.value,
              token.count == 64,
              token.allSatisfy({ $0.isHexDigit })
        else { return nil }
        return token.lowercased()
    }
}

struct GuardianAttendanceQRClient {
    var preview: (String) async throws -> [GuardianAttendancePreviewRow]
    var record: (String, [UUID], AttendanceAction) async throws -> [GuardianAttendanceResult]

    static let live = GuardianAttendanceQRClient(
        preview: { try await SchoolOperationsService.shared.previewGuardianQRAttendance(token: $0) },
        record: { try await SchoolOperationsService.shared.recordGuardianQRAttendance(token: $0, childIds: $1, action: $2) }
    )
}

@MainActor
@Observable
final class GuardianAttendanceQRModel {
    private let client: GuardianAttendanceQRClient
    private(set) var token: String?
    private(set) var rows: [GuardianAttendancePreviewRow] = []
    private(set) var results: [GuardianAttendanceResult] = []
    private(set) var isLoading = false
    private(set) var isSubmitting = false
    private(set) var errorMessage: String?

    init(client: GuardianAttendanceQRClient) {
        self.client = client
    }

    convenience init() {
        self.init(client: .live)
    }

    var schoolName: String? { rows.first?.schoolName }

    func preview(payload: String) async {
        guard let parsedToken = AttendanceQRPayload.token(from: payload) else {
            errorMessage = "This is not a valid FireflyFM attendance QR code."
            return
        }
        isLoading = true
        errorMessage = nil
        results = []
        defer { isLoading = false }
        do {
            let loadedRows = try await client.preview(parsedToken)
            guard loadedRows.isEmpty == false else {
                errorMessage = "No eligible children are connected to this school code."
                return
            }
            token = parsedToken
            rows = loadedRows
        } catch {
            errorMessage = AppErrorMessage.school("Could not verify this attendance code", error)
        }
    }

    func record(childIds: [UUID], action: AttendanceAction) async -> [GuardianAttendanceResult]? {
        guard let token, childIds.isEmpty == false else { return nil }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            let savedResults = try await client.record(token, childIds, action)
            results = savedResults
            if let failure = savedResults.first(where: { $0.success == false }) {
                errorMessage = failure.errorMessage ?? "One or more attendance updates could not be saved."
            }
            return savedResults
        } catch {
            errorMessage = AppErrorMessage.school("Could not update attendance", error)
            return nil
        }
    }

    func reset() {
        token = nil
        rows = []
        results = []
        errorMessage = nil
    }

    func showError(_ message: String) {
        errorMessage = message
    }
}

struct AttendanceLocationCodeClient {
    var fetch: (UUID) async throws -> AttendanceLocationCode?
    var rotate: (UUID) async throws -> AttendanceLocationCode
    var revoke: (UUID) async throws -> Void

    static let live = AttendanceLocationCodeClient(
        fetch: { try await SchoolOperationsService.shared.fetchAttendanceLocationCode(schoolId: $0) },
        rotate: { try await SchoolOperationsService.shared.rotateAttendanceLocationCode(schoolId: $0) },
        revoke: { try await SchoolOperationsService.shared.revokeAttendanceLocationCode(codeId: $0) }
    )
}

@MainActor
@Observable
final class AttendanceLocationCodeModel {
    private let client: AttendanceLocationCodeClient
    private(set) var code: AttendanceLocationCode?
    private(set) var isLoading = false
    private(set) var isSaving = false
    private(set) var errorMessage: String?

    init(client: AttendanceLocationCodeClient) {
        self.client = client
    }

    convenience init() {
        self.init(client: .live)
    }

    func load(schoolId: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            code = try await client.fetch(schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not load the attendance QR code", error)
        }
    }

    func rotate(schoolId: UUID) async {
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            code = try await client.rotate(schoolId)
        } catch {
            errorMessage = AppErrorMessage.school("Could not create the attendance QR code", error)
        }
    }

    func revoke() async {
        guard let code else { return }
        isSaving = true
        errorMessage = nil
        defer { isSaving = false }
        do {
            try await client.revoke(code.id)
            self.code = nil
        } catch {
            errorMessage = AppErrorMessage.school("Could not revoke the attendance QR code", error)
        }
    }
}

struct GuardianAttendanceQRView: View {
    @State private var model = GuardianAttendanceQRModel()
    @State private var selectedChildIds: Set<UUID> = []
    @State private var showingConfirmation = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            if model.results.isEmpty == false {
                receipt
            } else if model.isLoading {
                ProgressView("Verifying school code…")
                    .tint(AppConstants.Colors.accessibleYellow)
            } else if model.rows.isEmpty {
                scanner
            } else {
                childSelection
            }
        }
        .navigationTitle("Scan Check-In Code")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if model.rows.isEmpty == false, model.results.isEmpty, selectedChildIds.isEmpty == false {
                confirmBar
            }
        }
        .alert(confirmationTitle, isPresented: $showingConfirmation) {
            Button(actionTitle) { submit() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(confirmationMessage)
        }
    }

    private var scanner: some View {
        VStack(spacing: 16) {
            QRCodeScannerView { payload in
                Task { await model.preview(payload: payload) }
            } onError: { message in
                model.showError(message)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(AppConstants.Colors.accessibleYellow, lineWidth: 3)
                    .padding(42)
            }
            .frame(maxHeight: 460)

            Text("Point the camera at your school’s FireflyFM attendance code.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(AppConstants.Colors.secondaryText)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)

                if errorMessage.contains("Enable it in Settings") {
                    Button("Open Settings") {
                        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                        UIApplication.shared.open(url)
                    }
                    .buttonStyle(.bordered)
                }
            }

#if DEBUG
            if let payload = injectedPayload {
                Button("Use Test QR Code") {
                    Task { await model.preview(payload: payload) }
                }
                .buttonStyle(.bordered)
            }
#endif
        }
        .padding()
    }

    private var childSelection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(model.schoolName ?? "School")
                        .font(.title2.bold())
                    Text("Select the child or children you are checking in or out.")
                        .font(.subheadline)
                        .foregroundColor(AppConstants.Colors.secondaryText)
                }

                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(model.rows) { row in
                        childCell(row)
                    }
                }

                Button("Scan a Different Code") {
                    selectedChildIds.removeAll()
                    model.reset()
                }
                .font(.subheadline.bold())
            }
            .padding()
            .padding(.bottom, selectedChildIds.isEmpty ? 0 : 90)
        }
    }

    private func childCell(_ row: GuardianAttendancePreviewRow) -> some View {
        let isSelected = selectedChildIds.contains(row.id)
        let rowAction = action(for: row)
        let isCompatible = selectedChildIds.isEmpty || rowAction == selectedAction
        return Button {
            guard rowAction != nil else { return }
            if isSelected { selectedChildIds.remove(row.id) }
            else if isCompatible { selectedChildIds.insert(row.id) }
        } label: {
            VStack(spacing: 7) {
                Circle()
                    .fill(isSelected ? AppConstants.Colors.wingMist : stateColor(row.state).opacity(0.16))
                    .overlay {
                        if isSelected {
                            Image(systemName: "checkmark").font(.title2.bold())
                        } else {
                            Text(InitialsFormatter.initials(for: row.childName)).font(.headline.bold())
                        }
                    }
                    .frame(width: 68, height: 68)
                Text(row.childFirstName).font(.caption.bold()).lineLimit(1)
                Text(statusLabel(row.state)).font(.caption2).foregroundColor(stateColor(row.state)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .opacity(isCompatible && rowAction != nil ? 1 : 0.42)
        }
        .buttonStyle(.plain)
        .disabled(isCompatible == false || rowAction == nil)
        .accessibilityLabel("\(row.childName), \(statusLabel(row.state))")
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private var confirmBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("\(selectedChildIds.count) selected").font(.subheadline.bold())
                Spacer()
                Button("Clear") { selectedChildIds.removeAll() }.font(.caption.bold())
            }
            Button(actionTitle) { showingConfirmation = true }
                .buttonStyle(.borderedProminent)
                .tint(AppConstants.Colors.primaryAction)
                .foregroundColor(AppConstants.Colors.primaryActionText)
                .frame(maxWidth: .infinity)
                .disabled(model.isSubmitting)
        }
        .padding()
        .background(.ultraThinMaterial)
    }

    private var receipt: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: model.results.allSatisfy(\.success) ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 58))
                    .foregroundColor(model.results.allSatisfy(\.success) ? .green : .orange)
                Text(model.results.allSatisfy(\.success) ? "Attendance Recorded" : "Attendance Partially Recorded")
                    .font(.title2.bold())
                ForEach(model.results) { result in
                    HStack {
                        Text(name(for: result.childId)).font(.subheadline.bold())
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(result.success ? actionLabel(result.action) : "Not Saved")
                            if let occurredAt = result.occurredAt {
                                Text(occurredAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundColor(AppConstants.Colors.secondaryText)
                            }
                            if let errorMessage = result.errorMessage, result.success == false {
                                Text(errorMessage)
                                    .font(.caption2)
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                    }
                    .padding()
                    .background(AppConstants.Colors.card)
                    .cornerRadius(10)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
                Button("Scan Another Code") {
                    selectedChildIds.removeAll()
                    model.reset()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    private var selectedAction: AttendanceAction? {
        guard let id = selectedChildIds.first,
              let row = model.rows.first(where: { $0.id == id }) else { return nil }
        return action(for: row)
    }

    private var actionTitle: String {
        guard selectedAction == .checkOut else {
            let allCheckedOut = selectedRows.allSatisfy { $0.state == .checkedOut }
            return allCheckedOut ? "Check In Again" : "Check In"
        }
        return "Check Out"
    }

    private var confirmationTitle: String { "Confirm \(actionTitle)?" }
    private var confirmationMessage: String {
        let names = selectedRows.map(\.childFirstName).joined(separator: ", ")
        let absentWarning = selectedRows.contains(where: { $0.state == .absent })
            ? " This will keep the absence in history and start a new attendance session."
            : ""
        return "\(actionTitle) \(names) at \(model.schoolName ?? "this school")? The server records the time.\(absentWarning)"
    }
    private var selectedRows: [GuardianAttendancePreviewRow] {
        model.rows.filter { selectedChildIds.contains($0.id) }
    }

    private func submit() {
        guard let action = selectedAction else { return }
        let childIds = Array(selectedChildIds)
        Task { _ = await model.record(childIds: childIds, action: action) }
    }

    private func action(for row: GuardianAttendancePreviewRow) -> AttendanceAction? {
        switch row.state {
        case .expected, .checkedOut, .absent: .checkIn
        case .present: .checkOut
        case .needsAttention: nil
        }
    }
    private func statusLabel(_ state: AttendanceState) -> String { state == .expected ? "Not checked in" : state.title }
    private func stateColor(_ state: AttendanceState) -> Color {
        switch state { case .expected: .blue; case .present: .green; case .checkedOut: .gray; case .absent: .orange; case .needsAttention: .red }
    }
    private func actionLabel(_ action: AttendanceAction) -> String { action == .checkOut ? "Checked Out" : "Checked In" }
    private func name(for childId: UUID) -> String { model.rows.first(where: { $0.childId == childId })?.childName ?? "Child" }

#if DEBUG
    private var injectedPayload: String? {
        let prefix = "--qr-test-payload="
        return ProcessInfo.processInfo.arguments.first(where: { $0.hasPrefix(prefix) }).map { String($0.dropFirst(prefix.count)) }
    }
#endif
}

struct AttendanceQRCodeManagementView: View {
    let school: School
    @State private var model = AttendanceLocationCodeModel()
    @State private var showingFullScreen = false
    @State private var showingShare = false
    @State private var confirmingRotation = false
    @State private var confirmingRevocation = false

    var body: some View {
        ZStack {
            AppConstants.Colors.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 18) {
                    if model.isLoading {
                        ProgressView("Loading attendance code…")
                    } else if let code = model.code, let image = QRCodeImageRenderer.image(for: code.qrPayload) {
                        Image(uiImage: image)
                            .interpolation(.none)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: 280)
                            .padding(18)
                            .background(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                            .accessibilityLabel("Attendance QR code for \(school.name)")

                        Text("Parents can scan this code from your phone or from a printed copy.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(AppConstants.Colors.secondaryText)

                        VStack(spacing: 10) {
                            Button { showingFullScreen = true } label: {
                                Label("Show Full Screen", systemImage: "rectangle.inset.filled")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)

                            Button { showingShare = true } label: {
                                Label("Print or Share", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)

                            Button("Rotate Code") { confirmingRotation = true }
                                .buttonStyle(.bordered)
                            Button("Revoke Code", role: .destructive) { confirmingRevocation = true }
                                .buttonStyle(.bordered)
                        }
                    } else {
                        ContentUnavailableView(
                            "No Attendance Code",
                            systemImage: "qrcode",
                            description: Text("Create a reusable school code for guardian check-in and checkout.")
                        )
                        Button("Create School QR Code") {
                            Task { await model.rotate(schoolId: school.id) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isSaving)
                    }

                    Label(
                        "This code confirms possession of the school’s posted code, not guaranteed physical presence. Every action still requires a signed-in verified guardian and is audited.",
                        systemImage: "info.circle.fill"
                    )
                    .font(.caption)
                    .foregroundColor(.orange)
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(10)

                    if let errorMessage = model.errorMessage {
                        Text(errorMessage).font(.caption).foregroundColor(.red)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Check-In QR Code")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: school.id) { await model.load(schoolId: school.id) }
        .fullScreenCover(isPresented: $showingFullScreen) {
            if let code = model.code { AttendanceQRFullScreenView(school: school, payload: code.qrPayload) }
        }
        .sheet(isPresented: $showingShare) {
            if let code = model.code, let image = QRCodeImageRenderer.image(for: code.qrPayload) {
                ActivityView(items: [image, "\(school.name) FireflyFM attendance QR code"])
            }
        }
        .confirmationDialog("Rotate attendance code?", isPresented: $confirmingRotation, titleVisibility: .visible) {
            Button("Rotate Code", role: .destructive) { Task { await model.rotate(schoolId: school.id) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Every previously displayed or printed copy will stop working immediately.")
        }
        .confirmationDialog("Revoke attendance code?", isPresented: $confirmingRevocation, titleVisibility: .visible) {
            Button("Revoke Code", role: .destructive) { Task { await model.revoke() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Parents cannot use the code again unless a director creates a new one.")
        }
    }
}

private struct AttendanceQRFullScreenView: View {
    @Environment(\.dismiss) private var dismiss
    let school: School
    let payload: String
    @State private var previousBrightness: CGFloat = UIScreen.main.brightness
    @State private var previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .font(.headline)
                        .foregroundColor(.black)
                }
                Text(school.name).font(.title.bold()).foregroundColor(.black)
                if let image = QRCodeImageRenderer.image(for: payload) {
                    Image(uiImage: image).interpolation(.none).resizable().scaledToFit()
                }
                Text("Scan with FireflyFM to check in or check out")
                    .font(.headline).foregroundColor(.black).multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .onAppear {
            previousBrightness = UIScreen.main.brightness
            previousIdleTimerDisabled = UIApplication.shared.isIdleTimerDisabled
            UIScreen.main.brightness = 1
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            UIScreen.main.brightness = previousBrightness
            UIApplication.shared.isIdleTimerDisabled = previousIdleTimerDisabled
        }
    }
}

private enum QRCodeImageRenderer {
    static func image(for payload: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

private struct QRCodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> QRCodeScannerViewController {
        QRCodeScannerViewController(onCode: onCode, onError: onError)
    }
    func updateUIViewController(_ uiViewController: QRCodeScannerViewController, context: Context) {}
}

private final class QRCodeScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let onCode: (String) -> Void
    private let onError: (String) -> Void
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var deliveredCode = false

    init(onCode: @escaping (String) -> Void, onError: @escaping (String) -> Void) {
        self.onCode = onCode
        self.onError = onError
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { nil }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        prepareCamera()
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning { session.stopRunning() }
    }

    private func prepareCamera() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.configureSession() : self?.fail("Camera access is required to scan attendance QR codes. Enable it in Settings.")
                }
            }
        case .denied, .restricted:
            fail("Camera access is required to scan attendance QR codes. Enable it in Settings.")
        @unknown default:
            fail("The camera is unavailable on this device.")
        }
    }

    private func configureSession() {
        guard let camera = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else {
            fail("The camera is unavailable on this device.")
            return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            fail("QR scanning is unavailable on this device.")
            return
        }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in self?.session.startRunning() }
    }

    private func fail(_ message: String) {
        onError(message)
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard deliveredCode == false,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = object.stringValue else { return }
        deliveredCode = true
        session.stopRunning()
        onCode(value)
    }
}
