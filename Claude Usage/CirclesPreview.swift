import SwiftUI

#if DEBUG
struct CirclesPreview: View {
    @State private var sessionProgress: Double = 0.69
    @State private var sonnetProgress: Double = 0.33
    @State private var allModelsProgress: Double = 0.42
    @State private var sessionTime: Double = 0.42
    @State private var sonnetTime: Double = 0.60
    @State private var allModelsTime: Double = 0.55

    var body: some View {
        VStack(spacing: 20) {
            let input = CircleRendererInput(
                sessionProgress: sessionProgress,
                sonnetProgress: sonnetProgress,
                allModelsProgress: allModelsProgress,
                sessionTimeProgress: sessionTime,
                sonnetTimeProgress: sonnetTime,
                allModelsTimeProgress: allModelsTime
            )
            Image(nsImage: ConcentricCirclesRenderer.renderLargeView(input: input, size: 240))
                .frame(width: 240, height: 240)

            VStack(spacing: 12) {
                sliderRow("Session Usage", value: $sessionProgress)
                sliderRow("Session Time", value: $sessionTime)
                Divider()
                sliderRow("Sonnet Usage", value: $sonnetProgress)
                sliderRow("Sonnet Time", value: $sonnetTime)
                Divider()
                sliderRow("All Models Usage", value: $allModelsProgress)
                sliderRow("All Models Time", value: $allModelsTime)
            }
            .padding(.horizontal)
        }
        .padding()
        .frame(width: 380)
    }

    private func sliderRow(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .frame(width: 120, alignment: .leading)
            Slider(value: value, in: 0...1)
            Text(String(format: "%.0f%%", value.wrappedValue * 100))
                .font(.caption.monospacedDigit())
                .frame(width: 36, alignment: .trailing)
        }
    }
}

#Preview {
    CirclesPreview()
}
#endif
