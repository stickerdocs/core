[![License](https://img.shields.io/github/license/stickerdocs/core)](LICENSE)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

[StickerDocs](https://stickerdocs.com) is a secure, fun and affordable file and photo organisation and sharing, for people. This is the core on which the (closed-source) StickerDocs App runs.

## End-to-End Encryption (E2EE)

We use the established, popular [Libsodim](https://doc.libsodium.org/) library for all data encryption. We make use of both [public-key](https://doc.libsodium.org/public-key_cryptography/authenticated_encryption) and [secret-key](https://doc.libsodium.org/secret-key_cryptography/secretbox) as well as the hashing and key derivation features from this library.

## Password and Data Encryption

When you register an account with StickerDocs, your password never leaves your device. We generate a new cryptographic key for encrypting all your data, and we encrypt that key with a derived key from your password.

To mitigate against theft of login material from intercepting SSL devices/Man-in-the Middle, we use public key cryptograph, and requests are signed and unique to prevent tampering.

## Synchronisation

Since there is no centralised database each client has their own SQLite database and these databases are kept in sync through the use of Conflict-free Replicated Data Types (CRDTs).

## License

StickerDocs is distributed under [AGPL-3.0 license](LICENSE).

## Why is the App Not Open Source?

We are not making the app open source at this time to prevent unauthorised clones. You have to take our word when we say all comms from the app go via this components.
