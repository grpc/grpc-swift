/*
 * Copyright 2019, gRPC Authors All rights reserved.
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
import struct Foundation.Date
import NIOSSL

/// Wraps `NIOSSLCertificate` to provide the certificate common name and expiry date.
public struct SampleCertificate {
  public var certificate: NIOSSLCertificate
  public var commonName: String
  public var notAfter: Date

  public static let ca = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(caCert.utf8), format: .pem),
    commonName: "foo",
    // 22/07/2024 16:32:23
    notAfter: Date(timeIntervalSince1970: 1_721_662_343.0)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    // 22/07/2024 16:32:23
    notAfter: Date(timeIntervalSince1970: 1_721_662_343.0)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    // 22/07/2024 16:43:12
    notAfter: Date(timeIntervalSince1970: 1_721_662_992.0)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    // 22/07/2024 16:32:23
    notAfter: Date(timeIntervalSince1970: 1_721_662_343.0)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    // 13/05/2021 12:32:03
    notAfter: Date(timeIntervalSince1970: 1_620_909_123.0)
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

// NOTE: use the "makecerts" script in the scripts directory to generate new
// certificates and private keys when these expire.

private let caCert = """
-----BEGIN CERTIFICATE-----
MIICmDCCAYACCQDdfOxq8GY7uzANBgkqhkiG9w0BAQsFADAOMQwwCgYDVQQDDANm
b28wHhcNMTkwNzI0MTYzMjIzWhcNMjQwNzIyMTYzMjIzWjAOMQwwCgYDVQQDDANm
b28wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC6sq2mHj6HhX9kaMEB
39JT3QQoRJne/jELnLG7Z2tlKn1L4aSf5dYdBYK0OoPvko3VJtYIMK/7zl6LeEkB
vJjVmDI/t/g4EjW1IaN369L3xnUh+1CeT63pgQ2WAMIFCQ6Sg0cK9Yma0QmvIzp7
iPrYM4V7xKZMxSa+tNY2visaUFxsjY03ZAp8IrmmKvnfwGH4AjLTbmmJqR9Cx/0z
QASravOvwKLFlor1v1ngK5HCnkgi+mZjHE161rbt/mR6KjgBxP4/xCZxc4RaiyUa
DoTIOQ67wwkOd9SuBjLZ0snFTehoVPenlWlB6QfxglK/AMlaFwceKlAWH+AarGhZ
7SZVAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAFXzkgWBmF5U98VdeC9oyH2hRSiu
+SyKJ1dzxJaSRMxu/v0pnWXjlMiFbGOe5ioIR6uiF1ZI9nZIg7RZODrnA+KNLN5l
jaDVQ1iHXE8yEjljgkxBaUbgiHHNVMNLNpBOZGvix/dIhgIEyVzNOHzQZbN9uYA7
zBI9G9eZedZxCNBwBDJKcYGuFZ34wmEP5zZRlTgrbCWbpIMAp11TtJ/M0bJAME6l
0c6uF6AJOvJ/ocB98FMNwVDaKo4rFYJIF+WNebi/6kV3KhafUnToOrUcQIBK7kX4
rKSPSUzGCU9/oeLdKa6xXdrBa3ZhX7QEnkFme1OewSiD7VJYFWvOPrQXeDc=
-----END CERTIFICATE-----
"""

private let serverCert = """
-----BEGIN CERTIFICATE-----
MIICljCCAX4CAQEwDQYJKoZIhvcNAQEFBQAwDjEMMAoGA1UEAwwDZm9vMB4XDTE5
MDcyNDE2MzIyM1oXDTI0MDcyMjE2MzIyM1owFDESMBAGA1UEAwwJbG9jYWxob3N0
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAv2kGt8X2cNAmJTcPRfrL
ksCrV3UvN04P9A7VPQeINC+f7IY+cZd3EMcuTleRcnl14pW2CCeDltihi4EQvkxp
UxTj528mXh8P3nJ0wwIS8Dkrhdm8Ya1/UFHigLEaYaPJlUOzTPJqL5gFo8hQpB9N
80bXbz0NPtN7yyIbrCCek4XoWxUM/Hjhr6pgt2nl5y5JYKwKlWq5lCIfyPWwM+fG
Mo+RrUxDmKaCiorMJc5GOaF/X2BlR1TcRBz3N8Er9wP5kcmwsaXDar6YuNgLQ1Tb
ZYRUanV+C3f2/ndwduzQtlNLmFq2Vr4lekjyCNuaLD+WIC7S+mtEUEp+S5qcPMpt
rQIDAQABMA0GCSqGSIb3DQEBBQUAA4IBAQAUXmufkCiMxXSQRl1lz21G+1mhnxM0
fxEil43Eby5UYjyoAqTtrLmN3USKFVSpDvhzLbkAGEDeiM8GUdYF/nRVYuGnrpVX
+AW29oNhgxbEg75P0AGu7TbM9nX2Ojm65ZIncKatopuqJbR9JgyMFgjc/H3HCGQT
CcYNw8xzokuv0uHzQXtYok7AQ9JrUzIqzeuoJjOMiv2maIR0xKdS7nxyXpikgrMy
IPk+M4Aat92k/5PIXZxTE1Zy8C2eFqwyDtITR7tVHCb1HtcOcNj6elxSPHlwR5wS
vKLuveCELG7WZ8j8xOXLyPIAJ6Y0c7+5a/TPFxvkt1hGnqkbmsKZT3tv
-----END CERTIFICATE-----
"""

private let serverKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAv2kGt8X2cNAmJTcPRfrLksCrV3UvN04P9A7VPQeINC+f7IY+
cZd3EMcuTleRcnl14pW2CCeDltihi4EQvkxpUxTj528mXh8P3nJ0wwIS8Dkrhdm8
Ya1/UFHigLEaYaPJlUOzTPJqL5gFo8hQpB9N80bXbz0NPtN7yyIbrCCek4XoWxUM
/Hjhr6pgt2nl5y5JYKwKlWq5lCIfyPWwM+fGMo+RrUxDmKaCiorMJc5GOaF/X2Bl
R1TcRBz3N8Er9wP5kcmwsaXDar6YuNgLQ1TbZYRUanV+C3f2/ndwduzQtlNLmFq2
Vr4lekjyCNuaLD+WIC7S+mtEUEp+S5qcPMptrQIDAQABAoIBAA6b64FXQKn3mRG6
FBZZP/RhdDJmpUXpVVphT3ErBABHqkMZM+bjkpjbOvOLx3QfRRoYJx6UNXzr59iH
70k298r5izN8zkbcxA9MWRERNXTUSDgdGD20SkVNGqaL3eGZ6KbV1feHgQdE6RlJ
Dq6YHRD2VTcOR9aFuasVXVtT2gaUTeq6ZWIyg5ZbWJGyiyqE6TX+yEUzbHWEH9ra
yzwNNhibmCw6WI9Et2uLdlk+wT0jP2+Yj1DGxfv9rrl+rXian/buZNxIj++0hmQG
XnaWRNBTE8a5y6g6y+PxKx2Dgp92JkoBy9fHYcdVDxoOVMq5ScYCYwNU+rOX1QQ9
HLDH0xkCgYEA8q0yF25Sdfsalh6SuAhAyv3sgCDasb+mI6eEe6W0+Qy0WwrqEFRi
jS505rC+c61JGhLAKoHhc2hxx6uI2j8BXS5tf0WqPj14MImAX3opxOEhBFOEK81w
Ui7cfUWIBlrqth2KxJ4XhC49zuQ/t0+a5s8etrofu4AY2H73+CtLP8MCgYEAyetJ
Nc5v0rx/eArPw9/yhen3AX/wrMjjTCAUDdIKKEG2u9ACWhSaaqZaYUaIyT0yZCFU
Bx0rALhE/qmGeNtRtJFNDfiNEETld9FWhSXECwXGfl2x1svGILrf4sfUWtab+x1A
cctR5kAgghM8phvlqEoyWStP1PBo4+18adTftc8CgYEAoq7Uq7x7bzgchJKOTOzL
csly6BoeQZZ2q+Q6/iECBwsrRPU2IChRwM9p8tR9eFKsdNwpEtXq61ETJYWqwpQG
OA9NvEpZbEwM7IzhECB3K9K4LYxHSI36RD3B9gDMxWXhfqCjTFem8CeHq9B7nkmx
UBV9Q4XWi/29qjTDywxK770CgYBaWzaspE93/zAPeM8WeQ2fDV6iRi1eNJs6QpSW
xqoS760lCGU1CEk9dmm1ZAnr+72j/yIJ+Ox4av089IGfbY13fxn7KYF+iUYiQwQz
mv3KbPAxNh5R32gu11E+u2t0ptqwGZvwECr7HTEu5ArczlkL4P/81RvpTxew/2IQ
PdlKEwKBgEnZAq1XpUtwVkcL9wg8ja6DUK5UaJ7FEiNBwE5RXriSUkq2Q3SyYXWt
qNRk24xKHewLSjfD9ylR0F6u9BfyVTT5CF93fOiw4Zpb7VXEj/v6vQgcOmT7VOjd
6/McAU7hhTPTZINRhXP8A4Y8sXdGb+rgc/5N1ifLTXxD4FYjS+AA
-----END RSA PRIVATE KEY-----
"""

private let exampleServerCert = """
-----BEGIN CERTIFICATE-----
MIICmDCCAYACAQEwDQYJKoZIhvcNAQEFBQAwDjEMMAoGA1UEAwwDZm9vMB4XDTE5
MDcyNDE2NDMxMloXDTI0MDcyMjE2NDMxMlowFjEUMBIGA1UEAwwLZXhhbXBsZS5j
b20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQC85TeHIfnz8XeWVAYQ
NNPNZt1BeWfYSe90PbYhBEVjtQPLWTlDGjVtcWdVcFO1uIaZPrKmtDIrgi6vWIhq
VsW+LHKZW5lZgVzD/pIKOOAkgurxubGIR3E5O9f7qwHTM0Dv2jxYCtIujhK+K6C3
o9nD5GsQBLE5qn/K5DkPKhCIgvnmR1C+Mvaz4IxbkgPBRT73bCr48qqgOaQ0I4Tv
eOzu6uRKf/nwTpPGX9fjTwOb2Nu/oh2w0juFdEO3ZXMAN1F5Nn6w7zre2qR03rw1
Mm+q/8aXDzwlzjb3Q1TGoJx2Bgrj8Q1vUcWq8/NMoGVyTHCK4qhBk123xVRSYjmv
ANyxAgMBAAEwDQYJKoZIhvcNAQEFBQADggEBADpw4EOj4JNn8ltTTlJfuJKh7Gor
9R7xuvDC0M81814g0LOKTOegqtPV7ezYobQ+QGvfmBzLKke7boyYDTPeUo9Wx4g4
auRFXPWF3QKSvJFF4tPxZe0LXQ0nJFnnnYqqfT+3tro8BktQLeo7TUGLsQpPf5By
4Zx9NIjOCfOrLxg/zX+P8QgnSl3/k/X84LOZMV/oydajxFclE7h1YXTE8AKMRMff
iagsSobYwSoKTitC5EoJgdOB1UHMIR6PHNSgA6K+JWJkAoN+1EA12SeyWGJIt6wU
SroyIgFyKQBEzxlpBcoENKtPsn1jdrV+Qi8nfGea4ddsYnLdZHwX5NslBkI=
-----END CERTIFICATE-----
"""

private let exampleServerKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEAvOU3hyH58/F3llQGEDTTzWbdQXln2EnvdD22IQRFY7UDy1k5
Qxo1bXFnVXBTtbiGmT6yprQyK4Iur1iIalbFvixymVuZWYFcw/6SCjjgJILq8bmx
iEdxOTvX+6sB0zNA79o8WArSLo4Sviugt6PZw+RrEASxOap/yuQ5DyoQiIL55kdQ
vjL2s+CMW5IDwUU+92wq+PKqoDmkNCOE73js7urkSn/58E6Txl/X408Dm9jbv6Id
sNI7hXRDt2VzADdReTZ+sO863tqkdN68NTJvqv/Glw88Jc4290NUxqCcdgYK4/EN
b1HFqvPzTKBlckxwiuKoQZNdt8VUUmI5rwDcsQIDAQABAoH/av1pdiDIcmNSWNM+
m+9QCAc7Stp49wjpl+1cO1cv9kmQ3Jys0lUF7fdNkBcPUt4xXpsklUd7IymZR7fd
jF2Zox2Jy1MWiJu870ZBcYjFa+i7Ki8DXy0X9FLxAprZbcaaAUCa7UMzySqvcwdD
AMDNlybJfUkrGH5543Fg4DXzJ14Nmg6BMTfCDsFucjlDb3Nvp7bk3EyDCSOpqZt/
LESZfqNGM9cr81JidWh+V3ztwrCI/GIT9Twv1KjXhCm5QrUGAHVXP9nrvhngASRs
Z1m+SU/w/uSVsYwnUuD+9/CVeiggfoFPRN3RnoGk48xO7OL5ey+W3ItKvjl62DTQ
rfWlAoGBAPUY4gBapCQ3r6i3QHns4NTR+P9IJAtxvhwv0fhhu2Wujy41L9tiPivp
kiLmm8bn2frRYZeAe7B8MQ1mzcV4aBYt9E7j9YFJAW97zJE+6YmwkaYETctq5iPi
DSDNIy5fKgx/popyJsyan83elE4Kf8983FCEiiR21Xx6pjWJTaCPAoGBAMVMUbSV
e31BBadCDvYg0FaJ0YoDcihNHLnNHE1iBIz3jY3CIY4myvV91NqBJYSmi5keEL4V
TXW72dv2iuVHfYQxsM82kUI/TKQDoi9LbbbzRR5DmZMBSzae3VzZ0vcQQVPAv2HX
x/Lo6cAYhY/y7lnI4uhtWiqfXOlgO7v2bc6/AoGAd5iTtw6Dp7SQf2gkCxqePtrS
gGbIR9lRpdljwKqX0a8S6L5FQuy2X6ESkPssKiu6PtxqnY2xTVXcbairYd82ExSL
cO9lPZfNHoQvNvSW6nwBJhxVhZv8/qdwNoBC2X7QOtcTAd1ft1j//2nLviT7ZtiL
fLKf4dkmpR4H+nmsKlsCgYEAtW4LLI7Rskra0gYTEA74xruRruKgVaMjqVCOmDJs
kN0MlLFSfg/6T2nZFN3yDFvCv5lAOCwKwRtvqbC75T+qkqfHOaWqSks/RQv6Vpd8
WuK2SrBLRz3HVoEcesfsEjomeMgkterh+eRpH7btC4SP3oy27JmycsN9gzZ1d9GT
BK0CgYEAtLposqxVXBYtmnX4RKl+yp0gLWrDHPV7118N8UZujCHDOqarNs6Fb00Z
QStA8tRXB2NlNIrVTWXVUGAAw8zE6DCtaG4lh9TmZBH1h8eN/99STuyEZ9Y7+6kH
+SFKpnqz9phuS7e+Q1xvKR2KeZ7Ja0C2XAJPJmTDhhy1AWDd0m8=
-----END RSA PRIVATE KEY-----
"""

private let clientCert = """
-----BEGIN CERTIFICATE-----
MIICljCCAX4CAQEwDQYJKoZIhvcNAQEFBQAwDjEMMAoGA1UEAwwDZm9vMB4XDTE5
MDcyNDE2MzIyM1oXDTI0MDcyMjE2MzIyM1owFDESMBAGA1UEAwwJbG9jYWxob3N0
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvZguzd7SpvleMWDBXS8Q
Ugc/uE9nyCKDUHG6OgTZOeM6W16CfoKE2UI1lXAyL5V/FjOctzSVMXfMhbYT/Mw/
8RvrMyKGdJqf1j6OP6ziJpbWT/hAlFK143nB5zR/RxVTlUcE+Cq5IMkvsjL0QD2p
vQZ/eSRic3SWAfS2OnJI3xqhNipf3sIuDR7xVeUUVKxWAVSXGnjB6CBkUnLX4doh
PTtU8QKToCrWfMLTon4XOPTq++IPifRZ7Ct8gR8munE266Hz5dmVuFAPMuqt/LmE
UUcNv/sZXNyVjhx9AfKatstH6i7n4opBMyq1JBFsIpJHlzp1tR7rTRKlyfUwpVk9
HwIDAQABMA0GCSqGSIb3DQEBBQUAA4IBAQCoRe9bTYTgz+NduY64rmuvSCjvUvr+
2OlNFBp/6ZJzKR1vk2ALrbvPDBF+L4zoKNodlKyy3ejaeNPij/XsZzvReh+kyzXu
Xo0a6koUxrrYRW8YKgOCEnsGKc6zXVe4bpT7sAf5+dLPIEI5qIImeQGDfkkwkgWz
pM2/9HyNC+pahmM2+IOZOuCemo5cpZeruH3HVjoY4dsNnqO1QKKlk8LYhU+CY0mK
m01QXLslXNMYx7sZr3IMl5A9EUQfUUE1y+b4nD9sj1bL2hosP2TXwBnlaPM4O8cS
oyQpD9JXYI7yAoYLziq0aE0BGAJ8++bqaIoj7nVc1/HGPX/LnHc/VyTV
-----END CERTIFICATE-----
"""

private let clientKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAvZguzd7SpvleMWDBXS8QUgc/uE9nyCKDUHG6OgTZOeM6W16C
foKE2UI1lXAyL5V/FjOctzSVMXfMhbYT/Mw/8RvrMyKGdJqf1j6OP6ziJpbWT/hA
lFK143nB5zR/RxVTlUcE+Cq5IMkvsjL0QD2pvQZ/eSRic3SWAfS2OnJI3xqhNipf
3sIuDR7xVeUUVKxWAVSXGnjB6CBkUnLX4dohPTtU8QKToCrWfMLTon4XOPTq++IP
ifRZ7Ct8gR8munE266Hz5dmVuFAPMuqt/LmEUUcNv/sZXNyVjhx9AfKatstH6i7n
4opBMyq1JBFsIpJHlzp1tR7rTRKlyfUwpVk9HwIDAQABAoIBAF1APrUPRXjO6h9L
QY/9l/9ghVy34Ym0P/YPGdNzkww/0PIjt/dVZtYdFJHdzzFMTGe1Fv2dJUxhafzS
I16Rb1m9q59I+ezcKIWN2xVCiTEFu3810T2iuMebmV2ImplxydyAQ9dz2/5eNdFl
8nCuY5APZB9HYAz9aNKpc/+nOmRQsfDfVZkDXW9g7HPOY6dQyvqyVK8iitDRoZ60
xGe4I/L/ITfdlqsYVqBTF/btx/7A0wrQW/TpBleETSq7ipCG0r23n8ZRLMxjNT99
JJbyqDLNhAUF1F2+XpXS+/zSsd2q1leVGLa+u8tmgXhSaVUphwrwxZjW4ZihWj38
gFyrkaECgYEA4nqemFfDnH4DLE7oYnXrukXPMManeznH9yEjd6rm6LSdg3uJH5n0
b+mSah/hY4krl5KgOfXE8bm92rtVaC7vyN5p1K/8KFCaaTiwe0scWDPbAIYNGGRw
h5JZz3AtABrRiF1zb9vydRxOzYrDFcxqnSCm3FNAYvrc5BLWEwjKfbcCgYEA1k7D
ZqIRmAiiCYM9YM0iNlWFPux/ytb5Bk9sOlwM6Fvc9G1eBH+SsCTIXuI8IvsFjxsE
oLEBrvB5MJ+tVWzSplsIA4Z73CKJDKUmfEyA27MEuH9gBd2zGbhWQZ/S3IpOoacq
4DWMzSL1ydeCEt2GsoM4uS9StBnUptxpMfcgu9kCgYACZfYD+vnxUExMTdGcKU+D
u3WEOLZRUb1SWqF7hO3JDRCV8drz4Ld77+dDBG9olG1Hv5++vWGGhccC5/Txk32q
jOBmBi8PZjscXiNQSu1T6cip6sF8vqOKa/xTfAad96q8XPD6AERDBTe4aX3DX1TJ
sSzTLHaEFc/9Ak4OCYvLZQKBgQDGGSB+qqlgw/okmPAPnw9U8lCtDahDM9wVfS0p
9RTpZKEmQEJ8HgDWWent62pzW16UHgF1GKnZr+gWjkOHh4RgyhzqRVIQ9suAqNie
ZYlnjF98vCFiysBXshHpr3cW7bIps4DqqBVzOjHBVjiif6uXL70rURc96/KqG2wS
B8J2YQKBgQCNbtllYeQJpKylxlR4aDIYXVKlUXpXbiYegg1HFpwXRijTuFWE46FK
8xVRJeuUgN4pK9Qdh261IKWhHTQo1Fe1cAVxuHJEMLNlMraJoLK1RUiDvDV4pUzt
eEv8+Pr/GzzyAHdlESmPYdKjasD734+DL+c0imj7lmlt4d8kQs/oaQ==
-----END RSA PRIVATE KEY-----
"""

private let serverExplicitCurveCert = """
-----BEGIN CERTIFICATE-----
MIICEDCCAbYCCQDOr0V8CUAs8TAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
cGxlLmNvbTAeFw0yMDA1MTMxMjMyMDNaFw0yMTA1MTMxMjMyMDNaMBYxFDASBgNV
BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABChr
XwTLM3T1C0aA+8pJMVJOyVDP0Scd38OdqBISYvHLaNPRuIaMFA2KTE25pMqsqNe9
YNfgimABp6HUG7xKTMwwCgYIKoZIzj0EAwIDSAAwRQIhAM6ihMqgQ3Rr/w7oBhG6
uuA2+wn2KhZgSqgqTTtyo/ImAiBLrG/b76/7eaZ4t6xWHtKWH4y2e1zrxLDDpcjD
0zglag==
-----END CERTIFICATE-----
"""

private let serverExplicitCurveKey = """
-----BEGIN EC PRIVATE KEY-----
MIIBaAIBAQQgZeJYnJVaOdltFsUs6KatYy9XFmX6ujfUSkOR69RoyRWggfowgfcC
AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
YyVRAgEBoUQDQgAEKGtfBMszdPULRoD7ykkxUk7JUM/RJx3fw52oEhJi8cto09G4
howUDYpMTbmkyqyo171g1+CKYAGnodQbvEpMzA==
-----END EC PRIVATE KEY-----
"""
