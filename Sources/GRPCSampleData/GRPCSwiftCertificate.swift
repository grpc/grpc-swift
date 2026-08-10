/*
 * Copyright 2026, gRPC Authors All rights reserved.
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
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_817_906_771)
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
  MIICoDCCAYgCCQC5HiX0AeL/DDANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
  b21lLWNhMB4XDTI2MDgxMDE0MDYxMloXDTI3MDgxMDE0MDYxMlowEjEQMA4GA1UE
  AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALqFPklh
  CUtWiWb1ZH75MlVUAYPchquTAz84NrcLsPacyDh/Dx2wecX6ejIZeTln4uanRRFq
  Zs45KHKFyOsFPs13R2KGUwVf2za191PiZjVM8zkWE3Woc9uNSzyOqX+AcpIJT/48
  fp0qCakkQJVdEuEaGl6UFRjm4MQmviuZU8LdElag7HKZ9E0431scjWtrvoF3c6wD
  9l2GS+byvxhphv/b7ZOHEo4O2/nCAwbuX9GcLP5iT9453NcVRFg/C3+oJuxQC7r5
  XjgRIln5ds47lyqfCxG+0kb13FL1zUGJF1vyGvxDtwd9TvuXJrTNMSgbMx//by0S
  IWwjqe3AJYjCg/sCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAg/dw8BfqEHTVQEBW
  1DMzuF0Nho/KeX2hY8PUNrW7AQxOMBvkrZWUzibkWkxIx35wZXFoDjZCn7YhP2FV
  X2+EFIIU3tOCI++mGTNQKOrqkgn2+BiczGU0MoEqJgiqxzvnJmCMdCBMNXvjIvru
  zkkP9spLrz4kIwDtgklace1OHcVOzbHUf17YyJaE+8lsc53jBxjBdYgxWMu8rT3l
  b3OwY+FVMR5oYx7tECbpcu7uPGQtXCsu4nFypLDvqGAkX6GixMAiizaonUQm6x/2
  vOqi+Ec2XVmI7CtzKGEaLfRh8yijbE0wCS4kKa7vbtyjcPxpZijKZuuwLSirR/AN
  MEe+jQ==
  -----END CERTIFICATE-----
  """

private let otherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICrDCCAZQCCQCl5z1sTk7g2DANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
  b21lLW90aGVyLWNhMB4XDTI2MDgxMDE0MDYxMloXDTI3MDgxMDE0MDYxMlowGDEW
  MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
  AQoCggEBAKM8qdmHO/O7K2+1UInON87PnlpPHteXrl1s/PFcQosjJ6j5YejKCwUl
  WjYJZRDe+A1Xzm2r/BjfdD8H7jiPY1Im9hzEEvyVEmj+9GouAyKpX/4ROkxQFdMi
  VJ3SrHEcbj8oiogKqpOelmlS/Caevd1dJ3G00liOirAIztRlzvtZIWl5YRNcD2X0
  1FNJEEUa4p5gIfqmFkG+s+4/s59+N0dQywvBPz3h3MnwpeBERM+NaboCfxSk0OyX
  +vOBZaC2cAATsUU72GasQcMS5DViuU6Q3N2bQPM+iAYcbwAkntRdgTl11+k5g1IX
  rC/pLPOwgsZmOSxiXlmBuSXYmZbVBY0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
  cGhmlLU/wmaKczrtfGLqfpn1Ai24U6W8hGA8KdCGoQv9D8Gr5/cWGzhm9jqzP+5M
  7cNSGdEkR3bA16yGGfilwXC2vy84sIPmJzXplZf+IQg+LA4r0VAsQIFge2PN2OXm
  auR2x+zeMDwIyChWI2zriK7bjDqUk2CHlC2Y7RMoKN8vr5qIk425IWM6a524UVmO
  UBDHWVGKD6Jy1B1rhJnX7xC0UOyCYA5XIsQ72NGGTyIEkyOcVyXyqhYrK+qNzW0b
  99/QClLhuidd//b2tnDFjXs26YLy0ZJ/3BPKV38QE5xs7nsQGSTF436HV/IDGaQg
  aFuND08qobJd4wpoN0GF4Q==
  -----END CERTIFICATE-----
  """

private let serverCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNjA4MTAxNDA2MTJaFw0yNzA4MTAxNDA2MTJaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMMiveBYNlprIMDc
  qiRM7M+tHbh0URjcwMY1O4S1IwId7UMWIYtA5gDiLCUmjW36DPwm6l4s9c+JPKTJ
  X365Y7leSx/OMikL62C3QRVCQtDv8qEBuBHZFV91lmm/awsYV9IVwvi3uapkMF5Y
  MTomNCx9t7uxVYvApydJgWUvbTxDvPzl62ZgvcUj9VdSAL90AKAg5gxsUM7Bi59y
  7jCKq+N1dKMPL9JknK831nULMMUHDRPe/njE6bjOx5C5mcbBa13wH2oFkhQPmZME
  QruwRwezdQVwVcrqxF3+lm0hSOfaDScLgwr0WrkNBQSdNvixM5es5AqU2XPz72wr
  II25YykCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAJ0k7UlSiETwDbvhP5N2G/fvw
  l9u6SGdPUhcCPR2ORofkgfvX2T7M1y4Xg/4va2kcg6YYdsinsKIJPyYRqBySTSLF
  VAchPVDwWCun123DONCRMitS5KlaKvoK9xCjnNXUIlVy0O1jg5JBFTLIvs5677Y1
  dGkdqKBOv5H4b37zVn62wIlsRTIpFsPXzKYC8YT6MLxROzRVm55Ez8bcVASqYVp5
  M5EOaM07dMRMfBP5cSKJki0G75yoEdhupGUpq0hQFW+HK+QyouA8iXP+TIwwWwTh
  A9cRp9DDcpU3adu4zthoMSxxeHda8ex0k854RleTzXZ6orh8FKYZZCFbB09hpQ==
  -----END CERTIFICATE-----
  """

private let serverSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNjA4MTAxNDA2MTJaFw0yNzA4MTAxNDA2MTJaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMMiveBY
  NlprIMDcqiRM7M+tHbh0URjcwMY1O4S1IwId7UMWIYtA5gDiLCUmjW36DPwm6l4s
  9c+JPKTJX365Y7leSx/OMikL62C3QRVCQtDv8qEBuBHZFV91lmm/awsYV9IVwvi3
  uapkMF5YMTomNCx9t7uxVYvApydJgWUvbTxDvPzl62ZgvcUj9VdSAL90AKAg5gxs
  UM7Bi59y7jCKq+N1dKMPL9JknK831nULMMUHDRPe/njE6bjOx5C5mcbBa13wH2oF
  khQPmZMEQruwRwezdQVwVcrqxF3+lm0hSOfaDScLgwr0WrkNBQSdNvixM5es5AqU
  2XPz72wrII25YykCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEALX1W8Cd8tUZ8Gn3m
  T99WDFJ0QNxUC66fM2NJ1oIVOeKGFbPlR0HgeT1TlCXXT2WtInpAvix+lQeKBgEg
  D93h9JZHLTDGn7UD57oc2/VnEvl/zsj/xsy91u1uClrHJIWH2neS+mFq2wLQDvQD
  emU4vkyoVilu368jazv7sHhfCxnZy4VJK/xJhiW1fpS5iuMaNT1014fYNbMINJzz
  WlxGvKMtw8NMYvHWjOzmPhGx2JfjE1pw1gFpMGOcMkqbxkNqCmeMQcpNdsMEtCCR
  QCko5h+eDUFFt8OOePjGQtQcW12aVTNUz49tCpO1oHR/ck2xfrrSzKSYgp14F3hQ
  mN+n1Q==
  -----END CERTIFICATE-----
  """

private let serverKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEogIBAAKCAQEAwyK94Fg2WmsgwNyqJEzsz60duHRRGNzAxjU7hLUjAh3tQxYh
  i0DmAOIsJSaNbfoM/CbqXiz1z4k8pMlffrljuV5LH84yKQvrYLdBFUJC0O/yoQG4
  EdkVX3WWab9rCxhX0hXC+Le5qmQwXlgxOiY0LH23u7FVi8CnJ0mBZS9tPEO8/OXr
  ZmC9xSP1V1IAv3QAoCDmDGxQzsGLn3LuMIqr43V0ow8v0mScrzfWdQswxQcNE97+
  eMTpuM7HkLmZxsFrXfAfagWSFA+ZkwRCu7BHB7N1BXBVyurEXf6WbSFI59oNJwuD
  CvRauQ0FBJ02+LEzl6zkCpTZc/PvbCsgjbljKQIDAQABAoIBAD+6Kd6JkH6o+9Jg
  fmRKhxAvzkP+ILoI5iAVJHHroho/4cuF/8B1mmfxdU9QruGaxwDWSLYm4sQ7YoXC
  iiBdtTbFl600buc+0EkOr/+cWyvXIRr5775MchFx2oSAkhnWgl/G4ZzOi6EdBTra
  fIEsFt/s0sNGX9S7PxuygsKj4X3LYvTVnBPVdS1rbZRud0q39bgsCiGTzbO89Fdn
  g0x5uQh1/glxSYE8/Jm3LUBD0KnMWGQYt/XUmNbKLVgYOEAJD9QefEV1ZUJwKd5p
  JHYNYm2d/xs8cC24d/t4BaeVCL1Y+WRaOlSVZWEBAVy8kLeaMoJVnvyVHSfkm7lz
  7LaZLTECgYEA88D3rJs8Wx+xNp9DQmEpX7MLM+IOI/mhTvxPGQy9PSmVV8Jbr3wm
  2SzX9ImL/stSjpD+WKVNSoecJUxVyAJ/yTmzTtyzMfh0c48vz84v540s7Te2s1Be
  snFmUy3zvTYwOUTAKwQfbgdxZGaS4/4NKbU4pQTtY9DzaLDFXS/ASC0CgYEAzPB5
  aXDg473/LaubD4uGWCd4DyFo78cEILE1MQMQq7yUDBdh+ebOqRRDyWH7K9UFT97I
  uaaVSfdCQNSAI4dPyOegsh/DeC/sMTEKxu1V+kbu0jvXzqL3pnfFsFjlzNQmc6qP
  lbYlgYHLol3h+XYdVUq9bmu9U8Z1BLpTQfGGSG0CgYBPAn6FoW/n7ZboqKkJjCr4
  DTYVZDHHMXQ7AQe2i+2PNLpmzuYfNLP281Uwu6D4PvmMoqz/GN27yccwQ9UOVtkK
  5bwcVOd0zB8bEg+iYSgf+x/T6Jo891EqsB1F2wBFlZn+Bi3wA48YgCseKy1z33Zu
  zYIF41n7X9B2X84pjX/bJQKBgBIiSSv6T/v26Oh6ocrbVrTgMTBtjWKCIqxd4c4H
  bmcz1YnIW+QH90tgvqrIH7h+Le0mUm6S/ezAkz03UGtUYsvtKvv38Yzl+KlVpJV7
  lLsDocg6gVsIco9pU7XJ9/OK5igf9HqT1nfCK2mfkwpG2EuexGpL4EHUcrBLaGiS
  XYZ1AoGASAukBz2+w7Bw/OXCR0P1V8Q+BtIkyy+TQXiru8wQSy0T+5mFhBySstpS
  UojyrffOPvyJfpqP6Nu0MZEgdUqBaOEexkyBwfQe9YFNEyYCvcH9R2MEFNbB/5aM
  nTG98Lz1AVT/XGyAxdi7lJjYLthRR6xJVYPl91ymbzJOwNZEBZA=
  -----END RSA PRIVATE KEY-----
  """

private let exampleServerCert = """
  -----BEGIN CERTIFICATE-----
  MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNjA4MTAxNDA2MTJaFw0yNzA4MTAxNDA2MTJaMBYxFDASBgNVBAMMC2V4YW1w
  bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA38ZiwDl+9k0E
  lqmb8PCTqpi7coZzUyYoEPv4PZRrsD4bHDYYmdfiYDdXMr90ce5krBOWv1Br8rFo
  05mZPY23pdM74NY5v428OcSP7iX9+YsT+RxNqsNwEB2BJ7Aw851p77O+pLrOHoFW
  WO1mZXTFMhYoaXBmx0KPSDYgxsiv4TLuIbTlj1/x18PkLEFeicyC9IJK/WRco7om
  Lk3mGUFWr0C+25mc6UfcGrBAH4LlCbboQx7EL/xCTkXUvn0fdQzny3wOQcG5un9L
  cRmk/SyjOG0K/B76O7T+oZThq48i9isvamj5V62wdH+IPcc0pRDH2trUpQOZHaiP
  CtzwlIKCBQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQBTKin/cYudwkXs2PdqFW+i
  BS4atxmMQmn3PDdkkzwEoDLrKx30MyTu9+ompQWuqeKto/qIdBtH0DLZQl5iSKTa
  o7Py7dQvD5y3NvrgkRlCi1gwDOGmRyo2fXocgTz2G2SBymf3aoOMAJyQge5F7YIB
  tdZWA7ZpW4jZmPuo3IwgN8O1qq9ba7evTnKFSxCvxXMeZDl8acKu+DPzl8/zkayF
  wVxuYBNU+NfYaeYLr62Lv56QimzaS7sEyjUicRRIzoC1GvDF7cVbn+gmBGddRpV0
  5CVcv8hYiq1usaWd1mGfmVABHWliQ/DHLcYA/U9UYyq2qRgDzyEiAB3vMlVAPVvw
  -----END CERTIFICATE-----
  """

private let exampleServerKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEowIBAAKCAQEA38ZiwDl+9k0Elqmb8PCTqpi7coZzUyYoEPv4PZRrsD4bHDYY
  mdfiYDdXMr90ce5krBOWv1Br8rFo05mZPY23pdM74NY5v428OcSP7iX9+YsT+RxN
  qsNwEB2BJ7Aw851p77O+pLrOHoFWWO1mZXTFMhYoaXBmx0KPSDYgxsiv4TLuIbTl
  j1/x18PkLEFeicyC9IJK/WRco7omLk3mGUFWr0C+25mc6UfcGrBAH4LlCbboQx7E
  L/xCTkXUvn0fdQzny3wOQcG5un9LcRmk/SyjOG0K/B76O7T+oZThq48i9isvamj5
  V62wdH+IPcc0pRDH2trUpQOZHaiPCtzwlIKCBQIDAQABAoIBAFG0hO/8zk+uFWPR
  b//MR459j8ukLc2JXA2/gocxfxRtyMZHNjpN6fkJm8wKvcCvs5Bk4qDeA1wszMKe
  Daa87PYeJ3nTnmhDnxtUmtzwgEgyMMu/OtiD3ZH0w+iy21zH+BsufQh2sLXQsa9s
  lvuqZCoCjyTYhp5wvhI2uUb7lcRafnG8KzcRdzIsWzsYbClP27r/xh5P43c2iPTh
  5Jd2FLLMtUnm0P932BB1cfWKgk1sREs7X1VWnBvLy5o41GiHRCbD3TVc34qc6mi/
  0qVcUofU6XVCO3SYBInLyrMoTFzvdFzCoXFqcnnV2kugwrIBQtb40F5++WziYV+6
  WzScFwECgYEA73ZjdTsOCM/HmOS3pyVQx4swWD3uCh7UB8vtQk+bNcrnmdbWg1kl
  kHnwOCgXW3J1qxyVskWsVf53QRNoSeBETZeERFNh1/6hm5lzil1yYZRkMc0AOQwy
  XR3RHvD1VKDTEZQ1Yeso6+9X00gWXfVO82WAl2ye7TZD2Eyka2Fs98ECgYEA7zql
  yOtqatO35TkvPOvI40vXQjmKZQ7oPDIu5fP22zRVzkfkli9F6kUf0cIdtXnfBUoO
  slQ0abaLPMQDuJBC/ph9N+3GSX3ah9hPRbGCLU/zpuOzSEvmBw3uDnZ8Ed6NU6hb
  /HVTEzw+GNhCVQ68vTrY3Fq7Lc3pf6KGli2ae0UCgYBsckE4pjYE55SNOYeyusOK
  mw6Z5/IVw0BjB4e7sDGqeunIUfN0KLtKYu7Xf9CUKZIAnEFvKv6RM1zuq8tfKaHF
  Qgk0qE53c2nc/fHFh+x1JK77nsurCksEwKwkRxvT58GvBF/oqIcv0oUDunHmu2G1
  +RHzgc23wAuZuZv8xXKEAQKBgFq7S5VgdAQAOIbfoWLhqldKtGGRoUOi28G45sCg
  Psf0mXabHb84PrQTc3YCwXHKvyMqa1iHRzmw2i45yY9+Z2pYO2Wy8Ll+2hsblzU/
  lbfJ0wdA5QZOgve5+MfTeErutXs9J2YguVlaR9L0cnQAGuVKJGWuo79DkYOvCIx8
  z1JhAoGBAJGQnyYYAhJKfxsozH9Y6VkYnk2dNGdCTTAE9fOIIiU6Q62EKgR4i02O
  WaYiyXncp0FyxOmpVltAm+sUNBMsGk1Zv4NG59PVO+5Y1QkTKUaZgyDVqZeVIoOf
  7idFQAT/qgo1tE7uVCweKeMuYtmvOrc3Y/oVe0myRMLfisyhagtM
  -----END RSA PRIVATE KEY-----
  """

private let clientCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNjA4MTAxNDA2MTJaFw0yNzA4MTAxNDA2MTJaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALkVRjVFhcRC9hIp
  WYhjDc5ltnAPjd51a2AThKxwgGieAVDJLBHXLfsvg6cqqjMgOmi4t4mtHOGZIM9c
  Fwum0uPwn63LgAYgwqwZ8Ulq+3ot+K1hoRHkH3X1Ee6WVxzwMGB7K1cU7bUUTdbL
  LyKHd10H3f4luG5bwbwmhLtrsfV9O5483kAysy4FOJ89K0mCw1fn1kgnvCCfDhXp
  qStJ/YHJiMVf0RG4sYBCSgMzGdLfcHPHbeeg4LY+J92kY82vcPd5bKHz+g9xb5y2
  lPthY+2pon0ngn2Zivnh+nwC0UBe941uTmtqOpph3CBMMxL+oEu3T0BFsEcpGtBC
  v5YJzBECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAlAg+1Wz9jM+7zUetYRpCyTzC
  JAIkIkCyhDMPChT6SIUAFtIqKYsYyKAT4xfqT1ThuxPqyPcwdZyty+zziPaWAJbk
  za5lPAD3VqJKXNT7FnSgrcyFTNybphxLb/YOZyjpJU+V6oWugHgzCvGfvGPv57dk
  JwAjTuddrc/KdnVqQZG01vEjRTVVWLrzWa+LKvh/UdStIvjNeVxrfnEF+Zn0aeJr
  Suge82PPRt9IMJLtjiz4gE6VwEP59tVtC2QpFTmUEJ9UVb6CMlNFO7NK+Hlhqekp
  6h4mENS/2QPPvE5jlEjUJ2nqhoAgeYw0Jv57JfTpXKJnjsuLgKoqlAnnAPXhrg==
  -----END CERTIFICATE-----
  """

private let clientSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNjA4MTAxNDA2MTJaFw0yNzA4MTAxNDA2MTJaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALkVRjVF
  hcRC9hIpWYhjDc5ltnAPjd51a2AThKxwgGieAVDJLBHXLfsvg6cqqjMgOmi4t4mt
  HOGZIM9cFwum0uPwn63LgAYgwqwZ8Ulq+3ot+K1hoRHkH3X1Ee6WVxzwMGB7K1cU
  7bUUTdbLLyKHd10H3f4luG5bwbwmhLtrsfV9O5483kAysy4FOJ89K0mCw1fn1kgn
  vCCfDhXpqStJ/YHJiMVf0RG4sYBCSgMzGdLfcHPHbeeg4LY+J92kY82vcPd5bKHz
  +g9xb5y2lPthY+2pon0ngn2Zivnh+nwC0UBe941uTmtqOpph3CBMMxL+oEu3T0BF
  sEcpGtBCv5YJzBECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAZPPqBG5eY62gLAe+
  IaZainvW4zHO6QhnG4Z6x9U2ELxeg9YBgr7J2z1eHCTj1CvJVlrmNmpHWuElm+sL
  4TdmT+mnFdov6dwm/YMJnBJ/9uwMb12BzVbFFi8FBrZwQjtTatgj7LVqf+07Noml
  vzENwrj1Y1/CF85DCaz8Bv8AyI0rwZ/gnIcWu0LtTbo8wBBLboM2HDLHoGl6Sf8Y
  yVisg1i/S3HV6ngYUcBNV4z9AX6jfUvzDOH8aVqniC4NnwNIDhQk8hjmk2aWul4R
  FXA6/d4aMX/YAr4Oir0jv9iJBnAGceHLrkcO5mdLKj8hdSukzt0yCqOBSsYNpRR+
  cZcjKw==
  -----END CERTIFICATE-----
  """

private let clientKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEowIBAAKCAQEAuRVGNUWFxEL2EilZiGMNzmW2cA+N3nVrYBOErHCAaJ4BUMks
  Edct+y+DpyqqMyA6aLi3ia0c4Zkgz1wXC6bS4/CfrcuABiDCrBnxSWr7ei34rWGh
  EeQfdfUR7pZXHPAwYHsrVxTttRRN1ssvIod3XQfd/iW4blvBvCaEu2ux9X07njze
  QDKzLgU4nz0rSYLDV+fWSCe8IJ8OFempK0n9gcmIxV/REbixgEJKAzMZ0t9wc8dt
  56Dgtj4n3aRjza9w93lsofP6D3FvnLaU+2Fj7amifSeCfZmK+eH6fALRQF73jW5O
  a2o6mmHcIEwzEv6gS7dPQEWwRyka0EK/lgnMEQIDAQABAoIBADoo10ESMbC0ogKe
  /8V96u66w5N/L8OB/lXYjE5ro848KImsTa7lgUt3aNV08LrUG8aglPwsa/DwX4EJ
  nSxKJeb+zA6e7gH+9W2DUXESryd7nrNNBIJMvx4f/pyMnZ84UttemQXqS7AlSzh9
  7Lfa/cU8HaQpUkVLjBuFtxv2AZv0T51JlcL3RfvCVx/PYJDxX6D6k3gzhpvFWGz9
  E9jVG3ktXZBSf4x2RuUEG7wdpsKszk31JIw03cPgfN1W9ZCStWMXr/39wpKuIpqQ
  H5bKZgvDT5JsuiKvyOodIXZbbJqmw5D+HdyjIGJ4hgKg6t+Db4Us3KYRWHBVAuwJ
  InxJ/AkCgYEA3g15rG0iLp8xlFM4BaDSUpJPhjk5hBBKwwF5FXJOhQkZpsx1kU9N
  UFPtKD6FTJhJrydgg6bY6ckzToJqszt4dDFUK1argRiw87EhpIRW13NyVfxSVqmb
  tJFc927zQ8Ao/hd27hw5u0JWgzyrw/b2R1Se9zVCodqprO9dutrN1J8CgYEA1WDp
  8NqvJd9AAKftX+46VzwO2OltRtDCOpeqXrGi4ocL76APEhoCUonZdf8i3TX3UyCN
  kY4O64FWt6vHdtkqm1gFJS35bjF9tvU4FE3Yfe5tWzMi7m1dIxUu0m2WXYRYgSiT
  eL0qODhI5goAYZRVh6wuq/02vMHne/yjs1d1cU8CgYEAzN1B1IMbdkgJRf9BQHAP
  m37BP+Sr29vsHd3OCKtdJgAvWmRoU5gGjIXh169W7EPUN3Ts5omYtpiabWSFbLcB
  erHIJfPgZ0qQd0SE9XPjawNoCUyx6qKwtPcn/mCur2MqbsLXRvdjjBC4IHxpPHMs
  5MJ9pzXMM+e5g4OTxkD4haECgYB5PBsvUdD5/6JpvP/N5ZkYP3NgIyCHf80bZVjT
  fLJDat+JQrPNYSG4q8H2nQO+FA92F6TX8pLflBklOmCWUkU3BgfGXBzAUzZOYX1/
  a8t5oaJYkvFh7plgeYSk4sbwU2XF3LwNec0nLDOfIEefKZx+/YF3DuOu060mcSDB
  oQuFWQKBgFtynkAsbwzZg0idVZ6cZGiBcnFyO3khxAkeYfCUyiv7it/YSolHt8mO
  xOjO+sUIrSwXaQ/txbI62bdl889td+E7AZyGeUhkHgFKoCmRZNtezAWnqZpXhg6U
  YSyal8SvoY7uOuMDjqTo09Dkk6h5OnohodafGIdX2/GOB86lS8zN
  -----END RSA PRIVATE KEY-----
  """

private let serverExplicitCurveCert = """
  -----BEGIN CERTIFICATE-----
  MIICETCCAbYCCQDFmAHCp/B6UDAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
  cGxlLmNvbTAeFw0yNjA4MTAxNDA2MTJaFw0yNzA4MTAxNDA2MTJaMBYxFDASBgNV
  BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
  AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
  AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
  sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
  Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
  N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABJ4+
  SIHN/Gw+WsSeWW00a1Iox0Gl57rcNoMw/yWZvyzKnbxlEW9pUuNsKgkxUoGt620q
  10LDKFinJiOAO5/c1BUwCgYIKoZIzj0EAwIDSQAwRgIhAK/FwHgl3Bc6AK6OYbiD
  +Ktai4NM3sCIYhmeE9K8Yr8iAiEA4YFh2e5lbo3DHH/U4hiLcyYd6UThS4YHW5Ux
  ETCtYAE=
  -----END CERTIFICATE-----
  """

private let serverExplicitCurveKey = """
  -----BEGIN EC PRIVATE KEY-----
  MIIBaAIBAQQgidtQACmyJR8u54e+rXxgHAy2uAmT9pPma581Ix6zUc2ggfowgfcC
  AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
  MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
  vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
  axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
  K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
  YyVRAgEBoUQDQgAEnj5Igc38bD5axJ5ZbTRrUijHQaXnutw2gzD/JZm/LMqdvGUR
  b2lS42wqCTFSga3rbSrXQsMoWKcmI4A7n9zUFQ==
  -----END EC PRIVATE KEY-----
  """

#endif  // canImport(NIOSSL)
