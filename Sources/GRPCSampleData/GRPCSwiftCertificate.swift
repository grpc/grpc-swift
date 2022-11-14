
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
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let otherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(otherCACert.utf8), format: .pem),
    commonName: "some-other-ca",
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let exampleServer = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(exampleServerCert.utf8), format: .pem),
    commonName: "example.com",
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let serverSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let client = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let clientSignedByOtherCA = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(clientSignedByOtherCACert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699957385)
  )

  public static let exampleServerWithExplicitCurve = SampleCertificate(
    certificate: try! NIOSSLCertificate(bytes: .init(serverExplicitCurveCert.utf8), format: .pem),
    commonName: "localhost",
    notAfter: Date(timeIntervalSince1970: 1699957385)
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
MIICoDCCAYgCCQCm0QTHp5PSRzANBgkqhkiG9w0BAQsFADASMRAwDgYDVQQDDAdz
b21lLWNhMB4XDTIyMTExNDEwMjMwNVoXDTIzMTExNDEwMjMwNVowEjEQMA4GA1UE
AwwHc29tZS1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJnu6KyB
YYsnf8bPfwZcv3V0j6vwZqqIaoPAob18HtuJbiQMKWL8/AT7MbUunXZz8uxv+SRq
IsEcBqRu6SoaqdzsgnyAh5iW7B4GQEWwZBmxVr9nwtS+OWlrPmYl68vttK0E6A/S
mcsS/32Ie/cjrV8nFRTiCIBIpJAzK69p83MllJwI74FLkdFvoVfhvHpv9t980iXl
Ysj91o9nR2EWAwiC9jgkRVYLyxgjht4yAQ+UDSG+Y9bXzHHt+q6qM3heCK5CD64G
6PSF4vhv7L53RyH8m+Yk+9ujywVgpyZ9XLV06hhUi31tRPzDppLlgeUzX5B9uWef
7TxYBF+fyFjuGGsCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAfhlNLKe6qyPMTVFm
pAlRk+IUEjQcaFJigAYN8PziJQH2PhQxsYeTbTnZblXcrbQbsFg02hCeveDJm3Pu
50yKAtxAAwqUXuUilA4jh/yNJRPk64wlR0HNE3yUWF5UhFEEx+TkC4AMySiPrFhM
7oPVMk14ZAUDg5LSeLvB9ZcKlhCtXSjRPUMkuyGJSl/CAwXRz+8YS00EXnbondrT
Jhc4H/WepvbyrFDNMkuBm9QV5c45EPG1HEYIaUSTgR2nTWidkihwTagzzpZzS5FP
/j8k1ZKP9nw7OGJWXXkQI/xChcecga+PVuaI5WI5x3EpHhKPng0ODmVPwXr6wqHP
y6pJRw==
-----END CERTIFICATE-----
"""

private let otherCACert = """
-----BEGIN CERTIFICATE-----
MIICrDCCAZQCCQDl+1l5PUEwpTANBgkqhkiG9w0BAQsFADAYMRYwFAYDVQQDDA1z
b21lLW90aGVyLWNhMB4XDTIyMTExNDEwMjMwNVoXDTIzMTExNDEwMjMwNVowGDEW
MBQGA1UEAwwNc29tZS1vdGhlci1jYTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
AQoCggEBANIfhOssXQtX0nEhek1Lv1UI0wa1FP0EtaX4CwjAkhl3EN9gkEfJjk5p
bdWb6Q+UsZ+Axb5AA88Mnt9E5efJ9cFBzHx8dvRt45dfroy4go2OJK10lGugm7uV
S0Se5L9hH/wLW0qBmesqbEkbdHioX1sIctxwNkzL7aq75Vyy1pqu3xpNLCGuHr3Q
LqwDSs4SjWeDzO8z77LI89OwdFYr45d0GfIcfrTEv2+HN9LWD5sVlXgKVp3DypQQ
rCJ9ffjkjHbP2HCjS40eEHqrFcue5EJygU+WC8zSNJXHS7ZlzuKIClwNd/H/M+0a
UXThkvmdWSiMmnF483TIebmzEh1Z1VkCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEA
ICMHiiJzA/1Pguyfnw0jkzaGKWecBdiAbc/i7C3+kHxvDpc4RmoAg1u9827yvTqP
8nXIyLwPI1zHp89GgcXs7TnelBQgH61v05p6gQ6RfLcISx4/j/S6tbfRLU/F/2c4
5OzRwdk/LkGM8tWescott4dD3JZKcqucmGTDk8mdMtQENfzgc8YTMZ4igSaWCRv+
oEMpHJJTdUpZASB0L7+uS0VIOTevEqQS31eq5vgHzMPk2kT6uWjzM8XnYb83pcAH
PAnS4k9+dS+VEVNOWZnqn3gVNmybp6PINnQ0hm3kPPL/U2S/CY2QZNDkSaz3OUgg
iZjudreDSTZjI9KHi11Mrg==
-----END CERTIFICATE-----
"""

private let serverCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMjExMTQxMDIzMDVaFw0yMzExMTQxMDIzMDVaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ8L4Tv/wflnfCmG
ObB0HYdiUoQ5XsL1BoYXXq/q1AKFxypGoMyFrvFydMeWVkhRpAamHxhfua043rDn
GXYDMV/nNU8uVuKgiH5wkCUbV8viCEHGwwABbF9ArGnnNjDF+P/viAEs7m8X6n9+
QchIZbwGx12e4P3WLaRyNeGgHmexUzEoSv4FlVBI9eZUkG01bTJak74eRsqMVKXH
rDDOQrNncV7v+AIqakk08YcUEoEC226um9zpyqT+20Qso4hnrall3iwZ+fOU1PIM
/dBpV/bwwAOQnvone2BNjiQuL/sX4NwilNlR+lPnqAwRtTjQsJWYsu462JxuVd+k
ft98hEMCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAdEV+UYZ+7m87yngH7ng/L0ms
9JvEvsbCJi+Bqw8WjwvDTh0sfdlKEs6HrZCAq1Hhv2KJyfrZWn8f6r0Nfd9ROj1r
htBgvYoVlAyInCfLuWOTJruz0LtEZU4BgfFqyXayrKx537w4Ns8GkI4LoSSSht44
Tvg1k/9CMSEC9HU3YLnkWQN3qTbrRM89owrrIixl3wD2HirHiQB2t53oiNOP6UVb
xA3Ubb0NfkAIAkvKJbNkcTr1g3ey6IlDYAbsZKu+aqY31AJbiOpQer0fOCkTSVNK
/nIY52ydWCK4zsdnkGVZ2YBynMcyd1pdUf1gwjysFhlhOAtih9wJ8bMFmgSDeg==
-----END CERTIFICATE-----
"""

private let serverSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMjExMTQxMDIzMDVaFw0yMzExMTQxMDIzMDVaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAJ8L4Tv/
wflnfCmGObB0HYdiUoQ5XsL1BoYXXq/q1AKFxypGoMyFrvFydMeWVkhRpAamHxhf
ua043rDnGXYDMV/nNU8uVuKgiH5wkCUbV8viCEHGwwABbF9ArGnnNjDF+P/viAEs
7m8X6n9+QchIZbwGx12e4P3WLaRyNeGgHmexUzEoSv4FlVBI9eZUkG01bTJak74e
RsqMVKXHrDDOQrNncV7v+AIqakk08YcUEoEC226um9zpyqT+20Qso4hnrall3iwZ
+fOU1PIM/dBpV/bwwAOQnvone2BNjiQuL/sX4NwilNlR+lPnqAwRtTjQsJWYsu46
2JxuVd+kft98hEMCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAYClq3EzjLRDlOs4C
nx3OL7xKoZ3dU03O1G6bFeSs+V9zBAhjVWG1HW7BOz8O9iF6msv/1lOQaG1zJptr
Lrqv3+JU0Tr4Fa0aI5n0xqAzcFJF9rPIjd9JKqqOX4nhyiqk6bCsvqubumwWA/cP
qfL1DFFrkdBkymUSzoZ1mS6CY8za5begjnyRQNyoN6DV8xKunP7YbUB3DskDNouO
hJ5iz+OVro3fr7/m+RUkH3vGeuQ/JJeYBlXjgsuAzWkS8A12mukNrQUaFyyZ8xPD
06mW/2aklP2ml1Ko0QgYcck8ayADO8iGgmHB8f5Ex2nypG8RsOs2oXEkL5Jm2TVE
7RPOSA==
-----END CERTIFICATE-----
"""

private let serverKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAnwvhO//B+Wd8KYY5sHQdh2JShDlewvUGhhder+rUAoXHKkag
zIWu8XJ0x5ZWSFGkBqYfGF+5rTjesOcZdgMxX+c1Ty5W4qCIfnCQJRtXy+IIQcbD
AAFsX0Csaec2MMX4/++IASzubxfqf35ByEhlvAbHXZ7g/dYtpHI14aAeZ7FTMShK
/gWVUEj15lSQbTVtMlqTvh5GyoxUpcesMM5Cs2dxXu/4AipqSTTxhxQSgQLbbq6b
3OnKpP7bRCyjiGetqWXeLBn585TU8gz90GlX9vDAA5Ce+id7YE2OJC4v+xfg3CKU
2VH6U+eoDBG1ONCwlZiy7jrYnG5V36R+33yEQwIDAQABAoIBAD9NFyQuMyH00jIk
vilAzc/ojjcaLmEh7KrJ+mHB8Qff/tkQq0c7ndlzWI9ngofeFo6e55ln4BrVm6yF
DlkuBCTLfSg6pVIl2q2YV4atT1BScj7bwRjreBqhPv4XjDX1VZln2JW/MFb/CdIc
ikoQpo0jlY3pglsFN71Px6o5dGCITpQpJL6euiJMIPmhHS4D33dlGkzpE4y8e4xA
PCiwOT4FmeEpORrDmVyoNAz4KlgcUFtPrXFL2WLMzODZmHJXNpLcRdEoz8TuwXGk
s24V0i1PbNPXosoGY3XEtHRqtsBBtNWVRE8oCMGZ462CBtDXhJfi+ClpqB9aB8ye
FfoE4wECgYEAzNlY9r1RXcC3kL2g0hiY2exT/0H37DJVohGHB2Ly71Iu8x8HHFRv
XEZxRJYtr6LegVliosJK/SNxogrnozJv/XJMRVTNGQjHelDpTRbVnJViqskrMapj
d8aVpCQP5fhpKbdjHJobE8vwscv+IBhyt1kSdyBpM96gO/WLBduiEWECgYEAxsKs
GyKPJnk/UHPwVHX4bIiF1kztx2Y8+d0yEzoqSx0UnM3p72Lb85Z53S1k4arse8Uh
zYSuovbBAfjIss1knqWLH7d5x8Zst6CRmgGubLeNl0HPthRHURgCUzNHhJfbiX5k
X4Kn7K20aEzRjDncmufjjIOko5fSWXJiT0hypCMCgYANcMVRiyJnkFl6+bYvksWU
ptjsCpwFt1e/Bn9hkLB322CROxvwU+nqmASeh2v/9iO7QO4j17Or4EN4albAcnK+
ol02v1WlqtnLwLtN/42MdJDAu+pFm/Riy3jOCD+yyxW7UvkBy2qzZdIpGEVYPcJp
HUME5e+BI75HsNiqTbrYgQKBgA9T5+3Xxm5TH1zW9AuvZU8JYDjcieG8sqsaMchl
zeko/vPwtT+uwgOQ8SjrXUJB6ibJVwgAWW9b1BqQ0vlm+YF6hrYVciDD3pJyoYfc
5VSg+xxVCO2jtrQ8Q8GizLse8uExjBAJhWWtJ6J7ehV0SNzxUQz/Ae1Twfb/6TDw
B1c9AoGBAMCGYSeN+bQ8g6754YC2rmM6Lm+OXVYP52+HQiYDJZtV0aqBOUKej4Xh
mRrfi998SsZURtyYY5EbguKicoOSz1QjD2eRDlaTgkSnmCYORsm8pOlDmRCOtRr1
2IsCYn/iMOmIezM8ZwMG2KyNS4v//VCMATNc4lURiEqyALbSAUxc
-----END RSA PRIVATE KEY-----
"""

private let exampleServerCert = """
-----BEGIN CERTIFICATE-----
MIICnDCCAYQCAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMjExMTQxMDIzMDZaFw0yMzExMTQxMDIzMDZaMBYxFDASBgNVBAMMC2V4YW1w
bGUuY29tMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAvsCLe+n5BaEI
aPlFyQ2XvtbIwwpqRSUACIMWHIIksQjiQO7S6nE/okrfe3YrLpiFJPNbRmdKEwee
IEkSWBr1EShUNJrFtvxO0/upgMw6Z+vTsbjzrDe5gRdmbSbpUoajB7Kk+TNufSXj
eYsL7vds9MLU0ojrv8baXT/fmrz1HoakHwL8qoodSzl1WQYbViJezki2Lb5a8b96
pXV+/GBTYFUYcQf50JF6Z9wLtJnh1XdBUhEQ7Yp6cfP3da5o9prI9DKT+6eaRptQ
15XMW53j4AfxczmOG8GseUR87w90MEs+LzkcPxbD2KbPzQrhv9xYiKC6pRes2o70
tc2GnVmKkQIDAQABMA0GCSqGSIb3DQEBCwUAA4IBAQBl/lSg3EJwSBFHgRDuUgex
0EeUnUXo4H54zDH+96U0czS/PzdVF3gcYwMG7ctEBl7aPlZDz+T1VBxcIG8VRkRF
HibXlLql0C+aGgTYuRrwFbqHgJUdx7umiidMTSpu7mU3dZd14+lX6SrUZqd6sM2h
0NHgn2MrTihCEshyqhYOEmC9hDft7CL1GPSC7HpEjAbGmnq4OsGQhlbbDhqeoXyN
x/A5G4PiagMJFYrv4zf3yEpw/58rAn/eQaUR31CYzVGP/2r/KSDAvsgEjP2ONeFt
DVkvflfTX8jL+27jYvlX6lTPaErusBTgwGSdw7FPo6NlPrD4KyqYoYZ5PPEuhtM+
-----END CERTIFICATE-----
"""

private let exampleServerKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEowIBAAKCAQEAvsCLe+n5BaEIaPlFyQ2XvtbIwwpqRSUACIMWHIIksQjiQO7S
6nE/okrfe3YrLpiFJPNbRmdKEweeIEkSWBr1EShUNJrFtvxO0/upgMw6Z+vTsbjz
rDe5gRdmbSbpUoajB7Kk+TNufSXjeYsL7vds9MLU0ojrv8baXT/fmrz1HoakHwL8
qoodSzl1WQYbViJezki2Lb5a8b96pXV+/GBTYFUYcQf50JF6Z9wLtJnh1XdBUhEQ
7Yp6cfP3da5o9prI9DKT+6eaRptQ15XMW53j4AfxczmOG8GseUR87w90MEs+Lzkc
PxbD2KbPzQrhv9xYiKC6pRes2o70tc2GnVmKkQIDAQABAoIBAHSHY66bTIlnyp92
SG9+YkkvJQ4herIq3E5W5lccGhYcezt3qlmWPW2Dl+rwUYjxm8Tq9cOYrePaL3tB
qHcyYKvOm0JXmpkioXVWtEH+gV+i7XwQpKt8j1KRXP0pXDgSD95QAABMrx682q4R
h4TAmkscCq9i/cH2VMfKkWsSLBwszh9BhBnSDD/YJvm9gfkz+oQPUcYr/d0hTBsa
lw3weZMf5RVIb2p8Q362/mybcqte+BpJwAQajwB7jyeWxUpZyKWJ5tsycoRmIkY5
8ACnvZvEstz0avITxUuk5nx4yoFWb/tnwz+Zc2371UmbmQD6CZeItSCiHpis50kv
hUp6GAECgYEA5+QNihglJQBKMFck1BxN4a0k1ntu7ZhGAIokU/49F2Uy5MOv0spT
HpqDw+jyLSt7oNAd18GfmjTnMQWc7vnfqzmqbqUdsPIgCWQZMVed9FWla0l9PzNH
btIS1uze8R3myG6qghFDIQi73cZd8AxqTK/+r46PnC84RfBx8iqYJKECgYEA0pWO
BLKH65645oONXKrrQQyDau2WHydMP7zK+jA+9n2rSwwFR083fcZfOuhDhnrB4KWK
mUcqhGXNoL4keX59JkaTN9lHp/ZuS2M+dvyVhV+oE55lk8vqjalhKCk5fv3Sj3iI
rVCORwUfYgS53pDSBS+oIFwHava3mBiralX1r/ECgYEA5R7Nye6FdQPOSekwuGun
AB7F0S5wsk3MjOfxcRQ5ZI5XNPWtGgdTDV/6ZW4bK0pVgtVfRzlG62TuMd+r6ev2
dgYqQdzfc2ApC15eDgTWSv78zP71w6Z1JCho+PdeaLr0toGx84X+3/rzNPO1CWQa
+97BNNEVUGrPnTswOuifH0ECgYBCmALqX172VyJX22A33uE4l/FzPiEMRwwo19ZE
mj8/CezCddGxhE6jGrmA0nSQMX/gP9l9sXCzn9IQNDEqrqJ7GTRzI+YyKo8kjgTx
8dyC6gYn9h5fR8wr8lWEMs046KHOtypZzLDBqtAK2j3BMYEJHNIJMbEy1USn9501
qmtgsQKBgEz4BRA8rcTZxsywfwRpAZMHbQqzyd6u5Mp0VJldATkK6KlC3P2I85qt
HkmBLbc2F0ZqdKXy0Qqpk6w7ndw48IVOz45XWYVEoQVgnly3qF1WmQAn8uimmO9l
m8GRIVdZv6EmJeI7RZ8b0HjbtbQKK1cr2JFwFwDZgip+PWAFVGLf
-----END RSA PRIVATE KEY-----
"""

private let clientCert = """
-----BEGIN CERTIFICATE-----
MIICmjCCAYICAQEwDQYJKoZIhvcNAQELBQAwEjEQMA4GA1UEAwwHc29tZS1jYTAe
Fw0yMjExMTQxMDIzMDZaFw0yMzExMTQxMDIzMDZaMBQxEjAQBgNVBAMMCWxvY2Fs
aG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMBuAuLSonagjpzN
QL60STtQf4fDmcHDqa4Tnm0jZebaI69muAv5XhVZeOq+V0+qeZreRzcV+GsQgrR+
CtnzfRNbYRb7e2i33ZFr1cxX8Vnc4XYpVKD/KnQ8xlMuGQHM8Gj6BqwvYVbh3RiV
BQ7dLatksF6N4pEwGTRsKjZ5jVKsP5b3UIe3OpsSMlGdJQmY6LU+xda2apxzIt82
1+SBHFxximjKwEhe3SQkSqXrNfwUejgxGIhmw26JsBcJj/OITMT9U1RKrzjd+3gI
H2Tb5RnR4neRyoANo+7kOIGVIzViNr5of5DFQyCBUbQ3JuSOkNYgd7NhihCdEuRu
w8SsI7cCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAIN2pdbW+bRU1cN0RdiBydIhB
wIYHtbVjetdqiUrNb6Xh/LEC7cPFaYGKGGuNM9vA9fo5gL3YO4OjUs4jHCX8Hkyf
HLPDP7AXpOSQnYvRm2bcrt0jyu19uunGWXrdVhi9ZHw2sPgMrbPuqKXXx4c5fN2b
Ug7J2EtR1zEpBba+fIh0bHN+3YsBFnH/XVXpicBkf2vdSSfsf46Ei63YZaqsX1PR
OXmlHNBAAQ07wIlh243/zkKB/iZQ1of5ZLnbyqU0DOXEKMRyLXBxujx1hhSrM6dT
/rgv+QPeEbJaliE/t/bzRLTCbsfgg3JPCzyjzW635cfbVmdbAVL7fPT4GuCZXw==
-----END CERTIFICATE-----
"""

private let clientSignedByOtherCACert = """
-----BEGIN CERTIFICATE-----
MIICoDCCAYgCAQEwDQYJKoZIhvcNAQELBQAwGDEWMBQGA1UEAwwNc29tZS1vdGhl
ci1jYTAeFw0yMjExMTQxMDIzMDZaFw0yMzExMTQxMDIzMDZaMBQxEjAQBgNVBAMM
CWxvY2FsaG9zdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAMBuAuLS
onagjpzNQL60STtQf4fDmcHDqa4Tnm0jZebaI69muAv5XhVZeOq+V0+qeZreRzcV
+GsQgrR+CtnzfRNbYRb7e2i33ZFr1cxX8Vnc4XYpVKD/KnQ8xlMuGQHM8Gj6Bqwv
YVbh3RiVBQ7dLatksF6N4pEwGTRsKjZ5jVKsP5b3UIe3OpsSMlGdJQmY6LU+xda2
apxzIt821+SBHFxximjKwEhe3SQkSqXrNfwUejgxGIhmw26JsBcJj/OITMT9U1RK
rzjd+3gIH2Tb5RnR4neRyoANo+7kOIGVIzViNr5of5DFQyCBUbQ3JuSOkNYgd7Nh
ihCdEuRuw8SsI7cCAwEAATANBgkqhkiG9w0BAQsFAAOCAQEAZcXslo3m0F2m3YkG
0mLDdj57GPRpYZF+FrMjxWgEn5pfbF+hu2jRoZEbV+H9PUW+PdSAFrCuMp+uxiCZ
dLiHwHnEoO2ClSR2N7JU+l1eLXnbDGlWwugTgT74kLhkeHuzqj/2pNVxB/533UXw
Drzmoqmod5Y/VbblteHh39WOhbtb22nCApMiyAlJBH2HaJwms/w5c/ahaMLMekfg
womA7XI0PSuuITGMh8d5Q5aEzf+3cJSNTeZzPfrU0jUSoHsw4CV7WYAix5Z9pMqV
RCCtHbdVfrSjN7eFVHhKXRSiv0m33JR5Mo9imWbiEuxSYm4E8nAmyllkOr5MLaVX
BxCksQ==
-----END CERTIFICATE-----
"""

private let clientKey = """
-----BEGIN RSA PRIVATE KEY-----
MIIEpQIBAAKCAQEAwG4C4tKidqCOnM1AvrRJO1B/h8OZwcOprhOebSNl5tojr2a4
C/leFVl46r5XT6p5mt5HNxX4axCCtH4K2fN9E1thFvt7aLfdkWvVzFfxWdzhdilU
oP8qdDzGUy4ZAczwaPoGrC9hVuHdGJUFDt0tq2SwXo3ikTAZNGwqNnmNUqw/lvdQ
h7c6mxIyUZ0lCZjotT7F1rZqnHMi3zbX5IEcXHGKaMrASF7dJCRKpes1/BR6ODEY
iGbDbomwFwmP84hMxP1TVEqvON37eAgfZNvlGdHid5HKgA2j7uQ4gZUjNWI2vmh/
kMVDIIFRtDcm5I6Q1iB3s2GKEJ0S5G7DxKwjtwIDAQABAoIBAGkWKwFP4mVCPV+o
P6llr3By/5JW4YsNnYZxNF2JrUaq7j4FrJDtd9HU8NHRbMEW6h4HMYEFwIpHk/mZ
s7de33lIt/bjE3wWnSujZjiX9jgLBh2PaKYbc0XTQsN+My3mi4vorugtX80gv6uD
BiYd56jn7eFVPtvnFnyobU0eiG0SrKq/eXXjAKjGfbB/acEknGbRNP1huvlwlZqq
QPz+M/46Ex4xqya0pwalZ8G6WBa61b3sKY6bqhHZoO9C9W3AYiEuWmQLZjTIzh02
xY3H3PwDk1zfbTRQnZtk72GNgqDcXdpxw49Q/gyLOWgvC6YnuAqBhYdBeGKk3YgL
8whyaUECgYEA8sFzmQuxPlsvqS3ML23m7hIcJIWregWGP76lEId4L4eQG5524RkJ
NBH/z5sTVID03PWHn83rJY4saniZVl1k+uU+ha5Kuj30hu6dv/Fzl5x7eqby18Lz
Jo+M8OFgKB8k/K7CVhejJOsbIvV/P64SkFI5RuGHotTqBoCcLrKrjRECgYEAyu2p
VtNbL59wReHCUqmgV+oQytd7dzY8iKKJmTCqGZ6auXp0FBz7WcPm1akig8kRiL2b
CngYh+C1t+LgokyFtw+mzSxq3IfJdhiQ6CbgUmINdyISXaWWE7Xt5g7BO3lbJi9L
w7Hk7EGqEDiOeaMY+gwnR6Vhy59YAX8twkmnxEcCgYEAgfc+O27+GsNZFftV+QKf
A1CgzpDeCHsSr+gSmXHdz5yFc7P4M3Vi7wS/71c4FyLfdbjiPpVRUo72ip48gfeI
i6bWPV3d1i47T05LGKtdVotJtJXTJ97QrRFnxML05yYdeEbb9pm7F5Xjtmi3EtHQ
UIIk9iTiqDPTg12xwHKZ0/ECgYEAsCQ21szC28VzONVLTWE7ctQTG16LJuEHDjq3
YScinvZSqyilVUgKzNIErfUPpoCDHcQmraGs+VSNpz3haj8t2cZWLMWfRCkBL+cG
8Nu93wSJV51Vf7/ZUuaZxxWLmMov2ic3hngFkyU0LrxIv0BYz8J43fGpv4tiYno4
B+rTGsUCgYEAk88TcUWZLSQHp9x0tB3buysax7fKCQrL5F5i3oNpJK4s4sI9j0Dp
bi9fJsZMl9mNmnpQTkr8yVzZt9cs589WoytpdOoHn1hP5OFIB+IqEnmSOK9GeMAi
QUNP5wic1UNgUF+cwTe7ShK+qGr9rJp+Y1KBduvv9Ngve76ydNr+dTo=
-----END RSA PRIVATE KEY-----
"""

private let serverExplicitCurveCert = """
-----BEGIN CERTIFICATE-----
MIICETCCAbYCCQDXq3r/J2UZKjAKBggqhkjOPQQDAjAWMRQwEgYDVQQDDAtleGFt
cGxlLmNvbTAeFw0yMjExMTQxMDIzMDZaFw0yMzExMTQxMDIzMDZaMBYxFDASBgNV
BAMMC2V4YW1wbGUuY29tMIIBSzCCAQMGByqGSM49AgEwgfcCAQEwLAYHKoZIzj0B
AQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////MFsEIP////8AAAAB
AAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57PrvVV2mIa8ZR0GsMxT
sPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEEaxfR8uEsQkf4vObl
Y6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54WK84zV2sxXs7LtkBo
N79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8YyVRAgEBA0IABKNy
aiBhSbtBW/+yJgEkgdyKJVtnx7ZAzq23frRMHgpS4tpwj6SXZoMfkfIbexLHq0dL
bEAV2JZwqXdH4IG7DCYwCgYIKoZIzj0EAwIDSQAwRgIhAP64oZ1RSywZBCxXWU33
iTl/v2r9RWIsl7o7+ILiyXehAiEA3eGGETVa7bC0eMzLtUkTtUEQLT951d8zkE8L
4Nr4ySA=
-----END CERTIFICATE-----
"""

private let serverExplicitCurveKey = """
-----BEGIN EC PRIVATE KEY-----
MIIBaAIBAQQgejGCxnO7XyFLSyRfS1zqqDs610j0RBtRNN6CY/7t4R6ggfowgfcC
AQEwLAYHKoZIzj0BAQIhAP////8AAAABAAAAAAAAAAAAAAAA////////////////
MFsEIP////8AAAABAAAAAAAAAAAAAAAA///////////////8BCBaxjXYqjqT57Pr
vVV2mIa8ZR0GsMxTsPY7zjw+J9JgSwMVAMSdNgiG5wSTamZ44ROdJreBn36QBEEE
axfR8uEsQkf4vOblY6RA8ncDfYEt6zOg9KE5RdiYwpZP40Li/hp/m47n60p8D54W
K84zV2sxXs7LtkBoN79R9QIhAP////8AAAAA//////////+85vqtpxeehPO5ysL8
YyVRAgEBoUQDQgAEo3JqIGFJu0Fb/7ImASSB3IolW2fHtkDOrbd+tEweClLi2nCP
pJdmgx+R8ht7EserR0tsQBXYlnCpd0fggbsMJg==
-----END EC PRIVATE KEY-----
"""

#endif // canImport(NIOSSL)
