#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

echo "Starting  for $ORG_NAME..."

# 1. Create CSV header rows
echo "Team Name,Team Slug,Member Username,Member Role,Associated Repository,Repo Permission" > org_teams_audit.csv

# 2. Fetch all teams in the organization (handles pagination up to 100 teams per page)
teams_json=$(gh api "orgs/$ORG_NAME/teams?per_page=100")

# 3. Loop over each team found
echo "$teams_json" | jq -c '.[]' | while read -r team; do
    team_name=$(echo "$team" | jq -r '.name')
    team_slug=$(echo "$team" | jq -r '.slug')
    
    echo "Processing Team: $team_name ($team_slug)..."
    
    # Fetch members of the current team
    members_json=$(gh api "orgs/$ORG_NAME/teams/$team_slug/members?per_page=100" --silent || echo "[]")
    
    # Fetch repositories tied to the current team
    repos_json=$(gh api "orgs/$ORG_NAME/teams/$team_slug/repos?per_page=100" --silent || echo "[]")
    
    # Format and map members/repos array counts
    member_count=$(echo "$members_json" | jq '. | length')
    repo_count=$(echo "$repos_json" | jq '. | length')

    # If the team is completely empty, log a placeholder line
    if [ "$member_count" -eq 0 ] && [ "$repo_count" -eq 0 ]; then
        echo "\"$team_name\",\"$team_slug\",\"No Members\",\"N/A\",\"No Repositories\",\"N/A\"" >> org_teams_audit.csv
        continue
    fi

    # Flatten out arrays to create cross-referenced line rows
    # Temporary files to cleanly read fields
    echo "$members_json" | jq -c '.[]' > temp_members.json || true
    echo "$repos_json" | jq -c '.[]' > temp_repos.json || true

    # Matrix combination layout processing
    if [ "$member_count" -gt 0 ] && [ "$repo_count" -eq 0 ]; then
        while read -r member; do
            m_user=$(echo "$member" | jq -r '.login')
            echo "\"$team_name\",\"$team_slug\",\"$m_user\",\"Member\",\"No Repositories\",\"N/A\"" >> org_teams_audit.csv
        done < temp_members.json
    elif [ "$member_count" -eq 0 ] && [ "$repo_count" -gt 0 ]; then
        while read -r repo; do
            r_name=$(echo "$repo" | jq -r '.full_name')
            r_perm=$(echo "$repo" | jq -r '.permissions | to_entries | map(select(.value == true)) | map(.key) | join("/")')
            echo "\"$team_name\",\"$team_slug\",\"No Members\",\"N/A\",\"$r_name\",\"$r_perm\"" >> org_teams_audit.csv
        done < temp_repos.json
    else
        # When both exist, report user-to-repo relational grid rows
        while read -r member; do
            m_user=$(echo "$member" | jq -r '.login')
            while read -r repo; do
                r_name=$(echo "$repo" | jq -r '.full_name')
                r_perm=$(echo "$repo" | jq -r '.permissions | to_entries | map(select(.value == true)) | map(.key) | join("/")')
                echo "\"$team_name\",\"$team_slug\",\"$m_user\",\"Member\",\"$r_name\",\"$r_perm\"" >> org_teams_audit.csv
            done < temp_repos.json
        done < temp_members.json
    fi

    # Clean up loop temp files
    rm -f temp_members.json temp_repos.json

done

echo "Audit completed successfully. Results saved to org_teams_audit.csv"
