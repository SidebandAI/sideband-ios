# Sideband iOS SDK

Sideband helps iOS apps collect lightweight in-app feedback pulses and send simple product events to Sideband.

## Requirements

- iOS 15+
- Swift Package Manager
- A Sideband API key

## Installation

In Xcode, add this package URL:

```text
https://github.com/SidebandAI/sideband-ios
```

Then add the `Sideband` product to your app target.

## Quick Start

Configure Sideband once during app startup:

```swift
import Sideband

@main
struct MyApp: App {
	init() {
		Client.configure(apiKey: "YOUR_API_KEY")
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
		}
	}
}
```

Then call Sideband from anywhere in your app:

```swift
Client.tagUser("user-123")

Client.track(
	event: "session_started",
	metadata: ["source": "home"]
)

```

`tagUser`, `track`, and `flush` are fire-and-forget calls. They do not require `Task {}` or `await`.

## SwiftUI Pulse Overlay

Attach the built-in pulse overlay near the root of your SwiftUI app:

```swift
WindowGroup {
	ContentView()
		.sidebandPulseOverlay(using: Client.shared)
}
```

The overlay presents feedback pulses when Sideband returns one from sync.

### Customize The FAB

When a pulse is configured to start as a floating action button, pass a `SidebandFABStyle` to customize the built-in trigger:

```swift
WindowGroup {
	ContentView()
		.sidebandPulseOverlay(
			using: Client.shared,
			fabStyle: SidebandFABStyle(
				icon: Image(systemName: "clock.badge.questionmark.fill"),
				foregroundColor: .white,
				backgroundColor: .black
			)
		)
}
```

`SidebandFABStyle` supports an optional SwiftUI `Image`, a foreground color for the label, countdown ring, and default glyph, and a background color for the expanded capsule and condensed circle. The FAB title and timing still come from Sideband; `fabStyle` only controls the visual styling.

## Presentation Gating

Use a delegate when you need to decide whether a pulse should appear now:

```swift
final class PulseGate: ClientDelegate {
	@MainActor
	func clientShouldPresentPulse(_ pulse: PendingPulse) async -> PulsePresentationDecision {
		.showNow
	}
}
```

Configure Sideband with the delegate:

```swift
Client.configure(
	apiKey: "YOUR_API_KEY",
	delegate: PulseGate()
)
```

Return `.showNow` to present immediately, `.notNow` to skip this opportunity, or `.never` to decline the pulse permanently.

## UIKit Apps

UIKit apps can use the shared host API directly:

```swift
Client.configure(apiKey: "YOUR_API_KEY")
Client.tagUser("user-123")
Client.track(event: "checkout_started")
```

The built-in pulse UI is currently exposed as a SwiftUI overlay. A first-class UIKit pulse controller is planned.

## API Reference

### Configure

```swift
Client.configure(apiKey: "YOUR_API_KEY")
```

```swift
Client.configure(
	configuration: Configuration(
		apiKey: "YOUR_API_KEY",
		appVersion: "1.0.0",
		locale: "en_US"
	)
)
```

### Tag A User

```swift
Client.tagUser("user-123")
```

Use a stable host-app user identifier. Calling this updates sync context and requests a background sync.

### Track An Event

```swift
Client.track(
	event: "button_tapped",
	metadata: ["button": "subscribe"]
)
```

Metadata values are string key-value pairs.
