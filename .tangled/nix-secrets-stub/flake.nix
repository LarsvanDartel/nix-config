# nix-secrets-stub — keyless CI stand-in for the private nix-secrets input; see docs/src/secrets.md#plaintext-values.
{
  description = "Empty stand-in for nix-secrets, for credential-free CI";
  outputs = _: {
    gewis-aliases = ["alias@example.org"];
    gewis-address-books.example = "https://dav.example.org/Contacts/example/";
  };
}
