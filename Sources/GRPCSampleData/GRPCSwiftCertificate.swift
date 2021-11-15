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
    // Not After : Nov 12 13:06:40 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_400.0)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    // Not After : Nov 12 13:06:41 2022 GMT
    notAfter: Date(timeIntervalSince1970: 1_668_258_401.0)
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

// NOTE: use the "makecert" script in the scripts directory to generate new
// certificates and private keys when these expire.

private let caCert = """
-----BEGIN CERTIFICATE-----
MIIC9zCCAd+gAwIBAgIJAMfc2gvFlVceMA0GCSqGSIb3DQEBCwUAMBIxEDAOBgNV
BAMMB3NvbWUtY2EwHhcNMjExMTEyMTMwNjQwWhcNMjIxMTEyMTMwNjQwWjASMRAw
DgYDVQQDDAdzb21lLWNhMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA
8Ko4QgNV2oiM2h/zQcgyQHF4eFpgU8h3XQuev7Hwa8ZkMFOgVDQANZJEhURNtLV0
rFjft23uMet1tXrEnFBW2Lj05gIdkbsrZXVSyhRAZ+LKUyY5hCvXSy66JXQpkbQi
UhpKyqni3GhIMTyYb7HMo8dA/0XNWl+I+DrsivBXiE2hD2Fq/0b+G4gOxGHujYRJ
WGMm8uHA/B67sPej9V6yn7OKsqb9OEI/VE5IsfHumAR6HNV4KBHnlIqR+REzXcT1
eqra8koM9A7un1SRkMoU4HyVdk4VAdXzAxZ6IiFtXzmQR4uwfVpQfiQ1bZEpVKFV
kZusdmmoTvgfU1MQNZLj9QIDAQABo1AwTjAdBgNVHQ4EFgQU0qP3HeQn4dJyjUwN
EKLs4fZY/8QwHwYDVR0jBBgwFoAU0qP3HeQn4dJyjUwNEKLs4fZY/8QwDAYDVR0T
BAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAlPbE2MXzO06GcRuTj8z6P7FMRSEV
UrUvCkhHzSkJPYA2t3gsShbksNrj815LxQGu66QtuwqkL9Ey/K5pO/8XH00oR58H
QkDcPuAoVac/8ezEc2z1aJ6FzvAwiKBJDkS6q3EYllGmLHFRBFbg0oewtppHZuv5
6dVdra/4XH3KNMdSsdv8rKc/mAG34eRsT5UPNTuW0CBm2whfob4nq3sVwedh4/IU
aWeKsutFYsrVC/ppA1H3ZUS/L9bEcpj3CmEdjRtX1wXN6yC2WesjwFOvYBZ9ENWL
6p6Dk6yoQWwmoM9Y72MoWC5PMHc/4zkHNl4g6Fcbhv82prR5e2AzOaWB5w==
-----END CERTIFICATE-----
"""

private let otherCACert = """
-----BEGIN CERTIFICATE-----
MIIDAzCCAeugAwIBAgIJAKXWyMK52taJMA0GCSqGSIb3DQEBCwUAMBgxFjAUBgNV
BAMMDXNvbWUtb3RoZXItY2EwHhcNMjExMTEyMTMwNjQxWhcNMjIxMTEyMTMwNjQx
WjAYMRYwFAYDVQQDDA1zb21lLW90aGVyLWNhMIIBIjANBgkqhkiG9w0BAQEFAAOC
AQ8AMIIBCgKCAQEAnwzOvLDX6wsyZRbX8LaVGgtmVEEft2BWF8V+/2gHo428g1ba
YyHvMS8CJTOneIKB6HYlBEamB+wjnCFvWMz0eynzaT0HVJwhK5qhRYNZDr4ZtGFx
ov0Xau+rS/YW7NMNKLgLDgHYLMBDWLnyfDy+VWBUlhwV1lzlk9xeZdHvFodNbjpC
Mrw0gukfoFXvdvOqQSP4J/9TITv3jCY4gs4wZMFY/+XzpxQNEP5deEJGsH13PdXV
hHxx11VP+ippkkcx7d11UP8UR9Y/RJM319tgOl91H7hTfLE/dn+N18yFGdW7fGW8
+MGV9tnk8K9JavnGOL9pYfjCMuZav3dMd1ObaQIDAQABo1AwTjAdBgNVHQ4EFgQU
GJjjNxqJOPKpPAiKVIYT1TRhJYEwHwYDVR0jBBgwFoAUGJjjNxqJOPKpPAiKVIYT
1TRhJYEwDAYDVR0TBAUwAwEB/zANBgkqhkiG9w0BAQsFAAOCAQEAA+zbg+pxa3lI
W1lZcBb6fEiaK9sazyJfZ0vXBQmX3GuCQnWhTHmccvYQVAxqzQAwTfTEXfIu8nPr
76j60zr/rTjDHsc0i/xMoaCAsWX7h/UcMYOsfgbKbFR7kvbf5n/2RdKbIbd4A2Og
2sD8k7gqhBBsDgGbNsrIgzKoQYSrJOjTxTFlDAkG6gypRKqSzgiUvh+6wP1h4Jj7
GpS82LHl1x3oXH/RJR3mWBy61VMbOHDc54lmbezs43WLOvnfimAvr7LfsfYSmp3O
AlNpK9RvHP1Xfjx43l+Bb2EEJWAf/eBjWGpCcWz3EAl8k9W+lousBh9/wacdeLCV
lNtTzgbeYA==
-----END CERTIFICATE-----
"""

private let serverCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMTExMTIxMzA2NDFaFw0yMjExMTIxMzA2NDFaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKZbykEoZj1mdTRW
ofPPmEmBNlPJcepamcKtBqsqjv4OBbWVFgMIlmNgRef7ZWlz/YHE3cu7dISYEZ2/
C5zKgNGPiJFtiPC+GHKGPAbAHoxQa1kT204r5Hxpjr5iKAPVrHKilJO3wpF8Ins9
G6AcR63lyppO/bpW6RxcF4fivcjiVvcq+TtBRrA3JROduQjjD6rYXuRHcrIq9Hc6
CnUxQ1t1DCU7xqUGV8mdpJlI41NGqz0zoxFw/OKT2/3MR7mHGzAD/vHjIgKE0B5T
9xPa75ur7Gi70T5jT/3jwFaVKCt4bQCIAREuUEtzbwxGYoXDkSodUS/KLfbycCgy
u0wxOsECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAONUYolaHs2I3CVB9rCspr25I
jxQfW2xzGuLsm91l9GxvtDS89wEu15zhFDsQPR6u9br6qENfMVDiOa36wCmtvjxJ
2vYzWiWBVoSEBvwIkWMg/qlmdNB2lRxj/WgjcGNtUJwbe5Ex9ldquspoQNfEvwjz
KeKnDCJ8oit6IJvkdG0crowReX9w3fOFiARp87J/NoQlmm1hiY3FD0nQ3wvBhtby
0svSQSwG244B9TlzLBwEzRvC8+qLIP1LSjBXg3nXZCfkV6or/B2+gOl9uxB76O2h
KYJqo2GeZKYQHF5Lco7DYfzJcL7IeDNV2yeLk/3i7e6OoLcMr8G4aJ645em+WQ==
-----END CERTIFICATE-----
"""

private let serverSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMTExMTIxMzA2NDFaFw0yMjExMTIxMzA2NDFaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAKZbykEo
Zj1mdTRWofPPmEmBNlPJcepamcKtBqsqjv4OBbWVFgMIlmNgRef7ZWlz/YHE3cu7
dISYEZ2/C5zKgNGPiJFtiPC+GHKGPAbAHoxQa1kT204r5Hxpjr5iKAPVrHKilJO3
wpF8Ins9G6AcR63lyppO/bpW6RxcF4fivcjiVvcq+TtBRrA3JROduQjjD6rYXuRH
crIq9Hc6CnUxQ1t1DCU7xqUGV8mdpJlI41NGqz0zoxFw/OKT2/3MR7mHGzAD/vHj
IgKE0B5T9xPa75ur7Gi70T5jT/3jwFaVKCt4bQCIAREuUEtzbwxGYoXDkSodUS/K
LfbycCgyu0wxOsECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAb195ecB8D8P20X3j
Sc1dHF5s5845aTOB+wYeFVFKVWFbRJwx7x2qpUXv4KqYrHNNruQKukmFTIA1pBHC
Ejdr5PDudUoxLwZE43PrpjxqhdV8bgXogB13xTEJwCkpjj3b9BNsiL67n4B3BAzy
aXOiZJ7tPYmB9Fpxom4W6Iq0uc0n1UShbxZerAuBet0pYkmsoMPVupnIH8TqZbIL
6Jht6iodCjf+WP7hgK4nXEXVd0SFj9mjpWTaz/PPfv/hTd53K1kZE13VrEifi3C7
HrCPXcACcUohrXZJW1764yuODuQKpleBjBt+QvlhO54pBBXdP3F+h/FirQIrymA7
BBG4rg==
-----END CERTIFICATE-----
"""

private let serverKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEogIBAAKCAQEAplvKQShmPWZ1NFah88+YSYE2U8lx6lqZwq0GqyqO/g4FtZUW
AwiWY2BF5/tlaXP9gcTdy7t0hJgRnb8LnMqA0Y+IkW2I8L4YcoY8BsAejFBrWRPb
TivkfGmOvmIoA9WscqKUk7fCkXwiez0boBxHreXKmk79ulbpHFwXh+K9yOJW9yr5
O0FGsDclE525COMPqthe5Edysir0dzoKdTFDW3UMJTvGpQZXyZ2kmUjjU0arPTOj
EXD84pPb/cxHuYcbMAP+8eMiAoTQHlP3E9rvm6vsaLvRPmNP/ePAVpUoK3htAIgB
ES5QS3NvDEZihcORKh1RL8ot9vJwKDK7TDE6wQIDAQABAoIBABWH17trISBdPFoT
xE4r1gfdY0ygy8+K/k+F2VEZ5vvWkMKZkwm9eMlP0nxduxhU3MCI3DPcBQ6MJ+uE
qFoYk2eL7h70UD7oO33HBcnR36JFXj9fJIkPgTjg6IqXZZppczI6/IPJyrLNoCDX
HdYxEs3c6cXi50/Qo8b53EnH/Mwc2bS8HSAkL7sYd5+AKjfe2XlIt395nA6Vbpex
SRnGmWnfkyo/PdHyNd4WNjhDn4zW3rlJtFO6z/Rf7DZgU+utETf4CEDH3Bfm0hqV
bAl8zyuytpGWv/2e0eyvQ6dEQZLNI2RAuid5M+FjT5u5fBOpggaqGe1L7SfI5KiO
E1SiQAECgYEA1d5g2if0ZOLg3dG+tzYXscss62o5dhW4ULa5VzVZ9B0AX+CPBJCj
2uSpVbhibrCljzgoYdL4+sZw6955pieXBFrPMgzfR4sjfK5z9O9GerMFecUr3+i4
XLgYCzrmoSytNem64mV/H5WauR6Ob0UlDYrLDWfer1OMHClplDsVdoECgYEAxyFt
SYDCabN+4Yvh+TC/X80h65f2GNrwZqFrXjnfyOv4SyY9U2XvMy6YTjM9gTy5RJQ2
XaG7Upk2auRU6n0VL311/GA2eL7iBRqJL/3NHibT5KfeXfoiAAYyjlbHrGN1QJWe
3o8XdPaUh9ccGT8fZhl+Eg9VeorUmSCwC4UUJEECgYA8/CyiCMKoAgodNrIrjEE1
cbpdZuz7vzXPzksLkysTcTGqJV6i7pvKz2l6CBoJdlW/gUQCoSZeXDfXCpmlx6RI
mZx7qTACNqrn4tcuAQ0X7/SfxJm+P55S0iwJB8K8MwExXnTsGgUl/IMiRpRXJmBq
fClqqTPWyvwpC6YPnsmAAQKBgHLt3wa6Uvrwxz1kH9NUCFBBs98nALnNu0xww+hJ
XNi5IMA23NRCk/ElZnBT8J6jroZfSJV34AbHOPouuLfx44VaUvuLiETeXtL1QtK5
GGbboBZrsNLqqC79ZLZ0baAYczcIY/4t9irimk1goO4NWZDzC6lewkYM1LFghVrQ
vxRBAoGAEDEh/IUmsYjyPVVDm+nV4/6ODtnhqBpBpAGo0JL3FJ7XEOR3byH4DXQG
Rdz6haHMfQQqBfiPOk9HZ+Y2WO+PHJ3OrM6wyzZUXKZr7r4im5hkisITVbU/cIdl
FqOsrd5SuS98XIo05JKlWbPFLgzgYtnx2zLiU8ATyJHIF6LrbwY=
-----END RSA PRIVATE KEY-----
"""

private let exampleServerCert = """
-----BEGIN CERTIFICATE-----
MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMTExMTIxMzA2NDFaFw0yMjExMTIxMzA2NDFaMBYxFDASBgNVBAMMC2V4YW1w
bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5eeBEXc8K/Tg
YkfueXOlX3tZU45ooudYeBMyHPLG/2j1bRxLEHTPQ/1SrSKaTZH+s+KdKTtD7i7t
6SEatnMZi01NzWMA4etARx3cOMtDtZIoA8w6pgyxFVY8iOlehrQrPoOvZrZc1LJl
7xK6xZQR3v1t/68fhQDU9uOU6dNJgvyjMsrhOuJ6DPHmOAe1pUUVu+/7SCwCd4of
Vsq7pfahQhMQK5w8IUtOlqd4xg5tgTGWIPFmppVACYSOpDVDQM30KH8I1W7idhH8
EAyyTEbJx9B1wwi7PXd4u3cCeZRrSAgwEpRAYS/ZznCnXuZ5fafcvUO3X3gB7jAS
XRPrm7/EMQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQA12dbCAmQBefUQ5PkjDu02
pO+ajryeivexwM4mpn8u9IIANQKu7E1oJYfj3zflpIxly3DebuoHV7zdFzfDzdu4
LIQIEqqqDLsBA2gvk25INMgXx9rtA1fmL3pB4CDUoBGHkprJHdni6Z397sZIe0Bl
vOca55RbpZ4kj8qEUxI2WrSVtotRuQLS6KuqGEFeZS4+31kP6RVD7H3ZlO0gevNM
TgIHZknzu5Lvhdz5jx6PO/3RRwC3V5UB/mHnY6f8QS0M2c2gpS8nZUNpuN6dkRHX
bcEVVDiWHZnLwA8Ugts2m3eNXyPgmXSgFW6Be9FGYwuTCh6mvXR2Zf5pS+wAndBg
-----END CERTIFICATE-----
"""

private let exampleServerKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA5eeBEXc8K/TgYkfueXOlX3tZU45ooudYeBMyHPLG/2j1bRxL
EHTPQ/1SrSKaTZH+s+KdKTtD7i7t6SEatnMZi01NzWMA4etARx3cOMtDtZIoA8w6
pgyxFVY8iOlehrQrPoOvZrZc1LJl7xK6xZQR3v1t/68fhQDU9uOU6dNJgvyjMsrh
OuJ6DPHmOAe1pUUVu+/7SCwCd4ofVsq7pfahQhMQK5w8IUtOlqd4xg5tgTGWIPFm
ppVACYSOpDVDQM30KH8I1W7idhH8EAyyTEbJx9B1wwi7PXd4u3cCeZRrSAgwEpRA
YS/ZznCnXuZ5fafcvUO3X3gB7jASXRPrm7/EMQIDAQABAoIBAQDHu2A+NEBqT8vA
lo1vpjC9ywPHu6jcHfCWINcgnyqTKjROHo54NYL7plD1aWJ0kamdzfqLn5lcjBjU
uJXkfAptIzO8g454t1CYeDCihrTEQb3RztQE/nG5/7mHmHcuv8fx/6WarkPn5TT5
hmQM0p7UA4hU4WeYvShHdWAh5BWxXPUy4DC8Za+nBQC2cjnJk8lQMqPbA7wwbSpt
rh8RXGWvXB2kh9LDJfCgOlyN0FJavVJ+RsrEpgINw8jplOMipq6KMqzpbJvO7RGq
nyWttlMheFagav2VmQ79A9/mcMxK2JP8amD842alCQopkBCUpiJp3CNoF38BNtj8
7D3DMQahAoGBAPbbeMFX2PPkifDFlS9Cide1Vq9aCIkXFAVc+6Tcy0pk83U5XLs6
PrIqmeZ5+GD2KKe/zMBLiuAjLXuyNtZkQi1XpC8pInk77szvLTVOLFsJYne2YSAo
vQBAGrKRFsHzRn76SZcuV5CUSen3fLKudGggHFoUKUVR8dMHVc/eDY7HAoGBAO5r
S8cOR85mnRaGLopKERcWjUOq6X5k1/atHjO+gawPcAxSTMebSvdmI/WcNLHiaHHM
ZorlFzjIfpx4o+cpjNB85RsVnMfrt+sS/B6DUaSgz4HXRIRPJm6+G8JtSi0Aa6gC
CI8yCKZsjAkcC6s8KRmuY9e3vqTnG1itTnsQin1HAoGAGmK5FIlsQh1ydQ7ZdFS7
YRgb7OBFu0mBNVWL/EIxZIFH2IbKF6URIIAXNSBiYRLOo6eHniI09OItsWQKIn5S
6H/Op8/QxH6YdsU14tW5Pf3RzZPr68EO+qDfeaiycwaqyVW9WfB1IZoIEH8IkBy/
ioWsIiC3jJZGr9S/4lkMv+8CgYEAlf/LXSEO7DyC+HjTLw4KUoxNtBUDchHgDcI9
DjD9RFMyG45r3+lD8QLB/PSZ8pCPRYljul8HjSIXBjqgY/8wKLtrKO8gBGe4/pyj
Ik9cPkcuRnI5GUTy2RmiPWClGkr5cGpXGEBSUOJZ+CE89i6TbSTajA1+VCFSgygG
CEcP2mECgYAPgAJ7ukZCWMZwRNy1WDVmmZfUJIMHrt/QpdaUemORKefpsiwIm0JL
LL3fEaYXnvV6J4SNcKxFDNCF3hUQ2gleRJ34pMmA0EWlkPrYnNcobRVhA9E1N0tO
Xy5aj7bjNP3+fmgjbPwPT2BMwTEuOeEyrZdNNYcDnp0oMNbcyjIbYw==
-----END RSA PRIVATE KEY-----
"""

private let clientCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMTExMTIxMzA2NDFaFw0yMjExMTIxMzA2NDFaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ+3lfFuI8LRc31C
qzBJw60JEJMohIXRdoNYVmNnTSd1LQHaCd/qM5J2QU7LtMpAfJ29DyT0Q3Z67VMG
Bgz2kcx5lKGJpNfT7BJcB2F+Em1wgPj/N/wrHzQS+hBrnRokt0buyrqAaEsRRU6O
8g6trnda9+h7/5ktQpHkNpitJXWYyykyAP97NjYS1wDsSORbAYIbFIBuGoPQeiDW
AQVja9VTTCqEdYsShsUjXRGUPgBEk9i+IIqZg3eLZ26dEfVx0f5vGrmWnVDKCSNK
TzHL7p6mO8NL0k8CrTZwHYvfgUjVgZu43L6GIYiG3PTZhsHCZZgXZ4hUuRWrwTeJ
6wx6u8sCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAJfnPkN+JURx7aYnyBisPFD0s
wdF9XC6/Oxxe9GZ3aaLcNsf6Cwshd6sI/7FKOdP3EVtixcrCMupH16cN1sVw4UC8
o8iv7G8h9XeY3DrzpOaAm1xxnRAox4AjY9Hkz2FzKyywCFNfj7I/vuPivdi1xk4v
tWGPXQvMmVhl9bP5FVEbK4w0MFIMkV0XnXuKffh+6lKS2hZhVejQ56S4hRMYT7Qp
wLDLwn5b2fYUaPKwjeoj1RA6tuagPnzVbvwGMrViQiwSqDgv2X7BxMP/5IxsWxlr
Ar/Yo+UQbilfT7pJWKvuRomZ+h+lg63AW1YmoLMkGV0rQL3qTpVypIRiJTdPvQ==
-----END CERTIFICATE-----
"""

private let clientSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMTExMTIxMzA2NDFaFw0yMjExMTIxMzA2NDFaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ+3lfFu
I8LRc31CqzBJw60JEJMohIXRdoNYVmNnTSd1LQHaCd/qM5J2QU7LtMpAfJ29DyT0
Q3Z67VMGBgz2kcx5lKGJpNfT7BJcB2F+Em1wgPj/N/wrHzQS+hBrnRokt0buyrqA
aEsRRU6O8g6trnda9+h7/5ktQpHkNpitJXWYyykyAP97NjYS1wDsSORbAYIbFIBu
GoPQeiDWAQVja9VTTCqEdYsShsUjXRGUPgBEk9i+IIqZg3eLZ26dEfVx0f5vGrmW
nVDKCSNKTzHL7p6mO8NL0k8CrTZwHYvfgUjVgZu43L6GIYiG3PTZhsHCZZgXZ4hU
uRWrwTeJ6wx6u8sCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAlbFNTPHLbJABMLy2
DwfznwxAwkCfyAdZWq7A5gLP3GhY5xafc3HdeJ6gOfeXH9v1y3DEI6jeAXxmXAAJ
4hOIQuVfLL76PIkAwdHRXYrzLdTiN+pGNGVBRiOZoXIzGcdC4k+2KgeHGyVu5bb4
EDFeeiuHMaeNlBEeIrUH38AsTm8hruVPuqnm0WAZVJ5RvWPOJgv667P6B/le+U5O
z5F11zPr47l69Zlh5Ud+WlG3yymj2ZIibuqdcQC9iuiLFcig6PhBheJzxr7MCvcA
T8T/DZusQBdcHqVrMbBfSnL426Kunqd8AXWEz09o5oTkeyK/CNWFyMfPfJqEOTWs
tHgfiw==
-----END CERTIFICATE-----
"""

private let clientKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAn7eV8W4jwtFzfUKrMEnDrQkQkyiEhdF2g1hWY2dNJ3UtAdoJ
3+ozknZBTsu0ykB8nb0PJPRDdnrtUwYGDPaRzHmUoYmk19PsElwHYX4SbXCA+P83
/CsfNBL6EGudGiS3Ru7KuoBoSxFFTo7yDq2ud1r36Hv/mS1CkeQ2mK0ldZjLKTIA
/3s2NhLXAOxI5FsBghsUgG4ag9B6INYBBWNr1VNMKoR1ixKGxSNdEZQ+AEST2L4g
ipmDd4tnbp0R9XHR/m8auZadUMoJI0pPMcvunqY7w0vSTwKtNnAdi9+BSNWBm7jc
voYhiIbc9NmGwcJlmBdniFS5FavBN4nrDHq7ywIDAQABAoIBAAKBWrTCyYTQzEL2
vMCxJ4SbU8s7I3kF5BoDVLeScz9fMymIRgdhIRX3DOczgs55XHsM8CPgQP6mxvo6
afXiGD9g2Nf/1Lod9OIE14jL9XYKAbvmJParpn2mno2LYpd6Y/WU4VEzmm8zAidN
Tra0OrxcjO70ovnAH/8x2Tlj3eaOTKl3HzOHGj7gl/DikQu1J2ZgdXwfwUPGYhL/
TtlifD3+UWZbFaG/RjrqAmF3UJr1QI0EseFgQJ+/8VpCsc/FEL21VETCcHBSmYjO
AMXiJIN7MxMArYtVwdTgYwklCeK8zxucB9OvDkAbxghUTClWWPNIk/TBub6vG7C1
JibtVqECgYEAzDlVYJSTDtk+RVm0yf0UZ2WzRIuxp7+ldq8Na3BNiwLQVDuQiMBN
dYg5lT5JOE2w10+oiZwNUZXy+hVA5Kd+HsD/t2zVV1opciYwe6/GTTiveo74PyD0
SP9R+P9936xuFAPaYRKwYcmv0c/j6Vx1qAqG1mup6njBUh+n4dvM1YcCgYEAyDWk
rbQLknMIqTENLab6H7TYaDcqq6lcW8EgxzcecCSNFKccxL2YP4KUyfK/DRm1ufpU
nmKPrmTwzmtHPZ/pnKKFzlwEtdX+wfg8TBC8UU4g83UioR9J3hSylbkwETscQqgF
eMEIEaJx50JDMGmn0BKpqK+sLSQslP3Gbcc3+J0CgYEAjx9LF0Fogkp7WozQp5Im
f4QFi28/FOm5YyCxDe+JWHejWrTXyQ7D+i96833QQJYp7esUmUP1DY1B2EOW0+gR
+imVzI2IQgyc6TOcXMJF/g5Q5FpX3Z4RtSrB3vfm1h94kaxVmhxH4nA/OJIyDnRO
vHKMJq8TSJBSI2St+hpZRfcCgYEAxADAV84MBjPYJst+u1LdTG0f7+cSPzxuzuUj
0eSESAWAmNeBsppqksKkJ5EeuRSSdKA+d1DGmVT46xzbgdksO8xgcsZjViFKZ1s+
rLk1o+N5Ht9uJ48aIfDhZPMHu9bCs/8KXE2eOKVwHZchcCP/xhR/REW3qfngK3zG
5nJCuYECgYBd2qcQ6oZAfnBTqrHbMy/cHRwkoxIQ9HqkmiGkFC4nNRUKULToaxGA
Er6QJWO3htk1GImKZdmDeJZIUN+aFCgYfzbNVgq8CUJp9vD28cQKTDTwKpN8jNZ1
rQ44/3Dg9zUI2KWxWYafpawuQIVNchlt7PAlVhtgNxJXUHEQl+/Opw==
-----END RSA PRIVATE KEY-----
"""

private let serverExplicitCurveCert = """
-----BEGIN CERTIFICATE-----
MIICZzCCAg2gAwIBAgIJANBDrZOOttwWMAoGCCqGSM49BAMCMBYxFDASBgNVBAMM
C2V4YW1wbGUuY29tMB4XDTIxMTExMjEzMDY0MVoXDTIyMTExMjEzMDY0MVowFjEU
MBIGA1UEAwwLZXhhbXBsZS5jb20wggFLMIIBAwYHKoZIzj0CATCB9wIBATAsBgcq
hkjOPQEBAiEA/////wAAAAEAAAAAAAAAAAAAAAD///////////////8wWwQg////
/wAAAAEAAAAAAAAAAAAAAAD///////////////wEIFrGNdiqOpPns+u9VXaYhrxl
HQawzFOw9jvOPD4n0mBLAxUAxJ02CIbnBJNqZnjhE50mt4GffpAEQQRrF9Hy4SxC
R/i85uVjpEDydwN9gS3rM6D0oTlF2JjClk/jQuL+Gn+bjufrSnwPnhYrzjNXazFe
zsu2QGg3v1H1AiEA/////wAAAAD//////////7zm+q2nF56E87nKwvxjJVECAQED
QgAE+YMhPzGDLJuuMxB+ICQKWvPjbTEsRXgbq3Hmrds6x/1QY14e/xh4TqpAEW6M
0R5xhqg7ZU7O8NHtuiCyxPzCoqNQME4wHQYDVR0OBBYEFD22/486iAai5jKBCttn
JstzA2u8MB8GA1UdIwQYMBaAFD22/486iAai5jKBCttnJstzA2u8MAwGA1UdEwQF
MAMBAf8wCgYIKoZIzj0EAwIDSAAwRQIgHwZi/Vk9odNqrae9LBxmt/ve4twT8JT0
+CvvSVkNtnkCIQDcKZBIlsR1OVVxZDWGtcvz9oW+MMOrrbFYAIaf0akhWQ==
-----END CERTIFICATE-----
"""

private let serverExplicitCurveKey = """
-----BEGIN EC PRIVATE KEY-----
MIIBaAIBAQQgxqYoMA6z4uJGgk/XIg1R2j8qF/Sv/g38YJG81dGGq4SggfowgfcC
AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
YyVRAgEBoUQDQgAE+YMhPzGDLJuuMxB+ICQKWvPjbTEsRXgbq3Hmrds6x/1QY14e
/xh4TqpAEW6M0R5xhqg7ZU7O8NHtuiCyxPzCog==
-----END EC PRIVATE KEY-----
"""

#endif // canImport(NIOSSL)
