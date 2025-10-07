#!/usr/bin/env bash
set -euo pipefail

# create_ci_and_deploy.sh
# One-shot: create PR build workflow + deploy workflow, push branch, open & merge PR.
# Run from the repo root (~/ZERKER/sms-activate).

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ]; then
  echo "error: not inside a git repo. cd to repo root and run again."
  exit 1
fi
cd "$REPO_ROOT"

BRANCH="ci/deploy-workflows"
WORKFLOW_DIR=".github/workflows"

echo "-> Creating workflow directory: $WORKFLOW_DIR"
mkdir -p "$WORKFLOW_DIR"

echo "-> Writing PR CI workflow to $WORKFLOW_DIR/pr-ci.yml"
cat > "$WORKFLOW_DIR/pr-ci.yml" <<'YML'
name: PR — Build (frontend)

on:
  pull_request:
    branches: [ main ]

jobs:
  build:
    name: Build frontend
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Node setup
        uses: actions/setup-node@v4
        with:
          node-version: 18

      - name: Cache node modules
        uses: actions/cache@v4
        with:
          path: frontend/node_modules
          key: ${{ runner.os }}-node-${{ hashFiles('frontend/package-lock.json') }}
          restore-keys: |
            ${{ runner.os }}-node-

      - name: Install frontend deps
        working-directory: frontend
        run: npm ci

      - name: Build frontend
        working-directory: frontend
        run: npm run build

      - name: Upload build artifact (optional)
        uses: actions/upload-artifact@v4
        with:
          name: frontend-dist
          path: frontend/dist
YML

echo "-> Writing Deploy workflow to $WORKFLOW_DIR/deploy.yml"
cat > "$WORKFLOW_DIR/deploy.yml" <<'YML'
name: Deploy to Server

on:
  push:
    branches: [ main ]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Setup Node
        uses: actions/setup-node@v4
        with:
          node-version: 18

      - name: Install backend deps (optional)
        run: npm ci

      - name: Build frontend
        working-directory: frontend
        run: |
          npm ci
          npm run build

      - name: Copy files to server (scp)
        uses: appleboy/scp-action@v0.1.3
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ secrets.SSH_PORT }}
          source: |
            server.js
            package.json
            package-lock.json
            frontend/dist/**
          target: ${{ secrets.REMOTE_DIR }}

      - name: Remote deploy commands (npm install + pm2 restart)
        uses: appleboy/ssh-action@v0.1.7
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ secrets.SSH_PORT }}
          script: |
            set -e
            cd ${{ secrets.REMOTE_DIR }}
            npm ci --production || true
            pm2 restart ${{ secrets.PM2_PROCESS }} || pm2 start server.js --name ${{ secrets.PM2_PROCESS }}
            pm2 save
YML

# git ops: create branch, add, commit, push
echo "-> Creating branch $BRANCH and committing workflow files"
git fetch origin || true

# If branch exists locally, switch; otherwise create
if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
  git checkout "$BRANCH"
else
  git checkout -b "$BRANCH"
fi

git add "$WORKFLOW_DIR/pr-ci.yml" "$WORKFLOW_DIR/deploy.yml"
COMMIT_MSG="ci(workflows): add pr-ci and deploy workflows (auto)"
git commit -m "$COMMIT_MSG" || {
  echo "No changes to commit (maybe workflows already present)."
}

echo "-> Pushing branch $BRANCH to origin"
git push -u origin "$BRANCH"

# create PR via gh if available
if command -v gh >/dev/null 2>&1; then
  echo "-> Creating pull request via gh CLI"
  PR_URL="$(gh pr create --title "ci: add PR build & deploy workflows" --body "Adds PR build and automated deploy workflows. Requires repository secrets:\n\n- SSH_HOST\n- SSH_USER\n- SSH_PORT\n- SSH_PRIVATE_KEY\n- REMOTE_DIR\n- PM2_PROCESS\n\nSet those in repo Settings → Secrets before merging." --base main --head "$BRANCH" --web || true)"

  # If gh returned web URL or opened web, try to create non-web PR
  if [ -z "$PR_URL" ]; then
    # Attempt non-web creation
    gh pr create --title "ci: add PR build & deploy workflows" --body "Adds PR build and automated deploy workflows. Requires repository secrets:\n\n- SSH_HOST\n- SSH_USER\n- SSH_PORT\n- SSH_PRIVATE_KEY\n- REMOTE_DIR\n- PM2_PROCESS\n\nSet those in repo Settings → Secrets before merging." --base main --head "$BRANCH"
  fi

  # Try to merge immediately (auto)
  echo "-> Attempting to merge the PR automatically (requires permissions)"
  gh pr merge --auto --merge --delete-branch --subject "chore: add CI/deploy workflows" --body "Merging CI & deploy workflows" || {
    echo "Automatic merge failed or requires review. Open PR at: $(gh pr view --web || echo '(unable to open web view)')"
  }
else
  echo "gh CLI not found. PR created locally on branch $BRANCH and pushed."
  echo "Open a PR on GitHub from branch '$BRANCH' -> main and merge manually."
fi

echo "-> Done. If PR merged, the deploy workflow will run on pushes to main."
echo "-> Make sure the following repository secrets exist:"
echo "   SSH_HOST, SSH_USER, SSH_PORT, SSH_PRIVATE_KEY, REMOTE_DIR, PM2_PROCESS"

