# seed_admin.py
# -----------------------------------------------------------------------
# Creates the demo admin user in the admin_user table.
# Run this AFTER setup_db.py.
# Usage: python seed_admin.py
#
# Demo credentials (printed at the end and in README.md):
#   username: admin
#   password: admin123
#
# The password is hashed with werkzeug.security before storage –
# the plain-text password is never saved in the database.
# -----------------------------------------------------------------------

import mysql.connector
from werkzeug.security import generate_password_hash
import config

ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "admin123"


def main():
    conn = mysql.connector.connect(
        host=config.DB_HOST,
        port=config.DB_PORT,
        user=config.DB_USER,
        password=config.DB_PASSWORD,
        database=config.DB_NAME,
    )
    cursor = conn.cursor()

    # Hash the password using werkzeug (bcrypt-style pbkdf2)
    hashed = generate_password_hash(ADMIN_PASSWORD)

    # Use INSERT ... ON DUPLICATE KEY UPDATE so this script is re-runnable
    cursor.execute(
        """
        INSERT INTO admin_user (username, password_hash)
        VALUES (%s, %s)
        ON DUPLICATE KEY UPDATE password_hash = VALUES(password_hash)
        """,
        (ADMIN_USERNAME, hashed),
    )
    conn.commit()
    cursor.close()
    conn.close()

    print("=" * 50)
    print("  Admin user created / updated.")
    print(f"  Username : {ADMIN_USERNAME}")
    print(f"  Password : {ADMIN_PASSWORD}")
    print("=" * 50)


if __name__ == "__main__":
    main()
