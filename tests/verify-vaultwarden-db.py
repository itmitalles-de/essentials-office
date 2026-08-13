#!/usr/bin/env python3
"""Read-only structural verification of synthetic Vaultwarden browser data."""

from __future__ import annotations

import sqlite3
import sys


def count(connection: sqlite3.Connection, query: str, value: str) -> int:
    row = connection.execute(query, (value,)).fetchone()
    return int(row[0]) if row else 0


def main() -> int:
    if len(sys.argv) != 2:
        raise RuntimeError("usage: verify-vaultwarden-db.py DB_FILE")
    uri = f"file:{sys.argv[1]}?mode=ro"
    connection = sqlite3.connect(uri, uri=True)
    try:
        checks = {
            "organization": count(connection, "SELECT COUNT(*) FROM organizations WHERE name = ?", "Essentials Plus Synthetic Org"),
            "collection": count(connection, "SELECT COUNT(*) FROM collections WHERE name = ?", "Synthetic Shared Collection"),
            "group": count(connection, "SELECT COUNT(*) FROM groups WHERE name = ?", "Synthetic Editors"),
        }
        role_rows = connection.execute("SELECT DISTINCT type FROM users_organizations ORDER BY type").fetchall()
        roles = {int(row[0]) for row in role_rows}
        if any(value < 1 for value in checks.values()):
            raise RuntimeError(f"missing Vaultwarden browser objects: {checks}")
        if 0 not in roles or 2 not in roles:
            raise RuntimeError(f"expected owner and user role rows, found {sorted(roles)}")
    finally:
        connection.close()
    print("verify-vaultwarden-db: organization, collection, group, owner role, and user role passed")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exception:
        print(f"verify-vaultwarden-db: {exception}", file=sys.stderr)
        sys.exit(1)
