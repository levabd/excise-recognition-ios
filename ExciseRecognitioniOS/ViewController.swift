import AVFoundation
import UIKit
import Vision
import CoreML
//import GPUImage

class ViewController: UIViewController, G8TesseractDelegate {
    
    private var textDetectionRequest: VNDetectTextRectanglesRequest?
    private var textObservations = [VNTextObservation]()
    private var tesseract = G8Tesseract(language: "eng", engineMode: .tesseractOnly) // <-- Fatest
    // private var tesseract = G8Tesseract(language: "eng", engineMode: .tesseractCubeCombined) // <-- Most Accurate in docs but not accurate at all in real life
    private var recognizerEnabled = true
    private let session = AVCaptureSession()
    private let numberVerifier = ExciseStohasticVerifier(minimumCandidatesCount: 3, bottomProbabilityThreshold: 0.4)
    
    var recognizedText: String = ""
    
    /*func preprocessedImage(for tesseract: G8Tesseract?, sourceImage: UIImage?) -> UIImage? {
        // sourceImage is the same image you sent to Tesseract above
        let inputImage: UIImage? = sourceImage
        // Initialize our adaptive threshold filter
        let stillImageFilter = GPUImageAdaptiveThresholdFilter()
        stillImageFilter.blurRadiusInPixels = 4.0
        // adjust this to tweak the blur radius of the filter, defaults to 4.0
        // Retrieve the filtered image from the filter
        let filteredImage: UIImage? = stillImageFilter.image(byFilteringImage: inputImage)
        // Give the filteredImage to Tesseract instead of the original one,
        // allowing us to bypass the internal thresholding step.
        // filteredImage will be sent immediately to the recognition step
        return filteredImage
    }*/
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
        tap.numberOfTapsRequired = 1
        view.addGestureRecognizer(tap)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        tap.require(toFail: doubleTap)
        
        tesseract?.pageSegmentationMode = .singleChar
        // tesseract?.charWhitelist = "1234567890OoZzATSsgDpeBbGtaXq"
        tesseract?.charWhitelist = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890()-+*!/?.,@#$%&"
        //tesseract?.delegate = self
        
        if isAuthorized() {
            configureTextDetection()
            configureCamera()
        }
    }
    
    @objc func doubleTapped() {
        recognizerEnabled = !recognizerEnabled
        print("Play/Pause")
    }
    
    @objc func tapped() {
        numberVerifier.clearAccumulator()
        print("Accumulator cleared. Current result: \(numberVerifier.lastAddedNumber())")
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
    
    //OCR-REQUEST
    lazy var ocrRequest: VNCoreMLRequest = {
        do {
            //THIS MODEL IS TRAINED BY ME FOR FONT "Inconsolata" (Numbers 0...9 and UpperCase Characters A..Z)
            let model = try VNCoreMLModel(for:OCR().model)
            return VNCoreMLRequest(model: model, completionHandler: self.handleClassification)
        } catch {
            fatalError("cannot load model")
        }
    }()
    
    //OCR-HANDLER
    func handleClassification(request: VNRequest, error: Error?)
    {
        guard let observations = request.results as? [VNClassificationObservation]
            else {fatalError("unexpected result") }
        guard let best = observations.first
            else { fatalError("cant get best result")}
        
        var text = best.identifier.trimmingCharacters(in: CharacterSet.newlines)
        if !text.isEmpty {
            recognizedText.append(replaceFalseOccurence(input: text))
        }
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
        
        if (!recognizerEnabled) {
            return
        }
        
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
    
    // Convert from CIImage to UIImage
    func convert(cimage: CIImage) -> UIImage
    {
        let context:CIContext = CIContext.init(options: nil)
        let cgImage:CGImage = context.createCGImage(cimage, from: cimage.extent)!
        let image:UIImage = UIImage.init(cgImage: cgImage)
        return image
    }
    
    func saveImage(image: UIImage, mock: Bool, name: String) {
        if (mock){
            return
        }
        
        do {
            // Define the specific path, image name
            let documentsDirectoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).last!
            // create a name for your image
            let fileURL = documentsDirectoryURL.appendingPathComponent(name)
            
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
        
        let textLayer = CATextLayer()
        textLayer.backgroundColor = UIColor.clear.cgColor
        let textRect = CGRect(
            origin: CGPoint(x: viewWidth * 0.02, y: viewHeight * 0.02),
            size: CGSize(width: viewWidth * 0.98, height: viewHeight * 0.1)
        )
        
        textLayer.frame = textRect
        textLayer.string = self.recognizerEnabled ? "Recognized Enabled" : "Recognized Disabled"
        textLayer.foregroundColor = UIColor.magenta.cgColor
        self.view.layer.addSublayer(textLayer)
        
        let answerLayer = CATextLayer()
        answerLayer.backgroundColor = UIColor.clear.cgColor
        let answerRect = CGRect(
            origin: CGPoint(x: viewWidth * 0.02, y: viewHeight * 0.14),
            size: CGSize(width: viewWidth * 0.98, height: viewHeight * 0.1)
        )
        
        answerLayer.frame = answerRect
        answerLayer.string = self.numberVerifier.calculatePossibleNumber()
        answerLayer.foregroundColor = UIColor.green.cgColor
        self.view.layer.addSublayer(answerLayer)
    }
    
    func replaceFalseOccurence(input: String) -> String{
        // Required
        var resultString = input.replacingOccurrences(of: " ", with: "", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "O", with: "0", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "G", with: "6", options: .literal, range: nil)
        
        // Optional
        /*resultString = resultString.replacingOccurrences(of: "o", with: "0", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "Z", with: "7", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "z", with: "7", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "A", with: "4", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "T", with: "7", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "S", with: "5", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "s", with: "5", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "g", with: "9", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "D", with: "0", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "p", with: "0", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "e", with: "8", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "B", with: "8", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "b", with: "6", options: .literal, range: nil)
        
        // Very optional
        resultString = resultString.replacingOccurrences(of: "t", with: "1", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "a", with: "4", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "X", with: "7", options: .literal, range: nil)
        resultString = resultString.replacingOccurrences(of: "q", with: "4", options: .literal, range: nil)*/
        
        return resultString
    }
    
    // Camera Delegate and Setup
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        DispatchQueue.main.async {
            self.drawROI()
        }
        
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
        let transform4Recognize = ciImage.orientationTransform(for: CGImagePropertyOrientation(rawValue: 3)!)
        let transform4Save = ciImage.orientationTransform(for: CGImagePropertyOrientation(rawValue: 1)!)
        ciImage = ciImage.transformed(by: transform4Recognize)
        
        //NEEDED BECAUSE OF DIFFERENT SCALES
        let transform = CGAffineTransform.identity.scaledBy(x: ciImage.extent.size.width, y: ciImage.extent.size.height)
        
        // TODO: For saving images
        var imageCandidate = CIImage(cvPixelBuffer: pixelBuffer)
        imageCandidate = imageCandidate.transformed(by: transform4Save)
        
        let size = ciImage.extent.size
        recognizedText = ""
        
        for textObservation in textObservations {
            guard let rects = textObservation.characterBoxes else {
                continue
            }
            var iterator = 0
            for rect in rects {
                iterator += 1
                
                /*let imageRect = CGRect(
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
                
                // self.saveImage(image: (tesseract?.thresholdedImage)!, mock: false, name: "thr_image\(iterator).jpg")
                // print("Number #\(iterator)")
                // print(tesseract?.confidences(by: .symbol))
                
                guard var text = tesseract?.recognizedText else {
                    continue
                } */
                
                //SCALE THE BOUNDING BOX TO PIXELS
                let realBoundingBox = rect.boundingBox.applying(transform)
                
                //TO BE SURE
                guard (ciImage.extent.contains(realBoundingBox))
                    else { print("invalid detected rectangle"); return}
                
                //SCALE THE POINTS TO PIXELS
                let topleft = rect.topLeft.applying(transform)
                let topright = rect.topRight.applying(transform)
                let bottomleft = rect.bottomLeft.applying(transform)
                let bottomright = rect.bottomRight.applying(transform)
                
                //LET'S CROP AND RECTIFY
                let charImage = ciImage
                    .cropped(to: realBoundingBox)
                    .applyingFilter("CIPerspectiveCorrection", parameters: [
                        "inputTopLeft" : CIVector(cgPoint: topleft),
                        "inputTopRight" : CIVector(cgPoint: topright),
                        "inputBottomLeft" : CIVector(cgPoint: bottomleft),
                        "inputBottomRight" : CIVector(cgPoint: bottomright)
                        ])
                
                //PREPARE THE HANDLER
                let handler = VNImageRequestHandler(ciImage: charImage, options: [:])
                
                //SOME OPTIONS (TO PLAY WITH..)
                self.ocrRequest.imageCropAndScaleOption = VNImageCropAndScaleOption.scaleFill
                
                //FEED THE CHAR-IMAGE TO OUR OCR-REQUEST - NO NEED TO SCALE IT - VISION WILL DO IT FOR US !!
                do {
                    try handler.perform([self.ocrRequest])
                }  catch { print("Error")}
            }
            //print("Iteration")
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
            if (self.recognizedText.count > 0){
                
                // TODO: For saving images
                // self.saveImage(image: self.convert(cimage: imageCandidate), mock: false, name: "super_source_image.jpg")
                
                let textLayer = CATextLayer()
                textLayer.backgroundColor = UIColor.clear.cgColor
                let textRect = CGRect(
                    origin: CGPoint(x: viewWidth * 0.02, y: viewHeight * 0.08),
                    size: CGSize(width: viewWidth * 0.98, height: viewHeight * 0.1)
                )
                
                textLayer.frame = textRect
                textLayer.string = self.recognizedText
                textLayer.foregroundColor = UIColor.yellow.cgColor
                self.view.layer.addSublayer(textLayer)
                
                self.numberVerifier.addNumber(str: self.recognizedText)
            }
        }
    }
}
