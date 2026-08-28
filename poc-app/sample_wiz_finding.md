# Sample Wiz Finding for PoC Testing

You can use the following markdown as the body of a test GitHub Issue in your repository:

```markdown
### 🛡️ Wiz Security Finding Details

* **Vulnerability / Rule**: SQL Injection (CWE-89)
* **Severity**: High
* **Target File**: `app.py`
* **Line Number**: 29
* **Identifier**: WIZ-SEC-CWE89-001

#### Finding Description
User-controlled input `username` from HTTP request query parameters is formatted directly into a raw SQL query string via an f-string:
`query = f"SELECT id, username, email, role FROM users WHERE username = '{username}'"`
This allows an attacker to manipulate the SQL statement syntax and extract or alter database contents.

#### Remediation Guidance
Use parameterized queries:
`cursor.execute("SELECT id, username, email, role FROM users WHERE username = ?", (username,))`
```

---

### How to Trigger CodeMender:
Comment on the issue:
```text
@codemender please fix this SQL injection vulnerability
```
