import SwiftUI
import UIKit

struct CanvasInputView: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel
    @Binding var selectedTool: ToolbarView.ToolType
    @Binding var isFingerDrawingEnabled: Bool
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = true
        
        // Pencil Pan (Drawing)
        let pencilPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePencilPan(_:)))
        pencilPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
        pencilPan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pencilPan)
        
        // Finger Pan (Scrolling / Selection)
        let fingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFingerPan(_:)))
        fingerPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(fingerPan)
        
        // Pinch (Zoom)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        
        // Tap (Clear Selection / Add Text)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        
        // Double Tap (Add Text shortcut)
        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        // Ensure single tap fails if double tap detects
        tap.require(toFail: doubleTap)
        
        context.coordinator.view = view
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.parent = self
        
        // Update gesture configurations based on settings
        if let gestures = uiView.gestureRecognizers {
            // Pencil Pan (Index 0)
            if let pencilPan = gestures.first as? UIPanGestureRecognizer {
                if isFingerDrawingEnabled {
                    pencilPan.allowedTouchTypes = [
                        NSNumber(value: UITouch.TouchType.pencil.rawValue),
                        NSNumber(value: UITouch.TouchType.direct.rawValue)
                    ]
                } else {
                    pencilPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.pencil.rawValue)]
                }
            }
            
            // Finger Pan (Index 1)
            if gestures.count > 1, let fingerPan = gestures[1] as? UIPanGestureRecognizer {
                if selectedTool == .hand || selectedTool == .select || selectedTool == .text {
                    // Non-drawing tools always pan/select with 1 finger
                    fingerPan.minimumNumberOfTouches = 1
                } else {
                    // Pen or Eraser
                    if isFingerDrawingEnabled {
                        // If finger drawing is enabled, finger pan (scrolling) requires 2 touches
                        fingerPan.minimumNumberOfTouches = 2
                    } else {
                        // If finger drawing is disabled, we still capture 1 touch but will ignore it in the handler
                        // to prevent it from doing anything (like scrolling)
                        fingerPan.minimumNumberOfTouches = 1
                    }
                }
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: CanvasInputView
        weak var view: UIView?
        
        // State for selection moving
        var isMovingSelection = false
        
        init(_ parent: CanvasInputView) {
            self.parent = parent
        }
        
        @objc func handlePencilPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = view else { return }
            let location = gesture.location(in: view)
            
            switch gesture.state {
            case .began:
                if parent.selectedTool == .pen {
                    parent.viewModel.startStroke(at: location)
                } else if parent.selectedTool == .eraser {
                    parent.viewModel.eraseElement(at: location)
                } else if parent.selectedTool == .select {
                    handleSelectionStart(location: location)
                }
            case .changed:
                if parent.selectedTool == .pen {
                    parent.viewModel.continueStroke(at: location)
                } else if parent.selectedTool == .eraser {
                    parent.viewModel.eraseElement(at: location)
                } else if parent.selectedTool == .select {
                    handleSelectionChange(gesture: gesture, location: location)
                }
            case .ended, .cancelled:
                if parent.selectedTool == .pen {
                    parent.viewModel.endStroke()
                } else if parent.selectedTool == .select {
                    handleSelectionEnd()
                }
            default: break
            }
        }
        
        @objc func handleFingerPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = view else { return }
            let location = gesture.location(in: view)
            let translation = gesture.translation(in: view)
            
            switch gesture.state {
            case .began:
                if parent.selectedTool == .select {
                    handleSelectionStart(location: location)
                }
            case .changed:
                if parent.selectedTool == .select {
                    handleSelectionChange(gesture: gesture, location: location)
                } else if parent.selectedTool == .hand {
                    parent.viewModel.handleDrag(translation: CGSize(width: translation.x, height: translation.y))
                } else if parent.selectedTool == .pen || parent.selectedTool == .eraser {
                    if parent.isFingerDrawingEnabled {
                        // 2-finger pan (configured in updateUIView)
                        parent.viewModel.handleDrag(translation: CGSize(width: translation.x, height: translation.y))
                    } else {
                        // Finger drawing disabled: Do nothing (ignore finger)
                    }
                } else {
                    // Default fallback (e.g. text tool)
                    parent.viewModel.handleDrag(translation: CGSize(width: translation.x, height: translation.y))
                }
            case .ended, .cancelled:
                if parent.selectedTool == .select {
                    handleSelectionEnd()
                } else if parent.selectedTool == .hand {
                    parent.viewModel.endDrag(translation: CGSize(width: translation.x, height: translation.y))
                } else if parent.selectedTool == .pen || parent.selectedTool == .eraser {
                    if parent.isFingerDrawingEnabled {
                        parent.viewModel.endDrag(translation: CGSize(width: translation.x, height: translation.y))
                    }
                } else {
                    parent.viewModel.endDrag(translation: CGSize(width: translation.x, height: translation.y))
                }
            default: break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .changed:
                parent.viewModel.handleMagnification(value: gesture.scale)
            case .ended, .cancelled:
                parent.viewModel.endMagnification(value: gesture.scale)
                gesture.scale = 1.0 // Reset scale? No, handleMagnification multiplies.
                // Wait, handleMagnification: scale = lastScale * value.
                // UIPinchGestureRecognizer scale is cumulative.
                // So passing gesture.scale is correct if lastScale is fixed at start.
                // But CanvasViewModel updates lastScale only on endMagnification.
                // So gesture.scale (cumulative) is correct.
            default: break
            }
        }
        
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let location = gesture.location(in: view)
            
            if parent.selectedTool == .text {
                // Add text
                let canvasX = (location.x - parent.viewModel.offset.width) / parent.viewModel.scale
                let canvasY = (location.y - parent.viewModel.offset.height) / parent.viewModel.scale
                parent.viewModel.addText("New Text", at: CGPoint(x: canvasX, y: canvasY))
                parent.selectedTool = .select
            } else {
                parent.viewModel.clearSelection()
            }
        }
        
        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let view = view else { return }
            let location = gesture.location(in: view)
            
            let canvasX = (location.x - parent.viewModel.offset.width) / parent.viewModel.scale
            let canvasY = (location.y - parent.viewModel.offset.height) / parent.viewModel.scale
            
            parent.viewModel.addText("New Text", at: CGPoint(x: canvasX - 100, y: canvasY - 25))
        }
        
        // MARK: - Selection Helpers
        
        private func handleSelectionStart(location: CGPoint) {
            if parent.viewModel.isPointInSelectedElement(location) {
                isMovingSelection = true
                parent.viewModel.startMovingSelection()
            } else if let elementId = parent.viewModel.findElement(at: location) {
                parent.viewModel.selectElement(id: elementId)
                isMovingSelection = true
                parent.viewModel.startMovingSelection()
            } else {
                parent.viewModel.startSelection(at: location)
            }
        }
        
        private func handleSelectionChange(gesture: UIPanGestureRecognizer, location: CGPoint) {
            if isMovingSelection {
                let translation = gesture.translation(in: view)
                parent.viewModel.moveSelection(translation: CGSize(width: translation.x, height: translation.y))
            } else if parent.viewModel.selectionBox != nil {
                parent.viewModel.updateSelection(to: location)
            }
        }
        
        private func handleSelectionEnd() {
            if isMovingSelection {
                parent.viewModel.endMovingSelection()
                isMovingSelection = false
            } else {
                parent.viewModel.endSelection()
            }
        }
    }
}
