import SwiftUI
import AVFoundation

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    
    func makeUIView(context: Context) -> CameraPreviewView {
        let view = CameraPreviewView()
        view.setupPreviewLayer(with: session)
        return view
    }
    
    func updateUIView(_ uiView: CameraPreviewView, context: Context) {
        uiView.updateSession(session)
    }
}

class CameraPreviewView: UIView {
    private var previewLayer: AVCaptureVideoPreviewLayer?
    
    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        return layer as! AVCaptureVideoPreviewLayer
    }
    
    func setupPreviewLayer(with session: AVCaptureSession) {
        videoPreviewLayer.session = session
        videoPreviewLayer.videoGravity = .resizeAspectFill
    }
    
    func updateSession(_ session: AVCaptureSession) {
        videoPreviewLayer.session = session
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
}

