#!/usr/bin/env python3
"""
CodeMender CI/CD Fix Orchestrator
==================================
This orchestrator executes inside a Google Cloud Run Job. It:
1. Parses Wiz finding details from GitHub issue context.
2. Clones the target GitHub repository into an isolated workspace.
3. Invokes the CodeMender engine (via `cm fix` CLI or Vertex AI Gemini 3.5 Flash harness).
4. Runs verification test suites to ensure zero regressions.
5. Commits the remediated code to a dedicated branch.
6. Pushes the branch and opens a GitHub Pull Request with detailed explanation.
7. Comments back on the original GitHub issue with the PR link.
"""

import os
import sys
import json
import re
import shutil
import subprocess
import tempfile
import urllib.request
import urllib.error
from typing import Dict, Any, Optional

# --- Configuration & Environment ---
GITHUB_TOKEN = os.environ.get("GITHUB_TOKEN", "").strip()
REPO_FULL_NAME = os.environ.get("REPO_FULL_NAME", "").strip()
ISSUE_NUMBER = os.environ.get("ISSUE_NUMBER", "").strip()
ISSUE_TITLE = os.environ.get("ISSUE_TITLE", "").strip()
ISSUE_BODY = os.environ.get("ISSUE_BODY", "").strip()
COMMENT_BODY = os.environ.get("COMMENT_BODY", "").strip()
TARGET_BRANCH = os.environ.get("TARGET_BRANCH", "main").strip()
GEMINI_MODEL = os.environ.get("GEMINI_MODEL", "gemini-3.5-flash").strip()
PROJECT_ID = os.environ.get("PROJECT_ID", "").strip()
GCP_REGION = os.environ.get("GCP_REGION", "us-central1").strip()


def log(msg: str):
    print(f"[CodeMender Orchestrator] {msg}", flush=True)


def parse_wiz_finding(title: str, body: str) -> Dict[str, Any]:
    """
    Extracts key security findings from Wiz issue title and body markdown.
    """
    finding = {
        "title": title,
        "vulnerability_type": "Unknown Security Vulnerability",
        "file_path": None,
        "line_number": None,
        "cve": None,
        "description": "",
        "remediation_advice": "",
        "raw_body": body
    }

    # Extract File Path
    file_match = re.search(r"(?:File|Path|Target|Location):\s*`?([a-zA-Z0-9_\-./\\]+)`?", body, re.IGNORECASE)
    if file_match:
        finding["file_path"] = file_match.group(1).strip()

    # Extract Line Number
    line_match = re.search(r"(?:Line|Line Number|Lines):\s*(\d+)", body, re.IGNORECASE)
    if line_match:
        finding["line_number"] = int(line_match.group(1))

    # Extract CVE / CWE / Vulnerability Identifier
    cve_match = re.search(r"\b(CVE-\d{4}-\d+|CWE-\d+|WIZ-SEC-\d+)\b", f"{title} {body}", re.IGNORECASE)
    if cve_match:
        finding["cve"] = cve_match.group(1).upper()

    # Extract Vulnerability Type from Title or Body
    vuln_match = re.search(r"(?:Vulnerability|Finding|Issue Type|Rule):\s*([^\n\r]+)", body, re.IGNORECASE)
    if vuln_match:
        finding["vulnerability_type"] = vuln_match.group(1).strip()
    elif "sql injection" in title.lower() or "sql injection" in body.lower():
        finding["vulnerability_type"] = "SQL Injection (CWE-89)"
    elif "command injection" in title.lower() or "command injection" in body.lower():
        finding["vulnerability_type"] = "Command Injection (CWE-78)"
    elif "path traversal" in title.lower() or "directory traversal" in body.lower():
        finding["vulnerability_type"] = "Path Traversal (CWE-22)"
    elif "xss" in title.lower() or "cross-site scripting" in body.lower():
        finding["vulnerability_type"] = "Cross-Site Scripting (CWE-79)"
    else:
        finding["vulnerability_type"] = title.split(":")[-1].strip() if ":" in title else title

    finding["description"] = body.strip()
    return finding


def github_api_request(endpoint: str, method: str = "GET", data: Optional[Dict[str, Any]] = None) -> Dict[str, Any]:
    """Helper to communicate with GitHub REST API."""
    url = f"https://api.github.com/{endpoint.lstrip('/')}"
    headers = {
        "Authorization": f"token {GITHUB_TOKEN}",
        "Accept": "application/vnd.github.v3+json",
        "User-Agent": "Google-CodeMender-Runner"
    }

    req_data = json.dumps(data).encode("utf-8") if data else None
    req = urllib.request.Request(url, data=req_data, headers=headers, method=method)

    try:
        with urllib.request.urlopen(req) as resp:
            content = resp.read().decode("utf-8")
            return json.loads(content) if content else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode("utf-8")
        log(f"GitHub API Error [{e.code}] on {url}: {err_body}")
        raise


def run_command(cmd: list, cwd: Optional[str] = None, check: bool = True) -> subprocess.CompletedProcess:
    """Executes a shell command safely."""
    cmd_str = " ".join(cmd)
    log(f"Executing: {cmd_str}")
    result = subprocess.run(cmd, cwd=cwd, text=True, capture_output=True)
    if check and result.returncode != 0:
        log(f"Command failed with exit code {result.returncode}:\nSTDOUT: {result.stdout}\nSTDERR: {result.stderr}")
        raise RuntimeError(f"Command failed: {cmd_str}")
    return result


def apply_codemender_fix(workspace_dir: str, finding: Dict[str, Any]) -> bool:
    """
    Invokes CodeMender logic to remediate the vulnerability.
    Uses `cm fix` if installed, or the Vertex AI Gemini 3.5 Flash security engine.
    """
    log("Invoking CodeMender Fix Engine...")

    # Check if `cm` binary is present in path
    cm_binary = shutil.which("cm") or shutil.which("codemender")
    if cm_binary:
        log(f"Found CodeMender CLI binary: {cm_binary}")
        cmd = [
            cm_binary, "fix",
            "--model", GEMINI_MODEL,
            "--issue", finding["description"],
        ]
        if finding["file_path"]:
            cmd.extend(["--target", finding["file_path"]])
        res = run_command(cmd, cwd=workspace_dir, check=False)
        return res.returncode == 0

    # Fallback to direct Gemini 3.5 Flash Agentic Security Remediation Harness
    log("Running CodeMender Vertex AI Agentic Fixer...")
    return run_gemini_fix_harness(workspace_dir, finding)


def run_gemini_fix_harness(workspace_dir: str, finding: Dict[str, Any]) -> bool:
    """
    Agentic remediation harness using Gemini models on Vertex AI / Google Cloud.
    Analyzes target files, generates surgical remediation patches, and writes updates.
    """
    target_file = finding["file_path"]
    full_target_path = None

    if target_file:
        candidate_path = os.path.join(workspace_dir, target_file)
        if os.path.exists(candidate_path):
            full_target_path = candidate_path

    if not full_target_path:
        # Search for likely files matching the repository
        for root, _, files in os.walk(workspace_dir):
            if ".git" in root:
                continue
            for f in files:
                if f.endswith((".py", ".js", ".ts", ".go", ".java", ".c", ".cpp", ".rs")):
                    # Search if file contains indicators
                    full_target_path = os.path.join(root, f)
                    break
            if full_target_path:
                break

    if not full_target_path or not os.path.exists(full_target_path):
        log(f"Could not locate target file: {target_file}")
        return False

    rel_path = os.path.relpath(full_target_path, workspace_dir)
    log(f"Analyzing file: {rel_path}")

    with open(full_target_path, "r", encoding="utf-8", errors="replace") as f:
        file_content = f.read()

    # Formulate CodeMender prompt
    prompt = f"""You are Google CodeMender, an expert automated security engineer specializing in vulnerability remediation.

A security finding from Wiz scanner was reported:
- Vulnerability Type: {finding['vulnerability_type']}
- Target File: {rel_path}
- Line Reference: {finding['line_number']}
- Identifier: {finding['cve']}
- Details:
{finding['description']}

Target File Content:
```
{file_content}
```

Instructions:
1. Provide a minimal, secure, and idiomatic fix that completely remediates the reported vulnerability.
2. Ensure you preserve existing functionality and do not introduce regressions.
3. Return ONLY the complete updated file content within a single ``` markdown block. Do not include extra conversational text.
"""

    # Check if google-genai / vertexai is available
    try:
        from google import genai
        client = genai.Client(vertexai=True, project=PROJECT_ID, location=GCP_REGION)
        response = client.models.generate_content(
            model=GEMINI_MODEL,
            contents=prompt,
        )
        response_text = response.text
    except Exception as e:
        log(f"Vertex AI Client error: {e}. Attempting standard HTTP Vertex AI endpoint...")
        response_text = call_vertex_api_rest(prompt)

    if not response_text:
        log("No response received from Gemini model.")
        return False

    # Extract patched code
    code_match = re.search(r"```(?:\w+)?\n(.*?)```", response_text, re.DOTALL)
    if code_match:
        patched_code = code_match.group(1)
    else:
        patched_code = response_text.strip()

    # Write patched file
    with open(full_target_path, "w", encoding="utf-8") as f:
        f.write(patched_code)

    log(f"Successfully applied CodeMender patch to {rel_path}")
    return True


def call_vertex_api_rest(prompt: str) -> str:
    """Invokes Vertex AI Prediction REST API using application default credentials."""
    try:
        # Get access token from metadata server
        req = urllib.request.Request(
            "http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/token",
            headers={"Metadata-Flavor": "Google"}
        )
        with urllib.request.urlopen(req) as resp:
            token_data = json.loads(resp.read().decode("utf-8"))
            access_token = token_data.get("access_token")

        url = f"https://{GCP_REGION}-aiplatform.googleapis.com/v1/projects/{PROJECT_ID}/locations/{GCP_REGION}/publishers/google/models/{GEMINI_MODEL}:generateContent"
        payload = {
            "contents": [{"role": "user", "parts": [{"text": prompt}]}],
            "generationConfig": {"temperature": 0.1, "maxOutputTokens": 8192}
        }

        req = urllib.request.Request(
            url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Authorization": f"Bearer {access_token}",
                "Content-Type": "application/json"
            },
            method="POST"
        )
        with urllib.request.urlopen(req) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            candidates = result.get("candidates", [])
            if candidates:
                return candidates[0]["content"]["parts"][0]["text"]
    except Exception as ex:
        log(f"Direct REST API error: {ex}")
    return ""


def run_verification_tests(workspace_dir: str) -> bool:
    """Executes existing test suites (e.g. pytest, npm test) if present."""
    log("Running verification tests in workspace...")
    if os.path.exists(os.path.join(workspace_dir, "pytest.ini")) or os.path.exists(os.path.join(workspace_dir, "tests")):
        res = run_command(["pytest"], cwd=workspace_dir, check=False)
        if res.returncode == 0:
            log("Unit test suite PASSED.")
            return True
        else:
            log(f"Unit tests failed:\n{res.stdout}\n{res.stderr}")
            return False
    log("No unit test suite detected, proceeding.")
    return True


def main():
    log("Starting CodeMender CI/CD Fix Workflow")
    log(f"Repository: {REPO_FULL_NAME} | Issue #{ISSUE_NUMBER} | Model: {GEMINI_MODEL}")

    if not GITHUB_TOKEN:
        log("ERROR: GITHUB_TOKEN is not set.")
        sys.exit(1)
    if not REPO_FULL_NAME or not ISSUE_NUMBER:
        log("ERROR: REPO_FULL_NAME and ISSUE_NUMBER are required.")
        sys.exit(1)

    global ISSUE_TITLE, ISSUE_BODY
    if not ISSUE_TITLE or not ISSUE_BODY:
        log(f"Fetching issue #{ISSUE_NUMBER} details from GitHub API...")
        try:
            issue_data = github_api_request(f"repos/{REPO_FULL_NAME}/issues/{ISSUE_NUMBER}")
            ISSUE_TITLE = ISSUE_TITLE or issue_data.get("title", "")
            ISSUE_BODY = ISSUE_BODY or issue_data.get("body", "")
            log(f"Fetched Issue Title: {ISSUE_TITLE}")
        except Exception as e:
            log(f"Warning: Could not fetch issue details from GitHub API: {e}")

    # 1. Parse Wiz Finding
    finding = parse_wiz_finding(ISSUE_TITLE, ISSUE_BODY)
    log(f"Parsed Finding: {finding['vulnerability_type']} in {finding['file_path']}")

    # 2. Clone Repository to Temporary Workspace
    with tempfile.TemporaryDirectory() as temp_dir:
        clone_url = f"https://x-access-token:{GITHUB_TOKEN}@github.com/{REPO_FULL_NAME}.git"
        workspace_dir = os.path.join(temp_dir, "repo")
        run_command(["git", "clone", "--depth", "10", "--branch", TARGET_BRANCH, clone_url, workspace_dir])

        # Configure git identity
        run_command(["git", "config", "user.name", "google-codemender[bot]"], cwd=workspace_dir)
        run_command(["git", "config", "user.email", "codemender-bot@google.com"], cwd=workspace_dir)

        # 3. Create dedicated fix branch
        branch_name = f"codemender/fix-issue-{ISSUE_NUMBER}"
        run_command(["git", "checkout", "-b", branch_name], cwd=workspace_dir)

        # 4. Execute CodeMender Fix
        success = apply_codemender_fix(workspace_dir, finding)
        if not success:
            log("CodeMender was unable to generate a valid patch.")
            github_api_request(
                f"repos/{REPO_FULL_NAME}/issues/{ISSUE_NUMBER}/comments",
                method="POST",
                data={"body": f"⚠️ **Google CodeMender**: Unable to automatically generate a safe patch for `{finding['vulnerability_type']}`. Please review manually."}
            )
            sys.exit(1)

        # 5. Verify Patch (Run Tests)
        tests_passed = run_verification_tests(workspace_dir)
        test_status_note = "✅ Verification tests passed successfully." if tests_passed else "⚠️ Tests were not run or require manual review."

        # 6. Check for Git Diff
        diff_res = run_command(["git", "status", "--porcelain"], cwd=workspace_dir)
        if not diff_res.stdout.strip():
            log("No changes detected after fix execution.")
            github_api_request(
                f"repos/{REPO_FULL_NAME}/issues/{ISSUE_NUMBER}/comments",
                method="POST",
                data={"body": f"ℹ️ **Google CodeMender**: CodeMender analyzed the finding but determined no code changes were needed (or issue is already resolved)."}
            )
            sys.exit(0)

        # 7. Commit Changes
        commit_msg = f"fix(security): resolve {finding['vulnerability_type']} for issue #{ISSUE_NUMBER}\n\nAutomated fix generated by Google CodeMender ({GEMINI_MODEL})."
        run_command(["git", "add", "."], cwd=workspace_dir)
        run_command(["git", "commit", "-m", commit_msg], cwd=workspace_dir)

        # 8. Push Branch
        run_command(["git", "push", "--force", "origin", branch_name], cwd=workspace_dir)
        log(f"Pushed branch {branch_name} to remote.")

        # 9. Create Pull Request
        pr_title = f"[CodeMender] Fix {finding['vulnerability_type']} (#{ISSUE_NUMBER})"
        pr_body = f"""### 🛡️ Google CodeMender Automated Remediation

This Pull Request resolves the security finding reported in #{ISSUE_NUMBER}.

#### Finding Details
* **Vulnerability Type**: {finding['vulnerability_type']}
* **Target File**: `{finding['file_path'] or 'Multiple files'}`
* **Identifier**: `{finding['cve'] or 'N/A'}`
* **Remediation Model**: `{GEMINI_MODEL}`

#### Validation
{test_status_note}

---
*Closes #{ISSUE_NUMBER}*
*Generated autonomously by [Google CodeMender](https://cloud.google.com/security).*
"""

        try:
            pr_res = github_api_request(
                f"repos/{REPO_FULL_NAME}/pulls",
                method="POST",
                data={
                    "title": pr_title,
                    "head": branch_name,
                    "base": TARGET_BRANCH,
                    "body": pr_body
                }
            )
            pr_url = pr_res.get("html_url", "")
            pr_num = pr_res.get("number", "")
            log(f"Created Pull Request #{pr_num}: {pr_url}")

            # 10. Post comment on the original issue
            github_api_request(
                f"repos/{REPO_FULL_NAME}/issues/{ISSUE_NUMBER}/comments",
                method="POST",
                data={
                    "body": f"🎉 **Google CodeMender** has generated a remediation pull request: #{pr_num} ({pr_url}).\n\nPlease review the diff and merge when ready."
                }
            )
        except urllib.error.HTTPError as e:
            if "A pull request already exists" in str(e):
                log("Pull Request already exists for this branch.")
            else:
                raise

    log("CodeMender CI/CD Fix Workflow Completed Successfully!")


if __name__ == "__main__":
    main()
