/*
MIT License

Copyright © 2018 François Lamboley <francois.lamboley@frostland.fr>

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE. */

import Foundation



public struct LinkValue : Equatable {
	
	public var link: URL
	/**
	The context for the given `LinkValue`.
	
	This is the base URL from which all relative URL have been resolved when
	parsing the header. By default the relative URL given to the parser,
	overridden by the “anchor” parameter in the header.
	
	When “anchor” is not defined, the context is retrieved via with rules from
	rfc7231, section 3.1.4.1 (as stated by rfc8288). */
	public var context: URL?
	
	public var rel: [String]
	public var rev: [String]? /* Deprecated by RFC 8288 */
	
	/** The unparsed “hreflang” values. To parse, use ABNF “Language-Tag.” */
	public var hreflang: [String]?
	/** The unparsed “media” value. To parse, use ABNF “media-query-list.” */
	public var mediaQuery: String?
	public var title: String?
	/** The unparsed “type” value. To parse, use ABNF:
	`type-name "/" subtype-name ; see Section 4.2 of [RFC6838]`. */
	public var type: String?
	
	/** The target attributes extensions (non-listed in rfc8828) for the given
	link. Because rfc8828 states the names of the target attributes “MUST be
	compared in a case-insensitive fashion,” all the keys in this dictionary are
	lowercased. It has been a design choice not to give access to the original-
	cased attribute names. */
	public var extensions: [String: [String]]
	
}


/* https://www.rfc-editor.org/rfc/rfc8288.txt */
public struct LinkHeaderParser {
	
	static func parseLinkHeaderFrom(request: URLRequest, response: HTTPURLResponse, lax: Bool = true) -> [LinkValue]? {
		guard let linkHeader = response.allHeaderFields["Link"] as? String else {return nil}
		let context = contextFrom(requestURL: request.url, requestMethod: request.httpMethod, responseStatusCode: response.statusCode, contentLocationHeader: response.allHeaderFields["Content-Location"] as? String)
		return parseLinkHeader(linkHeader, defaultContext: context, contentLanguageHeader: response.allHeaderFields["Content-Language"] as? String, lax: lax)
	}
	
	static func parseLinkHeaders(_ linkHeaders: [String], requestURL: URL?, requestMethod: String?, responseStatusCode: Int?, contentLocationHeader: String?, contentLanguageHeader: String?, lax: Bool = true) -> [LinkValue]? {
		let context = contextFrom(requestURL: requestURL, requestMethod: requestMethod, responseStatusCode: responseStatusCode, contentLocationHeader: contentLocationHeader)
		return parseLinkHeaders(linkHeaders, defaultContext: context, contentLanguageHeader: contentLanguageHeader, lax: lax)
	}
	
	static func parseLinkHeaders(_ linkHeaders: [String], defaultContext: URL?, contentLanguageHeader: String?, lax: Bool = true) -> [LinkValue]? {
		return linkHeaders
			.compactMap{ parseLinkHeader($0, defaultContext: defaultContext, contentLanguageHeader: contentLanguageHeader, lax: lax) }
			.flatMap{ $0 }
	}
	
	/* Don't forget “anonymous” context (in anchor parameter) */
	static func parseLinkHeader(_ linkHeader: String, defaultContext: URL?, contentLanguageHeader: String?, lax: Bool = true) -> [LinkValue]? {
		/* If we’re “lax” parsing, we trim whitespaces from the input. */
		let linkHeader = (lax ? linkHeader.trimmingCharacters(in: spaceCharacterSet) : linkHeader)
		
		/* Example of input: “</TheBook/chapter2>; rel="previous"; title*=UTF-8'de'letztes%20Kapitel, </TheBook/chapter4>; rel="next"; title*=UTF-8'de'n%c3%a4chstes%20Kapitel” */
		let scanner = Scanner(string: linkHeader)
		scanner.charactersToBeSkipped = CharacterSet() /* We don’t skip anything */
		
		var results = [LinkValue]()
		
		var first = true
		var finishedWithWhites = false
		var currentParsedString: NSString?
		repeat {
			/* Strictly speaking, there should not be any leading commas in the
			 * list. However, rfc7230 states that for compatibility reasons,
			 * “parsers MUST parse and ignore a reasonable number of empty list
			 * elements.” So we allow them if we’re lax (default case)…
			 *
			 * More precisely, senders are required to send:
			 *    1#element => element *( OWS "," OWS element )
			 *    #element => [ 1#element ]
			 *
			 * but parser are required to parsed the more relaxed definition:
			 *    #element => [ ( "," / element ) *( OWS "," [ OWS element ] ) ]
			 *    1#element => *( "," OWS ) element *( OWS "," [ OWS element ] )
			 *
			 * In our case, we must parse a “#element”. If we’re lax we use the
			 * relaxed definition, otherwise we use the more restrictive one (can
			 * be used to validate a sender sends valid data for instance).
			 * Note: I’m not 100% the relaxed definition of “#element” does not
			 *       contain an error. If the string starts with a comma, according
			 *       to the definition it would be required to be followed by some
			 *       optional spaces, then another comma… Our parser does not have
			 *       this limitation. */
			let foundComma: Bool
			if !first || lax {
				foundComma = scanner.scanString(",", into: nil)
				scanner.scanCharacters(from: spaceCharacterSet, into: nil)
				if lax {
					/* Let’s consume all the commas we can find */
					while scanner.scanString(",", into: nil) {
						scanner.scanCharacters(from: spaceCharacterSet, into: nil)
					}
				}
			} else {
				foundComma = false
			}
			
			guard first || foundComma else {return nil}
			if lax && scanner.isAtEnd {break}
			
			guard scanner.scanString("<", into: nil) else {return nil}
			guard scanner.scanUpTo(">", into: &currentParsedString) else {return nil} /* ">" in a URI-Reference is forbidden (rfc3986) */
			guard scanner.scanString(">", into: nil) else {return nil}
			let uriReference = currentParsedString! as String
			
			var rawAttributes = [String: [(originalKey: String, value: String)]]()
			finishedWithWhites = scanner.scanCharacters(from: spaceCharacterSet, into: nil)
			while scanner.scanString(";", into: nil) {
				scanner.scanCharacters(from: spaceCharacterSet, into: nil)
				
				guard scanner.scanCharacters(from: tokenCharacterSet, into: &currentParsedString) else {return nil}
				let key = currentParsedString! as String
				guard !key.isEmpty else {return nil}
				
				/* There shouldn’t be any spaces after the key, but we allow it in
				 * lax mode (the RFC says there might be “bad” spaces) */
				if lax {scanner.scanCharacters(from: spaceCharacterSet, into: nil)}
				guard scanner.scanString("=", into: nil) else {return nil}
				if lax {scanner.scanCharacters(from: spaceCharacterSet, into: nil)}
				
				let value: String
				if scanner.scanString("\"", into: nil) {
					/* We must parse a quoted string */
					guard let v = parseQuotedString(from: scanner) else {return nil}
					value = v
				} else {
					guard scanner.scanCharacters(from: tokenCharacterSet, into: &currentParsedString) else {return nil}
					value = currentParsedString! as String
					guard !value.isEmpty else {return nil}
				}
				
				rawAttributes[key.lowercased(), default: []].append((originalKey: key, value: value))
				
				finishedWithWhites = scanner.scanCharacters(from: spaceCharacterSet, into: nil)
			}
			
			/* The “rel” attribute is mandatory */
			guard let relList = rawAttributes["rel"], let rawRel = relList.first?.value, (relList.count == 1 || lax) else {return nil}
			let rev = rawAttributes["rev"]?.first?.value.split(separator: " ").map(String.init)
			let rel = rawRel.split(separator: " ").map(String.init)
			guard !rel.isEmpty else {return nil}
			/* In theory, we should validate the rel and rev values here…
			 * From rfc8288, ABNF:
			 *    relation-type  = reg-rel-type / ext-rel-type
			 *    reg-rel-type   = LOALPHA *( LOALPHA / DIGIT / "." / "-" )
			 *    ext-rel-type   = URI ; Section 3 of [RFC3986] */
			
			/* The RFC does not state any particular rule about the anchor. In
			 * particular, it DOES NOT STATE there must be at most one “anchor”
			 * parameter in the attributes! */
			let effectiveContext: URL?
			if let anchorStr = rawAttributes["anchor"]?.first?.value {
				guard let context = URL(string: anchorStr, relativeTo: defaultContext) else {return nil}
				effectiveContext = context
			} else {
				effectiveContext = defaultContext
			}
			guard let link = URL(string: uriReference, relativeTo: effectiveContext) else {return nil}
			
			let hreflang = rawAttributes["hreflang"]?.map{ $0.value }
			
			let mediaList = rawAttributes["media"]
			guard lax || (mediaList?.count ?? 0) <= 1 else {return nil}
			let media = mediaList?.first?.value
			
			let titleNoStarList = rawAttributes["title"]
			guard lax || (titleNoStarList?.count ?? 0) <= 1 else {return nil}
			let titleNoStar = titleNoStarList?.first?.value
			
			let titleStarList = rawAttributes["title*"]
			guard lax || (titleStarList?.count ?? 0) <= 1 else {return nil}
			let titleStarUnparsed = titleStarList?.first?.value
			#warning("TODO: Parse the title star")
			let titleStar = titleStarUnparsed
			
			let title = titleStar ?? titleNoStar
			
			let typeList = rawAttributes["title"]
			guard lax || (typeList?.count ?? 0) <= 1 else {return nil}
			let type = typeList?.first?.value
			
			for k in ["rel", "rev", "anchor", "hreflang", "media", "title", "title*", "type"] {
				rawAttributes.removeValue(forKey: k)
			}
			
			#warning("TODO: Parse the star attributes")
			
			results.append(LinkValue(
				link: link, context: effectiveContext, rel: rel, rev: rev, hreflang: hreflang, mediaQuery: media, title: title, type: type,
				extensions: rawAttributes.mapValues{ $0.map{ $0.value } }
			))
			
			first = false
		} while !scanner.isAtEnd
		assert(scanner.isAtEnd)
		
		/* Note: It should be impossible to have lax parsing and have the
		 *       finishedWithWhites variable to be true here because we trim
		 *       whitespaces when lax parsing… */
		guard lax || !finishedWithWhites else {return nil}
		
		return results
	}
	
	private init() {}
	
	private static func parseQuotedString(from scanner: Scanner, currentlyParsed: String = "") -> String? {
		var parsedString = currentlyParsed
		var currentParsedString: NSString?
		
		/* Let’s try and parse whatever legal characters we can from the quoted
		 * string. The backslash and double-quote chars are not in the set we
		 * parse here, so the scanner will stop at these (among other). */
		if scanner.scanCharacters(from: quotedTextCharacterSet, into: &currentParsedString) {
			parsedString += currentParsedString! as String
		}
		
		/* Now let’s see if we stopped at a backlash. If so, we’ll retrieve the
		 * next char, verify it is in the legal charset for a backslashed char,
		 * add it to the parsed string, and continue parsing the quoted string
		 * from there. */
		guard !scanner.scanString("\\", into: nil) else {
			guard !scanner.isAtEnd else {return nil}
			
			/* Whatever char we have at the current location will be added to the
			 * parsed string (if in quotedPairSecondCharCharacterSet). We have to
			 * do ObjC-index to Swift index conversion though… */
			
			guard let swiftIdx = Range(NSRange(location: scanner.scanLocation, length: 0), in: scanner.string)?.lowerBound else {return nil}
			let addedStr = String(scanner.string[swiftIdx])
			scanner.scanLocation += 1
			
			guard addedStr.rangeOfCharacter(from: quotedPairSecondCharCharacterSet) != nil else {return nil}
			parsedString += addedStr
			
			return parseQuotedString(from: scanner, currentlyParsed: parsedString)
		}
		
		/* We have now consumed all legal chars from a quoted string and are not
		 * stopped on a backslash. The only legal char left is a double quote!
		 * Which also signals the end of the quoted string. */
		guard scanner.scanString("\"", into: nil) else {return nil}
		return parsedString
	}
	
	private static func contextFrom(requestURL: URL?, requestMethod: String?, responseStatusCode: Int?, contentLocationHeader: String?) -> URL? {
		/* Note: For the 203 status code, the payload may have been modified by a
		 * proxy or something else… */
		if Set(arrayLiteral: "GET", "HEAD").contains(requestMethod?.uppercased()) && Set(arrayLiteral: 200, 203, 204, 206, 304).contains(responseStatusCode) {
			return requestURL
		}
		
		/* Note: If the Content-Location header contains a different value than
		 *       the request URL, we _assume_ the context is the one given by the
		 *       header, but we implement no means of verifying such a claim (see
		 *       rfc7231, § 3.1.4.1). */
		return contentLocationHeader.flatMap{ URL(string: $0) }
	}
	
	private static let tokenCharacterSet = CharacterSet(charactersIn: "!#$%&'*+-.^_`|~0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ")
	private static let spaceCharacterSet = CharacterSet(charactersIn: " \t")
	
	private static let quotedTextCharacterSet = CharacterSet(charactersIn: "\t ")
		.union(CharacterSet(arrayLiteral: Unicode.Scalar(0x21)))
		.union(CharacterSet(charactersIn: Unicode.Scalar(0x23)...Unicode.Scalar(0x5b)))
		.union(CharacterSet(charactersIn: Unicode.Scalar(0x5d)...Unicode.Scalar(0x7e)))
		.union(CharacterSet(charactersIn: Unicode.Scalar(0x80)...Unicode.Scalar(0xff)))
	private static let quotedPairSecondCharCharacterSet = CharacterSet(charactersIn: "\t ")
		.union(CharacterSet(charactersIn: Unicode.Scalar(0x21)...Unicode.Scalar(0x7e)))
		.union(CharacterSet(charactersIn: Unicode.Scalar(0x80)...Unicode.Scalar(0xff)))
	
}