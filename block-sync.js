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

    // Skip events with IDs that match the timestamp pattern (recurring instances)
    if (event.id.match(/^.*_\d{8}T\d{6}Z$/)) {
      console.log("[%d: %s] skipping recurring instance", e, event.id);
      continue;
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
    if (blockCache.hasOwnProperty(event.id)) {
      console.log("[%d: %s] using cached block status: %s", e, event.id, blockCache[event.id] ? "found" : "not found");
    } else {
      // We haven't checked this event ID yet, so look for blocks on blocker calendar
      console.log("[%d: %s] checking blocker calendar for matching blocks", e, event.id);
      const blocks = Calendar.Events.list(blockerCalId, {
        q: event.id,
      });
      
      // Check if any of the returned items have a description that EXACTLY matches the event ID
      if (blocks.items && blocks.items.length > 0) {
        let matchingBlock = null;
        for (let block of blocks.items) {
          if (block.description === event.id) {
            console.log("[%d: %s] found exact matching block", e, event.id);
            // Store the matching block in cache
            matchingBlock = block;
            break;
          }
        }
        
        if (matchingBlock) {
          blockCache[event.id] = matchingBlock;
        } else {
          console.log("[%d: %s] found blocks with similar IDs but no exact match", e, event.id);
          // Store null in cache to indicate we checked but found no matching block
          blockCache[event.id] = null;
        }
      } else {
        console.log("[%d: %s] no blocks found", e, event.id);
        // Store null in cache to indicate we checked but found no matching block
        blockCache[event.id] = null;
      }
    }
    
    // Now use the cached result to determine what to do
    const matchingBlock = blockCache[event.id];
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

function removeDuplicateBlocks() {
  const props = PropertiesService.getScriptProperties().getProperties();
  const blockerCalId = props['blockerCal'];
  
  console.log("Starting duplicate removal for blocker calendar: " + blockerCalId);
  
  // Get all events from the blocker calendar
  const now = new Date();
  const oneYearAgo = new Date(now.getTime());
  oneYearAgo.setFullYear(now.getFullYear() - 1);
  
  const options = {
    timeMin: oneYearAgo.toISOString(),
    maxResults: 2500,
    singleEvents: false
  };
  
  let blocks = Calendar.Events.list(blockerCalId, options);
  if (!blocks.items || blocks.items.length === 0) {
    console.log("No events found on blocker calendar.");
    return;
  }
  
  console.log("Found " + blocks.items.length + " total events on blocker calendar");
  
  // Create a map to track which source event IDs we've seen
  const sourceEventMap = {};
  const duplicatesToRemove = [];
  const timestampInstancesToRemove = [];
  
  // Helper function to get the parent ID from any event ID
  function getParentEventId(eventId) {
    // If the ID contains an underscore followed by a timestamp, strip it
    const underscoreIndex = eventId.indexOf('_');
    if (underscoreIndex !== -1) {
      return eventId.substring(0, underscoreIndex);
    }
    return eventId;
  }
  
  // First pass - identify duplicates and timestamp instances
  for (const block of blocks.items) {
    if (!block.description) {
      console.log("Skipping block with no description: " + block.id);
      continue;
    }
    
    // Get the source event ID from the description
    const rawSourceEventId = block.description.trim();
    
    // Check if this is a timestamp instance (matches timestamp pattern)
    if (rawSourceEventId.match(/^.*_\d{8}T\d{6}Z$/)) {
      // This is a recurring instance - mark for removal
      timestampInstancesToRemove.push({
        blockId: block.id,
        sourceEventId: rawSourceEventId,
        summary: block.summary || "No summary"
      });
      continue;
    }
    
    // Normalize to the parent ID
    const sourceEventId = getParentEventId(rawSourceEventId);
    
    if (sourceEventMap[sourceEventId]) {
      // We've already seen this source event (or its parent) - this is a duplicate
      
      // If this is a parent event and what we've seen before is an instance,
      // keep this one and mark the previous one as duplicate instead
      const isParent = rawSourceEventId === sourceEventId;
      const previousIsParent = sourceEventMap[sourceEventId].rawSourceEventId === sourceEventId;
      
      if (isParent && !previousIsParent) {
        // This is a parent and previous was instance - swap them
        duplicatesToRemove.push({
          blockId: sourceEventMap[sourceEventId].blockId,
          sourceEventId: sourceEventMap[sourceEventId].rawSourceEventId,
          parentEventId: sourceEventId,
          summary: sourceEventMap[sourceEventId].summary
        });
        
        // Update the map with this parent event
        sourceEventMap[sourceEventId] = {
          blockId: block.id,
          rawSourceEventId: rawSourceEventId,
          summary: block.summary || "No summary"
        };
      } else {
        // Normal duplicate case
        duplicatesToRemove.push({
          blockId: block.id,
          sourceEventId: rawSourceEventId,
          parentEventId: sourceEventId,
          summary: block.summary || "No summary"
        });
      }
    } else {
      // First time seeing this source event ID - add to our map
      sourceEventMap[sourceEventId] = {
        blockId: block.id,
        rawSourceEventId: rawSourceEventId,
        summary: block.summary || "No summary"
      };
    }
  }
  
  console.log("Found " + duplicatesToRemove.length + " duplicate blocks to remove");
  console.log("Found " + timestampInstancesToRemove.length + " timestamp instance blocks to remove");
  
  // Second pass - remove duplicates
  let removedCount = 0;
  for (const duplicate of duplicatesToRemove) {
    try {
      console.log("Removing duplicate block: " + duplicate.blockId + 
                 " (Source event: " + duplicate.sourceEventId + 
                 ", Parent ID: " + duplicate.parentEventId +
                 ", Summary: " + duplicate.summary + ")");
                 
      Calendar.Events.remove(blockerCalId, duplicate.blockId, {
        sendUpdates: "none"
      });
      removedCount++;
    } catch (e) {
      console.log("Failed to remove duplicate block: " + duplicate.blockId + 
                 " Error: " + e.message);
    }
  }
  
  // Third pass - remove timestamp instances
  let timestampRemovedCount = 0;
  for (const instance of timestampInstancesToRemove) {
    try {
      console.log("Removing timestamp instance block: " + instance.blockId + 
                 " (Source event: " + instance.sourceEventId + 
                 ", Summary: " + instance.summary + ")");
                 
      Calendar.Events.remove(blockerCalId, instance.blockId, {
        sendUpdates: "none"
      });
      timestampRemovedCount++;
    } catch (e) {
      console.log("Failed to remove timestamp instance block: " + instance.blockId + 
                 " Error: " + e.message);
    }
  }
  
  console.log("Successfully removed " + removedCount + " duplicate blocks");
  console.log("Successfully removed " + timestampRemovedCount + " timestamp instance blocks");
  
  return {
    totalBlocks: blocks.items.length,
    duplicatesFound: duplicatesToRemove.length,
    duplicatesRemoved: removedCount,
    timestampInstancesFound: timestampInstancesToRemove.length,
    timestampInstancesRemoved: timestampRemovedCount
  };
}

// Function to drain all past events from a calendar (update sync token without creating blocks)
function drainCalendar(calendarId) {
  const props = PropertiesService.getScriptProperties().getProperties();
  
  console.log("Draining calendar: " + calendarId);
  
  // Force a full sync but with dry run mode
  if (calendarId === props['schedulerCal']) {
    processCalendar(calendarId, props['blockerCal'], props['homeEmail'], props['workEmail'], true, true, {});
  } else if (calendarId === props['homeCal']) {
    processCalendar(calendarId, props['blockerCal'], props['homeEmail'], props['workEmail'], false, true, {});
  } else {
    console.log("Unknown calendar ID: " + calendarId);
  }
  
  console.log("Calendar drained successfully: " + calendarId);
}

// Function to drain all calendars
function drainAllCalendars() {
  const props = PropertiesService.getScriptProperties().getProperties();
  
  drainCalendar(props['schedulerCal']);
  drainCalendar(props['homeCal']);
  
  console.log("All calendars drained successfully");
}
