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
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1_753_797_065)
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
  MIICoDCCAYgCCQCu3t2RYSXASjANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
  b21lLWNhMB4XDTI0MDcyOTEzNTEwNVoXDTI1MDcyOTEzNTEwNVowEjEQMA4GA1UE
  AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOtVwFmJ
  Znuf0gC8tZSVasYrSbiDiYGUJd701SskU+RbzNZl7paYIBcM2iAy4L6S2w02ehfa
  RZoatGoKKhTZnyMu9NAYM1xAGiODfqC0s467udVBU6J2rU8olhm1ChZqfVBxcd9y
  AF7VjvN1N3gnGM2klAWFIgqaHoFAqINwHROjycAnr40uXCLNLukkt90AmMtL5Rah
  Sh0wOrx0E5OiiqWyWkjePTcMTwiRaYrUepo+EGFdmERDyiJtp5t4pcqdInJ6uA4s
  eiev9NEiGdWeJy83lIdo3N777r8cK9VDsHxHGiz72ZKE35MeIEk9weC1ph81KIZV
  cUDuO8nRPwWvBDUCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAT6hoeq4sJdqkaN+p
  QvpF9cZ4DJLw0dFujcWQtYpPCtMVQx14QSXaPGmUG0GLVJ5mUvzV0cwUC58JDXmS
  CDQ/vBnfoWQyblFQDZXOP5aDGOTmNIpFn8hutqsSDvMteh8R3zvJZBr+CQtP2Bos
  TH3TcnchhKq580hYazFJJ1P4jOqBXIQb3Osnm8WjJpGuDtOP8DW2Q2AdN/8Zl+FQ
  OrwiGMwghkZm2O91tYKvr45VxvyIpah36d5IFyAP7xIT4ua7X7ZyaCMjBmlK1QHd
  kKUVuyR2bLgpIRpj/KQY/UOdl1zu3MUs9OkG0suPrY3EOa0K7hDkXnHjX2ZipSw7
  TAuG9Q==
  -----END CERTIFICATE-----
  """

private let otherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICrDCCAZQCCQDjS9iNRZ49lzANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
  b21lLW90aGVyLWNhMB4XDTI0MDcyOTEzNTEwNVoXDTI1MDcyOTEzNTEwNVowGDEW
  MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
  AQoCggEBAMC3EEHu7uYtDsH0RZEQHQol1oDEOxL+SDH7dbKIv0UpgW5LXLQDDGR9
  FlKQbeNNtMt5mTd4TalqxZz+eMUhfrv0k3f1heEky/Wz53uRFHVNbDLEf/wa6QMd
  99HOBePy2yDWdQC5/R6zLwjM3LuzZ146QMk0b4tx+/hjSkUKUO6GVQEJrO8DTdij
  XAco/3jCeM8wofQZQ6ipZ00gxI3BpubPgj60yRW7+aulHPlZmZuv3kDDmVcL+V3c
  V0n0GVckV62xMWMnYGNXqAajkK97f+mlo+zZ2exkGV/2Kja2VT+wZKEkO9RfL6XC
  23hG9pjx5OmD1lihlwYve7VFSo56xvUCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
  TubObtDxGjUya7GPqrfC9gP2aQ/mBjprZGzzga0ksWQC4jIhq3qOCYVROBNHeqjH
  mH3aleRrq9/QE6/fP7D6YruX6WEJ0hzFxf8eoVGYqETiNndlo9485bNVTB3afL2m
  +qLKsvOoSvfO4iYrgvteFKycGICSR63EfN2AJFVNfMPATk7DILJo8gnMx/keKcgG
  WWQaKHEeN2ufZRTDXz2/YNWx5K/w/L+/MDqZ9tZvWTiD/q+rQ9q7hbbbpCxrNgZF
  3PnNPtu9cTvaDl9p0liudFUc7FoI1PtEzT5hTMxYWoyNoFn9hUaVNreJKvS78nsx
  F4VLaY8K8w3ruk8p0Igclg==
  -----END CERTIFICATE-----
  """

private let serverCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNDA3MjkxMzUxMDVaFw0yNTA3MjkxMzUxMDVaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMJH2M/mJGXZneOE
  5UWbicTg1BxkdNND50p0fO/35CG4jDQ3CekXUuQ6kK6ZJ2idDQTOWJqd/jSB7Ctc
  zmZ9KBAfhP9PHMZQaVQSo+tpvX6vC/hw3PCOEne1l8H8O957hBdOhEDg1crAZ33M
  cTOtxTSNw7hh0OXzLyOTfq6h3nHyvjuj82fn8nyJ9lARDZ8grdLS5LVE+Je1G3My
  kXJKJoYCGQHGDKmj7o1nrwiii20uE0gnjwGEiTO1ngKQGXzL6guuR1bMmE1UIPD7
  IySu8Yg2nI8YB96dVNFaiB7gJg9Nde7a7GHPh+4t0NSqLlBL+k94c2J8lWgN38bZ
  ugoknf0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAXmSnx5fjn0Z9GLQYkaXxKUoc
  rYPkmzRCocso3GNMWz3kde351UmPpX3tf11638aIKO0xzJ6PZyYowdbCXZs4Co/o
  pYyeW2LOoxLwSBF8wFMAPN3FB54c/KfancXGV1ULTlhfpnoZvUPnqJDYoxFRUkIQ
  wVtlyA/p5Zfc9U8czer42eo5aj9D9ircBt4k6hx9IY99YvyNeFfMq4TLOgJZkZT7
  2AImVq4kBvIUVrK86MGyRuNbAWP4fY5OOymT0rEKA6U5Lx+c9PPaFgozbGk4QAMB
  ZTwv8ymHAKdcgiDRAoQ2NhkSlySnKi4oEwcKLYPuyrpt1eG2Lx993gdSa4z2eQ==
  -----END CERTIFICATE-----
  """

private let serverSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNDA3MjkxMzUxMDVaFw0yNTA3MjkxMzUxMDVaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMJH2M/m
  JGXZneOE5UWbicTg1BxkdNND50p0fO/35CG4jDQ3CekXUuQ6kK6ZJ2idDQTOWJqd
  /jSB7CtczmZ9KBAfhP9PHMZQaVQSo+tpvX6vC/hw3PCOEne1l8H8O957hBdOhEDg
  1crAZ33McTOtxTSNw7hh0OXzLyOTfq6h3nHyvjuj82fn8nyJ9lARDZ8grdLS5LVE
  +Je1G3MykXJKJoYCGQHGDKmj7o1nrwiii20uE0gnjwGEiTO1ngKQGXzL6guuR1bM
  mE1UIPD7IySu8Yg2nI8YB96dVNFaiB7gJg9Nde7a7GHPh+4t0NSqLlBL+k94c2J8
  lWgN38bZugoknf0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAOzQ4ZiHOY9mZyE5e
  aQPZn7FE93yZrnvZcuRwrv2WI5vQj70wU4oKdm6RuBbntercKgrP6xIf2mNrUSQk
  A0XfB70QZYHKD/Uoy/NXn2CwwExXixQNUv8OaytiR2PGDk2hdeqmcTEo18/v2sT0
  32PpizVqRTfxARtu7gWt2P+n/RaL9Dj8JqB6vxv4rL2HkrDys3lT5UZwH4W81Lfw
  hFI7gHRt9CjzpDIP/GFszdvTHLgozMXGKu+1UKWLepn1XEaKyQlS+CNMVGdI8qHn
  2KvU3L4zzB1MgJsTEmz+rdGtc7paBSHpLqp1DbrU+RjXCG+POBsWpRcHGkM8Q82X
  e2/YQg==
  -----END CERTIFICATE-----
  """

private let serverKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEAwkfYz+YkZdmd44TlRZuJxODUHGR000PnSnR87/fkIbiMNDcJ
  6RdS5DqQrpknaJ0NBM5Ymp3+NIHsK1zOZn0oEB+E/08cxlBpVBKj62m9fq8L+HDc
  8I4Sd7WXwfw73nuEF06EQODVysBnfcxxM63FNI3DuGHQ5fMvI5N+rqHecfK+O6Pz
  Z+fyfIn2UBENnyCt0tLktUT4l7UbczKRckomhgIZAcYMqaPujWevCKKLbS4TSCeP
  AYSJM7WeApAZfMvqC65HVsyYTVQg8PsjJK7xiDacjxgH3p1U0VqIHuAmD0117trs
  Yc+H7i3Q1KouUEv6T3hzYnyVaA3fxtm6CiSd/QIDAQABAoIBAA7RuikJjgcy1UdQ
  kMiBd73LxIIx63Nd/5t/TTRkvUMRN6iX9iqQe+Mq0HRw/D+Pkzmln76ThJtuuZwJ
  JTlOHKs2LEfpOfGqmo4uKdDALRMnuQsHWOMEg0YcVOoYGlz7IPVCKPZl8AjaKkq/
  OHdPrvY2RhKfa3bO2O6mxof9kuEwF90l+CjxAcKd4GGMFE+tUjfCxveA02eDHAgm
  dwgUGDKFLzgiOgKeBjh9kdLP181o3b5jHVqaw5ZkekYSS7KdLZr9dl1qbJ7xFhbj
  Jnls98aQ3Kn4zF+LJex44Zf5R/9Gfxul9QtGIyNJtsGhsmF9j+9POqRGyFfyiu9x
  guJ7sqECgYEA6+IwRW7wfjXzTSukhKzb385g8P+UiIghNHW8OSiVBR2mOhbRtvZd
  +qi35WXK5mr4cK2jrrU0v5Ddvs10xlMyPUkxIOrwsBw/OdPKzRfg+uaei8ldI+ue
  tYjnL2hoDVZxMUX0cX7Kju6MUWkf6R3J75av51AVVcvWtSSRu4hVqIUCgYEA0tli
  M3txGAOfxrhYxmk/vYYB3eE6gVpEZWo1F/3BnJaH7MeLmjpC/aXp5Srs0GwG31Nx
  TNO0nFu1ech17XatlZqk0eEkKau+w/wyd+v0xTy6d49SMvL3yY0H9I2O/TGWwZr3
  wO45pZtEML5S6VEIPf1lj20GEiY7oLm2cBd3VRkCgYEAoPCr9MPTzJkszstnLarv
  Pg2GsQgApQMUfMGT0f/xZRMstleZcNc5meuBxT+lp3720ZJ3qp0yRz4lPaja8vIS
  xiPpJEeIPvCW5vKtXS/crfOp20Bhjz+VAtFMw1jeHbOL+Y18Ue+rbsgt7uHmBtzv
  ScwraoyGcgppDSDNWgGUSC0CgYAkpdISvq7ujJq10I7llZ+Vkng6l44ys3zV37rw
  u5NuYx+nARv7p4rDSZY41dgpdc1P/dHgl5952drWGwicSJdtPF7PeAFwGMDkka43
  99QogCCs7UVNQ7vb1V5/nCcxTPA2IHhVmVJ9vVoB2uLQWNxE4glH/5whhXGxwvW5
  z+pW6QKBgQDn1kRJ+Y98UpDWKdG/7NLsSkHL+Nkf8GXu66fl435Pys5U44oTDNcu
  jMDtymBg0IE3lng1WbNILV7O9r9OKt1HH4L7eepzKJLP93PbpLneBlHQG9LvJmsD
  3ErhTxSu80oglR1Hy2UjL70cE1nPUUpUr8yciey0G1tbnxvsWIqGtQ==
  -----END RSA PRIVATE KEY-----
  """

private let exampleServerCert = """
  -----BEGIN CERTIFICATE-----
  MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNDA3MjkxMzUxMDVaFw0yNTA3MjkxMzUxMDVaMBYxFDASBgNVBAMMC2V4YW1w
  bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAsqJThZkRGF4y
  yfnnYQBuV+UCrwfiXoNvkxtEWufNah1mIWt7biM+s181Dfn52Lj8GUsNiMEZ6qrX
  xBzNwo55tmsoxqywxUS4G2FA4nrniAs6UD7hywKt1zosBrneAPclLBblFwJQsQhC
  DEgpsl/DDt5oHPRb5x1zB8DuB2zQhpvEu/pCX5OUlCLf0X1YxUCDU2yYGABokWSg
  adHgZ+kAB+Cbt/zH+zibdUS1IpVtz90BuoftS6Iwed5XxPCe9FCc/P1vkPd9KiZT
  OhREB3Ci8XfqPKSv9BRGbdg2C9tkmkgVTKcjhfkULsBdahrCLna8nOtoUXf1LJCC
  IMDjjDfUiQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQBj9JfAiC1qFkC7+kearHOB
  RDGiAFyxT3cQuSOgQPoU0WoBaQ+/YhFp8zxJHlQEcQTmicODItJA1kGj8iGT18uE
  Tno1lg7nkkMhoY/Q59yaMKLdfe6aETN2eqh8GJZdUwhOKO3dQBqUQuj25gxVR+1a
  1bcsv3ds8sNXdUNJM12iXzt5lAgwhLWX0SbxuApB+6rcQBKiqAoo3KY9N5tiEbRy
  1VeMkAl/C926+W2nOAQCxSryZWEUX5EL0VARfxBjrH6KzDk876HtrLuDb2LHFNJU
  w+3nE69pEtXzMEYAQgv4yMQJZx6CtCjwS+Oxr5A3AJPk3nUSzOXVYTe5rk3hmC5I
  -----END CERTIFICATE-----
  """

private let exampleServerKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEpAIBAAKCAQEAsqJThZkRGF4yyfnnYQBuV+UCrwfiXoNvkxtEWufNah1mIWt7
  biM+s181Dfn52Lj8GUsNiMEZ6qrXxBzNwo55tmsoxqywxUS4G2FA4nrniAs6UD7h
  ywKt1zosBrneAPclLBblFwJQsQhCDEgpsl/DDt5oHPRb5x1zB8DuB2zQhpvEu/pC
  X5OUlCLf0X1YxUCDU2yYGABokWSgadHgZ+kAB+Cbt/zH+zibdUS1IpVtz90Buoft
  S6Iwed5XxPCe9FCc/P1vkPd9KiZTOhREB3Ci8XfqPKSv9BRGbdg2C9tkmkgVTKcj
  hfkULsBdahrCLna8nOtoUXf1LJCCIMDjjDfUiQIDAQABAoIBAF65NRDi2e3SBZyU
  p90IHXr+NS4bQC5eBAw9qUGLKaHbdQzDse/1QIpdMgT3SUVi0kuXQNYDj3qgnUmg
  /HrukhvpNvYjHJl+lyHtsDpocd3yFjn3HkRIZ2Z5sl7esJpSc6OtgE1zLNazSlK4
  8WNk5Eo+JXc1HIaxVw4FgDLvwKOfkjgzr4W0bvHR/FaJ6ChMfsRaZjrIoDHvIuY/
  mV/1jI0t6hOf3VU3NTg/8gwu35vcVNqe24qV6dVk9dJikyE7P+/e2c5VCwqAcrGL
  V/Gnf7iaqHcUxDFihWWMFBP+yVAeQ26rrAzLxWSn+qb1fJ8igIJhTfdHJFjQbuoP
  UsoFAAECgYEA6i0RowjUjOakJD/USKHOD0Dy7ql8DehMvAurbuxtN0jXPVaR4ebt
  3jjyQkIrllRtAcZnZH2OlzM5mKQvUdhriMPvgZj4fpepYBbNcuXIDYXgfe5j0Na3
  XtVRjBvm2gwC4OY9G3HFubNVjjR0AxZaIfUeqzl+XsX8t+tms8WvbQECgYEAw0gl
  nnHTYtuw1p1mmPZFYJ5P3DFaqtkRnBPgq7XVgRCjmU0SYEQ6ogNbGESXQBDrKYIg
  IqpaZvuSv6nEy+b8aEuvkTsRqmu+gK1taATnZRhrzjzUeMOAVOn1gK86GcSq5Rmx
  Bj+ie5lBj+yxU+wJg0hRGNik/ltYVGKf/DNDf4kCgYEAiz5bQ19Hy7SFG4zctIeJ
  2GYdTa53tmlP32zs9hsdYgcs/SsRuYqwHDguTRm9gzkWTDzmU8mY1O0/rTTLclZG
  st8W9i+4asXRj/JfHZfmWawmbZsnvRE/neMoBzC8FyGXQJWG9l+zW5V4JQOpjABp
  fdGb9+JK8x21BMOzoOfGRQECgYEAuyvImtAguu001s9wygWpw4yZoMRRUdXSkhVf
  T1VueVFYbRQ5G7nptOWgh2cezVIqA9PsNy2ujmxsYHY44PLZVKHOelXyfbTdl/oi
  FgQ1QWmh0r/tKn6/3yOLorbQ6mfdIM96JDIT64GeHHPSF0zyZTmIOVdU9VLaG6+Y
  BiOge3kCgYAYe0+Dseqoy4KXICkHcdacbULJnm8ZZ0SpjoBhKWSS3gyC7Anx8UoO
  lSz/4owNrD/96NnlnxItq0Pi7ZU30TBdP1ZX7RuwQqS8ORO9xOSVrgzZR/PZCa3V
  ziqGo+jUjGowA795F7/hgb3fNML5dUpLe+JEEo/OuQH6Jh8puYlYBQ==
  -----END RSA PRIVATE KEY-----
  """

private let clientCert = """
  -----BEGIN CERTIFICATE-----
  MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
  Fw0yNDA3MjkxMzUxMDVaFw0yNTA3MjkxMzUxMDVaMBQxEjAQBgNVBAMMCWxvY2Fs
  aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALqEdoBgLtT1p+jn
  xjEXCQCpS6g5EIyHwjpIxC6gX49wACiFqNz67EmkDTX0HIPgk+/4wI5ljP7mYPzh
  NAMFU4P8gDpYhKXLQyaNno1VTXxgpINIp2OXrhtLtkT6oO0hXTFVJCnsO9uyi7UR
  0sBZbXBiAlmnPSMaY15UkzJvS49zBEJ7qnKeZyAer7V9dYe8OhtWt7kVD6sVhf3a
  7QlwQCdbg3jowodpM3mvHnU8W6JBJ6p7dtAG3zDFyHY0erzc4bfPKqJEtV6YRVij
  3zRCEjlU6A7c66y8V66eieNOB2FzEvutOwNrnrWfaR8jjafbhdZZIai9/GJd8w60
  rOBQoxkCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAqAYuUyEwGoDK2tOXPVHAFBaN
  7D6SlHQBxYDuI5jYfJWBfdw3+Dc/OoBXHtkg2OQIV315+uIYHguhScvL4GBmEjgn
  17zKGciymTPJ3eTcb6IIXJIkJr89YM5tyr7cveEUXRugSdAtX0aCaURRr2H4ycjk
  NLaSJyqCb02g9Ny0/5pql/v3gdY1XGF/hDEMwpLb5TxTt3VMtYj4r59Yz/5e/950
  MeINqAokIoLVtnYA+YW/Vj+T/ut9dFiC9E7arAw2z4zZ3uWvDVHTxhPQplUbpfyu
  /rwx/GpotyGL1qU/JKOur2Y5Is8lfGkKZ6OJWAOPG+ZqO233+s1tH/SEQkIfIA==
  -----END CERTIFICATE-----
  """

private let clientSignedByOtherCACert = """
  -----BEGIN CERTIFICATE-----
  MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
  ci1jYTAeFw0yNDA3MjkxMzUxMDVaFw0yNTA3MjkxMzUxMDVaMBQxEjAQBgNVBAMM
  CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALqEdoBg
  LtT1p+jnxjEXCQCpS6g5EIyHwjpIxC6gX49wACiFqNz67EmkDTX0HIPgk+/4wI5l
  jP7mYPzhNAMFU4P8gDpYhKXLQyaNno1VTXxgpINIp2OXrhtLtkT6oO0hXTFVJCns
  O9uyi7UR0sBZbXBiAlmnPSMaY15UkzJvS49zBEJ7qnKeZyAer7V9dYe8OhtWt7kV
  D6sVhf3a7QlwQCdbg3jowodpM3mvHnU8W6JBJ6p7dtAG3zDFyHY0erzc4bfPKqJE
  tV6YRVij3zRCEjlU6A7c66y8V66eieNOB2FzEvutOwNrnrWfaR8jjafbhdZZIai9
  /GJd8w60rOBQoxkCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEADl9prZ95iXY74KpV
  Vm5L/whTnfXQ2t1BVYD+nOKYyipAuVu+gTbBgseF7Ly+mEM0ewIgFgGbYZsO82Tz
  nCCYZY+ablJkewNOjn3DAsr3kTjIFnC4fpDbYQMw3IHEOWdollRLGv0d5SJNc9z+
  N4pB8y53Uz2nYBUKGc+HEGKRwn0XZL5Vmd+OnT9Ry0wlYh3NYcTxAY8ArtyJq9h+
  ROG4YH3en8e7RIGg1uB/m515Gm+CA4WphjErEiy5VH4YFAYtBWCxO/h2gPOwX+8o
  UnpdgUOkzB/YAc7S7OGGngz2IyBf+Rz/JC41uF4+efg8ijoZlWcO4/gB1yLiofBD
  /MgUQQ==
  -----END CERTIFICATE-----
  """

private let clientKey = """
  -----BEGIN RSA PRIVATE KEY-----
  MIIEogIBAAKCAQEAuoR2gGAu1PWn6OfGMRcJAKlLqDkQjIfCOkjELqBfj3AAKIWo
  3PrsSaQNNfQcg+CT7/jAjmWM/uZg/OE0AwVTg/yAOliEpctDJo2ejVVNfGCkg0in
  Y5euG0u2RPqg7SFdMVUkKew727KLtRHSwFltcGICWac9IxpjXlSTMm9Lj3MEQnuq
  cp5nIB6vtX11h7w6G1a3uRUPqxWF/drtCXBAJ1uDeOjCh2kzea8edTxbokEnqnt2
  0AbfMMXIdjR6vNzht88qokS1XphFWKPfNEISOVToDtzrrLxXrp6J404HYXMS+607
  A2uetZ9pHyONp9uF1lkhqL38Yl3zDrSs4FCjGQIDAQABAoIBAFcoiTuqNpg7h1BV
  5o6QBhvyALHGoM4aro+P62UieiVMIDbPZr6E3x/2clnxDdYuftMXuduQ5tdCjrX9
  AtIajhFSUBVzweC74FBGw32mDASAIMBcliP7AFgvBCitub+15JemArU4eCxM/e4K
  OyK5Z2Op2RFODkq2DRNKkFJ0IaoRN3fDSPLXg865RMSjDEd2I0gsADdh12Dk8+x+
  5tpiQGLIfgBgWcqQrTl908sHB00WwlH166sT6k1G+SFRPK60r2fhOpyQelTUC+Zl
  IOAtydE2ypsWG5Z3LnNkPwbwJl8m2hoL3M23syMnsxwTKQIblpYd3YdRR/5EozUf
  f33p2IECgYEA6z8VBggDNb29CZgWjJUS3N/xuNyN6K1/jew2LyoAYX5zZL1/pTLE
  Cm2MvJglY6B0r0/3eF6bBYGpHT9TWj3yzYlV0Q8iAdbz6se7skFrm7XXv50Bmjo8
  epzvVjM/oAvEz1/2bQXvZRTyunNwdyHBd9QCiuAHU8xuq8Qvq5+BNBECgYEAyvjc
  sWwZQJiU7alx5ynDB25GRbXu4APTzaz99vaw/V8DNsYw5c0habq3JfaC8Q0bse8Z
  G675M3F+gFRPG9TxqwSuYF9bpz1CQtKAT3pRXjjJQM3vfdixQjgBYspJMPKDi+qC
  Dzhr8VBE16HxMArMgDKzYP/gmjHnRlcT12udZokCgYAcd+7YYwHYcBS/Y3tfGe9F
  cYh0IaS+wrhL+Yj5HjEbm0zlpRUcbc9Rn75HWHY130YfrSK6m2BRQ0au9mnk4thO
  TU9oVFd+N4AfKnqpcMdP+aqZUqvN+Tw2bmV8XglWGfaAThGpUe2NowJY0/2JPTmH
  gc2o9sGMP5IpET3fnBbrsQKBgHLSCXbM4hQqvMUdf/P3Kf8AIPy6iOFtCNpnLFwS
  /di3cQgBYhP90RMQrx7orvZSJgKocZm5h/vUDm3mQ8JI2lWWllaqWxzmiJ9omXFc
  jr8wfJkOZpbYiJ4fNJmAOZtY9ZWnGeAmWNnwQKGDWP+GfF1hURxkY9iWtnCSPgU1
  OZuRAoGAOT0RQvvTVwxBU/BFRNJLSCjyJee8bz7+B/TmNui1Afyv+GBgzPeh5Z+L
  vUi1MlvdlTdUVb1LmFgmidHgjRCYDEUxVEl3HmNHljCJqAXcJA61bMfItoteCHr6
  RMrN29F8q/ZPKbTgT5eH6tBX2meUqEDotTbdgVT84IhWyWOVF+g=
  -----END RSA PRIVATE KEY-----
  """

private let serverExplicitCurveCert = """
  -----BEGIN CERTIFICATE-----
  MIICEDCCAbYCCQCV4KgFB2WjmjAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
  cGxlLmNvbTAeFw0yNDA3MjkxMzUxMDVaFw0yNTA3MjkxMzUxMDVaMBYxFDASBgNV
  BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
  AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
  AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
  sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
  Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
  N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABDJg
  pBr9ZhidkGWnjW+hvhPLTUH9V4iNr+WNsb2HjQK4NloOauRQ4mlc534XeBya5tRy
  aczylZHH6uC7ULCA8XcwCgYIKoZIzj0EAwIDSAAwRQIgVqWCUtszDMJU5ropnKDh
  UhsHq8r0ARIfTsjSKSdung8CIQChqts3cpW/OOp5PS2bEm23Bf7SWksW2kRvXj6E
  pjFODQ==
  -----END CERTIFICATE-----
  """

private let serverExplicitCurveKey = """
  -----BEGIN EC PRIVATE KEY-----
  MIIBaAIBAQQgYvOsKzMIHYIhfoUF1YqrM64ZR0Aotb++nOzoDB5mPrqggfowgfcC
  AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
  MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
  vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
  axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
  K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
  YyVRAgEBoUQDQgAEMmCkGv1mGJ2QZaeNb6G+E8tNQf1XiI2v5Y2xvYeNArg2Wg5q
  5FDiaVznfhd4HJrm1HJpzPKVkcfq4LtQsIDxdw==
  -----END EC PRIVATE KEY-----
  """

#endif  // canImport(NIOSSL)
