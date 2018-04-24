import GPUImage

class GPUImagePreprocessing {
    
    func preprocessedImage(for tesseract: G8Tesseract?, sourceImage: UIImage?) -> UIImage? {
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
    }
}
