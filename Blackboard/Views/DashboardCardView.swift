import SwiftUI

struct DashboardCardView: View {
    let title: String
    let description: String
    let icon: String?
    let backgroundColor: Color
    let buttonText: String
    let action: () -> Void
    
    // Derived property for text color based on background luminance roughly
    // For now, simpler logic: check if color is black or very dark
    var isDarkBackground: Bool {
        // Quick hack: assume blue/black are dark, white/gray are light
        backgroundColor == .black || backgroundColor == .blue
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            Text(title)
                .font(.system(size: 32, weight: .regular))
                .foregroundColor(isDarkBackground ? .white : .black)
                .padding(.top, 20)
            
            Text(description)
                .font(.body)
                .foregroundColor(isDarkBackground ? .gray : .secondary)
                .padding(.top, 5)
                .padding(.bottom, 20)
            
            Spacer()
            
            Button(action: action) {
                HStack {
                    Text(buttonText)
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .padding()
                .background(isDarkBackground ? Color.blue : Color.white)
                .foregroundColor(isDarkBackground ? .white : .blue)
                .border(isDarkBackground ? Color.clear : Color.blue.opacity(0.3), width: 1)
            }
            .frame(width: 180)
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: 250, alignment: .leading)
        .background(backgroundColor)
    }
}
