# setup_db.py
# -----------------------------------------------------------------------
# Re-runnable database setup script.
# Usage: python setup_db.py
#
# DELIMITER handling:
#   mysql-connector-python cannot handle DELIMITER $$ ... DELIMITER ;
#   This script splits each SQL file on those markers so that each
#   stored routine / trigger is sent as a single statement.
#   Re-runnable: 01_schema.sql does DROP DATABASE IF EXISTS first.
# -----------------------------------------------------------------------

import re
import sys
import io
import mysql.connector
import config

# Force UTF-8 output on Windows to avoid encoding errors with special chars
sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8', errors='replace')

SQL_FILES = [
    "sql/01_schema.sql",
    "sql/02_functions_procedures.sql",
    "sql/03_triggers.sql",
    "sql/04_views.sql",
    "sql/05_seed.sql",
]


def split_sql(content):
    """
    Split a SQL file into individual executable statements.

    Uses a state machine that understands:
      - Single-quoted strings '...' (ignores ; inside them)
      - Single-line comments -- ... (ignores ; inside them)
      - DELIMITER $$ ... DELIMITER ; blocks (routines/triggers)

    This correctly handles semicolons in string literals and comments.
    """
    # First extract DELIMITER $$ blocks separately
    delimiter_pattern = re.compile(
        r'DELIMITER\s+\$\$(.*?)DELIMITER\s+;',
        re.DOTALL | re.IGNORECASE,
    )

    # Replace each DELIMITER block with a placeholder
    placeholders = {}
    placeholder_idx = 0

    def replace_block(m):
        nonlocal placeholder_idx
        key = f'__PLACEHOLDER_{placeholder_idx}__'
        placeholder_idx += 1
        # Store each $$ chunk as a separate statement
        chunks = [c.strip() for c in m.group(1).split('$$') if c.strip()]
        placeholders[key] = chunks
        return key + ';'  # make it splittable

    processed = delimiter_pattern.sub(replace_block, content)

    # Now split the remaining content respecting strings and -- comments
    statements = []
    current = []
    i = 0
    n = len(processed)
    in_string = False
    string_char = None

    while i < n:
        ch = processed[i]

        if in_string:
            current.append(ch)
            if ch == '\\':
                # Escaped character
                i += 1
                if i < n:
                    current.append(processed[i])
            elif ch == string_char:
                in_string = False
        elif ch == "'":
            in_string = True
            string_char = "'"
            current.append(ch)
        elif ch == '-' and i + 1 < n and processed[i + 1] == '-':
            # Single-line comment: read to end of line
            while i < n and processed[i] != '\n':
                current.append(processed[i])
                i += 1
            continue  # don't increment i again at bottom
        elif ch == ';':
            stmt = ''.join(current).strip()
            if stmt:
                # Check if it's a placeholder
                ph_match = re.fullmatch(r'__PLACEHOLDER_\d+__', stmt)
                if ph_match:
                    statements.extend(placeholders[stmt])
                else:
                    statements.append(stmt)
            current = []
        else:
            current.append(ch)

        i += 1

    # Handle any trailing content without a terminating semicolon
    stmt = ''.join(current).strip()
    if stmt:
        statements.append(stmt)

    return statements


def is_empty(stmt):
    """Return True if statement contains only whitespace and SQL comments."""
    # Remove /* ... */ block comments first
    s = re.sub(r'/\*.*?\*/', '', stmt, flags=re.DOTALL)
    # Then check remaining lines: empty or starting with '--'
    non_comment = [
        line.strip() for line in s.splitlines()
        if line.strip() and not line.strip().startswith('--')
    ]
    return len(non_comment) == 0


def run_file(conn, filepath):
    """Read a SQL file and execute each statement, reporting results."""
    print(f"\n  Running {filepath} ...")
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    statements = split_sql(content)
    cursor = conn.cursor()
    ok = 0
    for stmt in statements:
        if is_empty(stmt):
            continue
        try:
            cursor.execute(stmt)
            # Consume all result sets (required after CALL statements)
            while cursor.nextset():
                pass
            ok += 1
        except mysql.connector.Error as e:
            preview = stmt[:100].replace('\n', ' ')
            print(f"    [WARN] {e.errno}: {e.msg}")
            print(f"           Statement: {preview!r}")
    cursor.close()
    conn.commit()
    print(f"  --> {ok} statements executed OK.")


def main():
    print("=" * 60)
    print("  carnet_import  -  Database Setup")
    print("=" * 60)

    # Connect without a database; 01_schema.sql will DROP and CREATE it
    try:
        conn = mysql.connector.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            user=config.DB_USER,
            password=config.DB_PASSWORD,
            autocommit=True,
        )
        print(f"\nConnected to MySQL at {config.DB_HOST}:{config.DB_PORT}")
    except mysql.connector.Error as e:
        print(f"\nERROR: Cannot connect to MySQL: {e}")
        sys.exit(1)

    for sql_file in SQL_FILES:
        run_file(conn, sql_file)

    conn.close()
    print("\n" + "=" * 60)
    print("  Setup complete!  Run:  python seed_admin.py")
    print("=" * 60)


if __name__ == "__main__":
    main()
