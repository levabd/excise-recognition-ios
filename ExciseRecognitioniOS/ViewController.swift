import AVFoundation
import UIKit
import Vision

class ViewController: UIViewController {
    
    private var textDetectionRequest: VNDetectTextRectanglesRequest?
    private let session = AVCaptureSession()
    private var textObservations = [VNTextObservation]()
    private var tesseract = G8Tesseract(language: "eng", engineMode: .tesseractOnly)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tesseract?.pageSegmentationMode = .singleChar
        tesseract?.charWhitelist = "1234567890OoZzATSsgDpeBbGtaXq"
        if isAuthorized() {
            configureTextDetection()
            configureCamera()
        }
        
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    private func configureTextDetection() {
        textDetectionRequest = VNDetectTextRectanglesRequest(completionHandler: handleDetection)
        // textDetectionRequest?.regionOfInterest = CGRect(x: (30 + 33)/128, y: 31/72, width: 33/128, height: 10/72)
        textDetectionRequest?.regionOfInterest = CGRect(x: 0.4921875, y: 0.430556, width: 0.2578125, height: 0.138889)
        textDetectionRequest!.reportCharacterBoxes = true
    }
    
    private func configureCamera() {
        preview.session = session
        
        let cameraDevices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: AVMediaType.video, position: .back)
        var cameraDevice: AVCaptureDevice?
        for device in cameraDevices.devices {
            if device.position == .back {
                cameraDevice = device
                break
            }
        }
        do {
            let captureDeviceInput = try AVCaptureDeviceInput(device: cameraDevice!)
            if session.canAddInput(captureDeviceInput) {
                session.addInput(captureDeviceInput)
            }
        }
        catch {
            print("Error occured \(error)")
            return
        }
        session.sessionPreset = .high
        let videoDataOutput = AVCaptureVideoDataOutput()
        videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "Buffer Queue", qos: .userInteractive, attributes: .concurrent, autoreleaseFrequency: .inherit, target: nil))
        if session.canAddOutput(videoDataOutput) {
            session.addOutput(videoDataOutput)
        }
        preview.videoPreviewLayer.videoGravity = .resize
        session.startRunning()
        
        drawROI()
    }
    
    private func handleDetection(request: VNRequest, error: Error?) {
        
        guard let detectionResults = request.results else {
            print("No detection results")
            return
        }
        let textResults = detectionResults.map() {
            return $0 as? VNTextObservation
        }
        if textResults.isEmpty {
            return
        }
        textObservations = textResults as! [VNTextObservation]
        DispatchQueue.main.async {
            
            guard let sublayers = self.view.layer.sublayers else {
                return
            }
            for layer in sublayers[1...] {
                if (layer as? CATextLayer) == nil {
                    layer.removeFromSuperlayer()
                }
            }
           
            self.drawROI()
            
            for result in textResults {

                if let textResult = result {
                    // Draw detected region
                    self.drawDetectedRegion(recognizedRect: textResult.boundingBox, borderColor: UIColor.red.cgColor)
                    if let boxes = textResult.characterBoxes {
                        for characterBox in boxes {
                            // Draw Character region
                            self.drawDetectedRegion(recognizedRect: characterBox.boundingBox, borderColor: UIColor.blue.cgColor)
                        }
                    }
                }
            }
        }
    }
    
    private var preview: PreviewView {
        return view as! PreviewView
    }
    
    private func isAuthorized() -> Bool {
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: AVMediaType.video)
        switch authorizationStatus {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: AVMediaType.video,
                                          completionHandler: { (granted:Bool) -> Void in
                                            if granted {
                                                DispatchQueue.main.async {
                                                    self.configureTextDetection()
                                                    self.configureCamera()
                                                }
                                            }
            })
            return true
        case .authorized:
            return true
        case .denied, .restricted: return false
        }
    }
}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func saveImage(inputCI: CIImage, mock: Bool) {
        if (mock){
            return
        }
        
        // Convert from CIImage to UIImage
        func convert(cimage: CIImage) -> UIImage
        {
            let context:CIContext = CIContext.init(options: nil)
            let cgImage:CGImage = context.createCGImage(cimage, from: cimage.extent)!
            let image:UIImage = UIImage.init(cgImage: cgImage)
            return image
        }
        
        do {
            // Define the specific path, image name
            let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
            // create a name for your image
            let fileURL = documentsDirectoryURL.appendingPathComponent("image.jpg")
            
            let image = convert(cimage: inputCI) // imgviewQRcode is UIImageView
            if !FileManager.default.fileExists(atPath: fileURL.path)
            {
                try UIImageJPEGRepresentation(image, 1.0)?.write(to: fileURL, options: .atomic)
                print("file saved \(fileURL.path)")
            } // Checking existing file
        } catch {
            print(error)
        }
    }
    
    func drawDetectedRegion(recognizedRect: CGRect, borderColor: CGColor) {
        
        let viewWidth = self.view.frame.size.width
        let viewHeight = self.view.frame.size.height
        
        let layer = CALayer()
        
        /*
         
         // for normal orientation
         rect.origin.x *= viewWidth
         rect.size.height *= viewHeight
         rect.origin.y = ((1 - rect.origin.y) * viewHeight) - rect.size.height
         rect.size.width *= viewWidth
         
         */
        
        let rect = CGRect(
            x: (1 - recognizedRect.origin.y - recognizedRect.size.height) * viewWidth,
            y: (1 - recognizedRect.origin.x - recognizedRect.size.width) * viewHeight,
            width: recognizedRect.size.height * viewWidth,
            height: recognizedRect.size.width * viewHeight)
        
        layer.frame = rect
        layer.borderWidth = 2
        layer.borderColor = borderColor
        self.view.layer.addSublayer(layer)
    }
    
    func drawROI() {
        let viewWidth = self.view.frame.size.width
        let viewHeight = self.view.frame.size.height
        
        // Draw ROI
        let ROIlayer = CALayer()
        
        let ROIrect = CGRect(
                origin: CGPoint(x: viewWidth * 31/72, y: viewHeight * 30/128),
                size: CGSize(width: viewWidth * 10/72, height: viewHeight * 33/128)
            )
        
        ROIlayer.frame = ROIrect
        ROIlayer.borderWidth = 2
        ROIlayer.borderColor = UIColor.white.cgColor
        self.view.layer.addSublayer(ROIlayer)
    }
    
    func replaceFalseOccurence(input: String) -> String{
        // Optional
        var resultString = input.replacingOccurrences(of: "O", with: "0", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "o", with: "0", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "Z", with: "7", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "z", with: "7", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "A", with: "4", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "T", with: "7", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "S", with: "5", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "s", with: "5", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "g", with: "9", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "D", with: "0", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "p", with: "0", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "e", with: "8", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "B", with: "8", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "b", with: "6", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "G", with: "6", options: .literal, range: nil)
        
        // Very optional
        resultString = input.replacingOccurrences(of: "t", with: "1", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "a", with: "4", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "X", with: "7", options: .literal, range: nil)
        resultString = input.replacingOccurrences(of: "q", with: "4", options: .literal, range: nil)
        
        return resultString
    }
    
    // Camera Delegate and Setup
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        drawROI()
        
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }
        var imageRequestOptions = [VNImageOption: Any]()
        if let cameraData = CMGetAttachment(sampleBuffer, kCMSampleBufferAttachmentKey_CameraIntrinsicMatrix, nil) {
            imageRequestOptions[.cameraIntrinsics] = cameraData
        }
        //let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 6)!, options: imageRequestOptions) // for normal orientation
        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: CGImagePropertyOrientation(rawValue: 3)!, options: imageRequestOptions)
        do {
            try imageRequestHandler.perform([textDetectionRequest!])
        }
        catch {
            print("Error occured \(error)")
        }
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        // let transform = ciImage.orientationTransform(for: CGImagePropertyOrientation(rawValue: 6)!) // for normal orientation
        let transform = ciImage.orientationTransform(for: CGImagePropertyOrientation(rawValue: 3)!)
        ciImage = ciImage.transformed(by: transform)
        
        // TODO: For saving images
        var imageCandidate = CIImage(cvPixelBuffer: pixelBuffer)
        imageCandidate = imageCandidate.transformed(by: transform)
        
        let size = ciImage.extent.size
        var recognizedText: String = ""
        for textObservation in textObservations {
            guard let rects = textObservation.characterBoxes else {
                continue
            }
            /*var xMin = CGFloat.greatestFiniteMagnitude
            var xMax: CGFloat = 0
            var yMin = CGFloat.greatestFiniteMagnitude
            var yMax: CGFloat = 0*/
            for rect in rects {
                
                /*xMin = min(xMin, rect.bottomLeft.x)
                xMax = max(xMax, rect.bottomRight.x)
                yMin = min(yMin, rect.bottomRight.y)
                yMax = max(yMax, rect.topRight.y)*/
                
                let imageRect = CGRect(
                    x: rect.bottomLeft.x * size.width,
                    y: rect.bottomRight.y * size.height,
                    width: (rect.bottomRight.x - rect.bottomLeft.x) * size.width,
                    height: (rect.topRight.y - rect.bottomRight.y) * size.height)
                let context = CIContext(options: nil)
                guard let cgImage = context.createCGImage(ciImage, from: imageRect) else {
                    continue
                }
                let uiImage = UIImage(cgImage: cgImage)
                tesseract?.image = uiImage
                tesseract?.recognize()
                guard var text = tesseract?.recognizedText else {
                    continue
                }
                text = text.trimmingCharacters(in: CharacterSet.newlines)
                text = replaceFalseOccurence(input: text)
                if !text.isEmpty {
                    recognizedText.append(text)
                }
                
                // TODO: For saving images
                //saveImage(inputCI: imageCandidate, mock: false)
            }
        }
        textObservations.removeAll()
        DispatchQueue.main.async {
            let viewWidth = self.view.frame.size.width
            let viewHeight = self.view.frame.size.height
            guard let sublayers = self.view.layer.sublayers else {
                return
            }
            for layer in sublayers[1...] {
                
                if let _ = layer as? CATextLayer {
                    layer.removeFromSuperlayer()
                }
            }
            if (recognizedText.count > 0){
                let textLayer = CATextLayer()
                textLayer.backgroundColor = UIColor.clear.cgColor
                let textRect = CGRect(
                    origin: CGPoint(x: viewWidth * 0.02, y: viewHeight * 0.02),
                    size: CGSize(width: viewWidth * 0.98, height: viewHeight * 33/128)
                )
                
                textLayer.frame = textRect
                textLayer.string = recognizedText
                textLayer.foregroundColor = UIColor.green.cgColor
                self.view.layer.addSublayer(textLayer)
            }
        }
    }
}
