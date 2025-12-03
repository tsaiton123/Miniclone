import SwiftUI

struct ToolbarView: View {
    @Binding var selectedTool: ToolType
    @Binding var strokeColor: String
    @Binding var strokeWidth: CGFloat
    
    var onAddGraph: () -> Void
    var onAskAI: () -> Void
    var onImportPDF: () -> Void
    var onImportImage: () -> Void
    var onToggleCalculator: () -> Void
    var onDeleteSelection: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onSettings: () -> Void
    var canUndo: Bool
    var canRedo: Bool
    
    enum ToolType {
        case select
        case hand
        case pen
        case eraser
        case text
    }
    
    let colors = ["#ffffff", "#ff3b30", "#34c759", "#007aff", "#ffcc00", "#af52de"]
    
    var body: some View {
        VStack(spacing: 12) {
            // Styling Controls (Only visible when Pen is selected)
            if selectedTool == .pen {
                HStack(spacing: 12) {
                    // Color Picker
                    ForEach(colors, id: \.self) { color in
                        Circle()
                            .fill(Color(hex: color))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Circle()
                                    .stroke(Color.white, lineWidth: strokeColor == color ? 2 : 0)
                            )
                            .onTapGesture {
                                strokeColor = color
                            }
                    }
                    
                    Divider()
                        .frame(height: 20)
                    
                    // Width Slider
                    Slider(value: $strokeWidth, in: 1...10)
                        .frame(width: 100)
                        .accentColor(Color(hex: strokeColor))
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            HStack(spacing: 20) {
                // Primary Tools
                Group {
                    Button(action: { selectedTool = .select }) {
                        Image(systemName: "cursorarrow")
                    }
                    .foregroundColor(selectedTool == .select ? .blue : .primary)
                    
                    Button(action: { selectedTool = .hand }) {
                        Image(systemName: "hand.raised")
                    }
                    .foregroundColor(selectedTool == .hand ? .blue : .primary)
                    
                    Button(action: { selectedTool = .pen }) {
                        Image(systemName: "pencil")
                    }
                    .foregroundColor(selectedTool == .pen ? .blue : .primary)
                    
                    Button(action: { selectedTool = .eraser }) {
                        Image(systemName: "eraser")
                    }
                    .foregroundColor(selectedTool == .eraser ? .blue : .primary)
                    
                    Button(action: { selectedTool = .text }) {
                        Image(systemName: "textformat")
                    }
                    .foregroundColor(selectedTool == .text ? .blue : .primary)
                }
                
                Divider()
                    .frame(height: 20)
                
                // Insert Tools
                Group {
                    Button(action: onAskAI) {
                        Image(systemName: "sparkles")
                    }
                    
                    Button(action: onImportPDF) {
                        Image(systemName: "doc.text")
                    }
                    
                    Button(action: onImportImage) {
                        Image(systemName: "photo")
                    }
                    
                    Button(action: onToggleCalculator) {
                        Image(systemName: "function")
                    }
                }
                
                Divider()
                    .frame(height: 20)
                
                // Actions
                Group {
                    Button(action: onUndo) {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .disabled(!canUndo)
                    .foregroundColor(canUndo ? .primary : .gray)
                    
                    Button(action: onRedo) {
                        Image(systemName: "arrow.uturn.forward")
                    }
                    .disabled(!canRedo)
                    .foregroundColor(canRedo ? .primary : .gray)
                    
                    Button(action: onDeleteSelection) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    
                    Button(action: onSettings) {
                        Image(systemName: "gear")
                    }
                }
            }
            .padding()
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
