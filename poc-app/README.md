# Proof-of-Concept (PoC) Application: CodeMender & Wiz CI/CD Integration

This directory contains a lightweight Python web application with a simulated security vulnerability designed to demonstrate end-to-end automated remediation using Google CodeMender.

## Overview

1. **Target Application (`app.py`)**: A Flask application exposing a user search endpoint (`/api/users/search`) containing a SQL Injection vulnerability (CWE-89).
2. **Test Suite (`tests/test_app.py`)**: Unit tests validating basic service health and verifying proper handling of SQL injection payloads.
3. **Wiz Finding (`sample_wiz_finding.md`)**: A sample security issue payload simulating a Wiz SAST detection.

## Local Testing

To run the application and execute tests locally:

```bash
cd poc-app
pip install -r requirements.txt

# Run the test suite (initially fails on SQL injection defense test)
pytest tests/test_app.py
```

## Running the PoC in GitHub CI/CD

1. Copy the `.github/workflows/codemender-fix.yml` file to your target repository.
2. Create a new GitHub issue using the content in `sample_wiz_finding.md`.
3. Post a comment:
   ```text
   @codemender fix
   ```
4. The GitHub runner triggers the Google Cloud Run Job via Workload Identity Federation.
5. Cloud Run executes the CodeMender engine, applies the parameterized query fix, validates the fix against `pytest`, pushes the branch, and opens a Pull Request linked to the issue.
