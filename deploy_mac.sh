#!/bin/bash

# Determine execution environment
is_github_action=false
if [ -n "$GITHUB_ACTIONS" ]; then
  is_github_action=true
  echo "Running in GitHub Actions environment"
else
  echo "Running in local environment"
  # For macOS, we don't need to modify PATH for nvm (commented out)
  # export PATH="$(find "$HOME/.nvm/versions/node" -maxdepth 1 -type d | sort -V | tail -n 1)/bin:$PATH"
fi

# Change to script directory
cd "$(dirname "$0")"

# Load environment variables
if [ -f .env ]; then
  source .env
else
  echo "Error: .env file not found"
  exit 1
fi

# Setup file and directory variables
TEXT_FILE='free.txt'
EXT_TEXT_FILE='ext.txt'
DEPLOY_DIR='deploy'
CAL_DIR='cal'

# Get date in ISO format - macOS compatible
if [[ "$OSTYPE" == "darwin"* ]]; then
  DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
else
  DATE=$(date -Iseconds -u | sed -E 's/\+00:00/Z/')
fi
echo "$DATE"

echo -e "last updated $DATE\n" >"$TEXT_FILE"
echo -e "last updated $DATE\n" >"$EXT_TEXT_FILE"

# Generate EXT_DIR if not present
if ! grep -q "^EXT_DIR=" .env; then
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS compatible random string generation
        echo "EXT_DIR=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1)" >>.env
    else
        echo "EXT_DIR=$(LC_ALL=C base64 </dev/urandom | tr -d '/+=' | head -c 32)" >>.env
    fi
    source .env # Re-source to get the new value
    echo "Generated new random EXT_DIR: $EXT_DIR"
fi

# Setup directories
mkdir -p "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/$EXT_DIR"
mkdir -p "$CAL_DIR"
rm -f "$DEPLOY_DIR"/* 2>/dev/null
rm -f "$DEPLOY_DIR/$EXT_DIR"/* 2>/dev/null
rm -f "$CAL_DIR"/* 2>/dev/null

# Download calendar files
if $is_github_action; then
  # In GitHub Actions, CAL_URLS comes from the secret as a multi-line string
  IFS=$'\n' read -d '' -ra CALENDAR_URLS <<< "$CAL_URLS"
  for CAL_URL in "${CALENDAR_URLS[@]}"; do
    # Remove any surrounding quotes if present
    CAL_URL=$(echo "$CAL_URL" | sed -e "s/^['\"]//;s/['\"]$//")
    wget -P "$CAL_DIR" "$CAL_URL"
  done
else
  # In local environment, CAL_URLS is already an array from .env
  # Ensure CAL_URLS is properly declared in .env
  if [ ${#CAL_URLS[@]} -eq 0 ]; then
    echo "Error: CAL_URLS array is empty or incorrectly formatted in .env"
    exit 1
  fi

  for CAL_URL in "${CAL_URLS[@]}"; do
    echo "Downloading: $CAL_URL"
    wget -P "$CAL_DIR" "$CAL_URL"
  done
fi

# Activate Python virtual environment
if $is_github_action; then
  source venv/bin/activate || echo "Failed to activate venv, continuing anyway"
else
  source venv/bin/activate
fi

# Get yesterday's date in YYYY-MM-DD format (macOS compatible)
if [[ "$OSTYPE" == "darwin"* ]]; then
  YESTERDAY=$(date -v-1d +"%Y-%m-%d")
else
  YESTERDAY=$(date -d 'yesterday' -Idate)
fi

# Generate standard free time - macOS compatible grep
python3 main.py \
    -s "$YESTERDAY" \
    -f $(find "$CAL_DIR" -type f -name '*.ics*') |
    grep -E '^$|^[A-Za-z]{3} +[0-9]{1,2} [A-Za-z]{3} @ +[0-9:]{4,5} [AP]M – +[0-9:]{4,5} [AP]M [A-Za-z0-9+_/-]{2,32} \([0-9hm ]+\)' \
        >>"$TEXT_FILE"

# Generate extended free time - macOS compatible grep
python3 main.py \
    -s "$YESTERDAY" \
    -w \
    --days 91 \
    -f $(find "$CAL_DIR" -type f -name '*.ics*') |
    grep -E '^$|^[A-Za-z]{3} +[0-9]{1,2} [A-Za-z]{3} @ +[0-9:]{4,5} [AP]M – +[0-9:]{4,5} [AP]M [A-Za-z0-9+_/-]{2,32} \([0-9hm ]+\)( +(morn|even|wknd( (morn|even))?))?$' \
        >>"$EXT_TEXT_FILE"

# Generate HTML files
cat >"$DEPLOY_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>free</title>
    <style>
        pre {
            font-family: monospace;
            white-space: pre-wrap;
            margin: 0;
        }
        body {
            background: #f5f5f5;
            padding: 20px;
            margin: 0;
        }
    </style>
</head>
<body>
    <pre>
$(cat "$TEXT_FILE")
    </pre>
</body>
</html>
EOF

cat >"$DEPLOY_DIR/$EXT_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>free (extended)</title>
    <style>
        pre, .filter-container {
            font-family: monospace;
            white-space: pre-wrap;
        }
        pre {
            margin: 0;
        }
        body {
            background: #f5f5f5;
            padding: 20px;
            margin: 0;
        }
    </style>
</head>
<body>
    <pre>
$(cat "$EXT_TEXT_FILE")
    </pre>
</body>
</html>
EOF

# Check if wrangler is installed, install if necessary
if ! command -v wrangler &> /dev/null; then
    echo "wrangler not found, installing..."
    npm install -g wrangler
fi

# Deploy using wrangler
wrangler pages deploy "$DEPLOY_DIR" --project-name="$PROJECT_NAME"