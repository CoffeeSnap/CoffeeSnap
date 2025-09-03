import Foundation
import SwiftUI
import AVFoundation
import UIKit

class CameraService: NSObject, ObservableObject {
    @Published var isPermissionGranted = false
    @Published var capturedImage: UIImage?
    @Published var isShowingCamera = false
    @Published var error: CameraError?
    
    private var captureSession: AVCaptureSession?
    private var photoOutput: AVCapturePhotoOutput?
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override init() {
        super.init()
        checkPermissions()
    }
    
    // MARK: - Public Methods
    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isPermissionGranted = true
        case .notDetermined:
            requestPermission()
        case .denied, .restricted:
            isPermissionGranted = false
            error = .permissionDenied
        @unknown default:
            isPermissionGranted = false
        }
    }
    
    func requestPermission() {
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                self?.isPermissionGranted = granted
                if !granted {
                    self?.error = .permissionDenied
                }
            }
        }
    }
    
    func startSession() {
        guard isPermissionGranted else {
            error = .permissionDenied
            return
        }
        
        setupCaptureSession()
    }
    
    func stopSession() {
        captureSession?.stopRunning()
    }
    
    func capturePhoto() {
        guard let photoOutput = photoOutput else {
            error = .captureSessionNotSetup
            return
        }
        
        let settings = AVCapturePhotoSettings()
        settings.flashMode = .auto
        
        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            settings.photoCodecType = .hevc
        }
        
        photoOutput.capturePhoto(with: settings, delegate: self)
    }
    
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer? {
        return previewLayer
    }
    
    // MARK: - Private Methods
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        guard let captureSession = captureSession else {
            error = .captureSessionNotSetup
            return
        }
        
        captureSession.beginConfiguration()
        
        // Set session preset
        if captureSession.canSetSessionPreset(.photo) {
            captureSession.sessionPreset = .photo
        }
        
        // Add video input
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let videoInput = try? AVCaptureDeviceInput(device: videoDevice),
              captureSession.canAddInput(videoInput) else {
            error = .cameraNotAvailable
            captureSession.commitConfiguration()
            return
        }
        
        captureSession.addInput(videoInput)
        
        // Add photo output
        photoOutput = AVCapturePhotoOutput()
        guard let photoOutput = photoOutput,
              captureSession.canAddOutput(photoOutput) else {
            error = .captureSessionNotSetup
            captureSession.commitConfiguration()
            return
        }
        
        captureSession.addOutput(photoOutput)
        
        // Setup preview layer
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer?.videoGravity = .resizeAspectFill
        
        captureSession.commitConfiguration()
        
        // Start session on background queue
        DispatchQueue.global(qos: .userInitiated).async {
            captureSession.startRunning()
        }
    }
}

// MARK: - AVCapturePhotoCaptureDelegate
extension CameraService: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.error = .photoCaptureFailed(error.localizedDescription)
            }
            return
        }
        
        guard let imageData = photo.fileDataRepresentation(),
              let image = UIImage(data: imageData) else {
            DispatchQueue.main.async {
                self.error = .imageProcessingFailed
            }
            return
        }
        
        DispatchQueue.main.async {
            self.capturedImage = image
        }
    }
}

// MARK: - Camera Error Types
enum CameraError: LocalizedError {
    case permissionDenied
    case cameraNotAvailable
    case captureSessionNotSetup
    case photoCaptureFailed(String)
    case imageProcessingFailed
    
    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission is required to take photos"
        case .cameraNotAvailable:
            return "Camera is not available on this device"
        case .captureSessionNotSetup:
            return "Camera session could not be setup"
        case .photoCaptureFailed(let message):
            return "Photo capture failed: \(message)"
        case .imageProcessingFailed:
            return "Failed to process the captured image"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .permissionDenied:
            return "Please enable camera access in Settings"
        case .cameraNotAvailable:
            return "Try using the photo library instead"
        case .captureSessionNotSetup:
            return "Please restart the app and try again"
        case .photoCaptureFailed:
            return "Please try taking the photo again"
        case .imageProcessingFailed:
            return "Please try taking another photo"
        }
    }
}

// MARK: - Camera Preview UIViewRepresentable
struct CameraPreview: UIViewRepresentable {
    let previewLayer: AVCaptureVideoPreviewLayer
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.layer.addSublayer(previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            previewLayer.frame = uiView.bounds
        }
    }
}
