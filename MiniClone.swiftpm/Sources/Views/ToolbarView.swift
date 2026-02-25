import SwiftUI

struct ToolbarView: View {
    @Binding var selectedTool: ToolType
    @Binding var strokeColor: String
    @Binding var strokeWidth: CGFloat
    @Binding var brushType: BrushType
    @Binding var eraserWidth: CGFloat
    var isDrawing: Bool = false
    var onPenTapped: (() -> Void)? = nil
    var onEraserTapped: (() -> Void)? = nil
    
    var onAddGraph: () -> Void
    var onImportPDF: () -> Void
    var onImportImage: () -> Void
    var onToggleCalculator: () -> Void
    var onDeleteSelection: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var onExport: () -> Void
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
    
    let colors = ["#000000", "#ff3b30", "#34c759", "#007aff", "#ffcc00", "#af52de"]
    
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        VStack(spacing: horizontalSizeClass == .compact ? 8 : 12) {
            // Styling Controls (Only visible when Pen is selected and NOT drawing)
            if selectedTool == .pen && !isDrawing {
                VStack(spacing: 8) {
                    // Brush Type Picker (compact)
                    HStack(spacing: 4) {
                        ForEach(BrushType.allCases, id: \.self) { type in
                            Button(action: { brushType = type }) {
                                Image(systemName: type.iconName)
                                    .font(.system(size: 18))
                                    .frame(width: 36, height: 36)
                                    .background(brushType == type ? appTheme.accentColor.opacity(0.2) : Color.clear)
                                    .foregroundColor(brushType == type ? appTheme.accentColor : .primary)
                                    .cornerRadius(8)
                            }
                            .help(type.displayName)
                        }
                    }
                    
                    Divider()
                    
                    ViewThatFits(in: .horizontal) {
                        colorPickerContent
                        ScrollView(.horizontal, showsIndicators: false) {
                            colorPickerContent
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }
            
            // Eraser Controls (Only visible when Eraser is selected and NOT drawing)
            if selectedTool == .eraser && !isDrawing {
                HStack(spacing: 12) {
                    Text("Size")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Slider(value: $eraserWidth, in: 5...50)
                        .frame(width: 120)
                        .accentColor(.gray)
                    
                    Text("\(Int(eraserWidth))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 24)
                }
                .padding(.horizontal)
                .padding(.top, 8)
            }

            
            ViewThatFits(in: .horizontal) {
                mainToolsContent
                ScrollView(.horizontal, showsIndicators: false) {
                    mainToolsContent
                }
            }
        }
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(4)
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, horizontalSizeClass == .compact ? 8 : 0)
    }
    
    @ViewBuilder
    private var colorPickerContent: some View {
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
    }
    
    @ViewBuilder
    private var mainToolsContent: some View {
        HStack(spacing: horizontalSizeClass == .compact ? 12 : 20) {
            // Primary Tools
            Group {
                Button(action: { selectedTool = .select }) {
                    Image(systemName: "cursorarrow")
                }
                .foregroundColor(selectedTool == .select ? appTheme.accentColor : .primary)
                
                Button(action: { selectedTool = .hand }) {
                    Image(systemName: "hand.raised")
                }
                .foregroundColor(selectedTool == .hand ? appTheme.accentColor : .primary)
                
                Button(action: {
                    if selectedTool == .pen {
                        // Toggle expand/collapse when already on pen
                        onPenTapped?()
                    } else {
                        selectedTool = .pen
                    }
                }) {
                    Image(systemName: "pencil")
                }
                .foregroundColor(selectedTool == .pen ? appTheme.accentColor : .primary)
                
                Button(action: {
                    if selectedTool == .eraser {
                        // Toggle expand/collapse when already on eraser
                        onEraserTapped?()
                    } else {
                        selectedTool = .eraser
                    }
                }) {
                    Image(systemName: "eraser")
                }
                .foregroundColor(selectedTool == .eraser ? appTheme.accentColor : .primary)
                
                Button(action: { selectedTool = .text }) {
                    Image(systemName: "textformat")
                }
                .foregroundColor(selectedTool == .text ? appTheme.accentColor : .primary)
            }
            
            Divider()
                .frame(height: 20)
            
            // Insert Tools
            Group {
                
                Button(action: {
                    print("ToolbarView: Button tapped directly")
                    onImportPDF()
                }) {
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
                
                Button(action: onExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                
                Button(action: onSettings) {
                    Image(systemName: "gear")
                }
            }
        }
        .padding(horizontalSizeClass == .compact ? 12 : 16)
    }
}
