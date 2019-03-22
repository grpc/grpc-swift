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
import Foundation
import NIOSSL

/// Wraps `NIOSSLCertificate` to provide the certificate common name and expiry date.
public struct SampleCertificate {
  public var certificate: NIOSSLCertificate
  public var commonName: String
  public var notAfter: Date

  public static let ca = SampleCertificate(
    certificate: try! NIOSSLCertificate(buffer: Array(caCert.utf8CString), format: .pem),
    commonName: "foo",
    notAfter: Date(timeIntervalSince1970: 1584530912.0))

  public static let server = SampleCertificate(
    certificate: try! NIOSSLCertificate(buffer: Array(serverCert.utf8CString), format: .pem),
    commonName: "example.com",
    // 18/03/2020 11:28:33
    notAfter: Date(timeIntervalSince1970: 1584530913.0))

  public static let client = SampleCertificate(
      certificate: try! NIOSSLCertificate(buffer: Array(clientCert.utf8CString), format: .pem),
      commonName: "localhost",
      // 18/03/2020 11:28:35
      notAfter: Date(timeIntervalSince1970: 1584530915.0))
}

extension SampleCertificate {
  /// Returns whether the certificate has expired.
  public var isExpired: Bool {
    return notAfter < Date()
  }
}

/// Provides convenience methods to make `NIOSSLPrivateKey`s for corresponding `GRPCSwiftCertificate`s.
public struct SamplePrivateKey {
  private init() { }

  public static let server = try! NIOSSLPrivateKey(buffer: Array(serverKey.utf8CString), format: .pem)
  public static let client = try! NIOSSLPrivateKey(buffer: Array(clientKey.utf8CString), format: .pem)
}

// MARK: - Certificates and private keys

// NOTE: use the "makecerts" script in the scripts directory to generate new
// certificates and private keys when these expire.

private let caCert = """
    -----BEGIN CERTIFICATE-----
    MIICmDCCAYACCQDGbQdNHHqGqDANBgkqhkiG9w0BAQsFADAOMQwwCgYDVQQDDANm
    b28wHhcNMTkwMzE5MTEyODMyWhcNMjAwMzE4MTEyODMyWjAOMQwwCgYDVQQDDANm
    b28wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDZejSltOdp41GdU58N
    pzwpz6NBKGBQ3Hvh+Gj5p0th6PbZxKXNynaca0eSXsDOifRX0AWpLPhmxgMlQ0Yj
    4npYVbef3E+yCOX1agGP228YrTwGChPvsCSiYLrx9iBLlxYosIyM2A2RnhrTxR8W
    0Zf3ANJVvKBKrLIFzStqf6317oBLdAH3txxWYVycdQWTlp3Fe+2seOyQbmi9CqPp
    dmDqMrbNBqpDm54VsGDBAyUo7Jwntyno7qbSpmFVHlTORdvmu94UccJrspH3AHzB
    yfQ6EC5xXpbXrJtFzwQJ+Uh3MXPeIvvEP9qOL3iuuHJajOpaFRD822Br7L913/Jq
    OqEhAgMBAAEwDQYJKoZIhvcNAQELBQADggEBAEAK72aJaU4mBjHV5zY6QpYTQ1Gc
    L5BC1WZTKKb1swp4sLL7KQEFewr7U/52T6i9rmep2qXVbQftFNgA2e1Gis7ws9Gj
    FfnvZVzXl3OBcba4siJSpjyyCZ+g6cd/FHdRWI4wyn0XhwN6VMCXEvOzmMVRgGWW
    RL2suwQhhsgMjKpdYs3XihUxaFxU/Uhd5bCPhFMg5WvUVZ8koMmkN/VT5geJPnZW
    xcZdNHCKpWQwPnfUEGgfFHVkvaJvf9gkkzZizEXXt7WyHiZ7lak5iI1O2pEjlpLW
    4+t1wS6/qBAYL+bmT6rn74cvF1P+tlTjRiFn3VR0ofdQbhTllgPwWkdGeko=
    -----END CERTIFICATE-----
    """

private let serverCert = """
    -----BEGIN CERTIFICATE-----
    MIICmDCCAYACAQEwDQYJKoZIhvcNAQEFBQAwDjEMMAoGA1UEAwwDZm9vMB4XDTE5
    MDMxOTExMjgzM1oXDTIwMDMxODExMjgzM1owFjEUMBIGA1UEAwwLZXhhbXBsZS5j
    b20wggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDS5ph7oNIX0Zc2IgeY
    6IXfV8Ecqct1ACcRBDzjofehKJoWK9z0DnK+H14yUKsai6n4y9l7k41TM13vv0q8
    ExkmDdO902uqi9h1f8ifE4K5UWMTUqoSh+ZhhEH5W8cr5wdpnfImziTCXbSKcZ6/
    /4MGY4YO9/MxCNebcvAoPjqfaem+xU0cuoJaKVF61HNh2tQ5QtMQRarnPJZiXDpm
    aIwXVEra8/2EDVqljoQbK9cHe9koB6FjlmWvidnjF8zYOiP9unVu0665/IaQSWOH
    wEDe44HuC/eLWeJ16Y368CNAHaLpMhIwKWNHSmWlGyVgYFaWCmuHsSGNLkWgaSNn
    O3z/AgMBAAEwDQYJKoZIhvcNAQEFBQADggEBAGpAZgAfjjwnyufM05ruCS532q//
    +Pv1FjcwebD1rRssM0uFZLYqcL59BdZ2CyQ7RgyGElTH9kZMW5ishWWTjnkqUG6S
    WL9sR23UGO1kIIHt/Q2PElo5e94/zrOHj/j44YeU+6nKlqES+eecvzZ8em1Del9I
    kXeQEq8/bcjt2vk1VzCGNxaYYerAafBaZQ6xRjl8eAPBrPgFdbXpZ1ohcEXTfds+
    wG2zhQbH37DdSZ4M/Kx/1iMgOZ25cOlMTk355HXaBEJDq4LOlUwMn0AZvskxHU7E
    yKY0Idsg519jJvW3ZgCZ6FMkher809H1TgpdK3zF3o96PxN2NjZhwSKXmO8=
    -----END CERTIFICATE-----
    """

private let serverKey = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEpQIBAAKCAQEA0uaYe6DSF9GXNiIHmOiF31fBHKnLdQAnEQQ846H3oSiaFivc
    9A5yvh9eMlCrGoup+MvZe5ONUzNd779KvBMZJg3TvdNrqovYdX/InxOCuVFjE1Kq
    EofmYYRB+VvHK+cHaZ3yJs4kwl20inGev/+DBmOGDvfzMQjXm3LwKD46n2npvsVN
    HLqCWilRetRzYdrUOULTEEWq5zyWYlw6ZmiMF1RK2vP9hA1apY6EGyvXB3vZKAeh
    Y5Zlr4nZ4xfM2Doj/bp1btOuufyGkEljh8BA3uOB7gv3i1nidemN+vAjQB2i6TIS
    MCljR0plpRslYGBWlgprh7EhjS5FoGkjZzt8/wIDAQABAoIBAHmKzWvKFeoGLvfS
    isBTmPtK7o7fR9LI4LrMz258ZGKrLIoEg1Tfkr8BAt9KYCFvReiNSmwOcA739nX5
    r09OTlsA8vteAZmK+JdWqj8LFnZIcimrpToCugGPIBpeCx3BCiOTE//LI6IkMKzs
    qAmMbm1bI+IygSPMLb13cvIuUsiVTH8oALd3bNM/unMIsTOXPaRwUEvskLMDoGZT
    z9J0ox7V+ziVXpB8qXMUEn1sB1USpdNcu47seKI8utOFCQ0v0KEW9xaV4wo3nT8W
    uXJifI3pSesq3MddSA7iE+2wO/ngBN+14rbmg9Rivu2Zk5jVP5T0h1ENvhkXmcli
    lvjycykCgYEA6HR1CP7t8h6pwPArgIRyPT7oCkUQwN0oae59ZVJH74uZhanTm2p4
    2Qz+Xp8Ee4I3A2JDyYNouzwVC9JOTSXjfvrxMaajGoMdacmNJ2UZ4/6Xww2gvikp
    MHPUwg6nKSQcu8Bo+/nhxHHBxfdSIEgvzUzXvirUQHLpbLX9Z8WM4zUCgYEA6EM9
    m2MoaSVIa6TBJQwwCDwHBCr3xaMoo/obsruCE231r0ZPh8DAlZRSwPoNa2oWzJvI
    6DFaIEMem60HXWzifY54jPQ70crMRehSGcNdUq+hbZPh9J5mMQxEiR7Ck9B7ijNE
    F4PONQeNQEMPvZ4CdNCaK1lfKLoy7wvOkyLJkeMCgYEAoB2Hd/jRQZMpboKAFHgm
    kFVCU8Ca953edokVyrLQZgoMZ2tBHK5MK4WtuNNjrQdWiXgoJSfk/gM2o/vqf213
    tEF53a9gbaSen/16wwX6vXbiZjJ+5D1J59wBUuHw9n+vYwv3xIisoDmTNZ9T7HSM
    qKcjfBPYO8RrULxSniYPE3kCgYEA4se0waIB9RhYK/KEPB44T/H8j888ehcjOWid
    3thC26HD/83RHaXQ5LwcSRxeOgEuHb4GXuDBNTsUCcDarhgA1cNkZYybU+6FocSD
    VXByEKg4IHwCZgy7jyyBRrloF1e7KGeCFsu1bgXfn11bYzODBngf8C+lQGj+DnYi
    z3tqAS0CgYEA0D6XZjezamgu7A9/zfidkvq154vIuYP7x3KmY1nBmkBZ9RsvcXZo
    wXwr1e0BNYx8ARwgsK/IJveIRcfrLIAM0gKbEi/WDRNUplobaPQJU5D9t3ptaO3s
    qHBR2ObzN2h8n6/IqXcUd57QWERQJAXmKn90erryBgnfP0f2bDBDOB8=
    -----END RSA PRIVATE KEY-----
    """

private let clientCert = """
    -----BEGIN CERTIFICATE-----
    MIICljCCAX4CAQEwDQYJKoZIhvcNAQEFBQAwDjEMMAoGA1UEAwwDZm9vMB4XDTE5
    MDMxOTExMjgzNVoXDTIwMDMxODExMjgzNVowFDESMBAGA1UEAwwJbG9jYWxob3N0
    MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAxoGJAQPCdIQlzMJ7aUMW
    dMPK8/MGGmtDmh4CNmS7eGuF4STxn10ca/yd+GqlXJbV38u3+4DiCKnv8oX7keKZ
    eovVJsNLs+7Lc+YPNlIrzYSAed6bzTaIyrOQVed7UCMt9cVxgw7rVcRgCQYNbuxe
    ZDTEfFNqqZ7G2g6X1AszCc+pmrwWPBBAOeJIPXkVrMEVWD9BczvptxA21N5bzGqs
    oM1v7qdTNMMsXXz2fFoUdiYgaw1aGCuPjyfPBHGFJ6arQkvwy/AxYj7TToHFNUgo
    RXD7uRonl2DFHyfLI5E1Fmi9GtYUAvc9Zsle94yjEpa5wQtunboqviMvNz6cbTCH
    dQIDAQABMA0GCSqGSIb3DQEBBQUAA4IBAQClCN5SJRmaQsPKlnVLlFAGuM400lsc
    DjkxZ+w5H3EmntnWVXOCAwh0/GWbk6FLLa8NdXikWX8/TOnUCGrETSEHp/oCA3Jw
    7rb0QDwLFdGCpAaxs5lRzppTro6rVOANW22h+whJ1E0YmeBYdy9ptAq4m4DCu7LX
    POATR+KgO2rXCWC4RPt0ZkP0r4S/gMwuW/ciDAcnC5GdyOvLjmAlxmoDZqa6CUmC
    V6r7twDyBlQ7fdsNmXe9YEdO34T6OWxl3gLSwmAG/EYiejTwpQvbJKZFAKghmF3s
    dfpLlHaroeBFmniRiZokRkGT6gkUUNBXCFbZB0Nh1D0onGJS5bhGFVm0
    -----END CERTIFICATE-----
    """

private let clientKey = """
    -----BEGIN RSA PRIVATE KEY-----
    MIIEogIBAAKCAQEAxoGJAQPCdIQlzMJ7aUMWdMPK8/MGGmtDmh4CNmS7eGuF4STx
    n10ca/yd+GqlXJbV38u3+4DiCKnv8oX7keKZeovVJsNLs+7Lc+YPNlIrzYSAed6b
    zTaIyrOQVed7UCMt9cVxgw7rVcRgCQYNbuxeZDTEfFNqqZ7G2g6X1AszCc+pmrwW
    PBBAOeJIPXkVrMEVWD9BczvptxA21N5bzGqsoM1v7qdTNMMsXXz2fFoUdiYgaw1a
    GCuPjyfPBHGFJ6arQkvwy/AxYj7TToHFNUgoRXD7uRonl2DFHyfLI5E1Fmi9GtYU
    Avc9Zsle94yjEpa5wQtunboqviMvNz6cbTCHdQIDAQABAoIBAA61Wmlw1d+8SvC5
    GFvcVLWiLE+XGkSq3f91acSOAjYSAYGFM0ITrB90QGA/xrDtnDtQ5PkFu7nYnabi
    tplAqQ6jfc+5eMqETx7vVQE5ZXV88+gTzoeOGuSqGW/EDycI9EbZsmd7m4RnYJZK
    lIQ7j2LtZgGwTJ703NcbbbSQf9+iGeXl0Bc7RPFzXdFVS30Kj3Gj2t3YIeuHfUz1
    Xo2YozIbhdosW38ryAbxYeBfYaF6wH00XYclyFYEe1krX4jfwwTUHF2xP2vymV8H
    GoKIuERWM6jYW3TXmyrCHrWPMyA3uwTChat47DUuVanAdJaA+B7MowZ9IQJy0hJn
    J95jQqECgYEA+J4d+NGZQpN7qTUKknmhROCJkyiQyn2XbE0ymBRXZwVqPCB43Axo
    UD7IorF73geFKJdcFjnZlmnNkFFrablTqk6rMa88vUeeawyWggwXfFzDxECFUR7n
    e9iPlv3ygtaQaApWzRLvIz76XN0UgogCEu2sYZ1B5ETunt+qr3kZ5vsCgYEAzGZ9
    vxm77+fBVdK0sKAJpaZZgKdLZeKEjmhSK0/yVX0W3k/2fvwcD9nirRwy4MWy/9en
    a7/HquwprA4wPqI8cijQV0R4j6pV5kYcho3RNY2o/9nLBCq2BGgONx23iw7FmtZt
    A5Bek7fpbaTmtlDuImjXJvw+hcH3LBzj8AkCwE8CgYAOLDVZMdmiyfWKt9NadkST
    QJmXIgDfCjnPmrb/pGk3Hj/oHZHGOY7YxDt7ytJc3eDhZ3+AZNvajz2AtKOC62Wx
    l7p6opq7z5FgWN9bmoTcOg2O6n6vGSvpC3dkDCX+/2xMAgrgteub/sMW+CNrLYWw
    vovNJMHU2Xkg5W89gZHQcQKBgC30BOVH1dbT1cWDv5fOAx04zvp7ohnf2Uli7sZK
    DQNnQhLtC0/1QiHWLH4azt111Q5r33n7/dnRinTiI7qRIuHPhzd3b1ttQi6pKJSf
    oZ9Wn94Viuz+5TkMY9XEWpVq1sY+2vdoJ7syJ8q8vhnTDBa0V1qubygHOZizThOT
    EwlFAoGALyfmW00GB4LPX73QJ+i+TzBloRpS+Epk3UAaUChzCytlCzZpEO2YiDrz
    /rJWYC4iq81UtI/iqrSMNg1K3LRCJdnfv47q2g7d4OZntUyI2dUVzGSfO6K+u5Ip
    mHNAjWkgR2RjHoHNxKHFN8evEc2aypUSKnHqxrnzwCCVvLNLk90=
    -----END RSA PRIVATE KEY-----
    """
