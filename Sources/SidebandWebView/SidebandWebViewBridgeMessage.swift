// Payload parsing for the default WebView bridge.
//
// Customize here if GTM posts a different shape than { action, userID, name, metadata }.
// Metadata values must be strings for Client.track; scalars are stringified and nested values are dropped.

import Foundation

enum WebViewBridgeAction: Equatable {
	case tagUser(String)
	case untagUser
	case track(name: String, metadata: [String: String])
}

enum WebViewBridgeMessage {
	static func parse(_ body: Any) -> WebViewBridgeAction? {
		guard let dictionary = dictionary(from: body) else { return nil }
		guard let action = stringValue(dictionary["action"]) else { return nil }

		switch action {
		case "tagUser":
			guard let userID = stringValue(dictionary["userID"]) else { return nil }
			return .tagUser(userID)
		case "untagUser":
			return .untagUser
		case "track":
			guard let name = stringValue(dictionary["name"]) else { return nil }
			guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
			return .track(name: name, metadata: coercedMetadata(dictionary["metadata"]))
		default:
			return nil
		}
	}

	private static func dictionary(from body: Any) -> [String: Any]? {
		if let dictionary = body as? [String: Any] {
			return dictionary
		}

		guard JSONSerialization.isValidJSONObject(body),
			let data = try? JSONSerialization.data(withJSONObject: body),
			let object = try? JSONSerialization.jsonObject(with: data)
		else {
			return nil
		}

		return object as? [String: Any]
	}

	private static func stringValue(_ value: Any?) -> String? {
		value as? String
	}

	private static func coercedMetadata(_ value: Any?) -> [String: String] {
		guard let dictionary = dictionary(from: value ?? [:]) else { return [:] }

		var metadata: [String: String] = [:]
		for (key, rawValue) in dictionary {
			guard let string = scalarString(rawValue) else { continue }
			metadata[key] = string
		}
		return metadata
	}

	private static func scalarString(_ value: Any) -> String? {
		if value is NSNull {
			return nil
		}
		if let string = value as? String {
			return string
		}
		if let number = value as? NSNumber {
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return number.boolValue ? "true" : "false"
			}
			if CFNumberIsFloatType(number) {
				return String(number.doubleValue)
			}
			return String(number.int64Value)
		}
		return nil
	}
}
