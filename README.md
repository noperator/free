# free-cal

## Description

Cross-reference multiple calendars to find free time slots.

## Getting started

### Prerequisites

You'll need at least one local or remote ICS (iCalendar/vCalendar) file.

### Install

```
git clone https://github.com/noperator/free-cal
```

### Configure

```
python3 -m venv venv
source venv/bin/activate
python3 -m pip install -r requirements.txt
```

### Usage

```
for CAL_URL in \
    'https://calendar.google.com/calendar/ical/<ACCOUNT>/<CALENDAR>/basic.ics' \
    'https://outlook.office365.com/owa/calendar/<ACCOUNT>/<CALENDAR>/calendar.ics' \
    wget -P cal/ "$CAL_URL"
done

source venv/bin/activate
python3 main.py -f $(ls -t cal/ | head -n 3 | sed 's|^|cal/|')

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
