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
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
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
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>free (extended)</title>
    <style>
        pre, .filter-container {
            font-family: monospace;
            white-space: pre-wrap;
        }
        body {
            background: #f5f5f5;
            padding: 20px;
        }
        .filter-container {
            margin-bottom: 5px;
            line-height: 1;
        }
        .filter-row {
            display: flex;
            flex-wrap: wrap;
            margin-bottom: 0;
        }
        .filter-option {
            margin-right: 15px;
            margin-bottom: 0;
            display: flex;
            align-items: center;
        }
        .filter-option input[type="checkbox"] {
            width: 20px;
            height: 20px;
        }
        .filter-option label {
            margin-left: 8px;
            cursor: pointer;
        }
        .clear-button {
            background: none;
            border: none;
            font-family: monospace;
            cursor: pointer;
            text-decoration: underline;
            padding: 0;
            margin-top: 0;
        }
        #content {
            margin-top: 3px;
        }
        @media (max-width: 768px) {
            .filter-container {
                padding: 0;
            }
            .filter-option {
                margin-right: 12px;
                margin-bottom: 0;
            }
        }
        .hidden {
            display: none;
        }
    </style>
</head>
<body>
    <div class="filter-container">
        <div class="filter-row">
            <div class="filter-option">
                <input type="checkbox" id="filter-morn" checked>
                <label for="filter-morn">morning</label>
            </div>
            <div class="filter-option">
                <input type="checkbox" id="filter-daytime" checked>
                <label for="filter-daytime">daytime</label>
            </div>
            <div class="filter-option">
                <input type="checkbox" id="filter-even" checked>
                <label for="filter-even">evening</label>
            </div>
        </div>
        <div class="filter-row">
            <div class="filter-option">
                <input type="checkbox" id="filter-wkday" checked>
                <label for="filter-wkday">weekday</label>
            </div>
            <div class="filter-option">
                <input type="checkbox" id="filter-wknd" checked>
                <label for="filter-wknd">weekend</label>
            </div>
        </div>
        <div class="filter-row">
            <button id="clear-filters" class="clear-button">clear</button>
        </div>
    </div>
    <pre id="content">
$(cat "$EXT_TEXT_FILE")
    </pre>

    <script>
        document.addEventListener('DOMContentLoaded', function() {
            // Get filter checkboxes
            const wkndFilter = document.getElementById('filter-wknd');
            const wkdayFilter = document.getElementById('filter-wkday');
            const mornFilter = document.getElementById('filter-morn');
            const evenFilter = document.getElementById('filter-even');
            const daytimeFilter = document.getElementById('filter-daytime');
            const clearButton = document.getElementById('clear-filters');
            
            // Get content element
            const content = document.getElementById('content');
            
            // Store original content
            const originalContent = content.innerHTML;
            
            // Process the content initially to remove filter keywords
            function processInitialContent() {
                const lines = originalContent.split('\n');
                const processedLines = [];
                
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    
                    // Remove filter keywords from the line
                    line = line.replace(/\s+(wknd|morn|even)(\s+(morn|even))?/g, '');
                    
                    processedLines.push(line);
                }
                
                return processedLines.join('\n');
            }
            
            // Store processed content (without filter keywords)
            const processedContent = processInitialContent();
            content.innerHTML = processedContent;
            
            // Function to apply filters
            function applyFilters() {
                // Get original content with filter keywords for filtering
                const lines = originalContent.split('\n');
                const filteredLines = [];
                
                // Process each line
                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    let processedLine = line.replace(/\s+(wknd|morn|even)(\s+(morn|even))?/g, '');
                    
                    // Skip empty lines
                    if (line.trim() === '') {
                        filteredLines.push(processedLine);
                        continue;
                    }
                    
                    // Check if line has any filter keywords
                    const hasWknd = line.includes('wknd');
                    const hasWkday = !hasWknd; // If not weekend, it's a weekday
                    const hasMorn = line.includes('morn');
                    const hasEven = line.includes('even');
                    const hasDaytime = !hasMorn && !hasEven; // If not morning and not evening, it's daytime
                    
                    // Skip lines that don't match the current filters
                    if ((hasWknd && !wkndFilter.checked) ||
                        (hasWkday && !wkdayFilter.checked) ||
                        (hasMorn && !mornFilter.checked) ||
                        (hasEven && !evenFilter.checked) ||
                        (hasDaytime && !daytimeFilter.checked)) {
                        continue;
                    }
                    
                    filteredLines.push(processedLine);
                }
                
                // Update content
                content.innerHTML = filteredLines.join('\n');
            }
            
            // Function to clear all filters
            function clearFilters() {
                wkndFilter.checked = false;
                wkdayFilter.checked = false;
                mornFilter.checked = false;
                evenFilter.checked = false;
                daytimeFilter.checked = false;
                applyFilters();
            }
            
            // Add event listeners to checkboxes
            wkndFilter.addEventListener('change', applyFilters);
            wkdayFilter.addEventListener('change', applyFilters);
            mornFilter.addEventListener('change', applyFilters);
            evenFilter.addEventListener('change', applyFilters);
            daytimeFilter.addEventListener('change', applyFilters);
            clearButton.addEventListener('click', clearFilters);
            
            // Initial application of filters
            applyFilters();
        });
    </script>
</body>
</html>
EOF

wrangler pages deploy "$DEPLOY_DIR" --project-name="$PROJECT_NAME"
