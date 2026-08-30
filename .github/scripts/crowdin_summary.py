"""Writes a translation status table for the GitHub Actions run summary."""

import json
import os
import urllib.error
import urllib.request

API = "https://api.crowdin.com/api/v2"


def fetch(path, token):
    request = urllib.request.Request(
        f"{API}{path}", headers={"Authorization": f"Bearer {token}"}
    )
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def main():
    project = os.environ.get("CROWDIN_PROJECT_ID", "").strip()
    token = os.environ.get("CROWDIN_PERSONAL_TOKEN", "").strip()
    if not project or not token:
        print("Crowdin credentials are not configured, no status to report.")
        return

    try:
        progress = fetch(f"/projects/{project}/languages/progress?limit=100", token)
    except (urllib.error.URLError, OSError, ValueError, KeyError) as error:
        print(f"Could not read the translation status from Crowdin: {error}")
        return

    try:
        details = fetch(f"/projects/{project}", token)["data"]
    except (urllib.error.URLError, OSError, ValueError, KeyError):
        details = {}

    name = details.get("name") or f"project {project}"
    source = details.get("sourceLanguageId", "")

    rows = [entry["data"] for entry in progress.get("data", [])]
    rows.sort(key=lambda row: (-row.get("translationProgress", 0), row.get("languageId", "")))

    print(f"## Translation status — {name}")
    print()
    if source:
        print(f"Source language: `{source}`.")
        print()
    if not rows:
        print("No target languages yet.")
    else:
        print("| Language | Translated | Approved | Strings | Words |")
        print("| --- | ---: | ---: | ---: | ---: |")
        for row in rows:
            phrases = row.get("phrases", {})
            words = row.get("words", {})
            print(
                f"| `{row.get('languageId', '?')}` "
                f"| {row.get('translationProgress', 0)}% "
                f"| {row.get('approvalProgress', 0)}% "
                f"| {phrases.get('translated', 0)} / {phrases.get('total', 0)} "
                f"| {words.get('translated', 0)} / {words.get('total', 0)} |"
            )

    identifier = details.get("identifier")
    if identifier:
        print()
        print(f"[Open the project on Crowdin](https://crowdin.com/project/{identifier})")


if __name__ == "__main__":
    main()
