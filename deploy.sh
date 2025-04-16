#!/bin/bash

# */5 * * * * /bin/bash -c '/home/noperator/free/deploy.sh &> /home/noperator/free/deploy.log'

export PATH="$(find "$HOME/.nvm/versions/node" -maxdepth 1 -type d | sort -V | tail -n 1)/bin:$PATH"

cd "$(dirname "$0")"

TEXT_FILE='free.txt'
EXT_TEXT_FILE='ext.txt'
DEPLOY_DIR='deploy'
CAL_DIR='cal'
DATE=$(date -Iseconds -u | sed -E 's/\+00:00/Z/')
echo "$DATE"

echo -e "last updated $DATE\n" >"$TEXT_FILE"

echo -e "last updated $DATE\n" >"$EXT_TEXT_FILE"

if ! grep -q "^EXT_DIR=" .env; then
    echo "EXT_DIR=$(LC_ALL=C base64 </dev/urandom | tr -d '/+=' | head -c 32)" >>.env
    echo "Generated new random EXT_DIR: $EXT_DIR"
fi

source .env

mkdir -p "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/$EXT_DIR"
mkdir -p "$CAL_DIR"
rm "$DEPLOY_DIR"/* 2>/dev/null
rm "$DEPLOY_DIR/$EXT_DIR"/* 2>/dev/null
rm "$CAL_DIR"/* 2>/dev/null

for CAL_URL in "${CAL_URLS[@]}"; do
    wget -P "$CAL_DIR" "$CAL_URL"
done

source venv/bin/activate

python3 main.py \
    -s $(date -Idate -d 'yesterday') \
    -f $(find "$CAL_DIR" -type f -name '*.ics*') |
    grep -E '^$|^[A-Za-z]{3} {1,2}[0-9]{1,2} [A-Za-z]{3} @ {1,2}[0-9:]{4,5} [AP]M – {1,2}[0-9:]{4,5} [AP]M [A-Za-z0-9+-/_]{2,32} \(([0-9]{1,2}h)?([0-9]{1,2}m)?\)' \
        >>"$TEXT_FILE"

python3 main.py \
    -s $(date -Idate -d 'yesterday') \
    -w \
    -f $(find "$CAL_DIR" -type f -name '*.ics*') |
    grep -E '^$|^[A-Za-z]{3} {1,2}[0-9]{1,2} [A-Za-z]{3} @ {1,2}[0-9:]{4,5} [AP]M – {1,2}[0-9:]{4,5} [AP]M [A-Za-z0-9+-/_]{2,32} \(([0-9]{1,2}h)?([0-9]{1,2}m)?\)( {1,4}(morn|even|wknd( (morn|even))?))?' \
        >>"$EXT_TEXT_FILE"

cat >"$DEPLOY_DIR/index.html" <<EOF
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>free</title>
    <style>
        pre {
            font-family: monospace;
            white-space: pre-wrap;
        }
        body {
            background: #f5f5f5;
            padding: 20px;
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
    <title>free (extended)</title>
    <style>
        pre {
            font-family: monospace;
            white-space: pre-wrap;
        }
        body {
            background: #f5f5f5;
            padding: 20px;
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

wrangler pages deploy "$DEPLOY_DIR" --project-name="$PROJECT_NAME"
