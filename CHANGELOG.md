# Changelog

All notable changes to **__ProjectName__** are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
-

### Changed
-

### Fixed
- Make template initialization transactional across staging, renames, settings activation, and cleanup.
- Restore metadata validation so generated TOML, YAML, Markdown, and shell content
  cannot be altered through unsafe author, email, owner, or description values.
- Report rollback and staging-cleanup failures instead of silently leaving artifacts
  or claiming that initialization succeeded.

[Unreleased]: https://github.com/__GitHubOwner__/__ProjectName__/commits/main
