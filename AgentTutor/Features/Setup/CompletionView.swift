import SwiftUI

struct CompletionView: View {
    @ObservedObject var viewModel: SetupViewModel
    @State private var showTitle = false
    @State private var showStats = false
    @State private var showWhatsNext = false
    @State private var showActionButtons = false

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                Spacer()

                AnimatedCheckmark()

                VStack(spacing: 8) {
                    Text("Setup Complete!")
                        .font(.title)
                        .fontWeight(.bold)
                    Text("Your development environment is ready.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
                .opacity(showTitle ? 1 : 0)
                .offset(y: showTitle ? 0 : 12)

                HStack(spacing: 32) {
                    VStack(spacing: 4) {
                        Text("\(viewModel.successfulStepCount)")
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Components Installed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        Text(viewModel.installDurationFormatted)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text("Total Time")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(16)
                .background(.quaternary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .opacity(showStats ? 1 : 0)
                .offset(y: showStats ? 0 : 15)

                VStack(alignment: .leading, spacing: 8) {
                    Text("What's Next")
                        .font(.headline)

                    Label("Open a terminal and start coding", systemImage: "terminal")
                        .font(.subheadline)
                    Label("Check installed tool versions with your package manager", systemImage: "shippingbox")
                        .font(.subheadline)
                    Label("Review the diagnostic log for details", systemImage: "doc.text.magnifyingglass")
                        .font(.subheadline)
                }
                .frame(maxWidth: 400, alignment: .leading)
                .opacity(showWhatsNext ? 1 : 0)
                .offset(y: showWhatsNext ? 0 : 15)

                if shouldShowActionButtons {
                    HStack(spacing: 12) {
                        if viewModel.shouldShowOpenClawDashboardButton {
                            Button("Open OpenClaw Dashboard") {
                                viewModel.openOpenClawDashboard()
                            }
                            .buttonStyle(.borderedProminent)
                        }

                        if viewModel.shouldShowCompletionLogFolderButton {
                            Button("Open Log Folder") {
                                viewModel.openLogFolder()
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .opacity(showActionButtons ? 1 : 0)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ConfettiView()
                .allowsHitTesting(false)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.5)) {
                showTitle = true
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(0.9)) {
                showStats = true
            }
            withAnimation(.spring(duration: 0.5, bounce: 0.15).delay(1.2)) {
                showWhatsNext = true
            }
            if shouldShowActionButtons {
                withAnimation(.spring(duration: 0.3, bounce: 0.1).delay(1.5)) {
                    showActionButtons = true
                }
            } else {
                showActionButtons = false
            }
        }
    }

    private var shouldShowActionButtons: Bool {
        viewModel.shouldShowCompletionLogFolderButton || viewModel.shouldShowOpenClawDashboardButton
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height
        path.move(to: CGPoint(x: w * 0.15, y: h * 0.5))
        path.addLine(to: CGPoint(x: w * 0.4, y: h * 0.75))
        path.addLine(to: CGPoint(x: w * 0.85, y: h * 0.25))
        return path
    }
}

private struct AnimatedCheckmark: View {
    @State private var circleScale: CGFloat = 0
    @State private var checkmarkTrim: CGFloat = 0
    @State private var glowScale: CGFloat = 0.8
    @State private var glowOpacity: CGFloat = 0

    var body: some View {
        ZStack {
            Circle()
                .stroke(.green.opacity(0.15), lineWidth: 6)
                .frame(width: 88, height: 88)
                .scaleEffect(glowScale)
                .opacity(glowOpacity)

            Circle()
                .fill(.green.gradient)
                .frame(width: 76, height: 76)
                .scaleEffect(circleScale)
                .shadow(color: .green.opacity(0.25), radius: 12, y: 4)

            CheckmarkShape()
                .trim(from: 0, to: checkmarkTrim)
                .stroke(.white, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .frame(width: 32, height: 32)
        }
        .onAppear {
            withAnimation(.spring(duration: 0.6, bounce: 0.35)) {
                circleScale = 1
            }
            withAnimation(.easeInOut(duration: 0.35).delay(0.35)) {
                checkmarkTrim = 1
            }
            withAnimation(.easeOut(duration: 0.8).delay(0.5)) {
                glowScale = 1.2
                glowOpacity = 1
            }
        }
    }
}

private struct ConfettiPieceData: Identifiable {
    let id: Int
    let color: Color
    let startX: CGFloat
    let startY: CGFloat
    let endX: CGFloat
    let endY: CGFloat
    let endRotation: Double
    let width: CGFloat
    let height: CGFloat
    let delay: Double
    let duration: Double

    static let colors: [Color] = [.red, .blue, .green, .yellow, .orange, .pink, .purple, .mint, .cyan]

    init(index: Int) {
        self.id = index
        self.color = Self.colors[index % Self.colors.count]
        self.startX = CGFloat.random(in: -25...25)
        self.startY = CGFloat.random(in: -180...(-80))
        self.endX = CGFloat.random(in: -300...300)
        self.endY = CGFloat.random(in: 150...500)
        self.endRotation = Double.random(in: -360...360)
        self.width = CGFloat.random(in: 4...8)
        self.height = CGFloat.random(in: 8...14)
        self.delay = Double.random(in: 0...0.6)
        self.duration = Double.random(in: 2.5...4)
    }
}

private struct ConfettiView: View {
    @State private var pieces: [ConfettiPieceData] = (0..<60).map { ConfettiPieceData(index: $0) }
    @State private var animate = false

    var body: some View {
        ZStack {
            ForEach(pieces) { piece in
                RoundedRectangle(cornerRadius: 2)
                    .fill(piece.color)
                    .frame(width: piece.width, height: piece.height)
                    .offset(
                        x: animate ? piece.endX : piece.startX,
                        y: animate ? piece.endY : piece.startY
                    )
                    .rotationEffect(.degrees(animate ? piece.endRotation : 0))
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: piece.duration).delay(piece.delay),
                        value: animate
                    )
            }
        }
        .drawingGroup()
        .onAppear {
            animate = true
        }
    }
}
