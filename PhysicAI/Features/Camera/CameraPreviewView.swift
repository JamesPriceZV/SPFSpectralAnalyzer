#if os(iOS)
import SwiftUI
import AVFoundation

/// Full-screen camera capture view using AVCaptureSession.
struct CameraPreviewView: UIViewControllerRepresentable {
    let onCapture: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.onCapture = onCapture
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

/// UIKit view controller managing the AVCaptureSession and photo capture.
final class CameraViewController: UIViewController {
    var onCapture: ((UIImage?) -> Void)?

    nonisolated(unsafe) private let captureSession = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private let delegateHandler = PhotoCaptureDelegate()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupSession()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task.detached(priority: .userInitiated) { [weak self] in
            self?.captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func setupSession() {
        captureSession.sessionPreset = .photo

        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              captureSession.canAddInput(input) else { return }

        captureSession.addInput(input)

        guard captureSession.canAddOutput(photoOutput) else { return }
        captureSession.addOutput(photoOutput)

        let layer = AVCaptureVideoPreviewLayer(session: captureSession)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.addSublayer(layer)
        previewLayer = layer
    }

    private func setupUI() {
        // Capture button
        let captureButton = UIButton(type: .system)
        captureButton.setImage(UIImage(systemName: "circle.inset.filled", withConfiguration: UIImage.SymbolConfiguration(pointSize: 64)), for: .normal)
        captureButton.tintColor = .white
        captureButton.translatesAutoresizingMaskIntoConstraints = false
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        view.addSubview(captureButton)

        // Cancel button
        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .white
        cancelButton.translatesAutoresizingMaskIntoConstraints = false
        cancelButton.addTarget(self, action: #selector(cancelCapture), for: .touchUpInside)
        view.addSubview(cancelButton)

        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -30),
            cancelButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            cancelButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20)
        ])
    }

    @objc private func capturePhoto() {
        let settings = AVCapturePhotoSettings()
        delegateHandler.completion = { [weak self] image in
            self?.onCapture?(image)
        }
        photoOutput.capturePhoto(with: settings, delegate: delegateHandler)
    }

    @objc private func cancelCapture() {
        onCapture?(nil)
    }
}

/// Delegate handling AVCapturePhoto results.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    var completion: ((UIImage?) -> Void)?

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else {
            completion?(nil)
            return
        }
        completion?(image)
    }
}
#endif
