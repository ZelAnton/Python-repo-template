# Security Policy

## Supported versions

Security fixes are applied to the latest released version of **__ProjectName__**.
Older versions are not maintained — upgrade to the latest release to receive
fixes.

## Reporting a vulnerability

**Do not open a public issue for security vulnerabilities.**

Report privately through GitHub's
[private vulnerability reporting](https://github.com/__GitHubOwner__/__ProjectName__/security/advisories/new)
(repository **Security → Advisories → Report a vulnerability**). If that is
unavailable, contact the maintainer listed on the
[__GitHubOwner__](https://github.com/__GitHubOwner__) profile.

Please include:

- a description of the vulnerability and its impact;
- steps to reproduce (a minimal proof of concept is ideal);
- affected version(s).

You can expect an initial acknowledgement within a few days. Once a fix is
ready, a patched release is published to PyPI and the advisory is disclosed.

## Automated scanning

- **[CodeQL](.github/workflows/codeql.yml)** runs GitHub's static analysis
  (`security-and-quality` queries) on every push and pull request to `main`, and
  on a weekly schedule. Python is a CodeQL-supported language.
- **[pip-audit](https://pypi.org/project/pip-audit/)** runs in CI on every pull
  request and every push to `main` (the `pip-audit` job in
  [`.github/workflows/ci.yml`](.github/workflows/ci.yml)). It scans the resolved
  dependency tree against the [PyPI Advisory Database](https://github.com/pypa/advisory-database)
  and fails the build on a known vulnerability.
- **[Dependabot](.github/dependabot.yml)** opens weekly pull requests to keep the
  Python dependencies (and the pinned GitHub Actions) current, so advisory fixes
  land promptly.
