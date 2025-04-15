from datetime import datetime, timedelta, time
from icalendar import Calendar
from zoneinfo import ZoneInfo, available_timezones
from typing import List, Tuple
import argparse
import requests
from pathlib import Path
import sys
import holidays
from operator import itemgetter

def parse_calendar(ical_data: str, verbose: bool = False, start_date: datetime = None) -> List[Tuple[datetime, datetime, str]]:
    """Parse iCal data and return list of (start, end, status) tuples in ET."""
    cal = Calendar.from_ical(ical_data)
    events = []
    debug_events = []
    et_tz = ZoneInfo("America/New_York")

    # Use provided start_date or default to now
    search_start = start_date if start_date else datetime.now(et_tz)
    cutoff_date = search_start + timedelta(days=31)

    # Track moved instances by their UID and original date
    moved_instances = {}

    # First pass: collect all moved instances
    for event in cal.walk('vevent'):
        recurrence_id = event.get('recurrence-id')
        if recurrence_id:
            uid = event.get('uid')
            # Store the original date for this moved instance
            if uid not in moved_instances:
                moved_instances[uid] = set()
            # Convert to ET for consistency
            original_date = recurrence_id.dt
            if isinstance(original_date, datetime):
                if original_date.tzinfo:
                    original_date = original_date.astimezone(et_tz)
                else:
                    original_date = original_date.replace(tzinfo=et_tz)
                moved_instances[uid].add(original_date)

    # Track modified events for table display
    modified_events = []

    for event in cal.walk('vevent'):
        # Add debug printing for recurring event modifications
        recurrence_id = event.get('recurrence-id')
        if recurrence_id and verbose:
            # Convert recurrence_id to Eastern Time for display
            original_date = recurrence_id.dt
            if isinstance(original_date, datetime):
                if original_date.tzinfo:
                    original_date = original_date.astimezone(et_tz)
                else:
                    original_date = original_date.replace(tzinfo=et_tz)

            # Convert start time to Eastern Time for display
            event_start = event.get('dtstart').dt
            if isinstance(event_start, datetime):
                if event_start.tzinfo:
                    event_start = event_start.astimezone(et_tz)
                else:
                    event_start = event_start.replace(tzinfo=et_tz)

            # Store for table display
            modified_events.append((
                original_date,
                event_start,
                event.get('uid')
            ))

    for event in cal.walk('vevent'):
        # Add debug printing for recurring event modifications
        recurrence_id = event.get('recurrence-id')
        if recurrence_id and verbose:
            # Convert recurrence_id to Eastern Time for display
            original_date = recurrence_id.dt
            if isinstance(original_date, datetime):
                if original_date.tzinfo:
                    original_date = original_date.astimezone(et_tz)
                else:
                    original_date = original_date.replace(tzinfo=et_tz)

            # Convert start time to Eastern Time for display
            event_start = event.get('dtstart').dt
            if isinstance(event_start, datetime):
                if event_start.tzinfo:
                    event_start = event_start.astimezone(et_tz)
                else:
                    event_start = event_start.replace(tzinfo=et_tz)

            print(f"Modified occurrence found:", file=sys.stderr)
            print(f"  Original date: {original_date}", file=sys.stderr)
            print(f"  Event ID: {event.get('uid')}", file=sys.stderr)
            print(f"  New time: {event_start}", file=sys.stderr)

        # Skip broken events
        if not event.get('dtend'):
            print("[*] no dtend:", event.get('uid'), file=sys.stderr)
            continue

        # Get start and end times
        start = event.get('dtstart').dt
        end = event.get('dtend').dt
        event_id = event.get('uid', 'NO-UID')

        # Handle all-day events (date objects instead of datetime)
        if isinstance(start, datetime):
            # Convert to ET
            if start.tzinfo:
                start = start.astimezone(et_tz)
            else:
                start = start.replace(tzinfo=et_tz)

            if end.tzinfo:
                end = end.astimezone(et_tz)
            else:
                end = end.replace(tzinfo=et_tz)

            # Skip events after cutoff date
            if start > cutoff_date:
                continue

            # Handle recurring events
            if event.get('rrule'):
                rule = event.get('rrule')
                if isinstance(rule, dict):
                    # Get the rule string and explicitly set TZID
                    rule_str = event.get('rrule').to_ical().decode('utf-8')

                    # Create a new start time in ET for rrule
                    start_et = start.astimezone(et_tz)

                    # Use dateutil.rrule with explicit timezone handling
                    from dateutil.rrule import rrulestr
                    dates = list(rrulestr(rule_str, dtstart=start_et, forceset=True).between(
                        search_start,
                        cutoff_date
                    ))

                    # Handle exclusions
                    exdates = event.get('exdate')
                    if exdates:
                        if not isinstance(exdates, list):
                            exdates = [exdates]
                        excluded = set()
                        for exdate in exdates:
                            if hasattr(exdate, 'dts'):
                                for dt in exdate.dts:
                                    # Convert exclusion dates to ET
                                    ex_dt = dt.dt
                                    if isinstance(ex_dt, datetime):
                                        if ex_dt.tzinfo:
                                            ex_dt = ex_dt.astimezone(et_tz)
                                        else:
                                            ex_dt = ex_dt.replace(tzinfo=et_tz)
                                        excluded.add(ex_dt)
                        dates = [d for d in dates if d not in excluded]

                    # Filter out any dates that correspond to moved instances
                    uid = event.get('uid')
                    if uid in moved_instances:
                        dates = [d for d in dates if d not in moved_instances[uid]]

                    for d in dates:
                        event_start = d
                        event_end = d + (end - start)
                        debug_events.append((
                            event_start,
                            event_end,
                            event.get('summary', 'No title'),
                            event.get('status', 'BUSY'),
                            'recurring',
                            event_id
                        ))
                        events.append((event_start, event_end, event.get('status', 'BUSY')))
            else:
                # Single event
                if start >= search_start and start <= cutoff_date:
                    debug_events.append((
                        start,
                        end,
                        event.get('summary', 'No title'),
                        event.get('status', 'BUSY'),
                        'single',
                        event_id
                    ))
                    events.append((start, end, event.get('status', 'BUSY')))
        else:  # Handle all-day events
            # Convert date to datetime at start of day
            start = datetime.combine(start, time(0, 0), tzinfo=et_tz)
            end = datetime.combine(end, time(0, 0), tzinfo=et_tz)

            # Skip events after cutoff date
            if start > cutoff_date:
                continue

            if start >= search_start and start <= cutoff_date:
                debug_events.append((
                    start,
                    end,
                    event.get('summary', 'No title'),
                    event.get('status', 'BUSY'),
                    'all-day',
                    event_id
                ))
                events.append((start, end, event.get('status', 'BUSY')))

    # Before sorting debug_events, add holidays
    if verbose:
        et_tz = ZoneInfo("America/New_York")
        now = datetime.now(et_tz)
        end_date = now + timedelta(days=31)
        us_holidays_list = get_us_holidays(now, end_date)

        for holiday_date, holiday_name in us_holidays_list:
            # Add full-day holiday events to debug output
            debug_events.append((
                holiday_date,
                holiday_date + timedelta(days=1),
                holiday_name,  # Use specific holiday name
                "BUSY",
                "holiday",
                holiday_name  # Show holiday name in ID column
            ))

    # Sort by start time first
    debug_events.sort(key=lambda x: x[0])

    # Only print debug table if verbose
    if verbose:
        # Print modified events table first if there are any modifications
        if modified_events:
            print("\nModified Recurring Events:", file=sys.stderr)
            print(f"{'Original Time':<25} {'New Time':<25} {'Event ID'}", file=sys.stderr)
            print("-" * 80, file=sys.stderr)

            # Sort by original date
            modified_events.sort(key=lambda x: x[0])

            for original, new, event_id in modified_events:
                print(
                    f"{original.strftime('%Y-%m-%d %H:%M:%S%z'):<25} "
                    f"{new.strftime('%Y-%m-%d %H:%M:%S%z'):<25} "
                    f"{event_id}",
                    file=sys.stderr
                )
            print(file=sys.stderr)  # Add blank line after table

        # Print main appointments table
        print(f"{'Type':<10} {'Start':<25} {'End':<25} {'ID'}", file=sys.stderr)
        print("-" * 80, file=sys.stderr)

        # Print events in columns
        for start, end, summary, _, event_type, event_id in debug_events:
            # For holidays, print the summary instead of the ID
            display_id = summary if event_type == "holiday" else event_id
            print(
                f"{event_type:<10} "
                f"{start.strftime('%Y-%m-%d %H:%M:%S%z'):<25} "
                f"{end.strftime('%Y-%m-%d %H:%M:%S%z'):<25} "
                f"{display_id}",
                file=sys.stderr
            )

    return events

def get_us_holidays(start_date: datetime, end_date: datetime) -> List[Tuple[datetime, str]]:
    """Get list of US federal holidays between start and end date with their names."""
    us_holidays = holidays.US()
    holidays_list = []

    current = start_date
    while current <= end_date:
        if current.date() in us_holidays:
            # Convert date to datetime at start of day and include holiday name
            holiday = current.replace(hour=0, minute=0, second=0, microsecond=0)
            holiday_name = us_holidays.get(current.date())
            holidays_list.append((holiday, holiday_name))
        current += timedelta(days=1)

    return holidays_list

def find_free_windows(events: List[Tuple[datetime, datetime, str]], 
                     buffer_mins: int = 30,
                     start_date: datetime = None,
                     target_tz: str = "America/New_York",
                     strict: bool = False,
                     work_start: time = time(10, 0),
                     work_end: time = time(17, 0),
                     extended: bool = False,
                     ext_start: time = time(7, 0),
                     ext_end: time = time(20, 0),
                     min_duration: int = 30) -> List[Tuple[datetime, datetime, bool]]:

    # print(f"work_start: {work_start}, work_end: {work_end}")

    """Find free time windows between 10am-5pm ET, excluding holidays."""
    et_tz = ZoneInfo("America/New_York")
    target_timezone = ZoneInfo(target_tz)
    now = start_date if start_date else datetime.now(et_tz)
    end_date = now + timedelta(days=30)

    # Get holidays
    holiday_list = get_us_holidays(now, end_date)
    # Convert holidays to a set of dates for faster lookup
    holiday_dates = {holiday[0].date() for holiday in holiday_list}

    # Initialize with working hours for each day
    free_windows = []
    current = (now + timedelta(days=1)).replace(hour=10, minute=0, second=0, microsecond=0)

    # Define early and late hours for extended mode
    early_start = ext_start
    early_end = work_start
    late_start = work_end
    late_end = ext_end

    while current < end_date:
        is_weekend = current.weekday() >= 5  # Saturday or Sunday
        is_extended_slot = False
        
        # Regular weekday slots (Mon-Fri)
        if current.weekday() < 5 and current.date() not in holiday_dates:
            day_start = current.replace(hour=work_start.hour, minute=work_start.minute)
            day_end = current.replace(hour=work_end.hour, minute=work_end.minute)

            if strict:
                # Convert to target timezone to check working hours there
                target_start = day_start.astimezone(target_timezone)
                target_end = day_end.astimezone(target_timezone)

                # Adjust window to respect working hours in both timezones
                # Start time should be no earlier than 10 AM in either timezone
                et_start = day_start
                target_start = target_start.replace(
                    hour=work_start.hour,
                    minute=work_start.minute
                )
                effective_start = max(et_start, target_start.astimezone(et_tz))

                # End time should be no later than 5 PM in either timezone
                et_end = day_end
                target_end = target_end.replace(
                    hour=work_end.hour,
                    minute=work_end.minute
                )
                effective_end = min(et_end, target_end.astimezone(et_tz))

                # Only add the window if there's actually time available
                if effective_start < effective_end:
                    free_windows.append((effective_start, effective_end, is_extended_slot))
            else:
                free_windows.append((day_start, day_end, is_extended_slot))
        
        # Extended mode: add weekend, early, and late slots
        if extended:
            # Add weekend slots (if it's a weekend)
            if is_weekend and current.date() not in holiday_dates:
                is_extended_slot = True
                day_start = current.replace(hour=work_start.hour, minute=work_start.minute)
                day_end = current.replace(hour=work_end.hour, minute=work_end.minute)
                
                if strict:
                    # Convert to target timezone to check working hours there
                    target_start = day_start.astimezone(target_timezone)
                    target_end = day_end.astimezone(target_timezone)

                    # Adjust window to respect working hours in both timezones
                    et_start = day_start
                    target_start = target_start.replace(
                        hour=work_start.hour,
                        minute=work_start.minute
                    )
                    effective_start = max(et_start, target_start.astimezone(et_tz))

                    # End time should be no later than 5 PM in either timezone
                    et_end = day_end
                    target_end = target_end.replace(
                        hour=work_end.hour,
                        minute=work_end.minute
                    )
                    effective_end = min(et_end, target_end.astimezone(et_tz))

                    # Only add the window if there's actually time available
                    if effective_start < effective_end:
                        free_windows.append((effective_start, effective_end, is_extended_slot))
                else:
                    free_windows.append((day_start, day_end, is_extended_slot))
            
            # Add early slots (ext_start to work_start) for all days
            if current.date() not in holiday_dates:
                is_extended_slot = True
                early_day_start = current.replace(hour=early_start.hour, minute=early_start.minute)
                early_day_end = current.replace(hour=early_end.hour, minute=early_end.minute)
                
                if strict:
                    # Convert to target timezone to check working hours
                    target_start = early_day_start.astimezone(target_timezone)
                    target_end = early_day_end.astimezone(target_timezone)
                    
                    # Check if the early hours are valid in both timezones
                    # This is a bit different since we're checking specific early hours
                    if (target_start.hour < work_start.hour and target_end.hour <= work_start.hour) or (target_start.hour < work_start.hour and target_end.minute == 0):
                        free_windows.append((early_day_start, early_day_end, is_extended_slot))
                else:
                    free_windows.append((early_day_start, early_day_end, is_extended_slot))
            
            # Add late slots (work_end to ext_end) for all days
            if current.date() not in holiday_dates:
                is_extended_slot = True
                late_day_start = current.replace(hour=late_start.hour, minute=late_start.minute)
                late_day_end = current.replace(hour=late_end.hour, minute=late_end.minute)
                
                if strict:
                    # Convert to target timezone to check working hours
                    target_start = late_day_start.astimezone(target_timezone)
                    target_end = late_day_end.astimezone(target_timezone)
                    
                    # Check if the late hours are valid in both timezones
                    # This is a bit different since we're checking specific late hours
                    if (target_start.hour >= work_end.hour and target_end.hour <= ext_end.hour) or (target_start.hour >= work_end.hour and target_end.minute == 0):
                        free_windows.append((late_day_start, late_day_end, is_extended_slot))
                else:
                    free_windows.append((late_day_start, late_day_end, is_extended_slot))

        current += timedelta(days=1)

    # Remove busy times and apply buffer
    busy_times = []
    for start, end, status in events:
        if status != 'FREE':
            buffer = timedelta(minutes=buffer_mins)
            busy_times.append((start - buffer, end + buffer))

    # Sort busy times first
    busy_times.sort()
    merged = []
    for busy in busy_times:
        if not merged or merged[-1][1] < busy[0]:
            merged.append(busy)
        else:
            merged[-1] = (merged[-1][0], max(merged[-1][1], busy[1]))

    # Remove busy times from free windows
    result = []
    for free_start, free_end, is_extended in free_windows:
        current = free_start
        for busy_start, busy_end in merged:
            # Fix: Only process busy times that overlap with the free window
            if busy_end > current and busy_start < free_end:
                if current < busy_start:
                    result.append((current, busy_start, is_extended))
                current = max(current, busy_end)
        if current < free_end:
            result.append((current, free_end, is_extended))

    # Filter windows shorter than min_duration
    min_duration_td = timedelta(minutes=min_duration)
    filtered_windows = [(start, end, is_extended) for start, end, is_extended in result 
                       if end - start >= min_duration_td]

    # Round start times up to next 15-minute boundary
    final_result = []
    for start, end, is_extended in filtered_windows:
        # Round up start time to next 15-minute boundary
        minutes = start.minute
        rounded_minutes = ((minutes + 14) // 15) * 15  # Rounds up to next 15
        if rounded_minutes == 60:
            start = start.replace(hour=start.hour + 1, minute=0)
        else:
            start = start.replace(minute=rounded_minutes)

        if start < end and end - start >= min_duration_td:
            final_result.append((start, end, is_extended))

    return final_result

def format_windows(windows: List[Tuple[datetime, datetime, bool]], target_tz: str = "America/New_York", compare: bool = False) -> List[str]:
    """Format time windows in the requested format."""
    formatted = []
    last_week = None
    target_timezone = ZoneInfo(target_tz)
    et_tz = ZoneInfo("America/New_York")
    
    # First pass to find the maximum length of formatted lines
    max_duration_len = 0
    for start, end, is_extended in windows:
        start = start.astimezone(target_timezone)
        end = end.astimezone(target_timezone)
        
        duration = end - start
        hours = duration.seconds // 3600
        minutes = (duration.seconds % 3600) // 60
        
        # Format duration
        duration_str = ""
        if hours > 0:
            duration_str += f"{hours}h"
            if minutes > 0:
                duration_str += f"{minutes}m"
        elif minutes > 0:
            duration_str += f"{minutes}m"
            
        max_duration_len = max(max_duration_len, len(duration_str))

    def format_window(s, e, tz_name, is_extended=False):
        day_str = str(s.day)
        if len(day_str) == 1:
            day_str = " " + day_str
        date_str = f"{s.strftime('%a')} {day_str} {s.strftime('%b')}"

        def format_time(dt):
            hour = dt.strftime("%I").lstrip("0")
            return f"{hour}:{dt.strftime('%M')} {dt.strftime('%p')}"

        start_str = format_time(s).rjust(8)
        end_str = format_time(e).rjust(8)

        duration = e - s
        hours = duration.seconds // 3600
        minutes = (duration.seconds % 3600) // 60

        # Format duration
        duration_str = ""
        if hours > 0:
            duration_str += f"{hours}h"
            if minutes > 0:
                duration_str += f"{minutes}m"
        elif minutes > 0:
            duration_str += f"{minutes}m"
        
        # Add type indicator for extended slots
        type_indicator = ""
        if is_extended:
            indicators = []
            # Weekend
            if s.weekday() >= 5:
                indicators.append("wknd")
            
            # Early morning hours (7-10 AM)
            if s.hour < 10:
                indicators.append("morn")
            # Evening hours (5-8 PM)
            elif s.hour >= 17:
                indicators.append("even")
            
            type_indicator = " ".join(indicators)

        # Format with proper columnation - ensuring all type indicators are aligned
        padded_duration = f"({duration_str})"
        if type_indicator:
            # Pad to max_duration_len + 2 (for the parentheses)
            return f"{date_str:>10} @ {start_str} – {end_str} {tz_name} {padded_duration:<{max_duration_len+2}} {type_indicator}"
        else:
            return f"{date_str:>10} @ {start_str} – {end_str} {tz_name} {padded_duration}"

    if compare:
        # First pass: calculate the maximum length of formatted lines
        max_length = 0
        formatted_pairs = []
        for start, end, is_extended in windows:
            target_start = start.astimezone(target_timezone)
            target_end = end.astimezone(target_timezone)
            et_start = start
            et_end = end

            target_line = format_window(target_start, target_end, target_start.tzname(), is_extended)
            et_line = format_window(et_start, et_end, et_start.tzname(), is_extended)
            max_length = max(max_length, len(target_line))
            formatted_pairs.append((target_line, et_line))

        # Second pass: pad lines to align pipes
        for target_line, et_line in formatted_pairs:
            padded_line = f"{target_line:<{max_length}}  |  {et_line}"
            formatted.append(padded_line)
    else:
        # Original single timezone output
        for start, end, is_extended in windows:
            start = start.astimezone(target_timezone)
            end = end.astimezone(target_timezone)

            # Check if we need to add a newline between weeks
            current_week = start.isocalendar()[1]
            if last_week is not None and current_week != last_week:
                formatted.append("")  # Add empty string for newline

            formatted.append(format_window(start, end, start.tzname(), is_extended))
            last_week = current_week  # Update last_week with current_week

    return formatted

def read_ical_from_file(file_path: str) -> str:
    """Read iCal data from a file."""
    return Path(file_path).read_text()

def fetch_ical_from_url(url: str) -> str:
    """Fetch iCal data from a URL."""
    response = requests.get(url)
    response.raise_for_status()
    return response.text

def main():
    parser = argparse.ArgumentParser(description='Cross-reference multiple calendars to find free time slots')
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('-f', '--files', nargs='+', help='Path to one or more iCal files')
    group.add_argument('-u', '--urls', nargs='+', help='URLs to fetch iCal data from')
    group.add_argument('-l', '--list-timezones', action='store_true', 
                      help='List all available timezones')
    parser.add_argument('-v', '--verbose', action='store_true', help='Enable verbose debug output')
    parser.add_argument('-t', '--timezone', default='America/New_York',
                      help='Target timezone for output (default: America/New_York)')
    parser.add_argument('-s', '--start-date', 
                      help='Start date for free window search (format: YYYY-MM-DD)')
    parser.add_argument('-r', '--strict', action='store_true',
                      help='Enforce working hours (10 AM - 5 PM) in both Eastern and target timezone')
    parser.add_argument('-c', '--compare', action='store_true',
                      help='Show times in both local (ET) and target timezone')
    parser.add_argument('--start', type=str, default='10:00',
                       help='Work start time in HH:MM format (default: 10:00)')
    parser.add_argument('--end', type=str, default='17:00',
                       help='Work end time in HH:MM format (default: 17:00)')
    parser.add_argument('-w', '--extended', action='store_true',
                       help='Include weekends and extended hours outside of regular working hours')
    parser.add_argument('--ext-start', type=str, default='07:00',
                       help='Start time for extended hours in HH:MM format (default: 07:00)')
    parser.add_argument('--ext-end', type=str, default='20:00',
                       help='End time for extended hours in HH:MM format (default: 20:00)')
    parser.add_argument('--buffer', type=int, default=30,
                       help='Buffer time in minutes to add before and after busy events (default: 30)')
    parser.add_argument('--min-duration', type=int, default=30,
                       help='Minimum duration in minutes for free windows (default: 30)')

    args = parser.parse_args()

    work_start = datetime.strptime(args.start, '%H:%M').time()
    work_end = datetime.strptime(args.end, '%H:%M').time()
    ext_start = datetime.strptime(args.ext_start, '%H:%M').time()
    ext_end = datetime.strptime(args.ext_end, '%H:%M').time()

    # Add timezone listing logic
    if args.list_timezones:
        now = datetime.now()
        # Create list of (timezone, offset) tuples
        tz_info = []
        for tz_name in available_timezones():
            try:
                tz = ZoneInfo(tz_name)
                offset = datetime.now(tz).utcoffset()
                # Convert offset to hours
                offset_hours = offset.total_seconds() / 3600
                tz_info.append((tz_name, offset_hours))
            except Exception:
                continue

        # Sort by offset first, then by name
        tz_info.sort(key=itemgetter(1, 0))

        print("\nAvailable timezones (sorted by offset):")
        for tz_name, offset_hours in tz_info:
            # Format offset as ±HH:MM
            hours = int(abs(offset_hours))
            minutes = int((abs(offset_hours) * 60) % 60)
            sign = '-' if offset_hours < 0 else '+'
            offset_str = f"{sign}{hours:02d}:{minutes:02d}"
            print(f"  UTC{offset_str}  {tz_name}")
        return

    try:
        # Parse start date if provided
        start_date = None
        if args.start_date:
            et_tz = ZoneInfo("America/New_York")
            start_date = datetime.strptime(args.start_date, '%Y-%m-%d')
            start_date = start_date.replace(tzinfo=et_tz)

        # New code to handle multiple calendars
        all_events = []

        if args.files:
            for file_path in args.files:
                print(f"reading {file_path}", file=sys.stderr)
                ical_data = read_ical_from_file(file_path)
                events = parse_calendar(ical_data, verbose=args.verbose, start_date=start_date)
                all_events.extend(events)
        elif args.urls:
            for url in args.urls:
                ical_data = fetch_ical_from_url(url)
                events = parse_calendar(ical_data, verbose=args.verbose, start_date=start_date)
                all_events.extend(events)

        free_times = format_windows(
            find_free_windows(
                all_events,  # Use combined events from all calendars
                buffer_mins=args.buffer,
                min_duration=args.min_duration,
                start_date=start_date,
                target_tz=args.timezone,
                strict=args.strict,
                work_start=work_start,
                work_end=work_end,
                extended=args.extended,
                ext_start=ext_start,
                ext_end=ext_end
            ),
            target_tz=args.timezone,
            compare=args.compare
        )
        for time in free_times:
            print(time)

    except Exception as e:
        print(f"Error: {str(e)}", file=sys.stderr)
        sys.exit(1)

if __name__ == '__main__':
    main()
