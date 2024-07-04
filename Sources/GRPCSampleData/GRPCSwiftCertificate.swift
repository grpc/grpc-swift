/*
 * Copyright 2024, gRPC Authors All rights reserved.
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
public struct SampleCertificate {
  public var certificate: NIOSSLCertificate
  public var commonName: String
  public var notAfter: Date

  public static let ca = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(caCert.utf8), format: .pem),
    commonName: "some-ca",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_751_648_938)
  )
}

extension SampleCertificate {
  /// Returns whether the certificate has expired.
  public var isExpired: Bool {
    return self.notAfter < Date()
  }
}

/// Provides convenience methods to make `NIOSSLPrivateKey`s for corresponding `GRPCSwiftCertificate`s.
public struct SamplePrivateKey {
  private init() {}

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
}

// MARK: - Certificates and private keys

private let caCert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCCQDhjLeDGLctlTANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
  b21lLWNhMB4XDTI0MDcwNDE3MDg1OFoXDTI1MDcwNDE3MDg1OFowEjEQMA4GA1UE
  AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALzrSLrp
  IcroapZ1CB2jz5N1O+S22oLpKyYE2KT+lXN1Bp44ni4bkklrXSNwyqwldqh9gk5m
  HRvXA00nNkXD4dx0wjDJqxgs3AME58EIWo3MKrCNUS4cnD6qeQNf9ZZkxE8dWq1U
  ZKhAVMuSWDMRYNZvSsiNjsMSRwIaPrpyDuUhAlG49HCmYLkBEzMckAhq1T1eiPwi
  zae9d+CO7P34CSm3hYmjV7eiiwRhmPWpJwt53SrZvjjwzVpzZjcP+RDef4v+PFpQ
  mvEfIl4H+T+IHacgkIJdvaxRn9uktf12naDHk0UvQI67JLKleU+QshcSScWb8FA6
  7mcD8cdfu1y2+vcCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAKdizzBFh65tDUIwz
  raukYSPIRm3erLD+Yky/bnenZrhofo4yLyoGu3UCwAvSjcXkEH2wPdRrJGm1nrQG
  yKauWmjFjD3AA3qidrPBJXg8REWpjQjXvrjPztI6N4OVaXsDFBXczr/7E1Ot/fu3
  rGGjv2lD4fFdEUb7vvmywwWdVG2eK33xuoGpUWNtHg781QiAW5XQlMTR8Nghdc/B
  yX3BlsR0ube//l3BKmWfSQbRM8vRQwO19VmZyaxjFwiQviW5ds3b7KReqxJn5UbU
  brcfWGL+eg0/lOWTVQkoIwHBsmAZnIE98AeC8OGuGKMRxqkYqZ9Fsg8DVUMdqQFe
  Dbu9pQ==
  -----END CERTIFICATE-----
  """

private let otherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICrDCCAZQCCQD8FZzejuvygjANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
  b21lLW90aGVyLWNhMB4XDTI0MDcwNDE3MDg1OFoXDTI1MDcwNDE3MDg1OFowGDEW
  MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
  AQoCggEBAPtxP9YCOZggO5iivxe4CEHk3DdfYXKul+jOdW/dU4P4pwKU/YutQu+F
  7tPnGYaP7eO3if8PtbILio0lubk+uSbTZ5hRteL/3yj9UN6jL4vaVOkSunpbP+/d
  HXdB8Aa0hzZlNPbG9+7TADGryxqt1KzgVo+KBAEY0p2vRc3E6HtLBnSkzlw3wi1X
  zmuy8WCnayTmdqt95djsJE8PNX+GtTNfaNtZ1M5qx4FiPqqJqFhgCKJHy4LRrO3u
  K5IfGVy8zfXkFSXfqvl9NKz71xecBIRMQJCATEpG6GXSyb+vmnOuAKZ+fVVLw7Kf
  oPYwG3sh2GRDfa2pfAoP0vjXZri8AWkCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
  525Wy4Cyx2Pd91RJufYWRgkAwI8KLe4KV+SoZiLNJzfBRemqUq0P36l2lSotq4bp
  I04d5HXkl8eQ7dje/RFWXMHfNQXRq06+KUfh1XA17GQ+VOEHFc0PYKW78ydXXZDk
  PS2+y6Ru/MD989Aoecr2JvD7sSEmSvprtPxuNYHifZKbaw2c8HbR0Z3WawxoIFRV
  zeb4aGUncWj7IKNRmL4f7CDA3Old0fwIRKYcxv5awTHK01PE4Yxo89M2RqRFiJQy
  xbmAl1y7D1nLlfzHjKXRP6wpBylPcSssTuOXfi+U3Mv87iNDvzKTVYUD3c6wT/QQ
  bIRjD4xVam65aa8pewlzRA==
  -----END CERTIFICATE-----
  """

private let serverCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNDA3MDQxNzA4NTlaFw0yNTA3MDQxNzA4NTlaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANTYUmWVpEP9ym/T
  dYpDxr1z0bMZ7HiFMDT3EW0XGrEs2Rta6QbPxP3lSIW9G1OdVJMugg8EB4yoPrRc
  x6ttS64X48DyfvEH4VbdX+gHZUeTIloN9GispPiIiY5Qodq9/JeSjAG744lnKWKm
  48w4A5bWb4zlZ8s7lNTiDphll686+oIuhhxAYI4nuKKsPhLatvclq/O6a1BypQv7
  7psyo1gxcRs7gRLIGchcByI75ofkAcpT0/p67rhCECOFwvJt+8uuMoVnAPxcAgBO
  jgPhbxS6DcOSzoliQYtOBv2YIKllplgOE+0eYxAvxBLfGY/wh3SeEhVKF8G8ltT6
  Anp2MPcCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEACG9shmrPmQvt+3dKpEuzR2BA
  GLrgON4zgc8byFIORHatPiM108LoEp2a8O+B3rFJqWbBBrowDBRR/5th7kLvyDsV
  J33Rb2mXaJv8K8hNkbSs5Ow5go9M5LveMcgRqiQTuYLuvgman3LvlGveEc5N2yar
  NCVmZfZ0ofTul+QqxaYBw2GlaXmzsyvpbZfowskYdGm/PipThWsuVy/e7BLHZsr7
  FF8f7qfbDsuVd0UpWPSlIHYUJLP4Bhj87YWnOQgXSEgq2cxybZHmahiG7YmZzg++
  Oz3B1+jGtb6nKk961X5LyGsitGjEULovA8tHQEJXWvKpYQTBXOMUCKWslrje3Q==
  -----END CERTIFICATE-----
  """

private let serverSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNDA3MDQxNzA4NTlaFw0yNTA3MDQxNzA4NTlaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANTYUmWV
  pEP9ym/TdYpDxr1z0bMZ7HiFMDT3EW0XGrEs2Rta6QbPxP3lSIW9G1OdVJMugg8E
  B4yoPrRcx6ttS64X48DyfvEH4VbdX+gHZUeTIloN9GispPiIiY5Qodq9/JeSjAG7
  44lnKWKm48w4A5bWb4zlZ8s7lNTiDphll686+oIuhhxAYI4nuKKsPhLatvclq/O6
  a1BypQv77psyo1gxcRs7gRLIGchcByI75ofkAcpT0/p67rhCECOFwvJt+8uuMoVn
  APxcAgBOjgPhbxS6DcOSzoliQYtOBv2YIKllplgOE+0eYxAvxBLfGY/wh3SeEhVK
  F8G8ltT6Anp2MPcCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA1cUeJkmPC+qjNzTY
  JJ6LUofrVfIXZbiZf2NugNx/iLAabrLSd4pZjIXQszWbd5t+wftyUBqUd1Z/GuPj
  XHmfES4ZUm1Fyu75KZjNzzXsXrlZ09IHIWvxAcA3FtqbDElw7naExbzcpup6s+45
  MgAMcFnMIoMj4Cdt9Ky0kzWKdl7tmNxIF+PNQby6JCVb7HPUgs3hqSalwDo9ddYF
  8lvJ5Q4ZzlKLL1zUKkpD7I4M6hvNLgHdnLa9nwtT40u0bbGr9z25W+YouJy5N4pD
  YsOhm4xYF9VBZIEsr/ZSrI2RtABu7I5NVNWhF7JAIYspur1Rghl5bRkSaQ1jf/BK
  Epog6w==
  -----END CERTIFICATE-----
  """

private let serverKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEA1NhSZZWkQ/3Kb9N1ikPGvXPRsxnseIUwNPcRbRcasSzZG1rp
  Bs/E/eVIhb0bU51Uky6CDwQHjKg+tFzHq21LrhfjwPJ+8QfhVt1f6AdlR5MiWg30
  aKyk+IiJjlCh2r38l5KMAbvjiWcpYqbjzDgDltZvjOVnyzuU1OIOmGWXrzr6gi6G
  HEBgjie4oqw+Etq29yWr87prUHKlC/vumzKjWDFxGzuBEsgZyFwHIjvmh+QBylPT
  +nruuEIQI4XC8m37y64yhWcA/FwCAE6OA+FvFLoNw5LOiWJBi04G/ZggqWWmWA4T
  7R5jEC/EEt8Zj/CHdJ4SFUoXwbyW1PoCenYw9wIDAQABAoIBABbY/cdPz+lIhgGJ
  BnYIHn5Zv2nlX3/0dB9LYkB+mWvpb4jDMn57sR68DRPmH9fS7LA77tQjz5emu8xq
  pTherCANCnK81SmUefj0HIZwvMt5HNfj5ZeS6MaRCYsQVr9/Y2z12zeYbq1iOIwR
  dCSI4sG/VQwf2At14t0TQxPS2/yAOwctWo2g4KVcHWUXTw+qKoNANX67h6tznLRA
  QH8fG3T19+wBtuSVq/VBiJTHwAjdHXyHz+eRr7eSxANIewrgmrfbJRpXwevnzVsz
  9WZedkcTKBn7yj6ZaoRMwuwfAspJ0S6p320ehPbdo96Wh25BXNs3VJ2/GcUfkAKe
  UGSymfkCgYEA+b68gdqr/IclrDPtFhGGJAYnKMZ6uQXkAij+x8w8X1Q/avkVLxFB
  jBAEd7DLD/brCY6BMmq/mzmWJiSpdaF501rwne2DVcsq5U1N3rIV6AWxpp368Zfa
  w2tut+bmq4ZEQtK4kJP2WXxE8HtQNSZ42qbGF0Rw0RoZ1pTr9oSkwCsCgYEA2iz/
  U6iedewf+Dqcggii6gGZEVpC/kXs6m7xxVgE6Nt2/tHskun2B/3Kqoq4KxOkR1In
  saG5GJIfUfVhnwiydAp9t+jlu7mplpFCF1hZpC/pwa3EP/tB8roLXlcRkL7257TR
  /4u9YHY85PpXUycsYZDibfxYLwenzePCZH7TIGUCgYEA14FnWQZA8qAMOhR0uV5V
  yjAlCmJ6873JirOlZvMuBXTFZKGbTgot7ZbExCOilhwTpSN7CO5keKWwkyl/sSmt
  3lvS1fRmKFowob2bPFef359KNOSN7nuDIq5J1BdDZS9vJ9p9uQR0x7McKge+pp6U
  GtlehiVg1I8ZTLklBIxhPhECgYEAuKs9suIWvlmO9d0mfCozOz7/AOEVs4QcdJJT
  smY+QZsBrc6iH/hId5sp4BBqsot9kaDIWGI6+cE1IXpBlwsVgYMfxnsreSo9kWSC
  PKBbv82OXpFme4GA4KL43HF2PL5m3tj+pv7w3KU4Bdif8ZJGzo6EGfRt7+Da+DrA
  X6+5pMECgYAkMyh/ypYwsTqkYalgRk1lPwe/EAP28lWFsyckIzBuP+CwOMg5q5o3
  mg1GEE3hWCY9P1cLTedewHFBYpfiiR4hDKSyivZElV32C5Kg1uHxGc86FFGyAl3v
  dEAYBVnuHnW4u1JpBh5a0rRa4U2UYeq9l9rZRJzsjV7FxkTIRgdNQw==
  -----END RSA PRIVATE KEY-----
  """

private let exampleServerCert = """
  -----BEGIN CERTIFICATE-----
  MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNDA3MDQxNzA4NTlaFw0yNTA3MDQxNzA4NTlaMBYxFDASBgNVBAMMC2V4YW1w
  bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2BfL1dswYSgf
  q+ZSp3Uy4bSlCayFuBeKc34W/XRl7+YJd8f/EJulI4gwYPjcBWYyFyHLzEyAjhJ8
  HMFW4a1PFNJ6gc3Djo60/qfhJ2/uAX8E/Gi7pVezKMsMwx6iBjG0SiN1zcQzGnns
  k12TRZWfsIl/RR5F1tZWMLggHXasT9DBZht4Ya9jx7nte4T43vFfWlzJHu7L3L2i
  8tBTv3d53msjImMF6pUIqpDQ9doo+jGI4ApqbfeKUfy+/OxrKuhVMXzYh9dhXnDc
  nJnhgxa51MumiJ9apqeUBT+rW+1zhYpIUE5Su0TgYXjNGecb+OwMoy8WYRJIusD6
  QVebKRhAqwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQC7s83kfzkbh2GdbJYGCG/v
  nWz/aZnLm542wyi0aXZNodNF/mTO4jSm8RKeAwLX+f1hleI32CG/d9/zSrvwOZiW
  ar2fccfVqA1UuRXT8XyZB/WUxKPxuT1WtMVbS/nLS51XL2PJRn50JRAwnw7vH/MJ
  Lb7IqY8MmIYZrnEBMfAqkPvSvN9eXZYrNuLQaeqV/I97XKz8FJ4IbR9Mz51STcHJ
  65lwzi/Tfdxq5awVfGx8bp+uj0aow6NPkpVqYS78LrCYVa4RYau9vHNVoHOzOumi
  dXRxp2NlVy4kJwd7RX4p5qE4OSNBpRgQBCtXYXWBV8eHIQo8mfDGcAMPfMFQ35TY
  -----END CERTIFICATE-----
  """

private let exampleServerKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEA2BfL1dswYSgfq+ZSp3Uy4bSlCayFuBeKc34W/XRl7+YJd8f/
  EJulI4gwYPjcBWYyFyHLzEyAjhJ8HMFW4a1PFNJ6gc3Djo60/qfhJ2/uAX8E/Gi7
  pVezKMsMwx6iBjG0SiN1zcQzGnnsk12TRZWfsIl/RR5F1tZWMLggHXasT9DBZht4
  Ya9jx7nte4T43vFfWlzJHu7L3L2i8tBTv3d53msjImMF6pUIqpDQ9doo+jGI4Apq
  bfeKUfy+/OxrKuhVMXzYh9dhXnDcnJnhgxa51MumiJ9apqeUBT+rW+1zhYpIUE5S
  u0TgYXjNGecb+OwMoy8WYRJIusD6QVebKRhAqwIDAQABAoIBAQCPtvPHnOkGFKtL
  pfieimF2nq+MSYL9NhrMSLV9hyYscG8njIlkQD+J7A9QzvF1Xcw+eimSC+cLlduZ
  PDRODvcjQABdx70hWGOjYX9qvRQrRpDIVddGVZc/sBsiwYK8X94p2H+Gg9AA8cmX
  EIrbonD79dYA3+tOwGm+KRaiwcRDp7b9q3pVeTJGEn4+njXPzA1hADuF/i/CtFJj
  d9PMamPRVDBj+ixQ7NpUwpTldIGFf4b1l54LIvqtZoRX470XuTc8Tw7BYXjEl4jv
  3mkhTwUIJ8W9VQCAvH4sz6Z/hM1rlgdk1a2o5aoQ7ohJvpb3jwGMvLNFVTSls78Y
  3rcpGKjxAoGBAPwVCQgE9LE5AQEaNWkbLgicyz0/qX6pVK7f9CDcrUxMcVo01Zjo
  cXr79Q9xw4Wl9gvzKq/YAYtY/SxyTL0A0ip9OwBHAyeGLvxEiodOCQ4qxKO4xAcy
  Y4GjveQwKANPttlJCPHgny3HqC8swYLf0dAGoYtBM53A9lPbvOKPFkDlAoGBANtz
  keSFim5V+vlpovxITdPowJzzaBXnKRFBEjcdBJsNio4iPuVoVHjMYaVkyVZ1FQ+s
  MTIYH0mTLlabQcIXHRF/gw6miEIILtBcJtcdE73gbyvZXgveweMsmZfP+TCKMgCO
  OYjZT+SIiyB6zCctA3z/bM4I2taoOAhHtasU/7JPAoGAXFBXvlgSQ9RcScsPRC5v
  7Td+Ni/aIkhgeqoI/P/Tdt2HpUEz94soA6HBXKaMs6TTNg0W1M6FwkIUdPJmp9Bl
  Jqo1sSRQQ2kgS8HN+T7akhWXbV18bCZHynHsWGRKQuwuSeQ1Il7f7CPxs1TwiLzu
  WQAUqKp3/I1tp8gQo+dCfwECgYEApjXJKQDv0RO0C9WziUqmD7r4r6c3jWdQVm4n
  grCqvVkrOO29H3m+iOObjW5hg+cXtZAgjqVwhQRBk3zx+DQTYx5lv+Hnz8Ns2YkC
  Lekq+6QR728p6Omlhg9QoYf2X4o7xunxr7GP7jJw1X/MQlu4iaLX4NEaFnzAO508
  fkBgTccCgYAV/S8vuIjaku8H86uPu1F3rMoUI3En5vCKHsEbef72FPIJNLqeoTX7
  1jKtxNBpoTnzv6CgGq7NRzFBdYwvcxbrMxVs/k76zgMp+EUY+SsPbQRSllum72pA
  XrfC2tdOnAx7NO4dAYLpmqfTAzKGDFcf4MiRwRiYwzQ8OIw+bmH8Tg==
  -----END RSA PRIVATE KEY-----
  """

private let clientCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNDA3MDQxNzA4NTlaFw0yNTA3MDQxNzA4NTlaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMT3FOJyfZpu6Ypq
  du3bMbdgWiVprdNMODJsRURJzKj7znKC1tLcD7gvv/536DKzpAl3VF/pbdd/yDU6
  JuXfel+2qxx3cvM+QLqBFEggUt9vd0rCs1DvZ9rT7A755hM2146gdE55g2JvXsJG
  C6gBskr40qkt5JrKSqOys5VE1TeifBt4lwCQphAB6qNeZM+0MEz6PSeeSFjVFZlo
  IdyF3+swCsioTvzbfXs9p14HthJzL3edoorbtJ8upZdUlwJNZ2AX7K34sL1SDM+b
  Ox+eoGLJ1OhPW+CHvjFMzpM3Q1dyTqR1SosBEiuYVpk/SAS/pBSNMp3yKqF1T3ch
  4oJOb7UCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAejNVcNvE3sNgMC7a1nm1gPKt
  mnzVpuk/7Wls4ldH2yB6QupoWBimNAWyCsvc+l1qsbPJf18JbVK8FviRTs6Fka1g
  +MFMqMs/SlcAgmSlkfHdpu3zZqUEgQxF8pNJJ/Dr2ypkxEMkZnS/g4KiPdQGnTAU
  uHTtTm3DiNpyCCJFoDq3xMb+qTj8UTlZI45HukmqPKINobW6IHuislYQvhZnRXM9
  pwu4L379lI848bncYCVhlQJMP4bQTWhaUQgWpqIrxHatLAplWorTrCUzS1qT3uJN
  B/zptXK9+LLU8Nc+pqR2kTBhMN5a1nN6MzPSi6UWwX+evr/NRigkOReHDqx9GQ==
  -----END CERTIFICATE-----
  """

private let clientSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNDA3MDQxNzA4NTlaFw0yNTA3MDQxNzA4NTlaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMT3FOJy
  fZpu6Ypqdu3bMbdgWiVprdNMODJsRURJzKj7znKC1tLcD7gvv/536DKzpAl3VF/p
  bdd/yDU6JuXfel+2qxx3cvM+QLqBFEggUt9vd0rCs1DvZ9rT7A755hM2146gdE55
  g2JvXsJGC6gBskr40qkt5JrKSqOys5VE1TeifBt4lwCQphAB6qNeZM+0MEz6PSee
  SFjVFZloIdyF3+swCsioTvzbfXs9p14HthJzL3edoorbtJ8upZdUlwJNZ2AX7K34
  sL1SDM+bOx+eoGLJ1OhPW+CHvjFMzpM3Q1dyTqR1SosBEiuYVpk/SAS/pBSNMp3y
  KqF1T3ch4oJOb7UCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAKLBSZDrKiqAUiJCi
  da+cdf2oMEh9Tz9vlGik2O3KW2uW+eG0kF1D0PSNN0yGcmGY6eTiDu2MRlmBmRIz
  c3TTRArhXsRA7BQ4uyHOL3uRvcRUMk5DEtGwLrVAr79RM8jgPdom6Ws/fPzqxr8h
  umm4zc6ixLFhfGqI5QbIwVyBO4jLxTmwjuJSjlHOuSKLa74K88oKlFUR74ANyu+U
  e5/+q4SzvmRZG0sd2x1ZqmPajJ8nG2orhMu/k2VC8JQhuRigTXnapCUCVmeKA7eu
  dcwqBMU6QyvmwcTTR8GRlpfOR7rXEZUa2qak4kf76iNWOHzYkgNI3nOsCe70bFIy
  Eeh5yg==
  -----END CERTIFICATE-----
  """

private let clientKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEogIBAAKCAQEAxPcU4nJ9mm7pimp27dsxt2BaJWmt00w4MmxFREnMqPvOcoLW
  0twPuC+//nfoMrOkCXdUX+lt13/INTom5d96X7arHHdy8z5AuoEUSCBS3293SsKz
  UO9n2tPsDvnmEzbXjqB0TnmDYm9ewkYLqAGySvjSqS3kmspKo7KzlUTVN6J8G3iX
  AJCmEAHqo15kz7QwTPo9J55IWNUVmWgh3IXf6zAKyKhO/Nt9ez2nXge2EnMvd52i
  itu0ny6ll1SXAk1nYBfsrfiwvVIMz5s7H56gYsnU6E9b4Ie+MUzOkzdDV3JOpHVK
  iwESK5hWmT9IBL+kFI0ynfIqoXVPdyHigk5vtQIDAQABAoIBAGH7cD4+KlGa/z7G
  O6eTtSW+HtohukE013ft+H9CHzepHEhG4ks/AerkhiQ2ziH6z42N+UFFRElB3fzs
  ktEj3SKkInckzOBIhbbB468FtXRFZRihxsZqckWfyvygQF4qmAzxsSogtMVRFdib
  M80+Gs3E/jb/B4whOgQ5L7D/7vmfUaOkD1tmm6mHfITihfdN9Jurg5OBZX2fWSHf
  j9j6VbfLjoIatDGcC4MTiMkcIOYECAeXtpGYVdyH4K5y+UDCyo0b3qG+QuzE87gS
  h2yVJNZKR6Y1vmcGqXQATVoZPGzS6Lc0/kUqcW50uoGBV5o5Sr4OKOUPIFCRwYa7
  3LFW84ECgYEA42KEyM1vzXrDXrcGEp7GxZ0Z96yd5/XF3+AZ5R2snahRzDa+PzV2
  GPPZIVe8/bmJUxhWr3krHsUD21+KjNXY2l4ioAo2r4dmVR4vH9upGfWYutlw0pH8
  kurGq7H6lpwUfvb80AF3MXnwaqYGLUPX3cVOt9mEl0hEsqzlDrVSBcUCgYEA3cCO
  RIWn8al+gse+xVqfpgGN9DuYM0qJuxvYpMy24EeJwGLyumwSesH6aK7zn2A9gME2
  eWFB93sL880QUeoGT2pHwBZAtC/4PvbNlrHO2W333/aMNVATBoGDIEUM8cjMkDr0
  jHx/iheLvXp81F5+W6o+sSSCI0RxkNXA/FcoUTECgYAw+fNn3PgL5jlWmU1xjUl7
  Hw+MzV1lrQZl5jstomqfurWDqvbnXniFf2BxUhie/euaPk/Nk+e5xO3Dvpx1IUqI
  HmaO2iRVQnDEPLAhyIpv0PqIpHUspc0lR/Rq3vb+obe4cTKbCvXFbmJeVkxWS5qf
  ZfRCnVN10lcZtSvRMzTrkQKBgGFrzxTbg0TwKdxa1Lzva2QLGspJxDwEay4AtdTw
  +wbdZu9WiTzNbfDwd4q2EeHa7io6uCvrRofrTvz1Ak56efs5vfvtys9eo7lFxFyI
  EVAEt/l033Qska8yBuGOdHlktjpHLFjr+Tw5y/KadWz3dpve11wLpgDIePwgbIBv
  6g6BAoGAA5lMXjQeQ26I5vXJTWd9NEvb7IVJeAheZOA03ruIPR4dVhorhsFt72bQ
  +tugqU9aGlhxvCuvbBpEz8ZYhYxVe/tvDpe/upCCdGg4lwETje2FtKiYig7vMxKS
  AwFfL4q1Bs2J1siAXCVSZ9fWFDGXWNbd1eLNzAfYqS766tBZyas=
  -----END RSA PRIVATE KEY-----
  """

private let serverExplicitCurveCert = """
  -----BEGIN CERTIFICATE-----
  MIICDzCCAbYCCQC4FdI3dXof+TAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
  cGxlLmNvbTAeFw0yNDA3MDQxNzA4NTlaFw0yNTA3MDQxNzA4NTlaMBYxFDASBgNV
  BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
  AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
  AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
  sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
  Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
  N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABBJm
  1grK+MXu4JYZqU6zD19w4MhWuhpPadq7PlpSxz4scMbWorth6pN/9hiqLAwKex7h
  IuaSXF+83OESJPTOagQwCgYIKoZIzj0EAwIDRwAwRAIgNGW97RYxaltyx02UMyHc
  E0AGSlMG3VFETZ5M9pMZGksCICgrTsLJXfOVdpyAjmI2vBibtZ/BisMftfXxupt3
  vM98
  -----END CERTIFICATE-----
  """

private let serverExplicitCurveKey = """
  -----BEGIN EC PRIVATE KEY-----
  MIIBaAIBAQQgD0lwrHX5wodoQFB4jhY7eqH4x5oBgL8aMjK9XndZODWggfowgfcC
  AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
  MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
  vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
  axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
  K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
  YyVRAgEBoUQDQgAEEmbWCsr4xe7glhmpTrMPX3DgyFa6Gk9p2rs+WlLHPixwxtai
  u2Hqk3/2GKosDAp7HuEi5pJcX7zc4RIk9M5qBA==
  -----END EC PRIVATE KEY-----
  """

#endif  // canImport(NIOSSL)
