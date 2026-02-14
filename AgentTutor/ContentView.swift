//
//  ContentView.swift
//  AgentTutor
//
//  Created by Kai on 2026-02-09.
//

import SwiftUI

enum AppMode {
    case none
    case setupEnvironment
    case configureOpenClaw
}

struct ContentView: View {
    @State private var appMode: AppMode = .none

    var body: some View {
        Group {
            switch appMode {
            case .none:
                ModeSelectorView(onSelect: { mode in
                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                        appMode = mode
                    }
                })
            case .setupEnvironment:
                SetupFlowView()
            case .configureOpenClaw:
                OpenClawConfigView(onBack: {
                    withAnimation(.spring(duration: 0.35, bounce: 0.1)) {
                        appMode = .none
                    }
                })
            }
        }
        .frame(minWidth: 960, minHeight: 680)
    }
}

// MARK: - Mode Selector

private struct ModeCard: Identifiable {
    let id: AppMode
    let icon: String
    let title: String
    let subtitle: String
    let description: String
}

private struct ModeSelectorView: View {
    let onSelect: (AppMode) -> Void

    private let cards: [ModeCard] = [
        ModeCard(
            id: .setupEnvironment,
            icon: "wrench.and.screwdriver",
            title: "Setup Environment",
            subtitle: "Dev Environment",
            description: "Install tools, runtimes, and configure your development environment with guided setup."
        ),
        ModeCard(
            id: .configureOpenClaw,
            icon: "cpu",
            title: "Configure OpenClaw",
            subtitle: "Agent Tools",
            description: "Set up search, browser, skills finder and other tools for your OpenClaw agent."
        ),
    ]

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "graduationcap.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(Color.accentColor)

                Text("AgentTutor")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Choose what you'd like to do")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                ForEach(cards) { card in
                    ModeCardView(card: card) {
                        onSelect(card.id)
                    }
                }
            }
            .padding(.horizontal, 60)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ModeCardView: View {
    let card: ModeCard
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.accentColor.opacity(0.12))
                            .frame(width: 48, height: 48)
                        Image(systemName: card.icon)
                            .font(.system(size: 22))
                            .foregroundStyle(Color.accentColor)
                    }
                    Spacer()
                    Text(card.subtitle)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary)
                        .clipShape(Capsule())
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(card.title)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(card.description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                HStack {
                    Spacer()
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(.quaternary.opacity(isHovered ? 0.8 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(.quaternary.opacity(isHovered ? 1.0 : 0.6), lineWidth: 1)
            )
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 8, y: 4)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

#Preview {
    ContentView()
}
