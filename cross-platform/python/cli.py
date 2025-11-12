#!/usr/bin/env python3
"""Simple cross-platform Python CLI smoke-test example."""
import sys


def main():
    print("Running example Python CLI from usefull-scripts")
    print(f"Python: {sys.version.split()[0]}")
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
