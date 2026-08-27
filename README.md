# Sideband iOS SDK

Sideband helps iOS apps collect lightweight in-app feedback pulses and send product events to Sideband.

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

`tagUser` and `track` are fire-and-forget calls. They do not require `Task {}` or `await`.

## SwiftUI Pulse Overlay

Attach the built-in pulse overlay near the root of your SwiftUI app:

```swift
WindowGroup {
	ContentView()
		.sidebandPulseOverlay(using: Client.shared)
}
```

The overlay presents feedback pulses when Sideband has one available for the current user and app context.

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

Install the built-in pulse overlay after your scene has a visible window:

```swift
import Sideband
import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
	var window: UIWindow?
	private var pulseOverlayInstallation: SidebandPulseOverlayInstallation?

	func scene(
		_ scene: UIScene,
		willConnectTo _: UISceneSession,
		options _: UIScene.ConnectionOptions
	) {
		guard let windowScene = scene as? UIWindowScene else { return }

		let window = UIWindow(windowScene: windowScene)
		window.rootViewController = UIViewController()
		self.window = window
		window.makeKeyAndVisible()

		Client.configure(apiKey: "YOUR_API_KEY")
		pulseOverlayInstallation = Client.installPulseOverlay(in: windowScene)
	}

	func sceneDidDisconnect(_: UIScene) {
		pulseOverlayInstallation?.uninstall()
		pulseOverlayInstallation = nil
	}
}
```

If you are installing from a view controller that is already attached to a window, use `Client.installPulseOverlay(on:)`.

## Google Tag Manager

HTML-wrapper apps that load content in a `WKWebView` can forward Google Tag Manager events to Sideband through the `SidebandWebView` bridge.

Add the bridge alongside the core SDK:

- Swift Package Manager: add the `SidebandWebView` product to the app target.
- CocoaPods: use `pod "Sideband/WebView"`, which includes the core SDK.

### 1. Install The Bridge

Install the bridge after configuring Sideband and before the WebView's first `load`.
Pulses continue to appear in the native overlay above the WebView.

```swift
import Sideband
import SidebandWebView

Client.configure(apiKey: "YOUR_API_KEY")
Client.installWebViewBridge(on: webView)
Client.installPulseOverlay(on: viewController)
```

### 2. Forward GTM Events

In Google Tag Manager, create a Custom HTML tag triggered by All Custom Events,
or only by the events Sideband should receive. Skip GTM's built-in `gtm.*` events.

```html
<script>
  (function () {
    var name = {{Event}};
    if (!name || String(name).indexOf('gtm.') === 0) return;
    if (window.Sideband) window.Sideband.track(name);
  })();
</script>
```

To include event properties, create GTM Data Layer variables and pass them as the second argument. Metadata values are sent to Sideband as strings.

```html
<script>
  if (window.Sideband) {
    window.Sideband.track('{{Event}}', {
      value: '{{Value}}'
    });
  }
</script>
```

### 3. Tag The User

Create a Custom HTML tag that runs on login, or on container load when a stable user ID is available:

```html
<script>
  if (window.Sideband && '{{User ID}}') {
    window.Sideband.tagUser('{{User ID}}');
  }
</script>
```

On logout, call `Client.untagUser()` from native code or `window.Sideband.untagUser()` from a GTM tag.

`{{Event}}` is GTM's built-in Event variable. `{{Value}}` and `{{User ID}}` are Data Layer variables supplied by the host app.

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

You can also manage a client instance yourself instead of using the shared client:

```swift
let client = Client(
	configuration: Configuration(apiKey: "YOUR_API_KEY")
)

client.tagUser("user-123")
client.track(event: "button_tapped")
```

### Tag A User

```swift
Client.tagUser("user-123")
```

Use a stable host-app user identifier. Calling this updates the current user context and schedules delivery in the background.

### Track An Event

```swift
Client.track(
	event: "button_tapped",
	metadata: ["button": "subscribe"]
)
```

Metadata values are string key-value pairs.
