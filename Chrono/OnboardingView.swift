//
//  OnboardingView.swift
//  Chrono
//
//  A lightweight multi-page welcome flow shown on first launch.
//

import SwiftUI

struct OnboardingView: View {
	@State private var currentIndex: Int = 0
	let onFinish: () -> Void
	
	private let pages: [OnboardingPage] = [
		OnboardingPage(
			title: "Welcome to Chrono",
			subtitle: "Your minimal time-tracking companion.",
			systemImage: "center-icon",
			imageName: "center-icon",
			isFullBleed: true
		),
		OnboardingPage(
			title: "Always in Your Menu Bar",
			subtitle: "Track time instantly from the top of your screen. Start, stop or reset with clean and simple controls.",
			systemImage: "window", // use from assets folder
			imageName: "window",
			isFullBleed: true
		),
		OnboardingPage(
			title: "Keyboard Shortcuts",
			subtitle: "Control Chrono without lifting your hands.",
			systemImage: "shortcuts",
			imageName: "shortcuts",
			isFullBleed: true
		),
		OnboardingPage(
			title: "Smart Auto-Pause",
			subtitle: "Chrono pauses when you’re away or your Mac sleeps.",
			systemImage: "notifications",
			imageName: "notifications",
			isFullBleed: true
		),
		OnboardingPage(
			title: "You’re All Set",
			subtitle: "Start tracking your time with Chrono..",
			systemImage: "checkmark.circle.fill",
			imageName: "chrono",
			isFullBleed: true
		),
	]
	
	var body: some View {
		VStack(spacing: 0) {
			TabView(selection: $currentIndex) {
				ForEach(pages.indices, id: \.self) { index in
					OnboardingPageView(
						page: pages[index],
						isFirst: index == 0,
						isLast: index == pages.count - 1,
						onPrevious: {
							if currentIndex > 0 {
								withAnimation { currentIndex -= 1 }
							}
						},
						onNext: {
							if currentIndex < pages.count - 1 {
								withAnimation { currentIndex += 1 }
							} else {
								onFinish()
							}
						}
					)
						.tag(index)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.background(Color.black.opacity(0.96))
				}
			}
			.tabViewStyle(DefaultTabViewStyle())
			#if compiler(>=5.9)
			.scrollIndicators(.hidden)
			#endif
			.padding(.bottom, 16)
			
			// Dots indicator
			HStack(spacing: 8) {
				ForEach(pages.indices, id: \.self) { i in
					Capsule()
						.fill(i == currentIndex ? Color.white : Color.white.opacity(0.3))
						.frame(width: i == currentIndex ? 20 : 8, height: 6)
						.animation(.spring(response: 0.35, dampingFraction: 0.8), value: currentIndex)
				}
			}
			.padding(.bottom, 16)
		}
		.clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
		.background(Color.clear)
		.frame(minWidth: 640, minHeight: 520)
	}
}

private struct OnboardingPage {
	let title: String
	let subtitle: String
	let systemImage: String
	let imageName: String?
	let isFullBleed: Bool
}

private struct OnboardingPageView: View {
	let page: OnboardingPage
	let isFirst: Bool
	let isLast: Bool
	let onPrevious: () -> Void
	let onNext: () -> Void
	
	var body: some View {
		ZStack {
			Color.black.opacity(0.96)
			
			VStack(spacing: 0) {
				// Top visual area fills remaining space
				ZStack {
					Color.black
					OnboardingTopImage(page: page)
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.clipped()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				
				// Bottom info panel with arrows
				ZStack {
					Color(hex: "#1e1e1e")
					HStack(alignment: .center, spacing: 12) {
						CircularArrowButton(systemName: "chevron.left", disabled: isFirst, action: onPrevious)
						VStack(alignment: .leading, spacing: 6) {
							Text(page.title)
								.font(.system(size: 18, weight: .semibold))
								.foregroundColor(.white)
								.multilineTextAlignment(.leading)
							Text(page.subtitle)
								.font(.system(size: 13))
								.foregroundColor(Color.white.opacity(0.8))
								.multilineTextAlignment(.leading)
								.lineLimit(2)
						}
						.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
						.padding(.leading, 60)
						.padding(.top, 24)
						if isLast {
							VStack {
								Spacer()
								Button("Get Started") {
									onNext()
								}
								.buttonStyle(.borderedProminent)
								.controlSize(.large)
								.keyboardShortcut(.defaultAction)
							}
							.frame(maxHeight: .infinity, alignment: .bottom)
							.padding(.bottom, 36)
						} else {
							CircularArrowButton(systemName: "chevron.right", disabled: false, action: onNext)
						}
					}
					.padding(.horizontal, 16)
				}
				.frame(height: 180) // fixed height bottom panel
			}
		}
	}
}

// Small circular chevron button used on the info panel
private struct CircularArrowButton: View {
	let systemName: String
	let disabled: Bool
	let action: () -> Void
	
	var body: some View {
		Button(action: action) {
			Image(systemName: systemName)
				.font(.system(size: 16, weight: .semibold))
				.foregroundColor(.white)
				.frame(width: 30, height: 53)
				.background(
					RoundedRectangle(cornerRadius: 8, style: .continuous)
						.fill(Color.white.opacity(disabled ? 0.15 : 0.25))
				)
		}
		.buttonStyle(.plain)
		.disabled(disabled)
		.opacity(disabled ? 0.4 : 1.0)
	}
}

// Top image renderer that prefers app icon for the first page and assets for others
private struct OnboardingTopImage: View {
	let page: OnboardingPage
	
	var body: some View {
		Group {
			if let name = page.imageName, let nsImage = loadNSImage(named: name) {
					Image(nsImage: nsImage)
						.resizable()
						.interpolation(.high)
						.antialiased(true)
						.scaledToFill()
						.frame(maxWidth: .infinity, maxHeight: .infinity)
						.clipped()
			} else {
				// Fallback to app icon if no page image provided
				Image(nsImage: NSApp.applicationIconImage)
					.resizable()
					.scaledToFill()
					// .frame(maxWidth: .infinity, maxHeight: .infinity)
					.cornerRadius(16)
					.clipped()
			}
		}
	}
	
	private func loadNSImage(named: String) -> NSImage? {
		// 0) Asset catalog name
		if let byName = NSImage(named: named) {
			return byName
		}
		// Try several resource paths inside the app bundle
		if let base = Bundle.main.resourceURL {
			let candidates: [URL] = [
				base.appendingPathComponent("\(named).png"),
				base.appendingPathComponent("assets/\(named).png"),
				base.appendingPathComponent("Chrono/assets/\(named).png")
			]
			for url in candidates {
				if let img = NSImage(contentsOf: url) {
					return img
				}
			}
		}
		// Generic bundle lookup as a fallback
		if let url = Bundle.main.url(forResource: named, withExtension: "png"),
		   let img = NSImage(contentsOf: url) { return img }
		if let url = Bundle.main.url(forResource: "assets/\(named)", withExtension: "png"),
		   let img = NSImage(contentsOf: url) { return img }
		return nil
	}
}

// Hex color convenience
extension Color {
	init(hex: String) {
		let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
		var int: UInt64 = 0
		Scanner(string: hex).scanHexInt64(&int)
		let a, r, g, b: UInt64
		switch hex.count {
		case 3: // RGB (12-bit)
			(a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
		case 6: // RGB (24-bit)
			(a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
		case 8: // ARGB (32-bit)
			(a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
		default:
			(a, r, g, b) = (255, 30, 30, 30) // default to #1e1e1e-ish if parse fails
		}
		self.init(
			.sRGB,
			red: Double(r) / 255,
			green: Double(g) / 255,
			blue: Double(b) / 255,
			opacity: Double(a) / 255
		)
	}
}


