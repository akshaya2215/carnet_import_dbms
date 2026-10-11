# db.py
# Database connection helper.
# get_db()  – returns a per-request mysql connection (stored in Flask's g object)
# query()   – runs a SELECT and returns all rows as dicts
# execute() – runs INSERT/UPDATE/DELETE and returns lastrowid

import mysql.connector
from flask import g
import config


def get_db():
    """
    Return the database connection for the current Flask request.
    Creates a new connection if one does not exist yet.
    The connection is automatically closed at the end of the request
    (see close_db registered in app.py with app.teardown_appcontext).
    """
    if "db" not in g:
        g.db = mysql.connector.connect(
            host=config.DB_HOST,
            port=config.DB_PORT,
            user=config.DB_USER,
            password=config.DB_PASSWORD,
            database=config.DB_NAME,
            autocommit=False,   # Flask code manages transactions manually
        )
    return g.db


def close_db(e=None):
    """Remove the database connection at the end of the request."""
    db = g.pop("db", None)
    if db is not None:
        db.close()


def query(sql, params=None):
    """
    Run a SELECT query and return a list of dicts (one per row).
    Always uses parameterized queries – never string formatting.
    """
    db = get_db()
    cursor = db.cursor(dictionary=True)
    cursor.execute(sql, params or ())
    rows = cursor.fetchall()
    cursor.close()
    return rows


def execute(sql, params=None):
    """
    Run an INSERT, UPDATE, or DELETE.
    Returns the lastrowid (useful after INSERT).
    Caller is responsible for commit/rollback.
    """
    db = get_db()
    cursor = db.cursor()
    cursor.execute(sql, params or ())
    last_id = cursor.lastrowid
    cursor.close()
    return last_id


def callproc(proc_name, args=()):
    """
    Call a stored procedure.
    Returns the result sets (list of list of dicts).
    """
    db = get_db()
    cursor = db.cursor(dictionary=True)
    cursor.callproc(proc_name, args)
    results = []
    for rs in cursor.stored_results():
        results.append(rs.fetchall())
    cursor.close()
    return results
