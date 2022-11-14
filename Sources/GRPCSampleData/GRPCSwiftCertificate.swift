/*
 * Copyright 2022, gRPC Authors All rights reserved.
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
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699960773)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699960773)
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
MIICoDCCAYgCCQCf2sGvEIOvlDANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
b21lLWNhMB4XDTIyMTExNDExMTkzM1oXDTIzMTExNDExMTkzM1owEjEQMA4GA1UE
AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOjCRRWS
ezh/izFLT4g8lAjVUGbjckCnJRPfwgWDAC1adTDi4QhzONVlmYUzUkx6VPCcVVou
vc/WM8hHC6cRDdf/ubGRZondGw6bzaO2yqc8K6BNSvqFnkuQHRpPoSc/RKHe+qTT
glhygm3GlAUaNl0hJpXWlLqOoIb0mn8emF7afbyyWariPPQyzY2rywPLPXipitmW
Jw7GxVC+Q2yx5GQxPvutCdtkAsrS1AsYxpvpW+kHmtj0Dj40N7yhTz1cw2QtCD2i
CQuk9oRwtIiJi54USy/r6oq5NOlwqHyq+DGDt5XZx1RKvGJTn3ujHPEJVipoTkdX
/K+RpqQxJNGhyO8CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAjKgbr1hwRMUwEYLe
AAf0ODw0iRfch9QG6qYTOFjuC3KyDKdzf52OGm49Ep4gVmgMPLcA3YGtUXd8dJSf
WYZ0pSJYeLVJiEkkV/0gwpc+vK2OxZe1XBPbW3JN+wmRBxi3MiL7bbSvDlYIj7Dv
8c1vs8SxE4VuSkFRrcrVV0V95xs01X1/M9aa8z9Lf59ecKytaLvKysorDrCN8nC3
zlMDehPCLH9y4UlBqp8ClUpKk/5/P8HXr40ZGq+5TFrR80YABPSVX7krRMcxIhfu
IFIT2yhjkxMQWj8SCDUZxamBElAXY9KHSlEv3y+teRQABBVNxslHXqLKfKTF3q4S
tUVJuA==
-----END CERTIFICATE-----
"""

private let otherCACert = """
-----BEGIN CERTIFICATE-----
MIICrDCCAZQCCQDQxWAzi9Y9LTANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
b21lLW90aGVyLWNhMB4XDTIyMTExNDExMTkzM1oXDTIzMTExNDExMTkzM1owGDEW
MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
AQoCggEBANOr3vaYLkfnqk0lREo0VJD/rnUGQ6BiVtKiou0uksb9gX4oHdKlnqyi
dvFuwaJHIzjBhdWD2EqgWwuBTB3y/UybD/ZvkojnLD+QNMnbgG5aCnO03gVlVBOf
JggEtAEM31C7Fi6X7Gr/QwRI721+kqNSB48Rj3BT93cDW73aSeL6IZ8jlvefWYR7
1UI3bP+4WG58PSJOhUs2edaOn0G5wRZ5LyK6A77noll90cP+CVNlqLj8HRapqhf1
XZhGwwaEYxNV1oDroxq9mcM+6E8LdWCsdE3N4Dx6pdL0lOjwvhevZ2ct/fb31NYE
fMstojwKf9Of5/J4kZaC1mp44IwPS00CAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
iUuX1YYdVwqamg13eji1I9/8eMP5demBnXjM7DYP3JqDhClTYNnN8aB+o1YW51ce
3V1FtN/f3g3YMgYB4YSOb241G9uXGCz5CwcYeBCJbUT/PdNZOrTW1EzA+gAy8GxS
yMbK+ZrXy+7mJr79sumIO2WGk//eznvgrmlKq+eZtVf/TDTYs5TdbqI4sqoN+qPQ
WyuBXEkU2D259VvZ+GLljVr7JCysciALKDk3QAb6cfjhFh3aOqb40m5i4Jg6g2G6
iFS1kE3KjaWhYYn66BRVOYzfT25RkFBxxJh2Pg6DQOyVUWsWJ+VrstpQlcGMElmq
/LaIwNYfuUNcKb90L+M6vg==
-----END CERTIFICATE-----
"""

private let serverCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMjExMTQxMTE5MzNaFw0yMzExMTQxMTE5MzNaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANEQLRL2oOHPHN7K
ozmP8Ks8CcndChJrunNTJAWCiMA/HFEVVfylnQpPyc/t+W2yD+d+PsJknu2hI1O5
o53SBsEDm1taHaCJt9ur5NKpEphzOI7VuwkgcoGqmY0Hz7GmBmbG06Z6ne8EZfg5
a/rjxhW3GyOmIT3s9xWiU3MW7VX0PDlVmkZzVYtcSp9+AXQMDpvLK48INu1mUC6u
1nbEzj6KuFwpU5+V1cRLHer+I9HVA7qBcgsIDDEdUDG0/l0MivAyDbNHGHDZcsfj
jwTMsGRcd+IONItHyYb72+JBEKv3/qFAe4XIeR6iJQP4OxZ4CoxeUFgkVQwqBNd+
1JYDuvECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEASoyiLe/ak0nH5Bl7RvwAsO+Y
J2kA/oIUCpFEmsqDxK9Nt4eGIvknGzWsfTsVM4jXQo1MYCE7XrjpG9H6fubeQvxG
b+eU3VaHztflxLouzBIM6LnzoXnt2/rjQWIMbWZri2Gwl4incvVDLOv3jm5VD1Uw
OePLd+DvD/NzQ4nWdqCqhZAjopEPUpOT7fP8OkJVjGddvAn/0KyXkg3tutmUMB9m
8KctofAp1fKmd056Lgj+j6DIFDxxWEiihTO1ae8FlS4X/teeGSEVGv5M4baWRrcD
29V9XNIbMiwCNa7DJlPpxkjHdT4KifwPDHJ92RfK54SU1k0i8LD9KByuV4av9w==
-----END CERTIFICATE-----
"""

private let serverSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMjExMTQxMTE5MzNaFw0yMzExMTQxMTE5MzNaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBANEQLRL2
oOHPHN7KozmP8Ks8CcndChJrunNTJAWCiMA/HFEVVfylnQpPyc/t+W2yD+d+PsJk
nu2hI1O5o53SBsEDm1taHaCJt9ur5NKpEphzOI7VuwkgcoGqmY0Hz7GmBmbG06Z6
ne8EZfg5a/rjxhW3GyOmIT3s9xWiU3MW7VX0PDlVmkZzVYtcSp9+AXQMDpvLK48I
Nu1mUC6u1nbEzj6KuFwpU5+V1cRLHer+I9HVA7qBcgsIDDEdUDG0/l0MivAyDbNH
GHDZcsfjjwTMsGRcd+IONItHyYb72+JBEKv3/qFAe4XIeR6iJQP4OxZ4CoxeUFgk
VQwqBNd+1JYDuvECAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAZN5RQsfPP09YIfYo
UGu9m5+lpzYhE0S2+szysTg2IpWug0ZK4xhnqQYd9cGRks+U6hiLPdiyHCwOykf6
OplIp5fMxPWZipREb9nA33Ra1G9vpB/tZxQJxDTvUeCH88SQOszdZk79+zWyVkaF
+TCa3jDXb/vT20+wKxpPUjse5w2j0VOh21KaP82EMyOY/ZvhbMC60QyHnFDvJAEV
sle77vbdLjYELpYUpf9N+TxFDZ2B4dY/edprLZGt3LcUUFv/WB8FxZdWcjdZML2F
TMqicbP7H27+V1HF1rFUJWKzDNh4Wg6bY6lQNTZeHUyLwf/WlUraXTKYpqSH8FQ1
703RGQ==
-----END CERTIFICATE-----
"""

private let serverKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA0RAtEvag4c8c3sqjOY/wqzwJyd0KEmu6c1MkBYKIwD8cURVV
/KWdCk/Jz+35bbIP534+wmSe7aEjU7mjndIGwQObW1odoIm326vk0qkSmHM4jtW7
CSBygaqZjQfPsaYGZsbTpnqd7wRl+Dlr+uPGFbcbI6YhPez3FaJTcxbtVfQ8OVWa
RnNVi1xKn34BdAwOm8srjwg27WZQLq7WdsTOPoq4XClTn5XVxEsd6v4j0dUDuoFy
CwgMMR1QMbT+XQyK8DINs0cYcNlyx+OPBMywZFx34g40i0fJhvvb4kEQq/f+oUB7
hch5HqIlA/g7FngKjF5QWCRVDCoE137UlgO68QIDAQABAoIBAEumodjh2/e6PYU1
KHl0567e69/bF4Dw8Kg4pqlDwf5nF/UTVmk0+K25j5qpT3/tVin7mfQ3+vacP69V
VqqOTJldl8Mnyd7E1v4rpoLAYZU+5HFzT9oOnsDjHetVr0dmf5yDSCVO64WJPuji
xnskHxLOjoiI3jCNZh+y/KWB32IhdofSwBccw852JM2qC5l8vgE+sfjOeWXDiPRI
YLlVRlxZFv7N2kn+EDnPEQ8m2OGYKvNzU0d9nz05NdkRXzMh9zegTTL4EQhTaMf0
2AXy2ekKFVvWouV4y8QW1shz5Tun2y4ZQJnwiCyldED9sMxaziQxfdJ6N7f4+K5c
Sh4+Ct0CgYEA7bGvY02jQfHcDPOjZ/xkXb98lr1uLGTSvwK3zw+rI0+nrUJwH6fB
nSaXyWk059OqHTKPpa/d8DxFL2LP6vbvfTWCv9mnn61WWWDmP0Eo/k93XgWkmclb
vQGfXV2wtCTnhz+iUSSJA8f8jZhCtOD6xa8pLsaYrGD6oR5wzfs0nysCgYEA4SoC
/JWDMkw4mndI2vQ8GqDzBFtJCMr/dva7YGCGtbimDzxuOI68vW/y4X8Izg2i1hVz
iKRYCI9KzRdQrQ7masZF2d4DeaqPeA72JN4hoUOw0TZjP8yD4ECifUt786ZNvV1n
NlEhNb55zD73Cl6v0OJZkEfp1MC5ZQwLw7bMYFMCgYEAvNu5Z0WAuhzZotDSvQSl
GnfTHlJU/6D8chhOw47Hg77+k4N+Yyh/hcXsRHP7PVfIinpp+FPMG91He2cfnKmn
j+y8foMJ1K19NnbvesLjN20cgvAo4KhE4+AuJ5kRlZDdBXFiHubQltiHqlmYZu97
USbjqe7Rz+UePnZZWtCF9xECgYEAjGODZTVbjdrUWAsT0+EAMKI1o3u/N8pKKkSA
ZAELPPaaI1nMZ1sn9v179HkeZks+QjkxxfqiIQQm4WUuGhj2NZDWMJcql4tu1K6P
bkFJuqDX+Dnu+/JqL0Jdjb2o1SvVwMIh/k3rZPUUP/LqWP7cpGLc8QbFlq9raMNv
+mFZYJ0CgYEA5IQzp7SymcKgQqwcq5no2YOr76AykSCjOnLYYrotFqbxGJ19Cnol
Z74Habxjv89Kc7bfIwbz/AolkhAS2y0CYwSJL4wZIUb8W2mroSmaHhsk3A4DMPBB
wgSsdiBpixQqNDUAvnHc3FIyAGdpA73TJQrGY2F6QyQ9re3a/R8Dc3k=
-----END RSA PRIVATE KEY-----
"""

private let exampleServerCert = """
-----BEGIN CERTIFICATE-----
MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMjExMTQxMTE5MzRaFw0yMzExMTQxMTE5MzRaMBYxFDASBgNVBAMMC2V4YW1w
bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA5UPdc3MERjIj
rKNMcsCJEPJtzFZG7T99rDaENxl5hF5TdlCuMfKQMyf4rmUk2KdQXduWDmP/9keO
Btc3Hw9xm7mHn7UPbK0kHjlncqTCnjZzVQ2j0stg4Q0WjGeS0aB8k1AHPiBaOnvJ
LYcBJrA8mZK+inEE0gWEJsODTM+bKb3+5I69qVoHAkU2tXTDV9g1YKfP4H3rufEg
622AR1yAo8UxaGjY3amWps6XF/9R2iaSDAPLH1dCBw/YWrIH51n75S+n/H3Rz0+H
/aT9Eze0M2F2Nj1cU8fVcbDNR0smssgXVmE2mvQ+OvbO0H7VTS1HK2q2aPOPkRWh
yhFnOvPnbQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQAWk5KHkWVsbXqz6/MnwxD5
fn7JrBR77Vz3mxQO9NDKN/vczNMJf5cli6thrB5VPprl5LFXWwQ+LUQhP+XprigQ
8owU1gMNqDzxVHn7By2lnAehLcWYxDoGc8xgTuf2aEjFAyW9xB67YP/kDx9uNFwY
z+zWc6eMVr6dtKcsHcrIEoxLPBO9kuC/wlNY+73q04mmy9XQny15iQLy4sQT0wk4
xV4p86rqDZcGepdV2/bLk2coF9cUOPOGwUBqEIc7n5GekC2WTXSnjOEK5c+2Wkbw
Yt4jXnvsaQ8bwpchHfM1K3mLn+2rCEZ3F4E5Ug7DKebrwU4z/Nccf1DwM4pdI0EI
-----END CERTIFICATE-----
"""

private let exampleServerKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEA5UPdc3MERjIjrKNMcsCJEPJtzFZG7T99rDaENxl5hF5TdlCu
MfKQMyf4rmUk2KdQXduWDmP/9keOBtc3Hw9xm7mHn7UPbK0kHjlncqTCnjZzVQ2j
0stg4Q0WjGeS0aB8k1AHPiBaOnvJLYcBJrA8mZK+inEE0gWEJsODTM+bKb3+5I69
qVoHAkU2tXTDV9g1YKfP4H3rufEg622AR1yAo8UxaGjY3amWps6XF/9R2iaSDAPL
H1dCBw/YWrIH51n75S+n/H3Rz0+H/aT9Eze0M2F2Nj1cU8fVcbDNR0smssgXVmE2
mvQ+OvbO0H7VTS1HK2q2aPOPkRWhyhFnOvPnbQIDAQABAoIBAQDk0+vAQ1hMx9ab
hRHUpx8nbxDwFl0Mh4Zj0LX+WMrUt2EOglCbQcNzi73GMuWn6LdqNrV6/4yGv7ye
T0iRE9UM3Qzk9s7CZb3a/OinoJMvXqGWjtqolp3HgkyzLt13pXsxfXr9I0Vrggm2
Cz2248hYcAMGIu/wv9i66AGxNLVl3nzlo3K3J+6LwGYSrM5MMsN8p/RIc7RD30cg
Qer6uiGdYemD2hbOuqcqImzhMLvoYn683uLOoDhiFLmAPIU+VxtHs2pMpp4ebjrl
PpS8TtHnV85v/fhX6RE/jo5razdSU4LxW/p/fF5Zte+QR6FJgFFWaQvZd6/Vtuh6
K0Hadt1xAoGBAP1fuBjUElQgWBtoXb422X2/LurnyHfNSqSDM3z8OiCSN08r5GmM
ylWqh7k1sQWBzQ4OAsZcbwvrpvxMGYEd1K99LtUcM235WcKTomz7QRRUKG74tyFk
VdCgcMF+q2DdBE+hlF08bTNk1dM6uPlinNiMklydhLFjjhLlfDkiteGTAoGBAOek
LXqKMK4H5I1VQBgNKAv25tVItDabX5MPqhJVxmsvbNNTh/pfaNW7ietZNkec8FXs
UtS2Hv2hwNMVSb8l9bk96b2x9wiww2exI4oWKjKkJrSVsIcWc4BgeZ2xUtnV6QR5
XSNm7D4E11KhuHPbB01cAZeC0Cf/4rTZ5ERhULL/AoGAS/UpHJBfGkdEAptsFv0c
gH0TFKr9xySNLvqCMgLvbhpHaH2xEQ97DOl9nMGC2zLJhWAf5tWJGNrBibtKnhGS
VDXEF3FH3b018oYN2HwOS4jbQkFfrSwGKfAfPXK67+PySekXsEfQOOsOyy88is7M
VIL30boLMJ621eVkM0C7o+8CgYBLiiK6n24YksJZxL9OGJxCqpXEYB1E4Y5davJP
YGGAesrGb6scXxjU+n+TnFgzKl7F5ndsnqeklqdHLt4J09s6OZKMJgklcF+I5R9t
3KSONzHYGiijJRMtfkiqwDUAjN2cc+eHr/zCjNmbPNnmDjtnYuWx/xrasHvB9nyW
QBYNCQKBgQCDqdvchLcreSdbXKr6swvBz8XxzCaEParbm7iOvdLlv93svvCaHgI8
6E+FlXk68Qc2Dj8de/xEnl/OonNQRgIQh7czBJmYP8+TCPECm8fvv2TsddNvjTmF
TTx8wf9gixHffRtXZ4ILrP1sX7c4if3bfaMxKz+0ZyfzWZry8qZtVQ==
-----END RSA PRIVATE KEY-----
"""

private let clientCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMjExMTQxMTE5MzRaFw0yMzExMTQxMTE5MzRaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOMSDHjt5P3MOmtw
atYP0PnCfr2sxsMd1uxKeb+x5mpYuckcsnm1UR0LcBCizwBZ7yYAZQkFyK7vdJge
Hv9P3Rki6+6Jj/ngLdpOirtUcOfnfzbdlA2k6qJtY6G+ZKyczDICWaZHzNRycDkL
Yv4kzUT8PynIRIK/LPyXQa+tGty9+G2exVPdpzKpCgE8fKd8FeCOLW06Z0RsP0FS
ySPSJxdDq0BRbfurhplhawh7uJ+7IoVfdWV2wwDvLztCEXHn2iiNpyzIixYapnVB
PX1MXelsPRJaa9EKwOiqJB5ZcV9JWk9wa4W7mJrRfFTRh/9HRsoXIAaJPIqjTmqI
ffat/1cCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAWpPkMzjKLAnxbfyasR6cPk3t
ZanuBQ9RqVJw2gPem+SmSpvyPZ3CJTi0ZeUbPRSJ2W8YHyogaA5XShZSm8JJQKye
TNYqUewVbU18OwVco0l7Wc8R1iiZgYEUcvMF2f/EWEMoCTmS3JlpbLl7LmdTy7iQ
gIrR+iQ649nLw1T4Q5kp7zxjI6WJ3eZVNUjlTrUzKapSY4Tm2/+GafD+WNVRRACh
Y9VNkaQ6qYy4SaLw6+bX2YdbDhIi275vAONHIZcAsMt6/aLJzKgfTxRqqmEvmJdQ
KSVRRaSKZ/qe9UBdl4oFn1wupFAoNDQWkXT/Q3kVhxVXZ8ZE+ylZnuWcj3CHvQ==
-----END CERTIFICATE-----
"""

private let clientSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMjExMTQxMTE5MzRaFw0yMzExMTQxMTE5MzRaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOMSDHjt
5P3MOmtwatYP0PnCfr2sxsMd1uxKeb+x5mpYuckcsnm1UR0LcBCizwBZ7yYAZQkF
yK7vdJgeHv9P3Rki6+6Jj/ngLdpOirtUcOfnfzbdlA2k6qJtY6G+ZKyczDICWaZH
zNRycDkLYv4kzUT8PynIRIK/LPyXQa+tGty9+G2exVPdpzKpCgE8fKd8FeCOLW06
Z0RsP0FSySPSJxdDq0BRbfurhplhawh7uJ+7IoVfdWV2wwDvLztCEXHn2iiNpyzI
ixYapnVBPX1MXelsPRJaa9EKwOiqJB5ZcV9JWk9wa4W7mJrRfFTRh/9HRsoXIAaJ
PIqjTmqIffat/1cCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAIqGPpw/m3oIb+Ok7
eZCEph/IcEwvkJXAFYeYjQHDsK1EW/HNoyjKKU3CaLJuWtvNbW+8GpmiVdAcO0XS
RN+xwDOLmB+9Ob70tZRsR/4/695WkkCm/70Y89YqTq3ev86vZmPWBGZsdXB/rvfs
sJbEkNeDRAquEbVQ3K8qmG7w8oC+VdzdQfQHY6hdkzsb0Q99aPASwGjxPVDz12Tb
v9g9f9yVwI+vxxabHr4nvKJ/GfuHRzG2eSW2TNBY/Kxp10+lCdMfbPq2p0LsV4eZ
eHPCFqiBe6CK80Pdpy7CNCPBBvGkGb7nfxBi4/tNVDgMlOQy6pA3PLjib8NLMCIA
5iUEvw==
-----END CERTIFICATE-----
"""

private let clientKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEA4xIMeO3k/cw6a3Bq1g/Q+cJ+vazGwx3W7Ep5v7Hmali5yRyy
ebVRHQtwEKLPAFnvJgBlCQXIru90mB4e/0/dGSLr7omP+eAt2k6Ku1Rw5+d/Nt2U
DaTqom1job5krJzMMgJZpkfM1HJwOQti/iTNRPw/KchEgr8s/JdBr60a3L34bZ7F
U92nMqkKATx8p3wV4I4tbTpnRGw/QVLJI9InF0OrQFFt+6uGmWFrCHu4n7sihV91
ZXbDAO8vO0IRcefaKI2nLMiLFhqmdUE9fUxd6Ww9Elpr0QrA6KokHllxX0laT3Br
hbuYmtF8VNGH/0dGyhcgBok8iqNOaoh99q3/VwIDAQABAoIBAQC5gA4mYJoY6FW1
XcI5m/QphcWKaHJ8BY2FvZXWj5vftxoXfNUk7oYURzrGrGqVK+Nd1Sa1Bz+aAc7r
UngaNQE3vrqlRUYUaRqsZEubm/Ec0pavmLaRqu9vwBOLmAGgrft2w0q/t5pS2CZr
w6ycWC5FNBjZplypv0oeE+c6gB0YxKJ2mjKEYHWOop+uBPql2G6TfCeu4mMekZPH
cHbMuMlBPN23HT7BmGCvk1YSaGbMt0iCTM0zThfe53AtLSVKn33szHm/XjLYJYGM
7N+SttwM+O88diFShWHUHmWsy5Lv0Mrkw3NRz37yQ8Uh1fJ0TMeLZEIzKSLrI8lv
XrBVE89ZAoGBAP8bBSytb6Aof6p1noIx8nu31d5/5mvRSUxoF1Lu/B/EeaNTGXxD
HvJEi4Lh/txm6/3IeC5gfJ0jExxoWyTD3wLqVvmf+FEMntXqnATC832uw3vkxZpd
E/MldDHE4UkWGBUvii7JN1fisyyZKLUu517crebJthpwk5Sf/1FgK1SbAoGBAOPd
3VTQ7uaD2zPn4QM9KZsFJ+7cS7l1qtupplj9e12T7r53tQLoFjcery2Ja7ZrF3aq
y07D2ww8y8v1ShxqTgSOdeqPCX1a4OS7Z93zsy58Jv3ZcXbfbSGiLbpoueQJbUZ0
vKlDIf4uHn78fz8WIbe87UwKneKnaRrO64DtHQX1AoGBAIH11vYCySozV46UaxLy
tRB3//lg+RcWQJwvLyqt2z2nzzv4OrSGUT6k0tnzne3UdQcN2MPvnaxD0RmYxE3/
hx4qGfMDnvJTVput8JuwYXE21hnI2y4fmuk0vHQaU5bzLYOle2UIVyxrrlHbGNTs
tywpimJXgnEHxvdhZyWis5BfAoGBAN45P2M6J+KzcRGb8DuiaHMAgkNWoJsMAEcd
mldrTeajINCsGeHtycyTpi/4tw0+P7HBO2ljZLr4h6AvZcl0ewXCkYjhWlXgTTeE
9PTmeDa7aaNjbl6J4vpMGeCTxcZ40xNFQcCo8fvbqm4ZfVdfFB8Gpz3jlLq4na5B
YjdoB0gJAoGAZCK3JbIN56KnmyENuZ6szWTZwkCMZq3kPVKBK8LAITVLVxg7Emjs
GyTU+JhMx9Hk2tU/tftM/dTZ2TRRMwmPbZNadtkQdDgsXDhfkrW9JmVewx4ECCcI
gBfWFOoABVTmVM9oNc74FeWu3nDjqGix5ZJ8+Zjjr8wUEcrU2TPZKn4=
-----END RSA PRIVATE KEY-----
"""

private let serverExplicitCurveCert = """
-----BEGIN CERTIFICATE-----
MIICEDCCAbYCCQDCeNe2vM7d6DAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
cGxlLmNvbTAeFw0yMjExMTQxMTE5MzRaFw0yMzExMTQxMTE5MzRaMBYxFDASBgNV
BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABDmd
3Pzv6HbsUTmNd7RljKbkYP+36ljl6qVZKZ+8m3Exq4DvtIzLKho/4NluAhWCsRev
2pWTfEiqiYS/U40TnfQwCgYIKoZIzj0EAwIDSAAwRQIhAI+BpDBjiqZD7r5vhPrG
TT9Kq9s4ekIc1/a4AoTioT8CAiAluJHscXt+vBcqEI9sH0wudusCdPJyLbvNtMZd
wdduCw==
-----END CERTIFICATE-----
"""

private let serverExplicitCurveKey = """
-----BEGIN EC PRIVATE KEY-----
MIIBaAIBAQQgBLTFlKchn4c+dQphsqJ2hWVpLPeRQ0opnSwvRsH+63iggfowgfcC
AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
YyVRAgEBoUQDQgAEOZ3c/O/oduxROY13tGWMpuRg/7fqWOXqpVkpn7ybcTGrgO+0
jMsqGj/g2W4CFYKxF6/alZN8SKqJhL9TjROd9A==
-----END EC PRIVATE KEY-----
"""

#endif // canImport(NIOSSL)
