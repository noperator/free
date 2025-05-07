# free

## Description

Cross-reference multiple calendars to find free time slots.

## Getting started

### Prerequisites

You'll need access to at least one local or remote ICS (iCalendar) file.

### Install

```
git clone https://github.com/noperator/free
```

### Configure

Install dependencies.

```
python3 -m venv venv
source venv/bin/activate
python3 -m pip install -r requirements.txt
```

If you want to use `deploy.sh` (for Cloudflare Pages), fill out `.env`.

```
CLOUDFLARE_ACCOUNT_ID=<>
CLOUDFLARE_API_TOKEN=<>
PROJECT_NAME=<>
CAL_URLS=(
    'https://calendar.google.com/calendar/ical/<ACCOUNT>/<CALENDAR>/basic.ics'
    'https://outlook.office365.com/owa/calendar/<ACCOUNT>/<CALENDAR>/calendar.ics'
)
```

### Usage

```
𝄢 python3 main.py -h
usage: main.py [-h] (-f FILES [FILES ...] | -u URLS [URLS ...] | -l) [-v] [-t TIMEZONE] [-s START_DATE] [-r] [-c] [--start START]
               [--end END] [-w] [--ext-start EXT_START] [--ext-end EXT_END] [--buffer BUFFER] [--min-duration MIN_DURATION]

Cross-reference multiple calendars to find free time slots

options:
  -h, --help            show this help message and exit
  -f, --files FILES [FILES ...]
                        Path to one or more iCal files
  -u, --urls URLS [URLS ...]
                        URLs to fetch iCal data from
  -l, --list-timezones  List all available timezones
  -v, --verbose         Enable verbose debug output
  -t, --timezone TIMEZONE
                        Target timezone for output (default: America/New_York)
  -s, --start-date START_DATE
                        Start date for free window search (format: YYYY-MM-DD)
  -r, --strict          Enforce working hours (10 AM - 5 PM) in both Eastern and target timezone
  -c, --compare         Show times in both local (ET) and target timezone
  --start START         Work start time in HH:MM format (default: 10:00)
  --end END             Work end time in HH:MM format (default: 17:00)
  -w, --extended        Include weekends and extended hours outside of regular working hours
  --ext-start EXT_START
                        Start time for extended hours in HH:MM format (default: 07:00)
  --ext-end EXT_END     End time for extended hours in HH:MM format (default: 20:00)
  --buffer BUFFER       Buffer time in minutes to add before and after busy events (default: 30)
  --min-duration MIN_DURATION
                        Minimum duration in minutes for free windows (default: 30)


Mon 27 Jan @ 10:00 AM – 11:00 AM EST (1h)
Mon 27 Jan @  4:15 PM –  5:00 PM EST (45m)
Tue 28 Jan @ 11:00 AM –  5:00 PM EST (6h)
Wed 29 Jan @ 10:00 AM – 11:00 AM EST (1h)
Wed 29 Jan @  2:30 PM –  5:00 PM EST (2h30m)
Thu 30 Jan @ 10:00 AM – 11:00 AM EST (1h)
Thu 30 Jan @  1:30 PM –  5:00 PM EST (3h30m)
Fri 31 Jan @ 10:00 AM – 11:00 AM EST (1h)
Fri 31 Jan @  1:00 PM –  5:00 PM EST (4h)

Mon  3 Feb @  3:00 PM –  5:00 PM EST (2h)
Tue  4 Feb @ 11:00 AM –  2:00 PM EST (3h)
Tue  4 Feb @  4:00 PM –  5:00 PM EST (1h)
Wed  5 Feb @ 10:00 AM – 11:00 AM EST (1h)
Wed  5 Feb @ 12:30 PM –  5:00 PM EST (4h30m)
Thu  6 Feb @ 10:00 AM – 11:00 AM EST (1h)
Thu  6 Feb @ 12:30 PM –  5:00 PM EST (4h30m)
Fri  7 Feb @ 10:00 AM – 11:00 AM EST (1h)
Fri  7 Feb @  1:00 PM –  5:00 PM EST (4h)
```

## Back matter

### See also

- [Zero-knowledge appointment scheduler](https://noperator.dev/posts/zero-knowledge-appointment-scheduler/)

### To-do

- [ ] document getting calendar links for Outlook, Google
- [ ] dynamically determine default timezone (vs. hardcoding ET)
- [x] min duration as cli opt
- [x] min buffer as cli opt
- [ ] in web ui, allow specifying local timezone
- [x] lookahead as cli opt
- [ ] containerize

## Automated Deployment

This repository includes GitHub Actions workflow to automatically deploy your calendar:

### GitHub Actions Setup

1. Fork or clone this repository
2. Go to your repository's Settings > Secrets and variables > Actions
3. Add the following secrets:
   - `CLOUDFLARE_ACCOUNT_ID`: Your Cloudflare account ID
   - `CLOUDFLARE_API_TOKEN`: Your Cloudflare API token
   - `PROJECT_NAME`: Your Cloudflare Pages project name
   - `CAL_URLS`: Your calendar URLs (one per line, enclosed in single quotes)

The workflow will run automatically every day at 4:00 AM UTC, or you can trigger it manually from the Actions tab.

In your GitHub repository:

Go to Settings > Secrets and variables > Actions
Create the following secrets:
- `CLOUDFLARE_ACCOUNT_ID`: Your Cloudflare account ID
- `CLOUDFLARE_API_TOKEN`: Your Cloudflare API token
- `PROJECT_NAME`: Your Cloudflare Pages project name
- `CAL_URLS`: Your calendar URLs as a formatted string (maintain proper quoting)
  - Example for the `CAL_URLS` secret:
    ```bash
    'https://calendar.google.com/calendar/ical/your-account/basic.ics'
    'https://outlook.office365.com/owa/calendar/your-account/calendar.ics'
    ```