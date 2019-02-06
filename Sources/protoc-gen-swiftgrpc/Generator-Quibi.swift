//
//  Genetaor-Quibi.swift
//
//  Created by Sean Liu on 2/5/19.
//

import Foundation
import SwiftProtobuf
import SwiftProtobufPluginLibrary

extension Generator {
  internal func printQuibiStub() {
    for method in service.methods {
      self.method = method
      // append QB to distingush it from original gRPC
      println("struct QB\(callName): ClientStub {")
      indent()
      println("typealias ResponseType = \(methodOutputName)")
      println("let path: String = \(methodPath)")
      println("let requestProtobuf: \(methodInputName)")
      printRequestBinaryData()
      printConstructor()
      printCallMethod()
      outdent()
      println("}")
      println()
    }
    println()
  }
  
  func printRequestBinaryData() {
    println("var requestBinaryData: Data {")
    indent()
    println("if let proto = try?requestProtobuf.serializedData() {return proto}")
    indent()
    println("return Data()")
    outdent()
    outdent()
    println("}")
  }
  
  func printConstructor() {
    println("init(requestProto: \(methodInputName)) {requestProtobuf = requestProto}")
    println()
    println("init() {requestProtobuf = \(methodInputName)()}")
    println()
  }
  
  func printCallMethod() {
    println("func qb\(method.name)(completion:@escaping (\(methodOutputName)) -> Void) {")
    indent()
    println("self.submitStub(completion: completion)")
    outdent()
    println("}")
  }
}
