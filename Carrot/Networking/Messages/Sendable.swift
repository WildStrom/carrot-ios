//
//  Sendable.swift
//  Carrot
//
//  Created by Gonzalo Nunez on 10/18/17.
//  Copyright © 2017 carrot. All rights reserved.
//

import Foundation

enum Sendable<T: Codable> {
  case message(SessionToken, String, Location2D, Message<T>)
}

extension Sendable: Codable {
  
  enum CodingError: Error {
    case decoding(String)
  }
  
  enum CodingKeys: String, CodingKey {
    case token = "session_token"
    case endpoint = "endpoint"
    case origin
    case message = "payload"
  }
  
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    guard let token = try? values.decode(SessionToken.self, forKey: .token),
          let endpoint = try? values.decode(String.self, forKey: .endpoint),
          let origin = try? values.decode(Location2D.self, forKey: .origin),
          let message = try? values.decode(Message<T>.self, forKey: .message)
    else {
      throw CodingError.decoding("Decoding Failed. \(dump(values))")
    }
    self = .message(token, endpoint, origin, message)
  }
  
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case let .message(token, endpoint, origin, message):
      try container.encode(token, forKey: .token)
      try container.encode(endpoint, forKey: .endpoint)
      try container.encode(origin, forKey: .origin)
      try container.encode(message, forKey: .message)
    }
  }
}
