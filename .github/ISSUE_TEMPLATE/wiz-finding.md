---
name: Wiz Security Finding
about: Security vulnerability detected by Wiz CLI / CI/CD scanner
title: '[Wiz] Vulnerability Detected: '
labels: ['security', 'wiz-finding']
assignees: ''
---

### 🛡️ Wiz Security Finding Details

* **Vulnerability / Rule**: SQL Injection (CWE-89)
* **Severity**: High
* **Target File**: `app.py`
* **Line Number**: 42
* **Identifier**: CVE-2024-XXXX / WIZ-SEC-1042

#### Finding Description
User-controlled input is directly concatenated into a dynamic SQL query without parameterization, allowing remote code / data access.

#### Remediation Guidance
Use parameterized queries or ORM placeholders rather than direct string formatting or f-strings.

---
*To trigger automated remediation via Google CodeMender, comment `@codemender` on this issue.*
