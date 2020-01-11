# APIacAuthMTLS

** WIP - do not use in prod env **

An `APIac.Authenticator` plug implementing **section 2** of
[OAuth 2.0 Mutual-TLS Client Authentication and Certificate-Bound Access Tokens](https://tools.ietf.org/html/draft-ietf-oauth-mtls-17)

Using this scheme, authentication is performed thanks to 2 elements:
- TLS client certificate authentication
- the `client_id` parameter of the `application/x-www-form-urlencoded` body

TLS client certificate authentication may be performed thanks to two methods:
- authentication with
a certificate issued by a Certificate Authority (CA) which is called [PKI
Mutual TLS OAuth Client Authentication Method](https://tools.ietf.org/html/draft-ietf-oauth-mtls-12#section-2.1).
In this case, the certificate **Distinguished Name** (DN) is checked against
the DN registered for the `client_id`
- authentication with a self-signed, self-issued certificate which is called [Self-Signed Certificate
Mutual TLS OAuth Client Authentication Method](https://tools.ietf.org/html/draft-ietf-oauth-mtls-12#section-2.2).
In this case, the certificate is checked against the **subject public key info**
of the registered certificates of the `client_id`

## Installation

```elixir
def deps do
  [
    {:apiac_auth_mtls, github: "tanguilp/apiac_auth_mtls", tag: "0.2.0"}
  ]
end
```

## Plug options

- `:allowed_methods`: one of `:pki`, `:selfsigned` or `:both`. No default value,
mandatory option
- `:pki_callback`: a
`(String.t -> String.t | {tls_client_auth_subject_value(), String.t()} | nil)`
function that takes the `client_id` as a parameter and returns its DN as a `String.t()` or
`{tls_client_auth_subject_value(), String.t()}` or `nil` if no DN is registered for
that client. When no `t:tls_client_auth_subject_value/0` is specified, defaults to
`:tls_client_auth_subject_dn`
- `:selfsigned_callback`: a `(String.t -> binary() | [binary()] | nil)`
function that takes the `client_id` as a parameter and returns the certificate
or the list of the certificate for `the client_id`, or `nil` if no certificate
is registered for that client. Certificates can be returned in DER-encoded format, or
native OTP certificate structure
- `:cert_data_origin`: origin of the peer cert data. Can be set to:
  - `:native`: the peer certificate data is retrieved from the connection. Only works when
  this plug is used at the TLS termination endpoint. This is the *default value*
  - `{:header_param, "Header-Name"}`: the peer certificate data, and more specifically the
  parameter upon which the decision is to be made, is retrieved from an HTTP header. When
  using this feature, **make sure** that this header is filtered by a n upstream system
  (reverse-proxy...) so that malicious users cannot inject the value themselves. For instance,
  the configuration could be set to: `{:header_param, "SSL_CLIENT_DN"}`. If there are several
  values for the parameter (for instance several `dNSName`), they must be sent in
  separate headers. Not compatible with self-signed certiticate authentication
  - `{:header_cert, "Header-Name"}`: the whole certificate us forwarded in the "Header-Name"
  and retrieved by this plug. The certificate must be a PEM-encoded value
- `:set_error_response`: function called when authentication failed. Defaults to
`APIacAuthBasic.send_error_response/3`
- `:error_response_verbosity`: one of `:debug`, `:normal` or `:minimal`.
Defaults to `:normal`

## Example

```elixir
plug APIacAuthMTLS, allowed_methods: :both,
                      selfsigned_callback: &selfsigned_certs/1,
                      pki_callback: &get_dn/1

# further

defp selfsigned_certs(client_id) do
  :ets.lookup_element(:clients, :client_id, 5)
end

defp get_dn("client-1") do
  "/C=US/ST=ARI/L=Chicago/O=Agora/CN=API access certificate"
end

defp get_dn(_), do: nil
```

## Configuring TLS for client authentication

See the module's information for further information, examples, and the security considerations.
