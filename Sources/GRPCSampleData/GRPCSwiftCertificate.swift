/*
 * Copyright 2025, gRPC Authors All rights reserved.
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
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_785_404_969)
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
  MIICoDCCAYgCCQDF5xyyZRK3ozANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
  b21lLWNhMB4XDTI1MDczMDA5NDkyOVoXDTI2MDczMDA5NDkyOVowEjEQMA4GA1UE
  AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALa8a09o
  bv/IQMRdHhr4wL1Ryd2UQYS3g5anWMpyRMlHQ0q12/bc5g3icecWyMislLhh9XQh
  iHniV7/d5oBIfti2UdP/SR3+HxCHaIJcLUwxkJcG9ou0nM1VV8+NVfgZBksCz0sL
  DbTATMHnDD1isUGZ/IjAVV/s53iEA8XqwYYfKTyPG0L89pFZ2dLH4RnssuZ+JTjV
  ms4APff3dVPMXI/MnXJ/PHWTEDuda0bu4i3gdLU7Cs/pkh7LT1wBCYJwUTEQmmPa
  jt4sRC1cMzvGlkbFwB9MFztmb5dy2FGlueNBNcdIHN2xyPUaYA2MXpmJwRHa20yF
  MhCk/+xo0LSpNA0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAgKcyMb5XMpz+2/8F
  vn3/ObCd0SgwZW9K0Kl3uQ7X+55f/uwIgZR5Mhnqf9UtXVY4dVZnsHZeQMafa83O
  0eLZojf6es4xLctECfQR+AXrdjsqPj2NLwKiKbvgG7jA7Uxg4DyZUMvFyGSiLFq7
  EhAY3JkqCautQVhttKf080E16ucQTLkkI3AbdQufi3ZWSR6Mqamcz0vFCP8AnRY/
  WEM8I8VNkQcX8D6xPG+1ZjBEHBf6cZtUT6ubY9jrRKJ8zxd1vhy20ibAyKLUkkUt
  xWV2/LsHT/3KEBGRt9eP8RfcJstXd19l7CDXl+iDo4N32KwlsUBAs8r8yBTxAhzI
  gCrq6g==
  -----END CERTIFICATE-----
  """

private let otherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICrDCCAZQCCQC+kH39mWpXVTANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
  b21lLW90aGVyLWNhMB4XDTI1MDczMDA5NDkyOVoXDTI2MDczMDA5NDkyOVowGDEW
  MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
  AQoCggEBAJWi4e/HQLa//fXiPK6MoYzNfh5fY6+pWn3ZW5M991bqLF3ncSxXFCwa
  WW4ev7byKCWAEgw8ZGvHWjN4No6kSN30RvFAirQh/A2S6ogfU6ntanO4xv1uJcjg
  aTJcRK01art1YXF+OL1vRGojUSwfB/xgPUrREkk45CeZfuHx/WbxL7K9OOPSo/PX
  TzxWgzr+Vq77a7PDGm5d0dW13BGHJJqpVoTocy+e5lNySJ3mnGRzTQ0t9vPHD9LK
  qp2RqGk0HhZey/4iZZUczmuTb0Q14aKHbsNAY4WAfkTxzmPn0IdMZsKXEHyw90i0
  M7D0eBQgePVAOu2nu5pSBi4+3E9ZmNUCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
  KQ5DpPmfkH54iRmi6YUBSTO+2Wb2McWJGremYzw34HALYHme+LI8vZhhwyR6Y2OD
  qJp6FSQl8dkdFJALQT1h4v1AJ7laL94BuV7AJOvEXnD6pEQ5i7Icv2i6eA4Vvokz
  Czy+haYtLj+s5hW7r4Efp5q8xw9Hi2DC9MV57g9aIjV5Q6u4zRowCBoh9thbDhuM
  ERdLWMmrzrdITIN48LnJ4HTZneZ3vud32qL+mdp2bCIu7e1MNzEjHn3OlyJYe0FK
  TvWAFtdZ7nj3cHoGWxatdJJ3+kTNkQgTTftsF/BhhOhGiem2KympdyL4qW+Rb5LK
  pXt+OvBkcytZ+DOEOpjbYA==
  -----END CERTIFICATE-----
  """

private let serverCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNTA3MzAwOTQ5MjlaFw0yNjA3MzAwOTQ5MjlaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAK+wbTRqD77+g+Bw
  p0dtYI/VnhiLO0GH7pxjBEiVlmfpA2RIbsoLAfoZTYM4R1qaX74Lmo2WxewBGG5O
  U0a3cAZm3pdtsNRDpKGmPYLUYckvCf9Th/heWBf5doGr1mEqMNridc+lTAGgdYGi
  g6DCY7pinbxQBRY/exoMIq1j0h1HK79XCiKkjMtfTy1qUzUXXRo2+modJKlvhrog
  u6hivGn4AiPrkSORm414YOOa2FUqysJYCfNZ/35KuMunphTEwXc7btVpogFlDzV1
  FcKthiWyWRP8qu36h1PvU87fqhE0C2r6CO1eaVTJeeoyBYpVVd5BGSOhaHQzk5Bb
  c57hUicCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAn09x85aOikP2ofCvT2nHjs72
  s0C9b6qqIPWc6bRfjI91b/6/eLOcMHByoU8MTpiD8pKSqKUOSREjNtS/jTyV9zKf
  KzolkXKo0gsa8dpJ9HC8+zuX+nfCMeWKL/F5Gbt2CyrLfMksv5OJqZk/JnDFkI01
  RguInOYJ79vfF9e5adDdU4oAMyrmlEl01VGV4qtbM+wB2eHgohpU8B//FxFgMMbM
  rBdAOOfpx5hKHXv0HAsj79qMRhQI+LYHNGgS0SN/WsEGGTT1106yECdEQOZ69ehj
  /epp/0b68T1xM/svCNrWawSln+E5XlZH20BvxMU1JcExw/u2KAKIXYnomroWpg==
  -----END CERTIFICATE-----
  """

private let serverSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNTA3MzAwOTQ5MjlaFw0yNjA3MzAwOTQ5MjlaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAK+wbTRq
  D77+g+Bwp0dtYI/VnhiLO0GH7pxjBEiVlmfpA2RIbsoLAfoZTYM4R1qaX74Lmo2W
  xewBGG5OU0a3cAZm3pdtsNRDpKGmPYLUYckvCf9Th/heWBf5doGr1mEqMNridc+l
  TAGgdYGig6DCY7pinbxQBRY/exoMIq1j0h1HK79XCiKkjMtfTy1qUzUXXRo2+mod
  JKlvhrogu6hivGn4AiPrkSORm414YOOa2FUqysJYCfNZ/35KuMunphTEwXc7btVp
  ogFlDzV1FcKthiWyWRP8qu36h1PvU87fqhE0C2r6CO1eaVTJeeoyBYpVVd5BGSOh
  aHQzk5Bbc57hUicCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAHwkmwqsUO6ieGBzy
  pGajXGRTSjTCAt01QVRmCh8At6teQr/ZWKMfzYdZk5A3wXUuDq9KDp09TW9Zrhjw
  JK/W50dCuwd/TIMPaV+YiK3D3vL119gdZjFL0J3EoV9iK4k9fA4MTBTOS9YdkipK
  fLMEGtccaVu+IrHcoFvdus8k1NjULL9OZcDCpD/l4RpNcOSZ4MjFZk1Fhx8+XX8i
  sgw8k4umziWF8+uzfDd9MhorLtt7xrX20wJ17+g7jF2qTR7VSdE8+VGZ8On8eUe+
  /klZaXQxcmIO9+P6UEX+PASvwRgVrMlOAgzhjZNA4bDP0/LX+fGLi+H3hBotPQW6
  KksYUA==
  -----END CERTIFICATE-----
  """

private let serverKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpQIBAAKCAQEAr7BtNGoPvv6D4HCnR21gj9WeGIs7QYfunGMESJWWZ+kDZEhu
  ygsB+hlNgzhHWppfvguajZbF7AEYbk5TRrdwBmbel22w1EOkoaY9gtRhyS8J/1OH
  +F5YF/l2gavWYSow2uJ1z6VMAaB1gaKDoMJjumKdvFAFFj97GgwirWPSHUcrv1cK
  IqSMy19PLWpTNRddGjb6ah0kqW+GuiC7qGK8afgCI+uRI5GbjXhg45rYVSrKwlgJ
  81n/fkq4y6emFMTBdztu1WmiAWUPNXUVwq2GJbJZE/yq7fqHU+9Tzt+qETQLavoI
  7V5pVMl56jIFilVV3kEZI6FodDOTkFtznuFSJwIDAQABAoIBAGskXcTMNaQVlRkn
  umwN4Qh2jr6LEm0JV9PZcsBNMXdXG/FpVt8yTVdXXPT8Ok+fu2mrq+pTG4qstFh4
  vcJvlgrhazfP9jnMsra+Kd8CZEwLur4SE+a8ql6cjM/RmqCQ2VBzMMOcG7kWQPL4
  x+sfATCmeWlhJ2kE967P3cn+CSI+xLG1gsIP3pSRQg9Upd6iMu6qbxarS4fOWAEv
  g6/VAKBnydwHqB+VMP0ysmLd06F8nJMWwZAB/W3Yflt7KXamoehPgYJS9I3nPdy5
  aUw9M36aBKzCnw7gQhDAyDVkN9v3fisiZvolMaJDl0dhLfbYXH1L5ZxwfK+FpJB+
  Jqa9m+kCgYEA4+JstCmuDhuyyIh4rRG4XaP7Om2qMowfPSLqhvSeI3lklLf2olqh
  U+qWN/9VtEK4RUXTcE3MzdOqIkNGvHpd5+HMgXjvgrJgl+kSPul28pMOx52d3Ige
  0LwxkjxAyGrOLi+u6gEPlE8O77fv+cu/oLs2xN0NYsRCO3XCDiUCroMCgYEAxV1y
  60uUoyEmpshCFdNHapqZqnHKloZSmdoWA4OJxLKyvBlWjgGFVwaSJcgQ9dSO1Rfb
  V8Apdf/HlqeTS/1PwVv7TnqwEyVb2TDIsilITthqMb5Ei7WTjt+drB0qCN5NDJuE
  MPAI40i1EPUQvF0WfxkB18E7fNGwqb0GtuaVvI0CgYEAtougbEmfBeomMwEvOeQh
  /dDn5IwIdGlOdNjNacH2E5Cgg4lB5hgXd3NJVh4Rd06i8crXbvTDhHVzqfKebUjQ
  hHmaKnTH17gwLEAlv4OhJvuqMTkPRaM8nBTE2NGvS1xTQSgtQ4IKCtGxs1FyyHTw
  Uj7lxpkUqfNw4tSX2GDJXyUCgYEAuct6BpU1DMiFeVZmF+O4hFubsz/CBifXFKyg
  MpielgPfjIGR4Mb/vmgaJuULSlDaUTJPM3Fb1pB+VI3WdR+2+ADeOAf5P1zY9UIe
  fNGuF0NV3RQPtTGvAj3yUXd2/bg/8lFohSVCSKxGf/sj0R8UsXtaJ8DpflxsIa4n
  5wB1D3UCgYEA3C2ow3kI58xdEfmY4HplzVjA9rU9Zb3SizQVQsscvkd/S5u0u8fR
  0dklHVF8zwLAYZyBEkwJ48SXXfQKlpjXFD2+rOAqiewl7CqnmjEMPg1kQ/SR4GSF
  y0uNIJkdh+5hFijxVcV9u7loHAb0tnFh/KjRLDK6DpTc/EqoUGLZ5XQ=
  -----END RSA PRIVATE KEY-----
  """

private let exampleServerCert = """
  -----BEGIN CERTIFICATE-----
  MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNTA3MzAwOTQ5MjlaFw0yNjA3MzAwOTQ5MjlaMBYxFDASBgNVBAMMC2V4YW1w
  bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvGLrSUpQlYkl
  t1Bxuz2yqBOHfsdQn4UiDFItbJcbZhNrOgNlwbPAO4p6s5iHDTcNyNdbnOr9zxNE
  9K2YJurFbEMZfU1v2B/VHYbjyjKXe2dG4I8gnm17ZCXXphwb1jlsIWyQW2qehs3E
  BK7pxbtJjzV+VSuEeHq6Yr8b/CN2CP1LHnM4SSXuQmoI/pXTRh0dNe0CyGyYLAni
  O6h/e1YAQKYwbVfI3R383GFGsh+7W58QFLWYRmCQAnZAT4+HAQS1l8M4EUDb+iBK
  MRQky3e9QnzzK4QMwh4qUs7TMauALoxnDEg707XPtlylKWOy8cG+E6O6bGl1C9C4
  vsr1r/rfQwIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQBrFKXsss5/bvswWjMif6ZO
  w1bzCjmhFTnB9xkny/Il5pNJot0iVAaKzUtGwAMb2jx40a6V+kl9+SqkSJwEf5dB
  2gcAD1mFak/Vwt2wnwLqdeVWb7mvyLfBNLxdmYFl4UmAQePBf+pJatI8zwHlSW2f
  YqhKDJAf4I359EZX2RSI1qGT5OKiOIhrNzvn6SzchFGGC4epMiUx6Rv6qtW8/jUx
  w7kHzEaXKlbRC+xTjNBIvCdASKgDMP7YJ38nUTdFvTADFJ632uZLI/Ms/bTOBIpf
  ZEJJblot5F09YT6/+VMwB7jCEG5bRKjv6ELcQApz+rbwrzgwHpdbcfJftuXirk6r
  -----END CERTIFICATE-----
  """

private let exampleServerKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEowIBAAKCAQEAvGLrSUpQlYklt1Bxuz2yqBOHfsdQn4UiDFItbJcbZhNrOgNl
  wbPAO4p6s5iHDTcNyNdbnOr9zxNE9K2YJurFbEMZfU1v2B/VHYbjyjKXe2dG4I8g
  nm17ZCXXphwb1jlsIWyQW2qehs3EBK7pxbtJjzV+VSuEeHq6Yr8b/CN2CP1LHnM4
  SSXuQmoI/pXTRh0dNe0CyGyYLAniO6h/e1YAQKYwbVfI3R383GFGsh+7W58QFLWY
  RmCQAnZAT4+HAQS1l8M4EUDb+iBKMRQky3e9QnzzK4QMwh4qUs7TMauALoxnDEg7
  07XPtlylKWOy8cG+E6O6bGl1C9C4vsr1r/rfQwIDAQABAoIBAHcz7Ieyo20LnDbz
  ixOcxbh+qwT4n7Zgqpu7QAzvTKH5dab+0VuRHvlN9bhAsmwVQv6r7sdLFpD6M27T
  jWxKr+OCTdWwsy3BbrvBR9AA1UN7pSigyFYXFrXXEC6GqMKUESzRIkMGIwtPllIU
  T84TZUdd5POFlswZdGjZXp7b3WtvrFmXzIYD66sGK9sf0h7vannGv6yaqtcN2yiG
  Fj9BvlyU9RKws5RMB42lZZ05vH835f7/23NY2MFHiTYwjqTObtFI4W3JTHIupZSe
  1KU2UDfi7uvP7BsCC+/RiVpbYkbb6qiDYh4P2kPyFaRwlgyAAvJVKKkW1BkiCqQ8
  OUv+N+ECgYEA7ZqiZEkywXMKT5y6PGodS+t8tMbJSg2JEzbVk9/939+eru28BWkr
  1RKj1TMvTfBtX75Ld6xJDMysvse9G8SCT036mZD4HS4fkOH1A5/rOscXb+EC0OtY
  WaZP4IDXfOxxQ2x4CpPTsQhyb5lYd12PayjWIwPF/zaYsrR7uKXFbjECgYEAyvjH
  snYkEcV6qLAYBKDJuYQp6G9llou9x+k6UXBwoW+MAurbvE94a00VSZ/7jBaAFpYZ
  XZrmEe+KHZryvkVfrVnEpsgTMmBYqFlybJBu1pXsFeO+ycA6GHH9Hde4tFGkmkpq
  /WQlNYcmkWfUZgnI8waCFgV0mphUsyyu5w6YQ7MCgYB3zt9PnjE/plhuqGKoEAHR
  xF5PcWUSOB0EWUP8mpeTCVkkb6+9Mrjtaca+vF5/+FnOS1AWegMjtxjr4h+THtVu
  U62nPZg+boFwNt+rAjpEmxtQSK941RLpsZjZZV5DGZ5LFyi4fK3juJSrfTFEjyLA
  MAk6Aq8V71uz0JoKE1yoIQKBgHYHYSj35lWnPoKlk/HtBiEpJ62QScTXkg6UI2OE
  PRrDYOm5ZPoGRIIxGvXrYD3AP8/ijPGPx8YaQ3ifyBS5BsApeV967R7YQ/XxvcY/
  3xRNrjG0dBeh/qaEcqpN7Yx+BXfrWnfrKnAMHXNkq3CCtCYOXMstdPcJKgffLf4S
  0JxdAoGBAK13W4zlnQpe181TMt1q8ZoiB3MHOk1H49cjErDw3QiAMr7l3VF95AjX
  gnRMOHIO0CviNxlY6WRKBd4hBLel7Zr9Eofg4hIGkOcI2SbRd5nlbW9BSmrcNfAR
  ZcqoSJTo5W336betEReJKi5LW+1PHu87mcPdM8ucAgDBPFPJqWPe
  -----END RSA PRIVATE KEY-----
  """

private let clientCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNTA3MzAwOTQ5MjlaFw0yNjA3MzAwOTQ5MjlaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOGBa6FEXnLsHT6O
  cwLDo6oKUBYaAQJIxE8puaUAwnd/Fvz8gd5ZCwtRFjlds2FQnjX2j3jLm+3AAwZi
  +dLYTC/oM8pUooBjbswgJ3OxIHJStJt8bKsYZezvlBQ3U4sz579zy+G3UywFlX6y
  dXqepe6KYonniZ2mX/0euGPw6hhbryR1RupYVzav0RgLWmjHUP0VJc7ml1pDcvCq
  fPTtfD8duZwIdAT4WnNbW6aQLY2DCxeG+gOx6zJ988hRbPayOyc5FH4bCaF4Fpip
  1KZvbvXrEbgzpYihmxPoT48ADlgo3iLwi1+5Yxkvy2rMNAfP7nZz544AkNWt5c/N
  x1Tvsl0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAm7pQJ+MVfsE8kap15YNgmVno
  snMItichI1GIpuxXhRCFpQgrhy3EIm/HZj6TQ/Qu6ua/qD0GyoaHz+7J+K/v9coH
  8QuP9vFagdIigmmTQqLlZwOOq6H/ZZBSA1WR6S3F13AZxSC9i/dpKPBC9FOquvfW
  o9z4EPpUxWFNB9DNp/noW3SGWiXct8h1X33R8swwIHS97k0GngQG8pwO7Evzg7MK
  7l8+Z2hxHTJbCqIk/DjG7aWHMd6Zt/diyROOoWfg4zL2MnqQuN3j+ORCokkKX0dW
  4ML+Rh9vaUgcoRNeAlRCcaoalw8Lxgm/qyKqN+s1mP0HWGoQnbWLZiddTpN9xQ==
  -----END CERTIFICATE-----
  """

private let clientSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNTA3MzAwOTQ5MjlaFw0yNjA3MzAwOTQ5MjlaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOGBa6FE
  XnLsHT6OcwLDo6oKUBYaAQJIxE8puaUAwnd/Fvz8gd5ZCwtRFjlds2FQnjX2j3jL
  m+3AAwZi+dLYTC/oM8pUooBjbswgJ3OxIHJStJt8bKsYZezvlBQ3U4sz579zy+G3
  UywFlX6ydXqepe6KYonniZ2mX/0euGPw6hhbryR1RupYVzav0RgLWmjHUP0VJc7m
  l1pDcvCqfPTtfD8duZwIdAT4WnNbW6aQLY2DCxeG+gOx6zJ988hRbPayOyc5FH4b
  CaF4Fpip1KZvbvXrEbgzpYihmxPoT48ADlgo3iLwi1+5Yxkvy2rMNAfP7nZz544A
  kNWt5c/Nx1Tvsl0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEARoIkr72iVZaoyypV
  jF/N2CQo5czT0f3hKxDWFGnib0w0sPdIJO/sdYtVmcrKT95lWw9boiqCID42IoCS
  PB06cWsxwsoF6sT3P6VMXVvjb33trdQZFMPbOWOYMP/zC/nxbWbo0AGmXPm+9LLf
  5bbU25zuhHRkVD3ylGLTwdfVDtVRLyq8E5hjz/OqJJzcjgcTGA8U6EVHYgPMTGey
  LZCm9pb78stf8ekOo4ejr63ApT8PGUWqv7LQJbeHdK3dD+UhKcWl4uDxvKtkj5iG
  m8Tfe/TgVYRzkjR12UKkjdf9zYmNYjovT14LG7ucKddvSqcQp1uFFh4nnodJGlc3
  vlG3cg==
  -----END CERTIFICATE-----
  """

private let clientKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpQIBAAKCAQEA4YFroURecuwdPo5zAsOjqgpQFhoBAkjETym5pQDCd38W/PyB
  3lkLC1EWOV2zYVCeNfaPeMub7cADBmL50thML+gzylSigGNuzCAnc7EgclK0m3xs
  qxhl7O+UFDdTizPnv3PL4bdTLAWVfrJ1ep6l7opiieeJnaZf/R64Y/DqGFuvJHVG
  6lhXNq/RGAtaaMdQ/RUlzuaXWkNy8Kp89O18Px25nAh0BPhac1tbppAtjYMLF4b6
  A7HrMn3zyFFs9rI7JzkUfhsJoXgWmKnUpm9u9esRuDOliKGbE+hPjwAOWCjeIvCL
  X7ljGS/Lasw0B8/udnPnjgCQ1a3lz83HVO+yXQIDAQABAoIBAQCCgm1xCumCp2YR
  c03atrE80vUgpXIaCVUb37Eibrsdf38lcVoT/gKnTQmIr9MGKis2XfkQ1v3qbisS
  AixFu4r0WvXGTo8xsNpJ5v4ONd/qajU+m5ckul0a8FkKDi8arDKemfzQKFJJcv3f
  MpdNHQ45bPu0hj0d8VEyZBohNSe2ahr0uNrqSmEvZbHjGWZZpm9seMuhZLZpnE/J
  bf2EDB1uunSfNOGQ8+1pXVfmTQ07sOH4+PHkg+ZWLhkcrJRCePSq1+FfNDCAfJ2y
  WjM9SJ6RQIQWggdoL2JAjCbTj/XOAPd5srvrxHWit1PJhLCM7LFUl5iVqOgrnswM
  2rjZVcRdAoGBAP5q/qdAlUHhHpQXOhsfcokZvYMFYqWXvmSLOYsrsb/dWKKcsZWW
  AFsbr/Iay8Vry1YKTL3C4j6X22gzJSmFUJ5Z6vmt1oweNDlDhltwsOPneeof9Dok
  CAq9mF3nm7QodeXhhq+KZMNB6G48QPKsoBJolw9C//zz05X0ioczVZ2zAoGBAOLo
  Znz6Cb16ZmCZ6BIh3KBly1WV7VFx1PeSRAwn6ssOaHwnXDWQMyB+acB3wx0wAWLz
  yhLo377k/1rhVD2r+MrlNT0BdeQ6Za9SXzqo1Ib0IBWud1Uhv3j4lHSDooTev2mZ
  8dX1OdVEtvMFTTUFU1U+0t415LXXiHhlZEw/AwevAoGBAKb7hqQzqUMSBEXicMq4
  ey4s7Mt/z10sGVRYZK5JQWLSXohsG8o4J4ekxng6yh+LPmv8Wp35uRCoDuN3Hh8A
  Vwd3sNerFzPj5xbmkNqXPiJ3HPdjfaJjX7vc8JJBn1pBbBAzU3kHdlcJfQpNFbux
  PWaXqv3jVayqQ+caF4nhUYItAoGBAKp8hSzXzWOxSKTCXszo5lUZxsoaaQItrh8J
  pdkgUNiajcTi6fRQ0SlT8e8rzMzsWc5Yb/b/Q8WxV2+YJ+xifv8rcnHQ3BxMCETP
  dj+jxHNVj5nayUyMm8mvtBNLKFv+5QDaKwtgQkDMbU1xKU5yHufI2TUedyZtt9sG
  C3MCUSt/AoGAbmc0HPMkanUCXFHPdl3YtdXLBleWcPvyAQTppLb7QwtpbuRV1Tlg
  Jq88YJZb4RE+sXpfJ1F53NV1GFjBQC2xLh1PO4m6Nt/psaAnhetgnmhr+/qHLshD
  p4EgJTZCuJtyrjld8wqtOo4NxDhSK8NWPQJF16mTDPeSd9ADoCVtltE=
  -----END RSA PRIVATE KEY-----
  """

private let serverExplicitCurveCert = """
  -----BEGIN CERTIFICATE-----
  MIICEDCCAbYCCQDG3HfWx7Z/uDAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
  cGxlLmNvbTAeFw0yNTA3MzAwOTQ5MjlaFw0yNjA3MzAwOTQ5MjlaMBYxFDASBgNV
  BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
  AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
  AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
  sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
  Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
  N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABFuX
  OmVSV0a7oOdoL3FrJ2ITZuF5onuYAs22HqypxyL5tcoSsqmTYAfTDj00eon/goGg
  sq1fxuIEUj++LV4ysW8wCgYIKoZIzj0EAwIDSAAwRQIhAKkqfMJJkz4wVwKnJmqh
  ljmIgx9H5X6sqFF4twkI83pOAiAI87mIic25v+2bvPpw76PVJeH6K0jksw0SemQ1
  Qrxb+g==
  -----END CERTIFICATE-----
  """

private let serverExplicitCurveKey = """
  -----BEGIN EC PRIVATE KEY-----
  MIIBaAIBAQQgv5J4cSA5lxk1ND23rci8NJSwtmsIQgmBfYEk86/8jzqggfowgfcC
  AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
  MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
  vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
  axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
  K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
  YyVRAgEBoUQDQgAEW5c6ZVJXRrug52gvcWsnYhNm4Xmie5gCzbYerKnHIvm1yhKy
  qZNgB9MOPTR6if+CgaCyrV/G4gRSP74tXjKxbw==
  -----END EC PRIVATE KEY-----
  """

#endif  // canImport(NIOSSL)
