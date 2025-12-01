import SwiftUI

struct ToolbarView: View {
    @Binding var selectedTool: ToolType
    var onAddGraph: () -> Void
    var onAskAI: () -> Void
    var onImportPDF: () -> Void
    var onDeleteSelection: () -> Void
    var onUndo: () -> Void
    var onRedo: () -> Void
    var canUndo: Bool
    var canRedo: Bool
    
    enum ToolType {
        case select
        case hand
        case pen
        case text
    }
    
    var body: some View {
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
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
