# Release process

1. Run all Swift, Python, and Zephyr tests.
2. Flash and exercise short, long, double, destructive-confirm, and cancellation paths.
3. Update `CHANGELOG.md` and the version in `packaging/macos/Info.plist`.
4. Run `scripts/package-macos.sh` with `KEYCAP_SIGNING_IDENTITY` set.
5. Set `KEYCAP_NOTARY_PROFILE` to submit and staple the notarization ticket.
6. Publish the zipped app, firmware hex, SHA-256 checksums, and source archive.
7. Verify installation and rollback on a clean macOS account.

Never publish unsigned replacement artifacts under an existing version number.
