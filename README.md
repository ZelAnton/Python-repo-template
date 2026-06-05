# __ProjectName__

__Description__

## Requirements

- Python 3.12 or later
- [uv](https://docs.astral.sh/uv/) (provisions the interpreter, manages the
  virtualenv, runs the tooling, and builds the package)

## Installation

Available on [PyPI](https://pypi.org/project/__ProjectName__/).

```sh
pip install __ProjectName__
# or, with uv:
uv add __ProjectName__
```

## Usage

```python
from __PackageName__ import greet

print(greet("World"))  # -> "Hello, World!"
```

## Verifying the package

Each GitHub Release ships a `SHA256SUMS` file alongside the published wheel and
sdist. Download them into the same directory, then:

```sh
sha256sum -c SHA256SUMS
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for the version history.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for build/test instructions and
conventions. To report a security issue, follow [SECURITY.md](SECURITY.md) —
please do not open a public issue.

## License

This project is licensed under the [MIT License](LICENSE).
