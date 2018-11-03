defmodule APISexAuthMTLSTest do
  # as we are using the registry for testing, we have to disable async
  # so as to avoir race conditions
  use ExUnit.Case, async: false
  doctest APISexAuthMTLS

  defmodule PKICert do
    use TestPlug, [allowed_methods: :pki, pki_callback: &TestHelperFunctions.test_dn/1]
  end

  defmodule SelfSignedCert do
    use TestPlug, [allowed_methods: :pki, pki_callback: &TestHelperFunctions.cert_from_ets/1]
  end

  setup_all do
    :ets.new(:mtls_test, [:set, :public, :named_table])
    :inets.start()

    :ok
  end

  test "valid pki certificate" do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)
    peer_root_cert = X509.Certificate.self_signed(peer_root_private_key,
      "/C=BZ/ST=MBH/L=Lorient/O=APISexAuthBearer/CN=test root CA peer certificate",
      template: :root_ca
    )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)
    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
         "/C=BZ/ST=MBH/L=Lorient/O=APISexAuthBearer/CN=test peer certificate",
         peer_root_cert, peer_root_private_key
         #extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name(["localhost"])]
         )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)
    server_ca_cert = X509.Certificate.self_signed(server_ca_private_key,
      "/C=RU/ST=SPB/L=SPB/O=APISexAuthBearer/CN=test server certificate",
      template: :root_ca)

    ref = make_ref()

    Plug.Cowboy.https(PKICert, [],
                      port: 8443,
                      ref: ref,
                      cert: X509.Certificate.to_der(server_ca_cert),
                      cacerts: [X509.Certificate.to_der(peer_root_cert)],
                      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
                      verify: :verify_peer)

    {:ok, {status, _headers, body}} =
      :httpc.request(:post,
      {'https://localhost:8443', [], 'application/x-www-form-urlencoded', 'client_id=testclient'},
      [ssl: [
        cacerts: [X509.Certificate.to_der(server_ca_cert)],
        cert: X509.Certificate.to_der(peer_cert),
        key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
      ]],
      [])
    
    Plug.Cowboy.shutdown(ref)

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apisex_client"] == "testclient"
    assert Poison.decode!(body)["apisex_authenticator"] == "Elixir.APISexAuthMTLS"
  end

  test "invalid pki certificate" do
    peer_root_private_key = X509.PrivateKey.new_ec(:secp256r1)
    peer_root_cert = X509.Certificate.self_signed(peer_root_private_key,
      "/C=BZ/ST=MBH/L=Lorient/O=APISexAuthBearer/CN=test root CA peer certificate",
      template: :root_ca
    )

    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)
    peer_cert =
      peer_private_key
      |> X509.PublicKey.derive()
      |> X509.Certificate.new(
         "/C=BZ/ST=MBH/L=Lorient/O=APISexAuthBearer/CN=invalid DN",
         peer_root_cert, peer_root_private_key
         #extensions: [subject_alt_name: X509.Certificate.Extension.subject_alt_name(["localhost"])]
         )

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)
    server_ca_cert = X509.Certificate.self_signed(server_ca_private_key,
      "/C=RU/ST=SPB/L=SPB/O=APISexAuthBearer/CN=test server certificate",
      template: :root_ca)

    ref = make_ref()
    Plug.Cowboy.https(PKICert, [],
                      port: 8443,
                      ref: ref,
                      cert: X509.Certificate.to_der(server_ca_cert),
                      cacerts: [X509.Certificate.to_der(peer_root_cert)],
                      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
                      verify: :verify_peer)

    {:ok, {status, _headers, _body}} =
      :httpc.request(:post,
      {'https://localhost:8443', [], 'application/x-www-form-urlencoded', 'client_id=testclient'},
      [ssl: [
        cacerts: [X509.Certificate.to_der(server_ca_cert)],
        cert: X509.Certificate.to_der(peer_cert),
        key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
      ]],
      [])
    
    Plug.Cowboy.shutdown(ref)

    assert elem(status, 1) == 401
  end

  test "valid self-signed certificate" do
    peer_private_key = X509.PrivateKey.new_ec(:secp256r1)
    peer_cert = X509.Certificate.self_signed(peer_private_key,
      "/C=BZ/ST=MBH/L=Lorient/O=APISexAuthBearer/CN=test self-signed CA peer certificate",
      template: :root_ca
    )

    :ets.insert(:mtls_test, {:cert, peer_cert})

    server_ca_private_key = X509.PrivateKey.new_ec(:secp256r1)
    server_ca_cert = X509.Certificate.self_signed(server_ca_private_key,
      "/C=RU/ST=SPB/L=SPB/O=APISexAuthBearer/CN=test server certificate",
      template: :root_ca)

    ref = make_ref()

    Plug.Cowboy.https(PKICert, [],
                      port: 8443,
                      ref: ref,
                      cert: X509.Certificate.to_der(server_ca_cert),
                      cacerts: :certifi.cacerts(),
                      key: {:ECPrivateKey, X509.PrivateKey.to_der(server_ca_private_key)},
                      verify: :verify_peer)

    {:ok, {status, _headers, body}} =
      :httpc.request(:post,
      {'https://localhost:8443', [], 'application/x-www-form-urlencoded', 'client_id=testclient'},
      [ssl: [
        cacerts: [X509.Certificate.to_der(server_ca_cert)],
        cert: X509.Certificate.to_der(peer_cert),
        key: {:ECPrivateKey, X509.PrivateKey.to_der(peer_private_key)}
      ]],
      [])
    
    Plug.Cowboy.shutdown(ref)

    assert elem(status, 1) == 200
    assert Poison.decode!(body)["apisex_client"] == "testclient"
    assert Poison.decode!(body)["apisex_authenticator"] == "Elixir.APISexAuthMTLS"
  end
end
