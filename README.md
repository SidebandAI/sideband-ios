# Sideband iOS SDK

Sideband helps iOS apps collect lightweight in-app feedback pulses and send product events to Sideband.

## Get Started

### Requirements

- iOS 15+
- Swift Package Manager or CocoaPods
- A Sideband API key

### Install

In Xcode, add this package URL:

```text
https://github.com/SidebandAI/sideband-ios
```

Then add the `Sideband` product to your app target.

With CocoaPods, add the same release to your `Podfile`:

```ruby
pod "Sideband"
```

### Configure

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

For more control over the app context, pass a `Configuration`:

```swift
Client.configure(
	configuration: Configuration(
		apiKey: "YOUR_API_KEY",
		appVersion: "1.0.0"
	)
)
```

You can also manage a client instance instead of using the shared client:

```swift
let client = Client(
	configuration: Configuration(apiKey: "YOUR_API_KEY")
)

client.tagUser("user-123")
client.track(event: "button_tapped")
```

### Present Pulses

#### SwiftUI

Attach the built-in pulse overlay near the root of your app:

```swift
WindowGroup {
	ContentView()
		.sidebandPulseOverlay(using: Client.shared)
}
```

The overlay presents feedback pulses when Sideband has one available for the current user and app context.

#### UIKit

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

### Identify Users and Track Events

Use a stable host-app user identifier, then track the events Sideband should use for targeting:

```swift
Client.tagUser("user-123")

Client.track(
	event: "session_started",
	metadata: ["source": "home"]
)
```

Metadata values are string key-value pairs. `tagUser` and `track` are fire-and-forget calls, so they do not require `Task {}` or `await`. Tagged user IDs may contain up to 256 characters. Longer IDs are rejected without changing the current in-memory or persisted identity or scheduling sync.

Sideband retains the tagged user ID until you replace it or clear it on logout:

```swift
Client.untagUser()
```

### Event Metadata and Pulse Targeting

Pass metadata to `track` as string key-value pairs. Use metadata to describe an
event without creating a separate event name for each source, item type, or mode.
Only these six keys support Pulse trigger filters and event-history conditions:

| Key | Value format | Example |
| --- | --- | --- |
| `source` | String | `"home"` |
| `item_type` | String | `"article"` |
| `mode` | String | `"manual"` |
| `variant` | String | `"control"` |
| `count` | Integer sent as a string | `"3"` |
| `duration` | Seconds sent as a string; fractions allowed | `"12.5"` |

Use the exact lowercase key names. The server trims and lowercases values for
`source`, `item_type`, `mode`, and `variant`. These keys support equals and
not-equals comparisons. It compares `count` and `duration` numerically, with
equals, not-equals, greater-than, greater-than-or-equal, less-than, and
less-than-or-equal comparisons. Send `duration` in seconds, not milliseconds.

```swift
Client.track(
	event: "content_created",
	metadata: [
		"source": "editor",
		"item_type": "article",
		"count": "3",
		"duration": "12.5",
		"content_id": "article-123",
	],
)
```

Custom keys such as `content_id`, `screen`, or `plan` are stored unchanged, but
cannot be used in Pulse targeting filters. A missing key does not match any
filter, including not-equals.

The server stores at most 20 metadata properties per event. It keeps valid
targeting keys first, then fills the remaining slots with custom keys in sorted
key order. It drops empty keys and invalid targeting values without rejecting
the event. For example, `count: "3.5"` and `count: "3.0"` are invalid; use
`count: "3"`. Normalization and numeric comparison happen on the server, not in
the SDK. These rules also apply to events sent through the WebView/GTM bridge.

### Control Pulse Presentation

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

## WebView Integration

Use the `SidebandWebView` bridge when your app loads product content in a `WKWebView`. The bridge exposes `window.Sideband` to the page while the API key, event delivery, and pulse UI remain native.

### Add WebView Support

- Swift Package Manager: add the `SidebandWebView` product to the app target.
- CocoaPods: use `pod "Sideband/WebView"`, which includes the core SDK.

The bridge is not part of `Sideband.xcframework`. It ships as source on the same public release tag.

### Install the Bridge and Pulse Overlay

Configure Sideband, install the bridge before the WebView's first `load`, and install the native pulse overlay:

```swift
import Sideband
import SidebandWebView

Client.configure(apiKey: "YOUR_API_KEY")
try Client.installWebViewBridge(
	on: webView,
	allowedOrigins: ["https://app.example.com"]
)
Client.installPulseOverlay(on: viewController)
```

At least one allowed origin is required. Each entry must be an exact `http` or `https` origin with a scheme and host, plus an optional port. Do not include wildcards, credentials, a non-root path, query, or fragment. Bridge messages are accepted only from the main frame when its native origin exactly matches one of these entries.

Pulses appear in the native overlay above the WebView.

### Use the JavaScript API

After the bridge is installed, code in the page can identify users and track events:

```javascript
window.Sideband.tagUser("user-123")
window.Sideband.track("checkout_started", { plan: "pro" })
```

Clear the identity when the user logs out:

```javascript
window.Sideband.untagUser()
```

Metadata scalar values are converted to strings. Nested values are ignored.

To customize the handler name, injected JavaScript, or payload parsing, copy `Sources/SidebandWebView/` into the host app and stop depending on the product or subspec.

## Google Tag Manager

Complete the WebView integration first. Google Tag Manager can then call the same `window.Sideband` API without requiring a new app release for each tracked event.

### Forward Events

In Google Tag Manager, create a Custom HTML tag triggered by All Custom Events, or only by the events Sideband should receive. Skip GTM's built-in `gtm.*` events.

```html
<script>
  (function () {
    var name = {{Event}};
    if (!name || String(name).indexOf('gtm.') === 0) return;
    if (window.Sideband) window.Sideband.track(name);
  })();
</script>
```

`{{Event}}` is GTM's built-in Event variable.

### Forward Event Metadata

Create GTM Data Layer variables for the properties you want to send, then pass them as the second argument. Metadata scalar values are sent to Sideband as strings.

```html
<script>
  if (window.Sideband) {
    window.Sideband.track('{{Event}}', {
      value: '{{Value}}'
    });
  }
</script>
```

`{{Value}}` is a Data Layer variable supplied by the host app.

### Identify Users

Create a Custom HTML tag that runs on login, or on container load when a stable user ID is available:

```html
<script>
  if (window.Sideband && '{{User ID}}') {
    window.Sideband.tagUser('{{User ID}}');
  }
</script>
```

`{{User ID}}` is a Data Layer variable supplied by the host app. On logout, call `Client.untagUser()` from native code or `window.Sideband.untagUser()` from a GTM tag.
