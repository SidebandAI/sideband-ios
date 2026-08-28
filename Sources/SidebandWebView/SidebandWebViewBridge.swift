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

	/// Errors that prevent the WebView bridge from being installed securely.
	public enum SidebandWebViewBridgeError: Error, Equatable, Sendable {
		/// At least one allowed origin is required.
		case allowedOriginsRequired
		/// An allowed origin was not an exact HTTP or HTTPS origin.
		case invalidAllowedOrigin(String)
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
		/// Allowed origins must include an `http` or `https` scheme and host, may include a port, and must not include
		/// credentials, a non-root path, query, fragment, or wildcard.
		///
		/// - Parameters:
		///   - webView: Host `WKWebView` that loads the HTML wrapper.
		///   - allowedOrigins: Exact origins permitted to send bridge messages, such as `https://app.example.com`.
		/// - Returns: Bridge installation handle.
		/// - Throws: `SidebandWebViewBridgeError` when no valid allowed origins are supplied.
		@discardableResult
		@MainActor
		public func installWebViewBridge(
			on webView: WKWebView,
			allowedOrigins: [String]
		) throws -> SidebandWebViewBridgeInstallation {
			let allowedOrigins = try WebViewBridgeOrigin.validate(allowedOrigins)
			let webViewIdentifier = ObjectIdentifier(webView)
			let existingInstallation = WebViewBridgeStore.installations[webViewIdentifier]
			if let existingInstallation, existingInstallation.matches(client: self, allowedOrigins: allowedOrigins) {
				return existingInstallation.handle
			}

			WebViewBridgeStore.installations[webViewIdentifier]?.uninstall()
			let installation = WebViewBridgeInstallation(webView: webView, client: self, allowedOrigins: allowedOrigins)
			WebViewBridgeStore.installations[webViewIdentifier] = installation
			return installation.handle
		}

		/// Installs a JavaScript bridge that forwards `window.Sideband` calls from a `WKWebView` into the shared client.
		///
		/// Call `configure(...)` before installing the bridge, and call this before the WebView's first `load`.
		///
		/// Allowed origins must include an `http` or `https` scheme and host, may include a port, and must not include
		/// credentials, a non-root path, query, fragment, or wildcard.
		///
		/// - Parameters:
		///   - webView: Host `WKWebView` that loads the HTML wrapper.
		///   - allowedOrigins: Exact origins permitted to send bridge messages, such as `https://app.example.com`.
		/// - Returns: Bridge installation handle, or `nil` if the shared client has not been configured.
		/// - Throws: `SidebandWebViewBridgeError` when no valid allowed origins are supplied.
		@discardableResult
		@MainActor
		public static func installWebViewBridge(
			on webView: WKWebView,
			allowedOrigins: [String]
		) throws -> SidebandWebViewBridgeInstallation? {
			let allowedOrigins = try WebViewBridgeOrigin.validate(allowedOrigins)
			guard Client.shared != nil else {
				NSLog(
					"[Sideband] ERROR: %@",
					"Client.installWebViewBridge(on:allowedOrigins:) called before Client.configure(...)."
				)
				return nil
			}

			let webViewIdentifier = ObjectIdentifier(webView)
			let existingInstallation = WebViewBridgeStore.installations[webViewIdentifier]
			if let existingInstallation, existingInstallation.matchesShared(allowedOrigins: allowedOrigins) {
				return existingInstallation.handle
			}

			WebViewBridgeStore.installations[webViewIdentifier]?.uninstall()
			let installation = WebViewBridgeInstallation(webView: webView, allowedOrigins: allowedOrigins)
			WebViewBridgeStore.installations[webViewIdentifier] = installation
			return installation.handle
		}
	}

	private struct WebViewBridgeOrigin: Hashable {
		let scheme: String
		let host: String
		let port: Int

		static func validate(_ values: [String]) throws -> Set<Self> {
			guard !values.isEmpty else {
				throw SidebandWebViewBridgeError.allowedOriginsRequired
			}

			return try Set(
				values.map { value in
					guard let origin = Self(allowedOrigin: value) else {
						throw SidebandWebViewBridgeError.invalidAllowedOrigin(value)
					}
					return origin
				}
			)
		}

		init?(allowedOrigin value: String) {
			guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
				let components = URLComponents(string: value),
				Self.hasValidAuthority(value, components: components),
				let scheme = components.scheme?.lowercased(),
				Self.allowedSchemes.contains(scheme),
				let parsedHost = components.host,
				let host = (parsedHost.hasPrefix("[") ? parsedHost : components.url?.host)?.lowercased(),
				!host.isEmpty,
				!host.contains("*"),
				components.user == nil,
				components.password == nil,
				components.path.isEmpty || components.path == "/",
				components.query == nil,
				components.fragment == nil
			else {
				return nil
			}

			self.scheme = scheme
			self.host = host
			port = components.port ?? Self.defaultPort(for: scheme)
		}

		init?(sourceProtocol: String, host: String, port: Int) {
			let scheme = sourceProtocol.lowercased()
			let host = host.lowercased()
			guard
				Self.allowedSchemes.contains(scheme),
				!host.isEmpty,
				port == 0 || (1...65535).contains(port)
			else {
				return nil
			}

			self.scheme = scheme
			self.host = host
			self.port = port == 0 ? Self.defaultPort(for: scheme) : port
		}

		private static let allowedSchemes: Set<String> = ["http", "https"]

		private static func hasValidAuthority(_ value: String, components: URLComponents) -> Bool {
			guard let separator = value.range(of: "://") else { return false }
			var authority = String(value[separator.upperBound...])
			if authority.hasSuffix("/") {
				authority.removeLast()
			}
			guard !authority.isEmpty, !authority.contains(where: { "/?#\\".contains($0) }) else { return false }
			guard hasValidHostAndPort(authority) else { return false }
			guard let port = components.port else { return true }
			return (1...65535).contains(port)
		}

		private static func hasValidHostAndPort(_ authority: String) -> Bool {
			if authority.hasPrefix("[") {
				guard let closingBracket = authority.firstIndex(of: "]") else { return false }
				let remainder = authority[authority.index(after: closingBracket)...]
				guard !remainder.isEmpty else { return true }
				guard remainder.hasPrefix(":") else { return false }
				return isValidPortText(remainder.dropFirst())
			}

			let parts = authority.split(separator: ":", omittingEmptySubsequences: false)
			guard parts.count <= 2, parts.first?.isEmpty == false else { return false }
			guard parts.count == 2 else { return true }
			return isValidPortText(parts[1])
		}

		private static func isValidPortText(_ value: Substring) -> Bool {
			guard !value.isEmpty, value.utf8.allSatisfy({ (48...57).contains($0) }), let port = Int(value) else {
				return false
			}
			return (1...65535).contains(port)
		}

		private static func defaultPort(for scheme: String) -> Int {
			scheme == "https" ? 443 : 80
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
		private let allowedOrigins: Set<WebViewBridgeOrigin>
		private let clientTarget: WebViewBridgeClientTarget
		private weak var webView: WKWebView?
		private let handler: WeakWebViewBridgeScriptMessageHandler
		private var isUninstalled = false

		lazy var handle = SidebandWebViewBridgeInstallation { [weak self] in
			self?.uninstall()
		}

		var isInstalled: Bool {
			!isUninstalled && webView != nil && clientTarget.client != nil
		}

		fileprivate init(webView: WKWebView, client: Client, allowedOrigins: Set<WebViewBridgeOrigin>) {
			webViewIdentifier = ObjectIdentifier(webView)
			self.webView = webView
			self.allowedOrigins = allowedOrigins
			clientTarget = .instance(WeakClientReference(client))
			handler = WeakWebViewBridgeScriptMessageHandler()
			handler.installation = self
			install(on: webView)
		}

		fileprivate init(webView: WKWebView, allowedOrigins: Set<WebViewBridgeOrigin>) {
			webViewIdentifier = ObjectIdentifier(webView)
			self.webView = webView
			self.allowedOrigins = allowedOrigins
			clientTarget = .shared
			handler = WeakWebViewBridgeScriptMessageHandler()
			handler.installation = self
			install(on: webView)
		}

		func handle(_ message: WKScriptMessage) {
			let securityOrigin = message.frameInfo.securityOrigin
			handle(
				messageName: message.name,
				isMainFrame: message.frameInfo.isMainFrame,
				sourceOrigin: (securityOrigin.protocol, securityOrigin.host, securityOrigin.port),
				body: message.body
			)
		}

		@discardableResult
		func handle(
			messageName: String,
			isMainFrame: Bool,
			sourceOrigin: (protocol: String, host: String, port: Int),
			body: Any
		) -> Bool {
			guard messageName == Self.handlerName else { return false }
			guard isMainFrame else { return false }
			guard
				let origin = WebViewBridgeOrigin(
					sourceProtocol: sourceOrigin.protocol,
					host: sourceOrigin.host,
					port: sourceOrigin.port
				)
			else { return false }
			guard allowedOrigins.contains(origin) else { return false }
			guard let action = WebViewBridgeMessage.parse(body) else { return false }
			guard let client = clientTarget.client else { return false }
			apply(action, to: client)
			return true
		}

		fileprivate func matches(client: Client, allowedOrigins: Set<WebViewBridgeOrigin>) -> Bool {
			isInstalled && self.allowedOrigins == allowedOrigins && clientTarget.matches(client)
		}

		fileprivate func matchesShared(allowedOrigins: Set<WebViewBridgeOrigin>) -> Bool {
			isInstalled && self.allowedOrigins == allowedOrigins && clientTarget.isShared
		}

		func uninstall() {
			guard !isUninstalled else { return }
			isUninstalled = true
			webView?.configuration.userContentController.removeScriptMessageHandler(
				forName: Self.handlerName,
				contentWorld: .page
			)
			WebViewBridgeStore.installations[webViewIdentifier] = nil
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

			webView.evaluateJavaScript(Self.javaScriptSource, in: nil, in: .page) { _ in }
		}

		private func apply(_ action: WebViewBridgeAction, to client: Client) {
			switch action {
			case .tagUser(let userID):
				client.tagUser(userID)
			case .untagUser:
				client.untagUser()
			case .track(let name, let metadata):
				client.track(event: name, metadata: metadata)
			}
		}
	}

	@MainActor
	private enum WebViewBridgeClientTarget {
		case instance(WeakClientReference)
		case shared

		var client: Client? {
			switch self {
			case .instance(let reference):
				reference.client
			case .shared:
				Client.shared
			}
		}

		var isShared: Bool {
			if case .shared = self {
				return true
			}
			return false
		}

		func matches(_ client: Client) -> Bool {
			if case .instance(let reference) = self {
				return reference.client === client
			}
			return false
		}
	}

	@MainActor
	private final class WeakClientReference {
		weak var client: Client?

		init(_ client: Client) {
			self.client = client
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
