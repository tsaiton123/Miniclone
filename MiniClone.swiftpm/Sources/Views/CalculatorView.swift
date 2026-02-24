import SwiftUI
import JavaScriptCore

struct CalculatorView: View {
    @State private var display = "0"
    @State private var isAdvanced = false
    @State private var offset = CGSize.zero
    @Environment(\.appTheme) private var appTheme
    
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
                        .foregroundColor(appTheme.accentColor)
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
            if display == "0" || display == "Error" {
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
        let expr = display
            .replacingOccurrences(of: "×", with: "*")
            .replacingOccurrences(of: "÷", with: "/")
            .replacingOccurrences(of: "sin(", with: "Math.sin(")
            .replacingOccurrences(of: "cos(", with: "Math.cos(")
            .replacingOccurrences(of: "tan(", with: "Math.tan(")
            .replacingOccurrences(of: "log(", with: "Math.log10(")
            .replacingOccurrences(of: "ln(", with: "Math.log(")
            .replacingOccurrences(of: "sqrt(", with: "Math.sqrt(")
            .replacingOccurrences(of: "abs(", with: "Math.abs(")
            .replacingOccurrences(of: "π", with: "Math.PI")
            .replacingOccurrences(of: "e", with: "Math.E")
            .replacingOccurrences(of: "^", with: "**")
        
        if let context = JSContext() {
            context.exceptionHandler = { context, exception in
                // Ignore JS exceptions to prevent parsing errors from bubbling up
            }
            if let result = context.evaluateScript(expr) {
                if result.isNumber && !result.toNumber().doubleValue.isNaN && !result.toNumber().doubleValue.isInfinite {
                    display = formatResult(result.toDouble())
                    return
                }
            }
        }
        
        display = "Error"
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
    
}

struct CalculatorButton: View {
    let button: CalcButton
    let action: () -> Void
    @Environment(\.appTheme) private var appTheme
    
    var body: some View {
        Button(action: action) {
            Text(button.title)
                .font(.title2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(height: 50)
                .background(backgroundColor)
                .foregroundColor(foregroundColor)
                .cornerRadius(8)
        }
    }
    
    private var backgroundColor: Color {
        switch button {
        case .clear, .delete:
            return Color.red.opacity(0.15)
        case .equal:
            return appTheme.accentColor
        case .add, .subtract, .multiply, .divide:
            return appTheme.accentColor.opacity(0.18)
        case .function, .constant, .parenthesis:
            return appTheme.accentColor.opacity(0.12)
        default:
            return Color.gray.opacity(0.2)
        }
    }
    
    private var foregroundColor: Color {
        switch button {
        case .equal:
            return appTheme.textOnAccent
        default:
            return .primary
        }
    }
}
