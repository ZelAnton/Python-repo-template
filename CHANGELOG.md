# Changelog

All notable changes to **__ProjectName__** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
-

### Changed
- Run YAML lint through the pinned project dependency managed by `uv`.

### Fixed
- Preserve the executable bit on the POSIX initializer so generated repositories
  can invoke `scripts/init.sh` directly on Unix-like systems.
- Report POSIX `find` traversal failures before initialization can mutate or
  claim success for a checkout.
- Reject unsafe initializer metadata before file mutation so generated release
  workflows cannot be altered through TOML, YAML, Markdown, or shell injection.
- Make template initialization transactional across staging, renames, settings activation, and cleanup.
- Restore metadata validation so generated TOML, YAML, Markdown, and shell content
  cannot be altered through unsafe author, email, owner, or description values.
- Report rollback and staging-cleanup failures instead of silently leaving artifacts
  or claiming that initialization succeeded.
- Keep the POSIX initializer compatible with macOS Bash 3.2 and BSD utilities while
  preserving transactional rollback and PowerShell output parity.
- POSIX initializer options now reject missing values, including following option tokens, before changing the checkout.
- Accept safe metadata such as underscored email addresses consistently in POSIX and PowerShell initializers while retaining unsafe-input rejection.
- Report POSIX command failures during metadata preflight and skip POSIX tests on Windows runners without a WSL distribution.

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
