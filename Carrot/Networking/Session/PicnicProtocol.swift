//
//  PicnicProtocol.swift
//  Carrot
//
//  Created by Gonzalo Nunez on 1/15/18.
//  Copyright © 2018 carrot. All rights reserved.
//

import CoreLocation
import Foundation
import Parrot
import simd

public class PicnicProtocol: SessionDriver {
  
  // MARK: Lifecycle
  
  init(
    socket: Socket,
    currentTransform: @escaping () -> matrix_float4x4?)
  {
    self.socket = socket
    self.currentTransform = currentTransform
  }
  
  // MARK: SessionDriver
  
  public typealias State = PicnicProtocolState
  
  public func start(state: State, updateState: @escaping (PicnicProtocolState) -> Void) {
    updateState(.opening)
  }
  
  public func end(state: State, updateState: @escaping (PicnicProtocolState) -> Void) {
    updateState(.closing)
  }
  
  public func socketDidOpen(state: State, updateState: @escaping (PicnicProtocolState) -> Void) {
    updateState(.pendingToken)
  }
  
  public func socketDidClose(state: State, updateState: @escaping (PicnicProtocolState) -> Void) {
    updateState(.closed)
  }
  
  public func socketDidFail(with error: Error?, state: State, updateState: @escaping (PicnicProtocolState) -> Void) {
    updateState(.failed(on: state, error ?? CarrotSessionError.failureWithoutError))
  }
  
  public func updateState(
    from state: State,
    with updateState: @escaping (State) -> Void)
  {
    switch state {
    case .opening:
      socket.open()
    case .closing:
      socket.close()
    case let .receivedInitialMessage(token, beaconInfo):
      let isPrimaryDevice = (token == beaconInfo.uuid)
      if isPrimaryDevice {
        let advertiser = beaconAdvertiser(with: beaconInfo, token: token)
        updateState(.pendingAdvertising(token, advertiser, .idle))
        advertiser.startAdvertising { advertiser, advertisingState in
          switch advertisingState {
          case .advertising:
            updateState(.authenticatedPrimary(token, advertiser))
          case .idle, .queued:
            updateState(.pendingAdvertising(token, advertiser, advertisingState))
          case let .error(error):
            updateState(.failed(on: state, error))
          }
        }
      } else {
        let monitor = beaconMonitor(for: beaconInfo)
        updateState(.pendingImmediatePing(token, monitor, .unknown))
        monitor.startMonitoring(
          onProximityUpdate: { [weak self] monitor, proximity in
            self?.handleProximityUpdate(
              to: proximity,
              monitor: monitor,
              token: token,
              beaconInfo: beaconInfo,
              state: state,
              handler: updateState)
          },
          onError: { error in
            updateState(.failed(on: state, error))
          }
        )
      }
    case .closed,
         .failed,
         .pendingToken,
         .pendingImmediatePing,
         .pendingAdvertising,
         .authenticatedSecondary,
         .authenticatedPrimary:
      break
    }
  }
  
  public func didReceive(
    data: Data,
    in state: State,
    updateState: @escaping (State) -> Void)
  {
    guard let reservedSendable = try? JSONDecoder().decode(ReservedSendable.self, from: data) else {
      return
    }
    if let token = state.token,
      let sendableResponse = response(for: reservedSendable.endpoint, token: token)
    {
      do {
        let data = try JSONEncoder().encode(sendableResponse)
        try socket.send(data: data)
      } catch {
        updateState(.failed(on: state, error))
      }
      return
    }
    switch state {
    case .pendingToken:
      do {
        let reservedSendable = try JSONDecoder().decode(ReservedSendable.self, from: data)
        switch reservedSendable.message {
        case let .beacon(beaconInfo):
          updateState(.receivedInitialMessage(reservedSendable.token, beaconInfo))
        case .transform, .none:
          break
        }
      } catch {
        // Fail silently if the server sends us something we aren't expecting?
        // Aka a non-reserved message.
        assert(false, "[ERROR]: \(error)")
      }
    case .opening,
         .closing,
         .closed,
         .receivedInitialMessage,
         .pendingImmediatePing,
         .pendingAdvertising,
         .failed,
         .authenticatedPrimary,
         .authenticatedSecondary:
      break
    }
  }
  
  // MARK: Private
  
  private let socket: Socket
  private let currentTransform: () -> matrix_float4x4?
  
  private func beaconAdvertiser(
    with beaconInfo: BeaconInfo,
    token: SessionToken) -> BeaconAdvertiser
  {
    return BeaconAdvertiser(
      uuid: token,
      identifier: beaconInfo.identifier,
      params: beaconInfo.params)
  }
  
  private func beaconMonitor(for beaconInfo: BeaconInfo) -> BeaconMonitor {
    return BeaconMonitor(
      uuid: beaconInfo.uuid,
      identifier: beaconInfo.identifier,
      params: beaconInfo.params)
  }
  
  private func handleProximityUpdate(
    to proximity: CLProximity,
    monitor: BeaconMonitor,
    token: SessionToken,
    beaconInfo: BeaconInfo,
    state: State,
    handler updateState: (State) -> Void)
  {
    switch proximity {
    case .immediate:
      guard let transform = currentTransform() else {
        updateState(.failed(on: state, CarrotSessionError.noTransform))
        return
      }
      updateState(.authenticatedSecondary(token))
      let sendable = ReservedSendable(token: token, message: .transform(transform))
      send(reservedSendable: sendable, state: state, updateState: updateState)
    case .near, .far, .unknown:
      updateState(.pendingImmediatePing(token, monitor, proximity))
    }
  }
  
  private func send(
    reservedSendable: ReservedSendable,
    state: State,
    updateState: (State) -> Void)
  {
    do {
      let data = try JSONEncoder().encode(reservedSendable)
      try socket.send(data: data)
    } catch {
      updateState(.failed(on: state, error))
    }
  }
  
  private func response(
    for endpoint: ReservedEndpoint,
    token: SessionToken) -> ReservedSendable?
  {
    switch endpoint {
    case .transform:
      guard let transform = currentTransform() else { return nil }
      return ReservedSendable(
        token: token,
        message: .transform(transform))
    case .beacon:
      return nil
    }
  }
}
