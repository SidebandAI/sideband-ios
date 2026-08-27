// Default WKWebView bridge for HTML-wrapper apps that track with Google Tag Manager.
//
// This module is not part of Sideband.xcframework. Use the SidebandWebView product as-is, or copy these
// files into the host app and edit them. Keep this file and SidebandWebViewBridgeMessage.swift together.
//
// Customization points:
// - handlerName: WKScriptMessageHandler name and window.webkit.messageHandlers.<name>
// - javaScriptSource: injected window.Sideband API (tagUser / untagUser / track)
// - SidebandWebViewBridgeMessage.parse: accepted payload shape and metadata coercion
// - handle(_:): main-frame-only filter and routing into Client.tagUser / untagUser / track
//
// The GTM Custom HTML tags in the README must keep using the same window.Sideband methods.

#if os(iOS)
	import Foundation
	import Sideband
	import WebKit

	/// Handle for a WKWebView JavaScript bridge installation.
	public final class SidebandWebViewBridgeInstallation {
		private let uninstallHandler: @MainActor () -> Void

		@MainActor
		init(uninstallHandler: @escaping @MainActor () -> Void) {
			self.uninstallHandler = uninstallHandler
		}

		/// Removes the script message handler from the WebView.
		///
		/// Injected `window.Sideband` user scripts remain until the WebView or its user content controller is rebuilt.
		@MainActor
		public func uninstall() {
			uninstallHandler()
		}
	}

	extension Client {
		/// Installs a JavaScript bridge that forwards `window.Sideband` calls from a `WKWebView` into this client.
		///
		/// Call this before the WebView's first `load` so the bridge is present when Google Tag Manager starts. If the
		/// current page is already loaded, the SDK also injects `window.Sideband` immediately.
		///
		/// The returned handle can be used to remove the script message handler during teardown. The bridge retains the
		/// installation, so host apps do not need to retain the handle just to keep the bridge active.
		///
		/// - Parameter webView: Host `WKWebView` that loads the HTML wrapper.
		/// - Returns: Bridge installation handle.
		@discardableResult
		@MainActor
		public func installWebViewBridge(on webView: WKWebView) -> SidebandWebViewBridgeInstallation {
			let webViewIdentifier = ObjectIdentifier(webView)
			if let existingInstallation = WebViewBridgeStore.installations[webViewIdentifier], existingInstallation.isInstalled {
				return existingInstallation.handle
			}

			let installation = WebViewBridgeInstallation(webView: webView, client: self)
			WebViewBridgeStore.installations[webViewIdentifier] = installation
			return installation.handle
		}

		/// Installs a JavaScript bridge that forwards `window.Sideband` calls from a `WKWebView` into the shared client.
		///
		/// Call `configure(...)` before installing the bridge, and call this before the WebView's first `load`.
		///
		/// - Parameter webView: Host `WKWebView` that loads the HTML wrapper.
		/// - Returns: Bridge installation handle, or `nil` if the shared client has not been configured.
		@discardableResult
		@MainActor
		public static func installWebViewBridge(on webView: WKWebView) -> SidebandWebViewBridgeInstallation? {
			guard let client = Client.shared else {
				NSLog("[Sideband] ERROR: %@", "Client.installWebViewBridge(on:) called before Client.configure(...).")
				return nil
			}

			return client.installWebViewBridge(on: webView)
		}
	}

	@MainActor
	enum WebViewBridgeStore {
		static var installations: [ObjectIdentifier: WebViewBridgeInstallation] = [:]

		static func reset() {
			for installation in Array(installations.values) {
				installation.uninstall()
			}
		}
	}

	@MainActor
	final class WebViewBridgeInstallation {
		static let handlerName = "sideband"

		static var javaScriptSource: String {
			#"""
			(() => {
				if (window.Sideband) return;
				const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.\#(handlerName);
				if (!handler) return;
				const post = (payload) => handler.postMessage(payload);
				window.Sideband = {
					tagUser: (userID) => {
						if (userID == null) return;
						post({ action: "tagUser", userID: String(userID) });
					},
					untagUser: () => post({ action: "untagUser" }),
					track: (name, metadata) => {
						if (name == null || String(name).trim() === "") return;
						post({
							action: "track",
							name: String(name),
							metadata: metadata && typeof metadata === "object" ? metadata : {}
						});
					}
				};
			})();
			"""#
		}

		let webViewIdentifier: ObjectIdentifier
		private weak var client: Client?
		private weak var webView: WKWebView?
		private let handler: WeakWebViewBridgeScriptMessageHandler
		private var isUninstalled = false

		lazy var handle = SidebandWebViewBridgeInstallation { [weak self] in
			self?.uninstall()
		}

		var isInstalled: Bool {
			!isUninstalled && webView != nil && client != nil
		}

		init(webView: WKWebView, client: Client) {
			webViewIdentifier = ObjectIdentifier(webView)
			self.webView = webView
			self.client = client
			handler = WeakWebViewBridgeScriptMessageHandler()
			handler.installation = self
			install(on: webView)
		}

		func handle(_ message: WKScriptMessage) {
			guard message.name == Self.handlerName else { return }
			guard message.frameInfo.isMainFrame else { return }
			guard let action = WebViewBridgeMessage.parse(message.body) else { return }
			apply(action)
		}

		func uninstall() {
			guard !isUninstalled else { return }
			isUninstalled = true
			webView?.configuration.userContentController.removeScriptMessageHandler(
				forName: Self.handlerName,
				contentWorld: .page
			)
			WebViewBridgeStore.installations[webViewIdentifier] = nil
			client = nil
			webView = nil
		}

		private func install(on webView: WKWebView) {
			let controller = webView.configuration.userContentController
			controller.removeScriptMessageHandler(forName: Self.handlerName, contentWorld: .page)
			controller.add(handler, contentWorld: .page, name: Self.handlerName)

			if !controller.userScripts.contains(where: { $0.source == Self.javaScriptSource }) {
				controller.addUserScript(
					WKUserScript(
						source: Self.javaScriptSource,
						injectionTime: .atDocumentStart,
						forMainFrameOnly: true,
						in: .page
					)
				)
			}

			webView.evaluateJavaScript(Self.javaScriptSource, in: nil, in: .page) { _, _ in }
		}

		private func apply(_ action: WebViewBridgeAction) {
			switch action {
			case .tagUser(let userID):
				client?.tagUser(userID)
			case .untagUser:
				client?.untagUser()
			case .track(let name, let metadata):
				client?.track(event: name, metadata: metadata)
			}
		}
	}

	private final class WeakWebViewBridgeScriptMessageHandler: NSObject, WKScriptMessageHandler {
		weak var installation: WebViewBridgeInstallation?

		func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
			guard let installation else { return }
			Task { @MainActor in
				installation.handle(message)
			}
		}
	}
#endif
