import SwiftUI
import LaTeXSwiftUI


struct CanvasElementView: View {
    let element: CanvasElementData
    @ObservedObject var viewModel: CanvasViewModel
    let isSelected: Bool
    var onDelete: () -> Void
    var isEditing: Bool = false
    var isSnapshot: Bool = false
    var onTextChange: ((String) -> Void)? = nil
    
    @State private var editedText: String = ""
    @FocusState private var isFocused: Bool
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        ZStack {
            switch element.data {
            case .text(let data):
                if isEditing {
                    TextEditor(text: $editedText)
                        .font(.custom(data.fontFamily, size: data.fontSize))
                        .foregroundColor(Color(hex: data.color))
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .writingToolsBehavior(.complete)
                        .focused($isFocused)
                        .onAppear {
                            editedText = data.text
                            viewModel.pendingEditedText = data.text
                            isFocused = true
                        }
                        .onChange(of: editedText) { newValue in
                            // Sync text changes to viewModel for saving on clearSelection
                            viewModel.pendingEditedText = newValue
                        }
                        .onChange(of: isFocused) { newValue in
                            // Save text when focus is lost
                            if !newValue {
                                onTextChange?(editedText)
                            }
                        }
                        .frame(width: element.width, height: element.height, alignment: .topLeading)
                } else {
                    // Transparent background provides hit-testing area for parent gestures
                    Color.clear
                        .contentShape(Rectangle())
                    
                    // Text content is non-interactive, gestures pass to parent
                    // Calculate scale factor: base size is 20, scale proportionally
                    // Calculate scale factor: base size is 20, scale proportionally
                    let scaleFactor = data.fontSize / 20.0
                    
                    if isSnapshot {
                         // Direct render for snapshot (No ScrollView) to ensure ImageRenderer captures it
                         LaTeX(data.text)
                             .foregroundColor(Color(hex: data.color))
                             .multilineTextAlignment(.leading)
                             .fixedSize(horizontal: false, vertical: true)
                             .scaleEffect(scaleFactor, anchor: .topLeading)
                             .frame(width: element.width / scaleFactor, alignment: .topLeading)
                             .frame(width: element.width, height: element.height, alignment: .topLeading)
                    } else {
                        ScrollView {
                            LaTeX(data.text)
                                .foregroundColor(Color(hex: data.color))
                                .multilineTextAlignment(.leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .scaleEffect(scaleFactor, anchor: .topLeading)
                                .frame(width: element.width / scaleFactor, alignment: .topLeading)
                        }
                        .frame(width: element.width, height: element.height, alignment: .topLeading)
                        .allowsHitTesting(false)
                    }
                }
            
            case .graph(let data):
                GraphShape(data: data)
                    .stroke(Color(hex: data.color), lineWidth: 2)
                    .background(Color.white.opacity(0.1)) // Touch target
                    .clipShape(Rectangle())
                    .overlay(
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                    .overlay(
                        Text(data.expression)
                            .font(.caption)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .foregroundColor(.white)
                            .cornerRadius(4)
                            .offset(y: -element.height/2 - 20)
                    )
            

            
            case .bitmapInk(let data):
                if let cachedImage = viewModel.imageCache[element.id] {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .onAppear {
                            viewModel.imageCache[element.id] = uiImage
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                }

            case .image(let data):
                if let cachedImage = viewModel.imageCache[element.id] {
                    Image(uiImage: cachedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if let uiImage = UIImage(data: Data(base64Encoded: data.src) ?? Data()) {
                    // Fallback decoding if not in cache (though pre-loading should handle it)
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .onAppear {
                            // Optionally populate cache if missing (lazy loading)
                            viewModel.imageCache[element.id] = uiImage
                        }
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.2))
                        .overlay(Text("Image Error"))
                }
                
            case .stroke(let data):
                // Render stroke with brush-specific styling
                Path { path in
                    guard let first = data.points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: first.y))
                    for point in data.points.dropFirst() {
                        path.addLine(to: CGPoint(x: point.x, y: point.y))
                    }
                }
                .stroke(
                    Color(hex: data.color).opacity(data.brushType.opacity),
                    style: StrokeStyle(
                        lineWidth: data.width * data.brushType.widthMultiplier,
                        lineCap: data.brushType.lineCap,
                        lineJoin: data.brushType.lineJoin
                    )
                )
            }
        }
        .frame(width: element.width, height: element.height)
        .position(x: element.x + element.width/2, y: element.y + element.height/2)
        .overlay(
            isSelected ? 
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .stroke(appTheme.accentColor, style: StrokeStyle(lineWidth: 2, dash: [5]))
                
                // Delete Button
                Button(action: onDelete) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .background(Color.white.clipShape(Circle()))
                }
                .offset(x: -10, y: -10)
            }
            .frame(width: element.width + 10, height: element.height + 10)
            .position(x: element.x + element.width/2, y: element.y + element.height/2)
            : nil
        )
    }
}

extension CanvasElementView: Equatable {
    static func == (lhs: CanvasElementView, rhs: CanvasElementView) -> Bool {
        return lhs.element == rhs.element &&
            lhs.isSelected == rhs.isSelected &&
            lhs.isEditing == rhs.isEditing &&
            lhs.isSnapshot == rhs.isSnapshot
    }
}

// Helper for Hex Color
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: min(max(Double(r) / 255, 0), 1),
            green: min(max(Double(g) / 255, 0), 1),
            blue: min(max(Double(b) / 255, 0), 1),
            opacity: min(max(Double(a) / 255, 0), 1)
        )
    }
}
