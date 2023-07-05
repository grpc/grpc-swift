/*
 * Copyright 2023, gRPC Authors All rights reserved.
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
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1720088924)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1720088924)
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
MIICoDCCAYgCCQCgCA1/0dKfFjANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
b21lLWNhMB4XDTIzMDcwNTEwMjg0NFoXDTI0MDcwNDEwMjg0NFowEjEQMA4GA1UE
AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBALTi2aJy
Vw3E0OQwNIm9GZOG4E/Rc0atKoJes9yWaMrMPGwoenLEc2JNIvJSdBGZHKO7HKAG
OnffpqVIXtRBIU7l8HEhX97Q+knI6wPz8O7JaGVf6KznLa2eFO6xGM1pogO7m+/M
0mw8LSftn2IEiJk9v00qj+WgfwJJqL/TUZRoT5M2+u99uiaW7bnI1+1vawo5i7A1
zfN6SBud5K/BaEYcAjxX1JMWCJLWSuOFZArWX7Je2MP+LqZkjh8kQO+d8ZZaLSIs
ujd6x6/r365Sl24l4auNfWy/5V1Ctfxl4avupAm7CpmEFpswe/ucNHkD0drUCzvt
hBeR3coLXWgbQs0CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAJm1Yntrrl6WxPbsA
s1DrI9YHdQjUNkouX0PtGp4yKrP7hwTclIhHjlGaQRJ2p1I7hllCMCPDa2YZa714
XhtvEmpWOeLXMFolpKEn83kccvkQviZ3yd2lKH64jDX1/g2Rf6dXhDZMKrMAkEdx
X3JwZwPxwb8VDtac7TkVgOcQFHRzdX2g6pQXz3eNsjckGNJgzzl/ln6DrHHDbruI
M7bfnc2ZCBcHUCLWts8LnX2ekUq9KOxMe4e3sD27sKPizklNfGH4Rdg4LByhkx3S
GGR3ziWyixfcs4BNhA5mbsvb8vpPdtOh1oFt+TtPxlQ2FQOnSHk6wF285XggYYgv
p8pG5Q==
-----END CERTIFICATE-----
"""

private let otherCACert = """
-----BEGIN CERTIFICATE-----
MIICrDCCAZQCCQC3Iplq4Q/2+jANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
b21lLW90aGVyLWNhMB4XDTIzMDcwNTEwMjg0NFoXDTI0MDcwNDEwMjg0NFowGDEW
MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
AQoCggEBAOko0E/i9WlJS5eBAfJsQ1Xz5cAse959qRz4LSE2PsRXYIqGD+CHSlxf
K549WPYfCTEJxT4+MCwU9MfyHSTmhYo/MEA6K1jMznZULhYFriLLiGBCB238W0Xo
bEf3EN9xrHlmHaYrN9EwI6Qiq/AYkpAmbrlgbLW5Ig03YWTODS8k4R1nrkB609BC
DBEyzBiCjgzo0xVduTgf6iiEfUg+dlvkeH+4qjLU0DRJq0g7YIM/kEX/zL2YUad5
9aytkDjO30IhcjQC+wvhCLBn6FDyYOpthaGM1cbMLG3efMpGAtyny2qATo63yVmf
kd8ftmV86BidAm+tCnFwBzxfXd4CB00CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
Qxth0x5noVZrWZs67kBpjhiNI5Zg4/IMFukL4qv4XqC4AkwJJ4XaMAVTgtZ+mGmr
yOJ6pEzw0C7nWmTtlUjQu32Z+YNLSnE6wcIEx8ed1fwI0kezcyBBrg+Rs1vDNi1c
Tshq0by3RBuuSLclYrR64pmzYj4XJjABYIPurmtBCh4iwVhEe3tYs8I5vlKhmvA3
ZTnqs21wD0v7FA4aM4EguFfLTMlBuD7U4G+agXvtcV4tXzQSh7RaXB06Mt4mNJ1k
LfqH39ZEnzeqUVm0vn283hvH9RzTYuHZu8J9wtmDrSTb6EcA4kpnILOgjhyLNL5G
EZi+HPA+wJ2bsRVlAxmuMA==
-----END CERTIFICATE-----
"""

private let serverCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMzA3MDUxMDI4NDRaFw0yNDA3MDQxMDI4NDRaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKTZdzuWLHyxPM/F
sviBBXpSzl2MxJxDkmir8DSdXO5E1sHCAymTaxy9bOdi1XUZbRTyKfTv3x6sdRdT
0Gs2WjhL0yFT9IEVrGZADt3GIYoHYZU56Yn/nLglGQZqIeo33wyPEIAkbWL6X4RG
1Hc6nJQxhw1aaVtsYNAoWjAVzP773TZgyRcsGliqHtYpD0q0b+EfmPkb0GM1yvBa
j88dWWFFlG00aZFQatSkIrPbkXG0Mu4/1UxYDEuxOYrIFkFMfR8V8h6ZQ2x3H6cS
cTJ2TpIlw3rO6E0J/HYaVhmvJpevIPQhvH/Q+vM1bkvaIkckLchW7VgU4P+ZzHEw
r/xMcqMCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAGpBsuzx72mOBa9o7m1eNh2cY
H6MrNi1b6vTaA3SOH68RDxg2qx6UrKxI34/No7FaOzRrfs9vUaKXHwwBnDxMskH5
iTmVAGegumDQE3Bd11j+v1tKxXWS/bvWH7tfK6taoex76ktR3L8qO+Hp8n4YKuSb
qJScIhMPIg7fWPonLvcszGFPdBIxU3YkAZJZFeom/s1WhWCYXsJZSYOXv4YRlaU5
ozeV3v9icDptaxNY7n4U6C32eykMjowJJ9dcOD+ib3PF88S+utmZnSEGYu+5bnXy
6MGWZcYH1wQ0RpNC+YzjQcGsKwHfaoBS4WFEK2fJdRfX4owZOu6HO1zhyoLpqw==
-----END CERTIFICATE-----
"""

private let serverSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMzA3MDUxMDI4NDRaFw0yNDA3MDQxMDI4NDRaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKTZdzuW
LHyxPM/FsviBBXpSzl2MxJxDkmir8DSdXO5E1sHCAymTaxy9bOdi1XUZbRTyKfTv
3x6sdRdT0Gs2WjhL0yFT9IEVrGZADt3GIYoHYZU56Yn/nLglGQZqIeo33wyPEIAk
bWL6X4RG1Hc6nJQxhw1aaVtsYNAoWjAVzP773TZgyRcsGliqHtYpD0q0b+EfmPkb
0GM1yvBaj88dWWFFlG00aZFQatSkIrPbkXG0Mu4/1UxYDEuxOYrIFkFMfR8V8h6Z
Q2x3H6cScTJ2TpIlw3rO6E0J/HYaVhmvJpevIPQhvH/Q+vM1bkvaIkckLchW7VgU
4P+ZzHEwr/xMcqMCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAY3vY+hng2gLh9t8q
/fvZewBiLAjsePbgRGT/xO4zCi3JwbHt07oGyQfo63ok5IJIrj3MPVy7N/oGJF0Y
niQrIhXs0NCKEZ/P9amh6wZJKAOtfD9t3oiNWTx56shm1vFQTTUdpykK0b37jGiK
y0N0p8M27ym/gQGTixfHNBtA0p+rmdDErOHqfU5Px3iQfmMmf4hxXPOSkGMixyre
3AR6wURMGLUCLVxi0sQYNd4fGo/GwbswTSJI7+sypZHMwpXbaN7KjorkSmI8UuoY
aGEewReM008rQWGWf3ybmNCChhru82lPQGMp6y9fN0s591iIzjpCXixzd1j1V4oY
yXRecw==
-----END CERTIFICATE-----
"""

private let serverKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEApNl3O5YsfLE8z8Wy+IEFelLOXYzEnEOSaKvwNJ1c7kTWwcID
KZNrHL1s52LVdRltFPIp9O/fHqx1F1PQazZaOEvTIVP0gRWsZkAO3cYhigdhlTnp
if+cuCUZBmoh6jffDI8QgCRtYvpfhEbUdzqclDGHDVppW2xg0ChaMBXM/vvdNmDJ
FywaWKoe1ikPSrRv4R+Y+RvQYzXK8FqPzx1ZYUWUbTRpkVBq1KQis9uRcbQy7j/V
TFgMS7E5isgWQUx9HxXyHplDbHcfpxJxMnZOkiXDes7oTQn8dhpWGa8ml68g9CG8
f9D68zVuS9oiRyQtyFbtWBTg/5nMcTCv/ExyowIDAQABAoIBAAq5FpdqqlQmF0WQ
n5aoldmiH0hYisV7Y7+pR4O0pMHe+nU6EIiYzUPeUoIunKH0WHMfWXlUTRgqsacl
zY3byDyXOhGV63amGUPBcPYeGDppRoC1dqqCVQhpaVpQdwpMPhcMC0+6jt78WFA7
Z0CmMF83ZYiJ1AadYyLHLS6pjF8dmkj/Rd6yeLIVkKr4xHxou7au/6WKorop5XLM
fEyWC2iotha2dkXw3i324n0qrbR2v/EYLnAn75uA9FF/pJWe6iPc6H5tfBSnzmO6
fkZ2rCrDt4ANabg6WMmRdrZXFHSR/JlPPyh4T4iJGenkLltKZG+wWSm2nVXE0DYt
JQdmhiECgYEAz3EclGIrk63Hp/2mAHAOIOUGh6+Tk4JA+ibHSzziVZZqJsGQ9jcK
eOn6TX5674+aNzo2ROnHCT6u2tCQEl5/lrB8YpYh3F6aaNqPvFwqRhDViOw2l8KL
Ic40x19o5ur3Ss914htwTxiEzQVB/n+5zhE7W4N/RaDIT2hedWR19PECgYEAy3AF
CiHa6P+pbhskoSETtxbWkhDENpXat2dlFRDrNN9T2NZNVmIxCjAE52arduCxaLTP
hazyq4d7FZ4OkxfbJY9D2HnBS6mF0RHB0gZXZ7iB/uEr0KcTex5saqX9TF3YA5Wj
PNVtOM37IIaLJ1qOmfXf4yL3EVlI30eNwfoMkNMCgYAv0VAYOET5Rs7GP6b7ZNks
5f5KWsO29giKYVQBWOiHeCPCCU6kIu3sD2teX7Bw9nZDEs0dt5Hk5Kkj0X3UbioV
D1us0hS+GqSXVQJbFhe8jPbcGC9BblvqEAGEj867pCAbA5WV6GNMKEe8huC+jKzE
/p3jK320DCsAevuDLgQu0QKBgHvE60v+zPB0muAiI2bkeNorSuAS001iXm62uQjY
AkFondqOhv7HPo60KEegbzEkAstxNdBeKEWzZ27/el6DZRC02NIbQT6HJKLN6t2c
fhDccDphRAbtnyyIle1Mj46miYWkxGt+bbThnKdtM7v9nESPEmdeHnKvn2Y4YkZh
msOBAoGAaarkv8JjjmIgjRZrJ7r4dkzZwZa/msm+/NHr3nlXK227ExMeFRPmzYls
zIofM+DoEk1sDXRfnv+8EU8Dn1DYSq6M6W8xrm7Ulpzj0kXE4f9TD+MUwSNCQ6Gg
zLRkHQBKblIa0lEvlulLtJT2UN9AnCmvTH2R11wD87DWjFDZKD8=
-----END RSA PRIVATE KEY-----
"""

private let exampleServerCert = """
-----BEGIN CERTIFICATE-----
MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMzA3MDUxMDI4NDVaFw0yNDA3MDQxMDI4NDVaMBYxFDASBgNVBAMMC2V4YW1w
bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0yKJAjr3evjW
69/krEH8V3hLdVBuJX7YnhyEPVT0k+0Q4jJ+95XROgElY3DsuARH5wuksTi+mek5
J5MObbUhHtGIaoqVaDew6TokawwQyBwngKudssu9/6rq38m33OSEv/5oc6xtTdKJ
Lrmqqf664+QajxCeec9CPMGJExQ25c1A5QOkkyC5xR+TcRRIcKPaDZ9aj6JlcD58
QxD672fQP3exR2iQQ1YZDfAdF/hcgh2ISI+qNV2Pl5DZL8ujEX8XCf8EyHc5GNYN
5nlT+Z9EjoDFTBpy8nNbp84rks0Ru36OYX9JyM+wu/a0iMVBr4Yk73VVhOaH+aUI
eNHaD7fhlQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQB1++0U/7RduytrWh2bu6uz
sFk4XK+5eIhKn4DMq6vKXFQYF94Tkz8K2RDGzZ3Cl8qRU7dLwlHrUgqFI89XMFAM
LjumIWoMnfik8A6cBmp/HqURzXPNv6Wgn4MtU7aDs8WAEsGYAo5TTtqVJUGc2Mlf
NkW3MQ/RTfUncamx2wNFjwLmGTuERgHA/OA8WQVnMDI5JLXH5sigdOMTkqgkGzhg
8NVWnqubG4b4a7W3xl4s2FjqglqXP3vu+c1F6cWJfKgOXIqd8NduJ+p2FJZ1rW2c
3jkHoqBLqA4/zua+HUn5ICcUZrZid7HgmlUoR/4n+dbjT3Jdpp4BpNn3q8JuWE4Q
-----END CERTIFICATE-----
"""

private let exampleServerKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA0yKJAjr3evjW69/krEH8V3hLdVBuJX7YnhyEPVT0k+0Q4jJ+
95XROgElY3DsuARH5wuksTi+mek5J5MObbUhHtGIaoqVaDew6TokawwQyBwngKud
ssu9/6rq38m33OSEv/5oc6xtTdKJLrmqqf664+QajxCeec9CPMGJExQ25c1A5QOk
kyC5xR+TcRRIcKPaDZ9aj6JlcD58QxD672fQP3exR2iQQ1YZDfAdF/hcgh2ISI+q
NV2Pl5DZL8ujEX8XCf8EyHc5GNYN5nlT+Z9EjoDFTBpy8nNbp84rks0Ru36OYX9J
yM+wu/a0iMVBr4Yk73VVhOaH+aUIeNHaD7fhlQIDAQABAoIBAElHYToO8ToTB7US
HjHTLRvGupna8n+9CL3Hs/X9eG2nCAcZ84tGyjlRkIJ0/RPZGIOOPPjtcunEUnvz
xDw7c2VY3/nqY3Sqb5JjBaTJqUFq1CMKbU9S+3yy+5X0UwYtog1o5SPQopcyDT7U
XfFmYcMatkUVRYuNbbXcjhC7IVqcQpPzPrBaGJ/cm8ZCdTJIWCrJfsI2mgDA9d+B
k5c5uQxhohPWFdZsGGTdJgRCJww1mlAHJXxR06hkBJEnG/vmRaCvsjBgrOtP0/iE
y8NBETAYMl1Ms+w9Pv+pcE8eHgAvicNkKiOlvLTeval1ZIV236IiGlvls808SaYb
RCTlN7kCgYEA+/sFtAMj/ZPacAcuv1mTFKaYUFwbeZAZGHVyniwfgRRvPDBtqQ9i
vGWOLL2fLqbp00sy9LS0FNo8OSnJSGux2IEmoHdNWDNzyORkXLhB9Lov5VqKj6V3
PO6JswgPtNrb+3fQulAq7YkU6qPdrtHGdU+to/lHQrD6FkMLdKz/zdMCgYEA1oC3
nOv/PsUwNWlUzkxfgQ0Pnv32NKfoFu2cWL9C0FlCgQxakm03JrbcfjEQafPR64jE
7uhe7aueiQz339jlMxyJk5BFNn/nIOBmLUFD3wV7xcsU1mRnbl/a4R1Wxk7vwmW1
s4LRu35iiWb/UkblsTA/qdMcigRlRPkOg3TYqfcCgYBWgWgE06swa+jq2txmnrbK
uSLDO8vG4PxslC2ENbufEcfaTvnmtzx7VxYHMBYM6wqNGlzk+4BzRDS2nyzV6vsE
S9pZ7nskE43lYts9pZgnDyBQSdQV2oVj6rRlPRg/S3+IBisnO0xxfcUrhJQfZy8N
qQwAphybvawtplixdo7fNwKBgQCEvxfipzJJOGNDSrJPEXixNtIKBQUPRTIermHp
kkPZCMRddLXAlJJjBRujhN2xlFC/QN8PMwM8ds8f5cSo5WPCo9CIX+pVdgYllHnn
W9KS/KPCnpGAtJZF+lBMrIl9JHDAj41JUJZXQDne6rzrwDB53XAouxuYVmwNqUxQ
EknbtQKBgQCylI9b7Syz5pBzZZNBSn4eqzlsdYgG3WUMGyEyvVzTjfbovWK98xeE
A5F8BNesnoopCW9MtW2QJ9iSLn24sNpj0Uvw9pobB3uDj5Jn0oIndGe7N/7beYhE
HjkJ4liJkM5Q1oUOvVFFPJWEm99cP8urojakeMO3la3tGaElwHVWWQ==
-----END RSA PRIVATE KEY-----
"""

private let clientCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMzA3MDUxMDI4NDVaFw0yNDA3MDQxMDI4NDVaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOP8JtVr8dF1Nzg/
gesU5U06YksuOu5xSphv3GEtsIY9i49rqTk6t4z1aNJgBG+2fPKqCMjPtPJxRSgj
qUhoxSS15Ap6yeDN9VJGGb2TH1jAYFHmVb6nB6gDdYdn9isYO+laIZ2o9qVe7uQr
bSWHxr4ZqOlVGM5kiBTIIoyQJYnExEZ6nz6nqBVj6ZkZ3Nww9zRQ8AjK8hUfMq5K
PGohTqAvIu3NUwU12AePtneb31Fpc1DKWM3ZeC8kNHheZuuIlBhrBmJ+B64HeKX9
xfl15zI9ziDLSzMa9IL6ZV+3c6IBiTeGavf5cjHO1atkQIX+jCRQwb+p4q/NHRvO
ADhAXesCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAsjJ+nFYDH31PmM9YpKGuytOw
DQYVLFYWIGybZC7FSESzlGx1GOZ5nY1AWj7gCnAvc7/Ct3efI/7qA0tSB+rbd2tA
/qqU0/0FJLZDyiXrpNzhFoYkg2VzZRSmFdsJbhzjNJM7iJRsWEhXn/7qydLyp1vj
i7DlYQVI2QgEQQz7BMJ6D3zPRxlyDzlVjr7l54M8RX9Dj8Oj9Sajd0RlkLiGW7YR
TC2nNebpRGN57Hi8dCM3xLWQcJ0N7BK0A67MnQaRbUQ0DMvxXO0+HUHxpfN39P/H
6Y81QkFAeeCMCsSWTGHspIJ8teKk+KmIe3xZ72taWNge1Cu3xas7Zsl1lbI2mw==
-----END CERTIFICATE-----
"""

private let clientSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMzA3MDUxMDI4NDVaFw0yNDA3MDQxMDI4NDVaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOP8JtVr
8dF1Nzg/gesU5U06YksuOu5xSphv3GEtsIY9i49rqTk6t4z1aNJgBG+2fPKqCMjP
tPJxRSgjqUhoxSS15Ap6yeDN9VJGGb2TH1jAYFHmVb6nB6gDdYdn9isYO+laIZ2o
9qVe7uQrbSWHxr4ZqOlVGM5kiBTIIoyQJYnExEZ6nz6nqBVj6ZkZ3Nww9zRQ8AjK
8hUfMq5KPGohTqAvIu3NUwU12AePtneb31Fpc1DKWM3ZeC8kNHheZuuIlBhrBmJ+
B64HeKX9xfl15zI9ziDLSzMa9IL6ZV+3c6IBiTeGavf5cjHO1atkQIX+jCRQwb+p
4q/NHRvOADhAXesCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAiEKKo8JIG29d16ZT
6d4ERj/o/3B2rwpTvSxmVaon3Zzz0gQ+HhuEH9D3XzzZ//P7qe8PxpcZ75veuv7X
ZcIPK+L7QqLAR/RrbWSbhI8CpQ0WX2MitKkz+cdRCey8/4JF4g8PXMMuFrP6fGEm
79l4aJoAiTNJ98qufUzD63kqU+kpPGjML6rnJFfwTVAWu/7Sy92u052IsoZfiKx0
yN1vYr9jLD48n26YsyVjuuqqMW+OKxzRGA3xCa02W3cILQb0NVv4hM0+yGd1laKe
1zGHzuaeCIL9bFGBtxRXTWyyEG9z5nohEz/waHpUHg5VcbrkLOIIAhsolLuDKQyl
JanCRA==
-----END CERTIFICATE-----
"""

private let clientKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEA4/wm1Wvx0XU3OD+B6xTlTTpiSy467nFKmG/cYS2whj2Lj2up
OTq3jPVo0mAEb7Z88qoIyM+08nFFKCOpSGjFJLXkCnrJ4M31UkYZvZMfWMBgUeZV
vqcHqAN1h2f2Kxg76Vohnaj2pV7u5CttJYfGvhmo6VUYzmSIFMgijJAlicTERnqf
PqeoFWPpmRnc3DD3NFDwCMryFR8yrko8aiFOoC8i7c1TBTXYB4+2d5vfUWlzUMpY
zdl4LyQ0eF5m64iUGGsGYn4Hrgd4pf3F+XXnMj3OIMtLMxr0gvplX7dzogGJN4Zq
9/lyMc7Vq2RAhf6MJFDBv6nir80dG84AOEBd6wIDAQABAoIBAGOV2hSxoSCAVg2Q
2BwqtXrFfPggCofrHs11V0tvnMMWkSalvXaNKm49KHt0i5uMmAmbslidOgoI5k+B
PEmv0iWV+jWFqzcyX+1/R3Eimbe32JsNxPiRl2uRjz4FcGckn87vmu12R762uB0c
xwF0zKBvLvQ1Qq+tBDAnt8e0k2EYqgl7LEIb/1vDsxyVLNLzpSBfENYbE24YD0rI
/PQwot0UJhWVFnYxYczbQSLxhep1tRzhLaUY3k1SrvGvG/TM389TK5upJoV1/emc
EgRCnBPM2geOq59Bul0ri9bvXyVh19VegNM8MLwdf9/UtDFEhApYyoePve96LspM
aOQSe2ECgYEA+NkCXElSy+TdPLH4944PGdXNm6GtuhlRjMc3pz+r/5gQ9J68rIRt
OJewx6bQx8lOFYxzhiTbN2wY7ylm9/Cn6jk7zfUXrqq73tbWgS+YSWajoPZM4sDB
QdQuOkArdLGkHMM5+2U81d/D7o5nb4/ACCY1XtvrNUqgBe6tyHe/INECgYEA6omj
GVY/yYK1RsRNrTmYipZbnR0UPpTsVevdAoX9TrHG5AHTgmh/ONGGCx3/dgmLqZO+
D4MZSGyK1appxJjpsKzkM5T7X+bznHWzXe6kGnzDzkgBzx4N4s3LHPZ4uUvNnZwi
h281KEBsblKOu4khDk8jL3LXjRxGYwOjqdisYfsCgYEA9ho4OWjSl486NYKVhM5b
pONLunUFSR0tB5smMSPJSLftXN94HO3CzstGK82QgWVW8fy7a5kbrA4eArjheqfo
iL4dpSyVRUrZDiNOdOjLJRx7Cv9LPp3/AsmDBlzcHUZp1YBF4ZhXt/Ta4xy2syBp
fCW9dpjsXwH0jKll+PJkdWECgYAjgDHv495D4kUOMSiQz+cHEztKzNwDnQco+kq5
1w5Amyg/2wbo9mhLcWuYwzGn7En3oSVjs7RgAg4ByYm4+GxnEcR5ClQCcDLvu+Eq
lrTATaJV1xBvCV2QtxXHjIc5hP/am4eeeHbTYO0IxfZU7KzUPaZVyExYT69XzXU4
gFOXgQKBgFbrLumJh27/nHtvUM0xh7RZ61NplRXDLez8DinSlNI9ZKl197LKdBzB
6cHi59SojJFJY6QAdqdtenj33KHKjgdc3rH1VvipytPBJRO2qohBpYuSZiY2y+Df
dW493Y3+mwD6VsGFFvBPSC3jhDBeIYxajEJChzkbClVDRS0muLQv
-----END RSA PRIVATE KEY-----
"""

private let serverExplicitCurveCert = """
-----BEGIN CERTIFICATE-----
MIICEDCCAbYCCQC7a34VXIF7+DAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
cGxlLmNvbTAeFw0yMzA3MDUxMDI4NDVaFw0yNDA3MDQxMDI4NDVaMBYxFDASBgNV
BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABN5Q
sDW36YI12PFC/kRnACzCt8a5lqjaFu6QNl0Y0ZYaiE9MdR+EOGcCfoSGf9r8n1Yl
peOOLlvsXQ0UO8WJbsYwCgYIKoZIzj0EAwIDSAAwRQIgGd0bh4HWEd3ytsCEGaw0
m567URfCk1u6sY4I77U64zQCIQD5hOn0PDS4eYR+kBB5MadQtcBtz8gjtW/OJcfV
D1NSHw==
-----END CERTIFICATE-----
"""

private let serverExplicitCurveKey = """
-----BEGIN EC PRIVATE KEY-----
MIIBaAIBAQQgHqp+i/1N/Iq8DUruPu0ep9WiB9I+n1Ox6qFucixKbr6ggfowgfcC
AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
YyVRAgEBoUQDQgAE3lCwNbfpgjXY8UL+RGcALMK3xrmWqNoW7pA2XRjRlhqIT0x1
H4Q4ZwJ+hIZ/2vyfViWl444uW+xdDRQ7xYluxg==
-----END EC PRIVATE KEY-----
"""

#endif // canImport(NIOSSL)
