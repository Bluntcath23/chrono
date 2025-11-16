import SwiftUI

struct LiveActivityView: View {
    @ObservedObject var viewModel: TimerViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                // Avatar placeholder
                Circle()
                    .fill(Color.gray.opacity(0.5))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "person.crop.circle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 32, height: 32)
                            .foregroundColor(.white.opacity(0.7))
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("Chrono")
                        .font(.headline)
                    Text(viewModel.isRunning ? "Timer Running" : "Timer Stopped")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                // Big timer
                Text(viewModel.formattedTimeForPopover())
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
            // Progress bar (simulated for now)
            ProgressView(value: min(viewModel.elapsed / 60, 1.0))
                .progressViewStyle(LinearProgressViewStyle(tint: .accentColor))
                .frame(height: 8)
                .padding(.bottom, 2)
            // Last row: subtitle
            Text("Session will pause after inactivity.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: Color.black.opacity(0.18), radius: 24, x: 0, y: 8)
        )
        .frame(width: 370)
    }
}

#Preview {
    LiveActivityView(viewModel: TimerViewModel())
}
