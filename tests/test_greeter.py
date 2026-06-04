from __PackageName__ import greet


def test_greet() -> None:
    assert greet("World") == "Hello, World!"
