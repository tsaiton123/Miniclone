import SwiftUI
import VisionKit

/// A SwiftUI wrapper around UIImageView that adds VisionKit's ImageAnalyzer
/// to enable native text selection and interaction (Live Text) on the image.
struct AnalyzableImageView: UIViewRepresentable {
    let image: UIImage
    @Binding var interaction: ImageAnalysisInteraction?
    
    // Provide a convenience initializer for when we don't care about extracting the interaction
    init(image: UIImage, interaction: Binding<ImageAnalysisInteraction?> = .constant(nil)) {
        self.image = image
        self._interaction = interaction
    }
    
    // We only enable this for iOS 16+ where ImageAnalyzer is available
    @available(iOS 16.0, *)
    func makeUIView(context: Context) -> UIImageView {
        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        
        // Ensure SwiftUI can resize the UIImageView properly without it collapsing or overflowing
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        
        let newInteraction = ImageAnalysisInteraction()
        imageView.addInteraction(newInteraction)
        
        // Pass it up to SwiftUI so we can read the `text` property later
        DispatchQueue.main.async {
            self.interaction = newInteraction
        }
        
        // Asynchronously analyze the image
        Task {
            let analyzer = ImageAnalyzer()
            let configuration = ImageAnalyzer.Configuration([.text])
            
            do {
                let analysis = try await analyzer.analyze(image, configuration: configuration)
                // Accessing UIKit on main thread
                await MainActor.run {
                    newInteraction.analysis = analysis
                    newInteraction.preferredInteractionTypes = .textSelection
                }
            } catch {
                print("VisionKit Analysis failed: \(error.localizedDescription)")
            }
        }
        
        return imageView
    }
    
    @available(iOS 16.0, *)
    func updateUIView(_ uiView: UIImageView, context: Context) {
        // If the image changes, update the view and re-analyze
        if uiView.image != image {
            uiView.image = image
            
            guard let interaction = uiView.interactions.first(where: { $0 is ImageAnalysisInteraction }) as? ImageAnalysisInteraction else { return }
            
            Task {
                let analyzer = ImageAnalyzer()
                let configuration = ImageAnalyzer.Configuration([.text])
                do {
                    let analysis = try await analyzer.analyze(image, configuration: configuration)
                    await MainActor.run {
                        if let currentInteraction = uiView.interactions.first(where: { $0 is ImageAnalysisInteraction }) as? ImageAnalysisInteraction {
                            currentInteraction.analysis = analysis
                        }
                    }
                } catch {
                    print("VisionKit Analysis failed on update: \(error.localizedDescription)")
                }
            }
        }
    }
}
