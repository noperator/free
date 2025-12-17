#!/bin/bash

# */5 * * * * /bin/bash -c '/home/noperator/free/deploy.sh &> /home/noperator/free/deploy.log'

if [[ "$OSTYPE" == 'linux-gnu' ]]; then
    # Sometimes wrangler will complain if it can't find latest Node.js
    export PATH="$($(which find) "$HOME/.nvm/versions/node" -maxdepth 1 -type d | sort -V | tail -n 1)/bin:$PATH"
fi

cd "$(dirname "$0")"

DEPLOY_DIR='deploy'
CAL_DIR='cal'
TXT_DIR='txt'

# Format: upd 17 Dec @  2:00 PM
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    DATE=$(TZ='America/New_York' date '+upd %e %b @ %l:%M %p')
else
    # Linux
    DATE=$(TZ='America/New_York' date '+upd %e %b @ %l:%M %p')
fi
echo "$DATE"

if ! grep -q "^EXT_DIR=" .env; then
    echo "EXT_DIR=$(LC_ALL=C base64 </dev/urandom | tr -d '/+=' | head -c 32)" >>.env
    echo "Generated new random EXT_DIR: $EXT_DIR"
fi

source .env

# Timezone mapping: abbreviation -> IANA timezone
declare -A TIMEZONES=(
    ["et"]="America/New_York"
    ["ct"]="America/Chicago"
    ["mt"]="America/Denver"
    ["pt"]="America/Los_Angeles"
    ["akt"]="America/Anchorage"
    ["hst"]="Pacific/Honolulu"
    ["gmt"]="Europe/London"
    ["cet"]="Europe/Paris"
    ["ist"]="Asia/Kolkata"
    ["jst"]="Asia/Tokyo"
    ["aet"]="Australia/Sydney"
    ["utc"]="UTC"
)

mkdir -p "$DEPLOY_DIR"
mkdir -p "$DEPLOY_DIR/$EXT_DIR"
mkdir -p "$DEPLOY_DIR/tz"
mkdir -p "$DEPLOY_DIR/$EXT_DIR/tz"
mkdir -p "$CAL_DIR"
mkdir -p "$TXT_DIR"
rm "$DEPLOY_DIR"/*.html 2>/dev/null
rm "$DEPLOY_DIR/tz"/* 2>/dev/null
rm "$DEPLOY_DIR/$EXT_DIR"/*.html 2>/dev/null
rm "$DEPLOY_DIR/$EXT_DIR/tz"/* 2>/dev/null
rm "$CAL_DIR"/* 2>/dev/null
rm "$TXT_DIR"/* 2>/dev/null

# Handle calendar downloads for both local and GitHub Actions
if [[ -n "$GITHUB_ACTIONS" ]]; then
    # In GitHub Actions, CAL_URLS comes from the secret as a multi-line string
    IFS=$'\n' read -d '' -ra CALENDAR_URLS <<<"$CAL_URLS"
    for CAL_URL in "${CALENDAR_URLS[@]}"; do
        # Remove any surrounding quotes if present
        CAL_URL=$(echo "$CAL_URL" | sed -e "s/^['\"]//;s/['\"]$//")
        wget -P "$CAL_DIR" "$CAL_URL"
    done
else
    # Local environment - CAL_URLS is an array from .env
    for CAL_URL in "${CAL_URLS[@]}"; do
        wget -P "$CAL_DIR" "$CAL_URL"
    done
fi

source venv/bin/activate

# Cross-platform yesterday date
if [[ "$OSTYPE" == "darwin"* ]]; then
    YESTERDAY=$($(which date) -v -1d -Idate)
else
    YESTERDAY=$($(which date) -d 'yesterday' -Idate)
fi

# Generate regular free time files for each timezone
for tz_abbr in "${!TIMEZONES[@]}"; do
    tz_name="${TIMEZONES[$tz_abbr]}"
    echo "Generating free time for $tz_abbr ($tz_name)..."

    python3 main.py \
        -s "$YESTERDAY" \
        -t "$tz_name" \
        -f $($(which find) "$CAL_DIR" -type f -name '*.ics*') | \
        grep -E '^$|^[A-Za-z]{3} {1,2}[0-9]{1,2} [A-Za-z]{3} @ {1,2}[0-9:]{4,5} [AP]M – {1,2}[0-9:]{4,5} [AP]M [A-Za-z0-9+/_-]{2,32} \(([0-9]{1,2}h)?([0-9]{1,2}m)?\)' \
        > "$TXT_DIR/${tz_abbr}.txt"

    # Prepend timestamp
    echo -e "$DATE\n$(cat $TXT_DIR/${tz_abbr}.txt)" > "$TXT_DIR/${tz_abbr}.txt"
done

# Generate extended free time files for each timezone
for tz_abbr in "${!TIMEZONES[@]}"; do
    tz_name="${TIMEZONES[$tz_abbr]}"
    echo "Generating extended free time for $tz_abbr ($tz_name)..."

    python3 main.py \
        -s "$YESTERDAY" \
        -w \
        --days 91 \
        -t "$tz_name" \
        -f $($(which find) "$CAL_DIR" -type f -name '*.ics*') | \
        grep -E '^$|^[A-Za-z]{3} {1,2}[0-9]{1,2} [A-Za-z]{3} @ {1,2}[0-9:]{4,5} [AP]M – {1,2}[0-9:]{4,5} [AP]M [A-Za-z0-9+/_-]{2,32} \(([0-9]{1,2}h)?([0-9]{1,2}m)?\)( {1,4}(morn|even|wknd( (morn|even))?))?' \
        > "$TXT_DIR/ext-${tz_abbr}.txt"

    # Prepend timestamp
    echo -e "$DATE\n$(cat $TXT_DIR/ext-${tz_abbr}.txt)" > "$TXT_DIR/ext-${tz_abbr}.txt"
done

# Copy timezone files to deploy directories
for tz_abbr in "${!TIMEZONES[@]}"; do
    cp "$TXT_DIR/${tz_abbr}.txt" "$DEPLOY_DIR/tz/"
    cp "$TXT_DIR/ext-${tz_abbr}.txt" "$DEPLOY_DIR/$EXT_DIR/tz/${tz_abbr}.txt"
done

cat >"$DEPLOY_DIR/index.html" <<'EOF'
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
        .tz-container {
            font-family: monospace;
            margin-bottom: 10px;
        }
        .tz-container select {
            font-family: monospace;
            font-size: 14px;
            padding: 2px 5px;
        }
    </style>
</head>
<body>
    <div class="tz-container">
        <label for="tz-select">tz:</label>
        <select id="tz-select">
            <option value="et">ET</option>
            <option value="ct">CT</option>
            <option value="mt">MT</option>
            <option value="pt">PT</option>
            <option value="akt">AKT</option>
            <option value="hst">HST</option>
            <option value="gmt">GMT</option>
            <option value="cet">CET</option>
            <option value="ist">IST</option>
            <option value="jst">JST</option>
            <option value="aet">AET</option>
            <option value="utc">UTC</option>
        </select>
    </div>
    <pre id="content">Loading...</pre>

    <script>
        const timezoneMap = {
            'America/New_York': 'et',
            'America/Detroit': 'et',
            'America/Indiana/Indianapolis': 'et',
            'America/Chicago': 'ct',
            'America/Denver': 'mt',
            'America/Phoenix': 'mt',
            'America/Los_Angeles': 'pt',
            'America/Anchorage': 'akt',
            'Pacific/Honolulu': 'hst',
            'Europe/London': 'gmt',
            'Europe/Paris': 'cet',
            'Europe/Berlin': 'cet',
            'Europe/Rome': 'cet',
            'Europe/Madrid': 'cet',
            'Asia/Kolkata': 'ist',
            'Asia/Calcutta': 'ist',
            'Asia/Tokyo': 'jst',
            'Australia/Sydney': 'aet',
            'Australia/Melbourne': 'aet',
            'UTC': 'utc',
            'Etc/UTC': 'utc'
        };

        const validTimezones = ['et', 'ct', 'mt', 'pt', 'akt', 'hst', 'gmt', 'cet', 'ist', 'jst', 'aet', 'utc'];

        function detectTimezone() {
            try {
                const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
                return timezoneMap[tz] || 'et';
            } catch (e) {
                return 'et';
            }
        }

        function getTimezoneFromUrl() {
            const params = new URLSearchParams(window.location.search);
            const tz = params.get('tz');
            if (tz && validTimezones.includes(tz.toLowerCase())) {
                return tz.toLowerCase();
            }
            return null;
        }

        function updateUrl(tz) {
            const params = new URLSearchParams(window.location.search);
            params.set('tz', tz);
            const newUrl = window.location.pathname + '?' + params.toString();
            window.history.pushState({}, '', newUrl);
        }

        async function loadTimezone(tz) {
            const content = document.getElementById('content');
            try {
                const response = await fetch('tz/' + tz + '.txt');
                if (!response.ok) throw new Error('Failed to load');
                const text = await response.text();
                content.textContent = text;
            } catch (e) {
                content.textContent = 'Error loading timezone data';
            }
        }

        document.addEventListener('DOMContentLoaded', function() {
            const select = document.getElementById('tz-select');

            // Determine initial timezone
            let initialTz = getTimezoneFromUrl();
            if (!initialTz) {
                initialTz = detectTimezone();
                updateUrl(initialTz);
            }

            // Set dropdown and load content
            select.value = initialTz;
            loadTimezone(initialTz);

            // Handle dropdown change
            select.addEventListener('change', function() {
                const tz = this.value;
                updateUrl(tz);
                loadTimezone(tz);
            });

            // Handle browser back/forward
            window.addEventListener('popstate', function() {
                const tz = getTimezoneFromUrl() || detectTimezone();
                select.value = tz;
                loadTimezone(tz);
            });
        });
    </script>
</body>
</html>
EOF

cat >"$DEPLOY_DIR/$EXT_DIR/index.html" <<'EOF'
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>free (extended)</title>
    <style>
        pre, .filter-container, .tz-container {
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
        .tz-container {
            margin-bottom: 10px;
        }
        .tz-container select {
            font-family: monospace;
            font-size: 14px;
            padding: 2px 5px;
        }
        .filter-container {
            margin-bottom: 5px;
            line-height: 0.5;
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
    <div class="tz-container">
        <label for="tz-select">tz:</label>
        <select id="tz-select">
            <option value="et">ET</option>
            <option value="ct">CT</option>
            <option value="mt">MT</option>
            <option value="pt">PT</option>
            <option value="akt">AKT</option>
            <option value="hst">HST</option>
            <option value="gmt">GMT</option>
            <option value="cet">CET</option>
            <option value="ist">IST</option>
            <option value="jst">JST</option>
            <option value="aet">AET</option>
            <option value="utc">UTC</option>
        </select>
    </div>
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
    <pre id="content">Loading...</pre>

    <script>
        const timezoneMap = {
            'America/New_York': 'et',
            'America/Detroit': 'et',
            'America/Indiana/Indianapolis': 'et',
            'America/Chicago': 'ct',
            'America/Denver': 'mt',
            'America/Phoenix': 'mt',
            'America/Los_Angeles': 'pt',
            'America/Anchorage': 'akt',
            'Pacific/Honolulu': 'hst',
            'Europe/London': 'gmt',
            'Europe/Paris': 'cet',
            'Europe/Berlin': 'cet',
            'Europe/Rome': 'cet',
            'Europe/Madrid': 'cet',
            'Asia/Kolkata': 'ist',
            'Asia/Calcutta': 'ist',
            'Asia/Tokyo': 'jst',
            'Australia/Sydney': 'aet',
            'Australia/Melbourne': 'aet',
            'UTC': 'utc',
            'Etc/UTC': 'utc'
        };

        const validTimezones = ['et', 'ct', 'mt', 'pt', 'akt', 'hst', 'gmt', 'cet', 'ist', 'jst', 'aet', 'utc'];

        function detectTimezone() {
            try {
                const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
                return timezoneMap[tz] || 'et';
            } catch (e) {
                return 'et';
            }
        }

        function getTimezoneFromUrl() {
            const params = new URLSearchParams(window.location.search);
            const tz = params.get('tz');
            if (tz && validTimezones.includes(tz.toLowerCase())) {
                return tz.toLowerCase();
            }
            return null;
        }

        // Store original content for filtering
        let originalContent = '';

        async function loadTimezone(tz) {
            const content = document.getElementById('content');
            try {
                const response = await fetch('tz/' + tz + '.txt');
                if (!response.ok) throw new Error('Failed to load');
                const text = await response.text();
                originalContent = text;
                applyFilters(false);
            } catch (e) {
                content.textContent = 'Error loading timezone data';
            }
        }

        document.addEventListener('DOMContentLoaded', function() {
            const tzSelect = document.getElementById('tz-select');
            const wkndFilter = document.getElementById('filter-wknd');
            const wkdayFilter = document.getElementById('filter-wkday');
            const mornFilter = document.getElementById('filter-morn');
            const evenFilter = document.getElementById('filter-even');
            const daytimeFilter = document.getElementById('filter-daytime');
            const clearButton = document.getElementById('clear-filters');
            const content = document.getElementById('content');

            function updateUrlParams() {
                const params = new URLSearchParams();

                // Always include timezone
                params.set('tz', tzSelect.value);

                // Build time of day parameter
                const todFilters = [];
                if (mornFilter.checked) todFilters.push('morn');
                if (daytimeFilter.checked) todFilters.push('dytm');
                if (evenFilter.checked) todFilters.push('even');

                // Build day of week parameter
                const dowFilters = [];
                if (wkdayFilter.checked) dowFilters.push('wkdy');
                if (wkndFilter.checked) dowFilters.push('wknd');

                // Only add parameters if they're not all selected (default state)
                if (todFilters.length > 0 && todFilters.length < 3) {
                    params.set('tod', todFilters.join(','));
                }

                if (dowFilters.length > 0 && dowFilters.length < 2) {
                    params.set('dow', dowFilters.join(','));
                }

                const newUrl = window.location.pathname + '?' + params.toString();
                window.history.pushState({}, '', newUrl);
            }

            function applyFilters(updateUrl = true) {
                const lines = originalContent.split('\n');
                const filteredLines = [];

                for (let i = 0; i < lines.length; i++) {
                    const line = lines[i];
                    let processedLine = line.replace(/\s+(wknd|morn|even)(\s+(morn|even))?/g, '');

                    if (line.trim() === '') {
                        filteredLines.push(processedLine);
                        continue;
                    }

                    const hasWknd = line.includes('wknd');
                    const hasWkday = !hasWknd;
                    const hasMorn = line.includes('morn');
                    const hasEven = line.includes('even');
                    const hasDaytime = !hasMorn && !hasEven;

                    if ((hasWknd && !wkndFilter.checked) ||
                        (hasWkday && !wkdayFilter.checked) ||
                        (hasMorn && !mornFilter.checked) ||
                        (hasEven && !evenFilter.checked) ||
                        (hasDaytime && !daytimeFilter.checked)) {
                        continue;
                    }

                    filteredLines.push(processedLine);
                }

                let result = filteredLines.join('\n');
                result = result.replace(/\n\s*\n\s*\n+/g, '\n\n');
                result = result.replace(/^\s*\n+/g, '');

                content.textContent = result;

                if (updateUrl) {
                    updateUrlParams();
                }
            }

            function loadFiltersFromUrl() {
                const params = new URLSearchParams(window.location.search);

                wkndFilter.checked = true;
                wkdayFilter.checked = true;
                mornFilter.checked = true;
                evenFilter.checked = true;
                daytimeFilter.checked = true;

                if (params.has('tod')) {
                    const todFilters = params.get('tod').split(',');
                    mornFilter.checked = todFilters.includes('morn');
                    daytimeFilter.checked = todFilters.includes('dytm');
                    evenFilter.checked = todFilters.includes('even');
                }

                if (params.has('dow')) {
                    const dowFilters = params.get('dow').split(',');
                    wkdayFilter.checked = dowFilters.includes('wkdy');
                    wkndFilter.checked = dowFilters.includes('wknd');
                }
            }

            function clearFilters() {
                wkndFilter.checked = false;
                wkdayFilter.checked = false;
                mornFilter.checked = false;
                evenFilter.checked = false;
                daytimeFilter.checked = false;
                applyFilters();
            }

            // Determine initial timezone
            let initialTz = getTimezoneFromUrl();
            if (!initialTz) {
                initialTz = detectTimezone();
            }

            // Set dropdown and load filters from URL
            tzSelect.value = initialTz;
            loadFiltersFromUrl();

            // Load content (this will also apply filters)
            loadTimezone(initialTz).then(() => {
                updateUrlParams();
            });

            // Handle timezone dropdown change
            tzSelect.addEventListener('change', function() {
                loadTimezone(this.value);
                updateUrlParams();
            });

            // Add event listeners to filter checkboxes
            wkndFilter.addEventListener('change', applyFilters);
            wkdayFilter.addEventListener('change', applyFilters);
            mornFilter.addEventListener('change', applyFilters);
            evenFilter.addEventListener('change', applyFilters);
            daytimeFilter.addEventListener('change', applyFilters);
            clearButton.addEventListener('click', clearFilters);

            // Handle browser back/forward
            window.addEventListener('popstate', function() {
                const tz = getTimezoneFromUrl() || detectTimezone();
                tzSelect.value = tz;
                loadFiltersFromUrl();
                loadTimezone(tz);
            });
        });
    </script>
</body>
</html>
EOF

# Install wrangler if needed
if ! command -v wrangler &>/dev/null; then
    echo "wrangler not found, installing..." >&2
    npm install -g wrangler
fi

wrangler pages deploy "$DEPLOY_DIR" --project-name="$PROJECT_NAME"
