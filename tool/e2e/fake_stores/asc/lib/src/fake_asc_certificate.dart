/// An Apple Distribution certificate for tests, made with openssl for them
/// (self-signed, no key kept), DER as base64: subject "Apple Distribution:
/// XPath Test (TEAM123456)", serial `0A1B2C3D4E5F`, valid until 2126.
library;

/// The certificate.
const fakeDistributionCertificate =
    'MIIDjjCCAnagAwIBAgIGChssPU5fMA0GCSqGSIb3DQEBCwUAMG0xNDAyBgNVBAMMK0FwcGxl'
    'IERpc3RyaWJ1dGlvbjogWFBhdGggVGVzdCAoVEVBTTEyMzQ1NikxEzARBgNVBAsMClRFQU0x'
    'MjM0NTYxEzARBgNVBAoMClhQYXRoIFRlc3QxCzAJBgNVBAYTAlVTMCAXDTI2MTAyNTE0MjE1'
    'N1oYDzIxMjYxMDAxMTQyMTU3WjBtMTQwMgYDVQQDDCtBcHBsZSBEaXN0cmlidXRpb246IFhQ'
    'YXRoIFRlc3QgKFRFQU0xMjM0NTYpMRMwEQYDVQQLDApURUFNMTIzNDU2MRMwEQYDVQQKDApY'
    'UGF0aCBUZXN0MQswCQYDVQQGEwJVUzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEB'
    'AI6tszsz9hjabHHa4jCXUQz2gi1CnWM7kBFvnROHwo/sfwggXFIDwRaimGm05BqWfGqGKcuh'
    'dyIz8xeZhRRtvwZRw6NjO+l6pp+JUncx+J3BTiolFuCcpbCwUnf73QRigIJ21IuL0Lc30Ec9'
    'fSZr+1L1KQndCsfXEU3NrmPdTCcoGW99TO0oI+R4cSran4so39KyIw/cd45Uvvy2zQr77Z4x'
    'uQPyCEcsrSMqlhgvBNDgpIcZdzjwAltAi4ihnxF6Neksy2+2NIiWw8Sih7I191tjlznPawBX'
    'YUhYOp1XViL+2e4ry4y3R7lkpZ+l+te/OTCiJpbcO1zxhLLEzvFW74MCAwEAAaMyMDAwHQYD'
    'VR0OBBYEFMWntj0kh0c4A/J1Ui6EskpaVv4yMA8GA1UdEwEB/wQFMAMBAf8wDQYJKoZIhvcN'
    'AQELBQADggEBAEewGP0emVIoQTDng4y5+bTzwV+exOmmBOzbscudwMjBQlQkySQ5dgC3xyD5'
    'MB7sUOSuEWtKnhWlFHLw4afkn7KIzmJRUjqD+wxorvIPZJEyqsRgnxv9qo0VeA/zU5etr/aB'
    'EGAEhWJcllUwVob9J2JW+/YPhR3Snc23eqw1jQu+77L0KvegSE1WJgdOkakNh6sFO4RTZ5QX'
    'cy8ZMhwMqEKWnVH5mOA1DxjkbkI5PG7CU800eWuNOW9GK8eYaBJJ/4x7zoO3LYVJi8nY7jMT'
    '0bWfEb2sW9CXYwEajS9gZf3fWK3gtkur6CGawEbyykK9LEbpQwyb3080Lw+XXP5MZQg=';

/// Its serial number as App Store Connect lists it.
const fakeDistributionSerial = '0A1B2C3D4E5F';
