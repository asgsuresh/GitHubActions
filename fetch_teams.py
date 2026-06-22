import os
import json
import csv
import subprocess

# Pull environment variables
org = os.getenv("ORG_NAME")
token = os.getenv("GH_TOKEN")

if not org or not token:
    raise ValueError("Missing ORG_NAME or GH_TOKEN environment variables.")

def run_gh_api(endpoint):
    """Helper function to execute GitHub CLI API requests."""
    cmd = ["gh", "api", "--paginate", endpoint]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        print(f"Error running api for {endpoint}: {result.stderr}")
        return []
    
    # gh api --paginate returns concatenated JSON arrays or objects line-by-line
    # We stitch them together into a single manageable list
    output = result.stdout.strip()
    if not output:
        return []
    
    # Parse potential multi-line/concatenated JSON structures
    try:
        return json.loads(output)
    except json.JSONDecodeError:
        # Fallback if paginated outputs are returned raw line-by-line
        records = []
        for line in output.split('\n'):
            if line.strip():
                try:
                    data = json.loads(line)
                    if isinstance(data, list):
                        records.extend(data)
                    else:
                        records.append(data)
                except:
                    pass
        return records

def main():
    print(f"Gathering metrics for Organization: {org}")
    
    # 1. Fetch all teams in the organization
    teams = run_gh_api(f"/orgs/{org}/teams")
    if not teams:
        print("No teams found or failed to fetch.")
        return

    # Prepare data storage
    report_data = []

    # 2. Iterate through each team to extract members and repos
    for team in teams:
        team_name = team.get("name")
        team_slug = team.get("slug")
        print(f"Processing Team: {team_name}...")

        # Fetch Members for this team
        members = run_gh_api(f"/orgs/{org}/teams/{team_slug}/members")
        member_list = [m.get("login") for m in members] if members else ["No Members"]

        # Fetch Repositories associated with this team
        repos = run_gh_api(f"/orgs/{org}/teams/{team_slug}/repos")
        repo_urls = [r.get("html_url") for r in repos] if repos else ["No Repositories"]

        # Cross-join members and repos to keep a structural tabular format
        max_len = max(len(member_list), len(repo_urls))
        for i in range(max_len):
            member = member_list[i] if i < len(member_list) else ""
            repo_url = repo_urls[i] if i < len(repo_urls) else ""
            
            report_data.append({
                "Team Name": team_name,
                "Team Slug": team_slug,
                "Member Username": member,
                "Associated Repo URL": repo_url
            })

    # 3. Write data to a clean Comma Separated CSV (Native Excel compatibility)
    output_file = "github_teams_report.csv"
    fields = ["Team Name", "Team Slug", "Member Username", "Associated Repo URL"]
    
    with open(output_file, mode="w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=fields)
        writer.writeheader()
        writer.writerows(report_data)
        
    print(f"Report successfully generated and saved to {output_file}")

if __name__ == "__main__":
    main()
