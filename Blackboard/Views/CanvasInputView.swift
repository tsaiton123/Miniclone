import SwiftUI
import UIKit

// MARK: - Custom Drawing View for Direct Touch Handling
/// This custom UIView captures touch events directly to avoid the gesture recognition delay
/// that causes the first portion of Apple Pencil strokes to be missed.
class DrawingCanvasView: UIView {
    weak var coordinator: CanvasInputView.Coordinator?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        isMultipleTouchEnabled = true
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let coordinator = coordinator else { return }
        
        for touch in touches {
            let location = touch.location(in: self)
            
            // Handle Apple Pencil touches for drawing
            if touch.type == .pencil {
                coordinator.parent.viewModel.isCanvasTouched = true
                coordinator.handleDrawingTouchBegan(at: location, touch: touch)
            }
            // Handle finger touches - always notify for toolbar collapse, but only draw if enabled
            else if touch.type == .direct {
                let tool = coordinator.parent.selectedTool
                // Collapse toolbar when finger touches canvas while using pen/eraser tool
                if tool == .pen || tool == .eraser {
                    coordinator.parent.viewModel.isCanvasTouched = true
                }
                // Only draw with finger if finger drawing is enabled
                if coordinator.parent.isFingerDrawingEnabled && (tool == .pen || tool == .eraser) {
                    coordinator.handleDrawingTouchBegan(at: location, touch: touch)
                }
            }
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let coordinator = coordinator else { return }
        
        for touch in touches {
            let location = touch.location(in: self)
            
            // Handle Apple Pencil touches for drawing
            if touch.type == .pencil {
                let tool = coordinator.parent.selectedTool
                
                // For eraser, skip coalesced touches to save CPU as it's a radius-based tool
                // Pen still needs coalesced touches for high-fidelity strokes
                if tool == .eraser {
                    coordinator.handleDrawingTouchMoved(at: location, touch: touch)
                    continue
                }
                
                // Process coalesced touches for smoother strokes (Pen tool)
                if let coalescedTouches = event?.coalescedTouches(for: touch) {
                    for coalescedTouch in coalescedTouches {
                        let coalescedLocation = coalescedTouch.location(in: self)
                        // Pass original touch for identity comparison, coalesced location for drawing
                        coordinator.handleDrawingTouchMoved(at: coalescedLocation, touch: touch)
                    }
                } else {
                    coordinator.handleDrawingTouchMoved(at: location, touch: touch)
                }
            }
            // Handle finger touches for drawing if enabled
            else if touch.type == .direct && coordinator.parent.isFingerDrawingEnabled {
                let tool = coordinator.parent.selectedTool
                if tool == .pen || tool == .eraser {
                    coordinator.handleDrawingTouchMoved(at: location, touch: touch)
                }
            }
        }
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let coordinator = coordinator else { return }
        
        for touch in touches {
            // Handle Apple Pencil touches
            if touch.type == .pencil {
                coordinator.parent.viewModel.isCanvasTouched = false
                coordinator.handleDrawingTouchEnded(touch: touch)
            }
            // Handle finger touches
            else if touch.type == .direct {
                let tool = coordinator.parent.selectedTool
                if tool == .pen || tool == .eraser {
                    coordinator.parent.viewModel.isCanvasTouched = false
                }
                // Handle drawing if enabled
                if coordinator.parent.isFingerDrawingEnabled && (tool == .pen || tool == .eraser) {
                    coordinator.handleDrawingTouchEnded(touch: touch)
                }
            }
        }
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let coordinator = coordinator else { return }
        
        for touch in touches {
            if touch.type == .pencil {
                coordinator.parent.viewModel.isCanvasTouched = false
                coordinator.handleDrawingTouchEnded(touch: touch)
            } else if touch.type == .direct {
                let tool = coordinator.parent.selectedTool
                if tool == .pen || tool == .eraser {
                    coordinator.parent.viewModel.isCanvasTouched = false
                }
                if coordinator.parent.isFingerDrawingEnabled && (tool == .pen || tool == .eraser) {
                    coordinator.handleDrawingTouchEnded(touch: touch)
                }
            }
        }
    }
}

struct CanvasInputView: UIViewRepresentable {
    @ObservedObject var viewModel: CanvasViewModel
    @Binding var selectedTool: ToolbarView.ToolType
    @Binding var isFingerDrawingEnabled: Bool
    
    func makeUIView(context: Context) -> DrawingCanvasView {
        let view = DrawingCanvasView()
        view.coordinator = context.coordinator
        
        // Finger Pan (Scrolling / Selection) - NOT for pencil drawing anymore
        let fingerPan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleFingerPan(_:)))
        fingerPan.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        view.addGestureRecognizer(fingerPan)
        
        // Pinch (Zoom)
        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        view.addGestureRecognizer(pinch)
        
        // Tap (Clear Selection / Add Text)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)
        
        context.coordinator.view = view
        
        return view
    }
    
    func updateUIView(_ uiView: DrawingCanvasView, context: Context) {
        context.coordinator.parent = self
        
        // Update gesture configurations based on settings
        if let gestures = uiView.gestureRecognizers {
            // Finger Pan (Index 0 now - we removed pencil pan gesture)
            if let fingerPan = gestures.first as? UIPanGestureRecognizer {
                if selectedTool == .hand || selectedTool == .select || selectedTool == .text {
                    // Non-drawing tools always pan/select with 1 finger
                    fingerPan.minimumNumberOfTouches = 1
                } else {
                    // Pen or Eraser
                    if isFingerDrawingEnabled {
                        // If finger drawing is enabled, finger pan (scrolling) requires 2 touches
                        fingerPan.minimumNumberOfTouches = 2
                    } else {
                        // Finger drawing disabled: single finger can pan
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
        
        // Track active drawing touch to handle multi-touch scenarios
        private var activeDrawingTouch: UITouch?
        
        init(_ parent: CanvasInputView) {
            self.parent = parent
        }
        
        // MARK: - Direct Touch Handling for Drawing (No Gesture Recognition Delay)
        
        func handleDrawingTouchBegan(at location: CGPoint, touch: UITouch) {
            // Only track one drawing touch at a time
            guard activeDrawingTouch == nil else { return }
            activeDrawingTouch = touch
            
            if parent.selectedTool == .pen {
                parent.viewModel.startStroke(at: location)
            } else if parent.selectedTool == .eraser {
                parent.viewModel.startErasing(at: location)
            } else if parent.selectedTool == .select {
                handleSelectionStart(location: location)
            }
        }
        
        // Store initial touch location for calculating translation
        private var initialTouchLocation: CGPoint?
        
        func handleDrawingTouchMoved(at location: CGPoint, touch: UITouch) {
            // Only process the active drawing touch
            guard touch === activeDrawingTouch else { return }
            
            if parent.selectedTool == .pen {
                parent.viewModel.continueStroke(at: location)
            } else if parent.selectedTool == .eraser {
                parent.viewModel.continueErasing(at: location)
            } else if parent.selectedTool == .select {
                // Handle selection with pencil
                if isMovingSelection {
                    // Calculate translation from initial touch
                    if let initial = initialTouchLocation {
                        let translation = CGSize(
                            width: location.x - initial.x,
                            height: location.y - initial.y
                        )
                        parent.viewModel.moveSelection(translation: translation)
                    }
                } else if parent.viewModel.selectionBox != nil {
                    parent.viewModel.updateSelection(to: location)
                }
            }
        }
        
        func handleDrawingTouchEnded(touch: UITouch) {
            // Only process the active drawing touch
            guard touch === activeDrawingTouch else { return }
            activeDrawingTouch = nil
            initialTouchLocation = nil
            
            if parent.selectedTool == .pen {
                parent.viewModel.endStroke()
            } else if parent.selectedTool == .eraser {
                parent.viewModel.endErasing()
            } else if parent.selectedTool == .select {
                handleSelectionEnd()
            }
        }
        
        // MARK: - Gesture Recognizer Handlers (for non-drawing gestures)
        
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
                    // Only hand tool allows canvas panning
                    parent.viewModel.handleDrag(translation: CGSize(width: translation.x, height: translation.y))
                }
                // Other tools (pen, eraser, text) do NOT pan the canvas
            case .ended, .cancelled:
                if parent.selectedTool == .select {
                    handleSelectionEnd()
                } else if parent.selectedTool == .hand {
                    parent.viewModel.endDrag(translation: CGSize(width: translation.x, height: translation.y))
                }
            default: break
            }
        }
        
        @objc func handlePinch(_ gesture: UIPinchGestureRecognizer) {
            // Only allow pinch zoom when hand tool is selected
            guard parent.selectedTool == .hand else { return }
            guard let view = view else { return }
            let center = gesture.location(in: view)
            
            switch gesture.state {
            case .changed:
                parent.viewModel.handleMagnification(value: gesture.scale, center: center)
            case .ended, .cancelled:
                parent.viewModel.endMagnification(value: gesture.scale, center: center)
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
        

        
        // MARK: - Selection Helpers
        
        private func handleSelectionStart(location: CGPoint) {
            // Store initial location for pencil translation calculation
            initialTouchLocation = location
            
            if parent.viewModel.isPointInSelectedElement(location) {
                isMovingSelection = true
                parent.viewModel.startMovingSelection()
            } else if let elementId = parent.viewModel.findElement(at: location) {
                // Just select it, don't start moving yet
                parent.viewModel.selectElement(id: elementId)
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
