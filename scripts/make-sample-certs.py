#!/usr/bin/env python3

# Copyright 2022, gRPC Authors All rights reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
import os
import subprocess
import datetime

TEMPLATE = """\
/*
 * Copyright {year}, gRPC Authors All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//-----------------------------------------------------------------------------
// THIS FILE WAS GENERATED WITH make-sample-certs.py
//
// DO NOT UPDATE MANUALLY
//-----------------------------------------------------------------------------

#if canImport(NIOSSL)
import struct Foundation.Date
import NIOSSL

/// Wraps `NIOSSLCertificate` to provide the certificate common name and expiry date.
public struct SampleCertificate {{
  public var certificate: NIOSSLCertificate
  public var commonName: String
  public var notAfter: Date

  public static let ca = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(caCert.utf8), format: .pem),
    commonName: "some-ca",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: {timestamp})
  )
}}

extension SampleCertificate {{
  /// Returns whether the certificate has expired.
  public var isExpired: Bool {{
    return self.notAfter < Date()
  }}
}}

/// Provides convenience methods to make `NIOSSLPrivateKey`s for corresponding `GRPCSwiftCertificate`s.
public struct SamplePrivateKey {{
  private init() {{}}

  public static let server = try! NIOSSLPrivateKey(bytes: .init(serverKey.utf8), format: .pem)
  public static let exampleServer = try! NIOSSLPrivateKey(
    bytes: .init(exampleServerKey.utf8),
    format: .pem
  )
  public static let client = try! NIOSSLPrivateKey(bytes: .init(clientKey.utf8), format: .pem)
  public static let exampleServerWithExplicitCurve = try! NIOSSLPrivateKey(
    bytes: .init(serverExplicitCurveKey.utf8),
    format: .pem
  )
}}

// MARK: - Certificates and private keys

private let caCert = \"""
{ca_cert}
\"""

private let otherCACert = \"""
{other_ca_cert}
\"""

private let serverCert = \"""
{server_cert}
\"""

private let serverSignedByOtherCACert = \"""
{server_signed_by_other_ca_cert}
\"""

private let serverKey = \"""
{server_key}
\"""

private let exampleServerCert = \"""
{example_server_cert}
\"""

private let exampleServerKey = \"""
{example_server_key}
\"""

private let clientCert = \"""
{client_cert}
\"""

private let clientSignedByOtherCACert = \"""
{client_signed_by_other_ca_cert}
\"""

private let clientKey = \"""
{client_key}
\"""

private let serverExplicitCurveCert = \"""
{server_explicit_curve_cert}
\"""

private let serverExplicitCurveKey = \"""
{server_explicit_curve_key}
\"""

#endif // canImport(NIOSSL)
"""

def load_file(root, name):
    with open(os.path.join(root, name)) as fh:
        return fh.read().strip()


def extract_key(ec_key_and_params):
    lines = []
    include_line = True
    for line in ec_key_and_params.split("\n"):
        if line == "-----BEGIN EC PARAMETERS-----":
            include_line = False
        elif line == "-----BEGIN EC PRIVATE KEY-----":
            include_line = True

        if include_line:
            lines.append(line)
    return "\n".join(lines).strip()


if __name__ == "__main__":
    now = datetime.datetime.now()
    # makecert uses an expiry of 365 days.
    delta = datetime.timedelta(days=365)
    # Seconds since epoch
    not_after = (now + delta).strftime("%s")

    # Expect to be called from the root of the checkout.
    root = os.path.abspath(os.curdir)
    executable = os.path.join(root, "scripts", "makecert")
    try:
        subprocess.check_call(executable)
    except FileNotFoundError:
        print("Please run the script from the root of the repository")
        exit(1)

    kwargs = {
        "year": now.year,
        "timestamp": not_after,
        "ca_cert": load_file(root, "ca.crt"),
        "other_ca_cert": load_file(root, "other-ca.crt"),
        "server_cert": load_file(root, "server-localhost.crt"),
        "server_signed_by_other_ca_cert": load_file(root, "server-localhost-other-ca.crt"),
        "server_key": load_file(root, "server-localhost.key"),
        "example_server_cert": load_file(root, "server-example.com.crt"),
        "example_server_key": load_file(root, "server-example.com.key"),
        "client_cert": load_file(root, "client.crt"),
        "client_signed_by_other_ca_cert": load_file(root, "client-other-ca.crt"),
        "client_key": load_file(root, "client.key"),
        "server_explicit_curve_cert": load_file(root, "server-explicit-ec.crt"),
        "server_explicit_curve_key": extract_key(load_file(root,
            "server-explicit-ec.key"))
    }

    formatted = TEMPLATE.format(**kwargs)
    with open("Sources/GRPCSampleData/GRPCSwiftCertificate.swift", "w") as fh:
        fh.write(formatted)
