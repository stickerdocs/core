[![License](https://img.shields.io/github/license/stickerdocs/core)](LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

[StickerDocs](https://stickerdocs.com) is a secure and affordable file and photo organisation and sharing, for people. This is the core on which the StickerDocs App is built.

## End-to-End Encryption (E2EE)

We use the established, popular [Libsodim](https://doc.libsodium.org/) library for all data encryption. We make use of both [public-key](https://doc.libsodium.org/public-key_cryptography/authenticated_encryption) and [secret-key](https://doc.libsodium.org/secret-key_cryptography/secretbox) as well as the hashing and key derivation features from this library.

## Synchronisation

Since there is no centralised database ech client has their own SQLite database and these databases are kept in sync via Conflict-free Replicated Data Types (CRDTs).

## License

StickerDocs is distributed under [AGPL-3.0 license](LICENSE).
