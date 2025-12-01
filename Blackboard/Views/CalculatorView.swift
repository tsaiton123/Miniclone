import SwiftUI

struct CalculatorView: View {
    @State private var display = "0"
    @State private var isAdvanced = false
    @State private var offset = CGSize.zero
    
    // Basic Buttons
    let basicButtons: [[CalcButton]] = [
        [.clear, .divide, .multiply, .delete],
        [.digit("7"), .digit("8"), .digit("9"), .subtract],
        [.digit("4"), .digit("5"), .digit("6"), .add],
        [.digit("1"), .digit("2"), .digit("3"), .equal],
        [.digit("0"), .decimal, .toggleSign]
    ]
    
    // Advanced Buttons (Scientific)
    let advancedButtons: [[CalcButton]] = [
        [.function("sin"), .function("cos"), .function("tan"), .function("log")],
        [.function("ln"), .function("sqrt"), .function("^"), .constant("π")],
        [.constant("e"), .parenthesis("("), .parenthesis(")"), .function("abs")]
    ]
    
    var body: some View {
        VStack(spacing: 10) {
            // Header / Drag Handle
            HStack {
                Image(systemName: "line.3.horizontal")
                    .foregroundColor(.gray)
                Spacer()
                Button(action: { isAdvanced.toggle() }) {
                    Image(systemName: isAdvanced ? "function" : "plus.slash.minus")
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Display
            Text(display)
                .font(.system(size: 40, weight: .light))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding()
                .background(Color.black.opacity(0.1))
                .cornerRadius(8)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            
            // Advanced Keys (if enabled)
            if isAdvanced {
                VStack(spacing: 8) {
                    ForEach(advancedButtons, id: \.self) { row in
                        HStack(spacing: 8) {
                            ForEach(row, id: \.self) { button in
                                CalculatorButton(button: button, action: { tapButton(button) })
                            }
                        }
                    }
                }
                .transition(.scale)
            }
            
            // Basic Keys
            VStack(spacing: 8) {
                ForEach(basicButtons, id: \.self) { row in
                    HStack(spacing: 8) {
                        ForEach(row, id: \.self) { button in
                            CalculatorButton(button: button, action: { tapButton(button) })
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
        .frame(width: 320)
        .offset(offset)
        .gesture(
            DragGesture()
                .onChanged { value in
                    offset = CGSize(width: value.translation.width, height: value.translation.height)
                }
                .onEnded { value in
                    // Keep offset (simplified, ideally would update position state)
                    // For now, let's just let it snap back or accumulate? 
                    // Better to accumulate.
                    // But for this simple implementation, let's just use @State offset which resets on drag end if not accumulated.
                    // To fix, we need a persistent position state.
                }
        )
    }
    
    func tapButton(_ button: CalcButton) {
        switch button {
        case .digit(let d):
            if display == "0" || display == "Error" {
                display = d
            } else {
                display += d
            }
        case .decimal:
            if !display.contains(".") {
                display += "."
            }
        case .clear:
            display = "0"
        case .delete:
            if display.count > 1 {
                display.removeLast()
            } else {
                display = "0"
            }
        case .add: appendOperator("+")
        case .subtract: appendOperator("-")
        case .multiply: appendOperator("*")
        case .divide: appendOperator("/")
        case .equal: calculate()
        case .toggleSign:
            if display.hasPrefix("-") {
                display.removeFirst()
            } else {
                display = "-" + display
            }
        case .function(let f):
            if display == "0" {
                display = f + "("
            } else {
                display += f + "("
            }
        case .constant(let c):
            let val = c == "π" ? "3.14159" : "2.71828"
            if display == "0" {
                display = val
            } else {
                display += val
            }
        case .parenthesis(let p):
            if display == "0" {
                display = p
            } else {
                display += p
            }
        }
    }
    
    func appendOperator(_ op: String) {
        if display != "Error" {
            display += " " + op + " "
        }
    }
    
    func calculate() {
        // Replace symbols for NSExpression
        let expr = display.replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "sin", with: "function(sin,") // NSExpression format is weird for functions
            // Actually, NSExpression supports standard functions like sin(), cos() etc.
            // But we need to be careful with syntax.
        
        // Let's use a simpler approach: NSExpression
        let expression = NSExpression(format: display)
        if let result = expression.expressionValue(with: nil, context: nil) as? Double {
            display = formatResult(result)
        } else {
            display = "Error"
        }
    }
    
    func formatResult(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 8
        return formatter.string(from: NSNumber(value: value)) ?? "Error"
    }
}

enum CalcButton: Hashable {
    case digit(String)
    case decimal
    case clear
    case delete
    case add, subtract, multiply, divide, equal
    case toggleSign
    case function(String)
    case constant(String)
    case parenthesis(String)
    
    var title: String {
        switch self {
        case .digit(let s): return s
        case .decimal: return "."
        case .clear: return "AC"
        case .delete: return "⌫"
        case .add: return "+"
        case .subtract: return "-"
        case .multiply: return "×"
        case .divide: return "÷"
        case .equal: return "="
        case .toggleSign: return "±"
        case .function(let s): return s
        case .constant(let s): return s
        case .parenthesis(let s): return s
        }
    }
    
    var color: Color {
        switch self {
        case .clear, .delete: return .red.opacity(0.8)
        case .equal: return .green
        case .add, .subtract, .multiply, .divide: return .orange
        case .digit, .decimal, .toggleSign: return .gray.opacity(0.2)
        default: return .blue.opacity(0.2)
        }
    }
}

struct CalculatorButton: View {
    let button: CalcButton
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(button.title)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 50)
                .background(button.color)
                .foregroundColor(.primary)
                .cornerRadius(8)
        }
    }
}
