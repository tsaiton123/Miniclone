import SwiftUI
import VisionKit

struct ImagePreviewView: View {
    let image: UIImage
    let onCancel: () -> Void
    let onInsertImage: () -> Void
    let onInsertText: (String) -> Void
    
    @State private var interaction: ImageAnalysisInteraction?
    
    var body: some View {
        NavigationView {
            GeometryReader { geometry in
                ZStack {
                    Color.black.ignoresSafeArea()
                    
                    if #available(iOS 16.0, *) {
                        AnalyzableImageView(image: image, interaction: $interaction)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .navigationTitle("Preview Image")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(.red)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        if #available(iOS 16.0, *) {
                            Button(action: {
                                if let text = interaction?.text, !text.isEmpty {
                                    onInsertText(text)
                                }
                            }) {
                                Text("Add Text")
                                    .fontWeight(.semibold)
                            }
                            // Only show if there is actually selected text, or always show but disable?
                            // interaction.text is only updated lazily so we just leave it always enabled.
                        }
                        
                        Button(action: onInsertImage) {
                            Text("Add Image")
                                .fontWeight(.bold)
                        }
                    }
                }
            }
        }
    }
}
