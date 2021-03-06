defmodule APIacAuthMTLSTest do
  # as we are using the registry for testing, we have to disable async
  # so as to avoir race conditions
  use ExUnit.Case, async: false
  doctest APIacAuthMTLS

  defmodule PKICert do
    use TestPlug, allowed_methods: :pki, pki_callback: &TestHelperFunctions.test_dn/1
  end

  defmodule PKIDNSCert do
    use TestPlug, allowed_methods: :pki, pki_callback: &TestHelperFunctions.test_dns/1
  end

  defmodule PKIHeaderCertPEM do
    use TestPlug,
      allowed_methods: :pki,
      pki_callback: &TestHelperFunctions.test_dn/1,
      cert_data_origin: {:header_cert_pem, "X-SSL-CERT"}
  end

  defmodule PKIHeaderCertDER do
    use TestPlug,
      allowed_methods: :pki,
      pki_callback: &TestHelperFunctions.test_dn/1,
      cert_data_origin: :header_cert
  end

  defmodule PKIHeaderCertPEMWithDNS do
    use TestPlug,
      allowed_methods: :pki,
      pki_callback: &TestHelperFunctions.test_dns/1,
      cert_data_origin: {:header_cert_pem, "X-SSL-CERT"}
  end

  defmodule PKIHeaderValue do
    use TestPlug,
      allowed_methods: :pki,
      pki_callback: &TestHelperFunctions.test_dn/1,
      cert_data_origin: {:header_param, "ssl_client_i_dn"}
  end

  defmodule SelfSignedCert do
    use TestPlug,
      allowed_methods: :selfsigned,
      selfsigned_callback: &TestHelperFunctions.cert_from_ets/1
  end

  setup_all do
    :ets.new(:mtls_test, [:set, :public, :named_table])
    :inets.start()

    :ok
  end

  setup do
    ref = make_ref()

    on_exit(fn ->
      Plug.Cowboy.shutdown(ref)
    end)

    [ref: ref]
  end

  test "valid pki certificate with DN validation", context do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_root_cert =
      X509.Certificate.self_signed(
        peer_root_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test root CA peer certificate",
        template: :root_ca
      )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test peer certificate",
        peer_root_cert,
        peer_root_private_key
      )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKICert, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      cacerts: [X509.Certificate.to_der(peer_root_cert)],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
      verify: :verify_peer
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {'https://localhost:8443', [], 'application/x-www-form-urlencoded',
         'client_id=testclient'},
        [
          ssl: [
            cacerts: [X509.Certificate.to_der(server_ca_cert)],
            cert: X509.Certificate.to_der(peer_cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
          ]
        ],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "valid pki certificate with DNS name validation", context do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_root_cert =
      X509.Certificate.self_signed(
        peer_root_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test root CA peer certificate",
        template: :root_ca
      )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    extension = X509.Certificate.Extension.subject_alt_name(
      ["www.example.com", "www.example.org", "www.example.br"]
    )

    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test peer certificate",
        peer_root_cert,
        peer_root_private_key,
        extensions: [subject_alt_name: extension]
      )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKIDNSCert, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      cacerts: [X509.Certificate.to_der(peer_root_cert)],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
      verify: :verify_peer
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {'https://localhost:8443', [], 'application/x-www-form-urlencoded',
         'client_id=testclient'},
        [
          ssl: [
            cacerts: [X509.Certificate.to_der(server_ca_cert)],
            cert: X509.Certificate.to_der(peer_cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
          ]
        ],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "valid pki certificate, cert in header", context do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_root_cert =
      X509.Certificate.self_signed(
        peer_root_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test root CA peer certificate",
        template: :root_ca
      )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test peer certificate",
        peer_root_cert,
        peer_root_private_key
      )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKIHeaderCertPEM, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      cacerts: [X509.Certificate.to_der(peer_root_cert)],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {
          'https://localhost:8443',
          [{'X-SSL-CERT', peer_cert |> X509.Certificate.to_pem() |> String.to_charlist()}],
          'application/x-www-form-urlencoded',
          'client_id=testclient'
        },
        [ssl: [cacerts: [X509.Certificate.to_der(server_ca_cert)]]],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "valid pki certificate, cert in header (DER format)", context do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_root_cert =
      X509.Certificate.self_signed(
        peer_root_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test root CA peer certificate",
        template: :root_ca
      )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test peer certificate",
        peer_root_cert,
        peer_root_private_key
      )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKIHeaderCertDER, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      cacerts: [X509.Certificate.to_der(peer_root_cert)],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {
          'https://localhost:8443',
          [
            {'Client-Cert',
              peer_cert |> X509.Certificate.to_der() |> Base.encode64() |> String.to_charlist()
            }
          ],
          'application/x-www-form-urlencoded',
          'client_id=testclient'
        },
        [ssl: [cacerts: [X509.Certificate.to_der(server_ca_cert)]]],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "valid pki certificate, param in header", context do
    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKIHeaderValue, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {
          'https://localhost:8443',
          [
            {'ssl_client_i_dn',
              TestHelperFunctions.test_dn("app_client_id") |> String.to_charlist()
            }
          ],
          'application/x-www-form-urlencoded',
          'client_id=testclient'
        },
        [ssl: [cacerts: [X509.Certificate.to_der(server_ca_cert)]]],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "valid pki certificate, cert in header and DNS SAN check", context do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_root_cert =
      X509.Certificate.self_signed(
        peer_root_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test root CA peer certificate",
        template: :root_ca
      )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    extension = X509.Certificate.Extension.subject_alt_name(
      ["www.example.com", "www.example.org", "www.example.br"]
    )

    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test peer certificate",
        peer_root_cert,
        peer_root_private_key,
        extensions: [subject_alt_name: extension]
      )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKIHeaderCertPEMWithDNS, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {
          'https://localhost:8443',
          [{'X-SSL-CERT', peer_cert |> X509.Certificate.to_pem() |> String.to_charlist()}],
          'application/x-www-form-urlencoded',
          'client_id=testclient'
        },
        [ssl: [cacerts: [X509.Certificate.to_der(server_ca_cert)]]],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "invalid pki certificate", context do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_root_cert =
      X509.Certificate.self_signed(
        peer_root_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test root CA peer certificate",
        template: :root_ca
      )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=invalid DN",
        peer_root_cert,
        peer_root_private_key
      )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca
      )

    Plug.Cowboy.https(PKICert, [],
      port: 8443,
      ref: context[:ref],
      cert: X509.Certificate.to_der(server_ca_cert),
      cacerts: [X509.Certificate.to_der(peer_root_cert)],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
      verify: :verify_peer
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {'https://localhost:8443', [], 'application/x-www-form-urlencoded',
         'client_id=testclient'},
        [
          ssl: [
            cacerts: [X509.Certificate.to_der(server_ca_cert)],
            cert: X509.Certificate.to_der(peer_cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
          ]
        ],
        []
      )

    assert elem(status, 1) == 401
    assert body == []
  end

  test "valid self-signed certificate (DER-encoded)", context do
    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      X509.Certificate.self_signed(
        peer_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test self-signed CA peer certificate",
        template: :server
      )

    :ets.insert(:mtls_test, {:cert, X509.Certificate.to_der(peer_cert)})

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca,
        extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name(["localhost"])]
      )

    Plug.Cowboy.https(SelfSignedCert, [],
      port: 8443,
      ref: context[:ref],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
      cert: X509.Certificate.to_der(server_ca_cert),
      verify: :verify_peer,
      verify_fun: {&verify_fun_selfsigned_cert/3, []}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {'https://localhost:8443', [], 'application/x-www-form-urlencoded',
         'client_id=testclient'},
        [
          ssl: [
            cacerts: [X509.Certificate.to_der(server_ca_cert)],
            cert: X509.Certificate.to_der(peer_cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
          ]
        ],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "valid self-signed certificate (OTP certificate struct)", context do
    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      X509.Certificate.self_signed(
        peer_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test self-signed CA peer certificate",
        template: :server
      )

    :ets.insert(:mtls_test, {:cert, peer_cert})

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca,
        extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name(["localhost"])]
      )

    Plug.Cowboy.https(SelfSignedCert, [],
      port: 8443,
      ref: context[:ref],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
      cert: X509.Certificate.to_der(server_ca_cert),
      verify: :verify_peer,
      verify_fun: {&verify_fun_selfsigned_cert/3, []}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {'https://localhost:8443', [], 'application/x-www-form-urlencoded',
         'client_id=testclient'},
        [
          ssl: [
            cacerts: [X509.Certificate.to_der(server_ca_cert)],
            cert: X509.Certificate.to_der(peer_cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
          ]
        ],
        []
      )

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apiac_client"] == "testclient"
    assert Poison.decode!(body)["apiac_authenticator"] == "Elixir.APIacAuthMTLS"
  end

  test "invalid self-signed certificate", context do
    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    peer_cert =
      X509.Certificate.self_signed(
        peer_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test self-signed CA peer certificate",
        template: :server
      )

    invalid_peer_private_key = X509.PrivateKey.new_ec(:secp256r1)

    invalid_peer_cert =
      X509.Certificate.self_signed(
        invalid_peer_private_key,
        "/C=BZ/ST=MBH/L=Lorient/O=APIacAuthBearer/CN=test self-signed CA peer certificate",
        template: :server
      )

    :ets.insert(:mtls_test, {:cert, X509.Certificate.to_der(invalid_peer_cert)})

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)

    server_ca_cert =
      X509.Certificate.self_signed(
        server_ca_private_key,
        "/C=RU/ST=SPB/L=SPB/O=APIacAuthBearer/CN=test server certificate",
        template: :root_ca,
        extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name(["localhost"])]
      )

    Plug.Cowboy.https(SelfSignedCert, [],
      port: 8443,
      ref: context[:ref],
      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
      cert: X509.Certificate.to_der(server_ca_cert),
      verify: :verify_peer,
      verify_fun: {&verify_fun_selfsigned_cert/3, []}
    )

    {:ok, {status, _headers, body}} =
      :httpc.request(
        :post,
        {'https://localhost:8443', [], 'application/x-www-form-urlencoded',
         'client_id=testclient'},
        [
          ssl: [
            cacerts: [X509.Certificate.to_der(server_ca_cert)],
            cert: X509.Certificate.to_der(peer_cert),
            key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
          ]
        ],
        []
      )

    assert elem(status, 1) == 401
    assert body == []
  end

  # FIXME should we make it an exported function in main lib?
  defp verify_fun_selfsigned_cert(_, {:bad_cert, :selfsigned_peer}, user_state),
    do: {:valid, user_state}

  defp verify_fun_selfsigned_cert(_, {:bad_cert, _} = reason, _),
    do: {:fail, reason}

  defp verify_fun_selfsigned_cert(_, {:extension, _}, user_state),
    do: {:unkown, user_state}

  defp verify_fun_selfsigned_cert(_, :valid, user_state),
    do: {:valid, user_state}

  defp verify_fun_selfsigned_cert(_, :valid_peer, user_state),
    do: {:valid, user_state}
end
