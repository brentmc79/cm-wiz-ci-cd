"""
Sample Web Application for CodeMender CI/CD Proof-of-Concept
============================================================
Contains an intentional vulnerability (SQL Injection) for Wiz scanner detection
and CodeMender automated remediation.
"""

import sqlite3
from flask import Flask, request, jsonify

app = Flask(__name__)

def init_db():
    conn = sqlite3.connect(":memory:", check_same_thread=False)
    cursor = conn.cursor()
    cursor.execute("CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT, email TEXT, role TEXT);")
    cursor.execute("INSERT INTO users (username, email, role) VALUES ('admin', 'admin@example.com', 'administrator');")
    cursor.execute("INSERT INTO users (username, email, role) VALUES ('alice', 'alice@example.com', 'user');")
    cursor.execute("INSERT INTO users (username, email, role) VALUES ('bob', 'bob@example.com', 'user');")
    conn.commit()
    return conn

db_conn = init_db()

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "healthy"})

# VULNERABLE ENDPOINT: Wiz Finding (CWE-89 SQL Injection)
@app.route("/api/users/search", methods=["GET"])
def search_user():
    username = request.args.get("username", "")
    cursor = db_conn.cursor()

    # REMEDIATION: Using parameterized query to prevent SQL Injection
    cursor.execute("SELECT id, username, email, role FROM users WHERE username = ?", (username,))
    
    results = cursor.fetchall()
    users = [{"id": r[0], "username": r[1], "email": r[2], "role": r[3]} for r in results]
    return jsonify({"users": users})

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)

