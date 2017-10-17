//
//  Message.swift
//  Carrot
//
//  Created by Gonzalo Nunez on 10/17/17.
//  Copyright © 2017 carrot. All rights reserved.
//

import Foundation

public enum Message<T: Codable> {
  case event(EventMessage<T>)
  case stream(StreamMessage<T>)
}

/*
extension Message: Codable {
  
  enum CodingError: Error {
    case decoding(String)
  }
  
  enum CodingKeys: String, CodingKey {
    case event
    case stream
  }
  
  public init(from decoder: Decoder) throws {
    
  }
  
  public func encode(to encoder: Encoder) throws {
    
  }
}
*/
