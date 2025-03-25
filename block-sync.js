function main() {
  const props = PropertiesService.getScriptProperties().getProperties();
  
  // Create a cache to track event IDs we're creating blocks for
  const blockCreationCache = {};

  // Process scheduler calendar (with attendee modification)
  processCalendar(props['schedulerCal'], props['blockerCal'], props['homeEmail'], props['workEmail'], true, false, blockCreationCache);
  
  // Process home calendar (without attendee modification)
  processCalendar(props['homeCal'], props['blockerCal'], props['homeEmail'], props['workEmail'], false, false, blockCreationCache);
}

function processCalendar(sourceCalId, blockerCalId, homeEmail, workEmail, addAttendees, dryRun, blockCreationCache) {
  // Look for created/updated/deleted events on the source calendar
  const events = logSyncedEvents(sourceCalId, false);
  console.log("got %d new event(s) from %s", events.length, sourceCalId);
  
  // Create a local cache for this execution
  const blockCache = {};
  
  console.log("Dry run: " + dryRun);
  if (dryRun) {
    console.log("DRY RUN MODE: Not creating/updating/deleting any events");
    return;
  }
  
  let e = 0
  for (let event of events) {
    e += 1
    console.log("[%d: %s] event: %s", e, event.id, event.summary || "No summary available");

    // Handle recurring event instances (events with IDs ending with timestamp)
    if (event.id.match(/^.*_\d{8}T\d{6}Z$/)) {
      console.log("[%d: %s] detected recurring instance", e, event.id);
      
      // Extract the parent event ID by removing the timestamp suffix
      const parentEventId = event.id.replace(/_\d{8}T\d{6}Z$/, '');
      console.log("[%d: %s] parent event ID: %s", e, event.id, parentEventId);
      
      // Check if parent event has a block on the blocker calendar
      const parentBlock = checkForBlockOnCalendar(blockerCalId, parentEventId, blockCache, e);
      
      // If parent event has a block, skip this instance
      if (parentBlock) {
        console.log("[%d: %s] parent event has a block, skipping instance", e, event.id);
        continue;
      } else {
        // Check if the event start date is more than 90 days from today
        const today = new Date();
        const eventStartDate = new Date(event.start.dateTime || event.start.date);
        const daysDifference = Math.floor((eventStartDate - today) / (1000 * 60 * 60 * 24));
        
        if (daysDifference > 90) {
          console.log("[%d: %s] instance is more than 90 days in the future (%d days), skipping", e, event.id, daysDifference);
          continue;
        }
        
        console.log("[%d: %s] parent event does not have a block, processing instance", e, event.id);
        // Continue processing this instance as a normal event
      }
    }
    
    // If requested, ensure the home email is added as an attendee (only for scheduler calendar)
    if (addAttendees && event.status != "cancelled") {
      if (event.attendees && event.attendees.length > 0) {
        if (!event.attendees.map(({ email }) => email).includes(homeEmail)) {
          console.log("[%d: %s] adding attendee", e, event.id);
          event.attendees.push({ email: homeEmail });
          updateEvent(sourceCalId, event.id, event);
        }
      } else {
        console.log("[%d: %s] adding attendee", e, event.id);
        event.attendees = [{ email: homeEmail }];
        updateEvent(sourceCalId, event.id, event);
      }
    }

    // Check if we already have a cached result for this event ID
    const matchingBlock = checkForBlockOnCalendar(blockerCalId, event.id, blockCache, e);
    
    // Now use the result to determine what to do
    if (matchingBlock) {
      // A matching block exists for this event ID
      // If the source calendar event was deleted, then delete its matching block on the blocker calendar
      if (event.status == "cancelled") {
        console.log("[%d: %s] deleting block", e, event.id);
        deleteEvent(blockerCalId, matchingBlock.id);
        blockCache[event.id] = null; // Update cache to reflect deletion
      // If the source calendar event was updated, then update the corresponding blocker calendar block if needed
      } else {
        const eventRecurrence = (event.recurrence ? event.recurrence : null);
        const blockRecurrence = (matchingBlock.recurrence ? matchingBlock.recurrence : null);
        if (matchingBlock.start != event.start || matchingBlock.end != event.end || blockRecurrence != eventRecurrence) {
          console.log("[%d: %s] updating block", e, event.id);
          matchingBlock.start = event.start;
          matchingBlock.end = event.end;
          delete matchingBlock.recurrence;
          if (eventRecurrence) {
            matchingBlock.recurrence = eventRecurrence
          }
          updateEvent(blockerCalId, matchingBlock.id, matchingBlock);
          
          // Update the cache with the updated block
          blockCache[event.id] = matchingBlock;
        }
      }
    // If there's no matching block on the blocker calendar, then check our cache before creating it
    } else {
      if (event.status != "cancelled") {
        // Check if we've already initiated creating a block for this event
        if (blockCreationCache[event.id]) {
          console.log("[%d: %s] block creation already in progress, skipping", e, event.id);
        } else {
          console.log("[%d: %s] creating block", e, event.id);
          // Add the event ID to our cache before creating the block
          blockCreationCache[event.id] = true;
          
          let block = {
            summary: "🟢 BLOCK",
            description: event.id,
            start: event.start,
            end: event.end,
            attendees: [{ email: workEmail }],
          };
          if (event.recurrence) {
            block.recurrence = event.recurrence
          }
          const createdBlock = createEvent(blockerCalId, block);
          
          // Update the cache with the newly created block if available
          if (createdBlock) {
            blockCache[event.id] = createdBlock;
          }
        }
      }
    }
  }
  
  return; // Return nothing
}

/**
 * Helper function to check for blocks on the blocker calendar
 * @param {string} blockerCalId - The ID of the blocker calendar
 * @param {string} eventId - The event ID to check for
 * @param {Object} blockCache - Cache object to store and retrieve results
 * @param {number} e - Event index for logging
 * @return {Object|null} - The matching block or null if not found
 */
function checkForBlockOnCalendar(blockerCalId, eventId, blockCache, e = 0) {
  // Check if we already have a cached result for this event ID
  if (blockCache.hasOwnProperty(eventId)) {
    console.log("[%d: %s] using cached block status: %s", e, eventId, blockCache[eventId] ? "found" : "not found");
    return blockCache[eventId];
  }
  
  // We haven't checked this event ID yet, so look for blocks on blocker calendar
  console.log("[%d: %s] checking blocker calendar for matching blocks", e, eventId);
  const blocks = Calendar.Events.list(blockerCalId, {
    q: eventId,
  });
  
  // Check if any of the returned items have a description that EXACTLY matches the event ID
  if (blocks.items && blocks.items.length > 0) {
    let matchingBlock = null;
    for (let block of blocks.items) {
      if (block.description === eventId) {
        console.log("[%d: %s] found exact matching block", e, eventId);
        // Store the matching block in cache
        matchingBlock = block;
        break;
      }
    }
    
    if (matchingBlock) {
      blockCache[eventId] = matchingBlock;
      return matchingBlock;
    } else {
      console.log("[%d: %s] found blocks with similar IDs but no exact match", e, eventId);
      // Store null in cache to indicate we checked but found no matching block
      blockCache[eventId] = null;
      return null;
    }
  } else {
    console.log("[%d: %s] no blocks found", e, eventId);
    // Store null in cache to indicate we checked but found no matching block
    blockCache[eventId] = null;
    return null;
  }
}

function deleteEvent(calendarId, eventId) {
  try {
    const deletedEvent = Calendar.Events.remove(calendarId, eventId, {
      sendUpdates: "all",
    });
    console.log("successfully deleted event: %s", deletedEvent.id);
  } catch (e) {
    console.log("delete failed with error: %s", e.message);
  }
}

function updateEvent(calendarId, eventId, event) {
  try {
    const updatedEvent = Calendar.Events.update(event, calendarId, eventId, {
      sendUpdates: "all",
    });
    console.log("successfully updated event: %s ", updatedEvent.id);
  } catch (e) {
    console.log("update failed with error: %s", e.message);
  }
}

function createEvent(calendarId, event) {
  try {
    const createdEvent = Calendar.Events.insert(event, calendarId, {
      sendUpdates: "all",
    });
    console.log("successfully created event: %s", createdEvent.id);
    return createdEvent;
  } catch (e) {
    console.log("create failed with error: %s", e.message);
  }
}

function getRelativeDate(daysOffset, hour) {
  const date = new Date();
  date.setDate(date.getDate() + daysOffset);
  date.setHours(hour);
  date.setMinutes(0);
  date.setSeconds(0);
  date.setMilliseconds(0);
  return date;
}

function logSyncedEvents(calendarId, fullSync) {
  const properties = PropertiesService.getUserProperties();
  
  // Get all sync tokens as a JSON object
  let syncTokens = {};
  const syncTokensStr = properties.getProperty("syncTokens");
  if (syncTokensStr) {
    try {
      syncTokens = JSON.parse(syncTokensStr);
    } catch (e) {
      console.log("Error parsing sync tokens, resetting: %s", e.message);
      syncTokens = {};
    }
  }
  
  const options = {
    maxResults: 100,
  };
  
  // Use calendar-specific sync token
  if (!fullSync && syncTokens[calendarId]) {
    options.syncToken = syncTokens[calendarId];
  } else {
    // Sync events up to thirty days in the past.
    options.timeMin = getRelativeDate(-30, 0).toISOString();
  }
  
  // Retrieve events one page at a time.
  let evts = [];
  let events;
  let pageToken;
  do {
    try {
      options.pageToken = pageToken;
      events = Calendar.Events.list(calendarId, options);
    } catch (e) {
      // Check to see if the sync token was invalidated by the server; if so, perform a full sync instead.
      if (e.message.includes("Sync token is no longer valid")) {
        delete syncTokens[calendarId];
        properties.setProperty("syncTokens", JSON.stringify(syncTokens));
        return logSyncedEvents(calendarId, true);
      } else {
        throw new Error(e.message);
      }
    }
    
    if (events.items && events.items.length > 0) {
      evts = evts.concat(events.items);
    }
    
    pageToken = events.nextPageToken;
  } while (pageToken);
  
  // Store the calendar-specific sync token
  if (events.nextSyncToken) {
    syncTokens[calendarId] = events.nextSyncToken;
    properties.setProperty("syncTokens", JSON.stringify(syncTokens));
  }
  
  return evts;
}

function resetSyncToken(calendarId) {
  const properties = PropertiesService.getUserProperties();
  let syncTokens = {};
  
  const syncTokensStr = properties.getProperty("syncTokens");
  if (syncTokensStr) {
    try {
      syncTokens = JSON.parse(syncTokensStr);
    } catch (e) {
      console.log("Error parsing sync tokens: %s", e.message);
    }
  }
  
  if (calendarId) {
    // Reset specific calendar sync token
    delete syncTokens[calendarId];
    console.log("Reset sync token for calendar: " + calendarId);
  } else {
    // Reset all sync tokens
    syncTokens = {};
    console.log("Reset all sync tokens");
  }
  
  properties.setProperty("syncTokens", JSON.stringify(syncTokens));
}
