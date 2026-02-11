// ============================================
// CONFIGURATION - Update these values
// ============================================
const CONFIG = {
  API_KEY: 'YOUR_SECRET_API_KEY_HERE',  // Generate a random string
  PARENT_FOLDER_ID: 'YOUR_PARENT_FOLDER_ID_HERE',  // The "שבצק - אירועים" folder ID
  ARCHIVE_FOLDER_NAME: 'ארכיון'
};

// ============================================
// MAIN ENTRY POINT
// ============================================
function doPost(e) {
  try {
    const request = JSON.parse(e.postData.contents);

    // Validate API key
    if (request.apiKey !== CONFIG.API_KEY) {
      return jsonResponse({ success: false, error: 'Invalid API key' }, 401);
    }

    // Route to appropriate action
    switch (request.action) {
      case 'createFolder':
        return handleCreateFolder(request);
      case 'renameFolder':
        return handleRenameFolder(request);
      case 'deleteFolder':
        return handleDeleteFolder(request);
      case 'listFiles':
        return handleListFiles(request);
      case 'archiveCheck':
        return handleArchiveCheck(request);
      default:
        return jsonResponse({ success: false, error: 'Unknown action' }, 400);
    }
  } catch (error) {
    return jsonResponse({ success: false, error: error.toString() }, 500);
  }
}

// Also support GET for testing
function doGet(e) {
  return jsonResponse({ status: 'Apps Script Drive Service is running' });
}

// ============================================
// ACTION HANDLERS
// ============================================

/**
 * Create a new folder for an event
 * Request: { action: 'createFolder', name: string, date: string (ISO), endDate?: string (ISO) }
 * Response: { success: true, folderId: string, folderLink: string }
 */
function handleCreateFolder(request) {
  const { name, date, endDate } = request;

  // Log the received request for debugging
  console.log('CreateFolder request:', JSON.stringify(request));

  if (!name || !date) {
    console.log('Missing name or date. name:', name, 'date:', date);
    return jsonResponse({ success: false, error: 'Missing name or date' }, 400);
  }

  const folderName = formatFolderName(name, date, endDate);
  const parentFolder = DriveApp.getFolderById(CONFIG.PARENT_FOLDER_ID);

  // Check if folder with same name already exists (shouldn't happen due to DB validation, but just in case)
  const existing = parentFolder.getFoldersByName(folderName);
  if (existing.hasNext()) {
    return jsonResponse({ success: false, error: 'Folder already exists' }, 409);
  }

  const newFolder = parentFolder.createFolder(folderName);
  console.log('Created folder:', folderName, 'with ID:', newFolder.getId());

  return jsonResponse({
    success: true,
    folderId: newFolder.getId(),
    folderLink: newFolder.getUrl()
  });
}

/**
 * Rename an existing folder
 * Request: { action: 'renameFolder', folderId: string, name: string, date: string (ISO), endDate?: string (ISO) }
 * Response: { success: true }
 */
function handleRenameFolder(request) {
  const { folderId, name, date, endDate } = request;

  if (!folderId || !name || !date) {
    return jsonResponse({ success: false, error: 'Missing folderId, name, or date' }, 400);
  }

  try {
    const folder = DriveApp.getFolderById(folderId);
    const newName = formatFolderName(name, date, endDate);
    folder.setName(newName);

    return jsonResponse({ success: true });
  } catch (error) {
    // Folder might have been deleted manually
    return jsonResponse({ success: false, error: 'Folder not found', notFound: true }, 404);
  }
}

/**
 * Delete (trash) a folder
 * Request: { action: 'deleteFolder', folderId: string }
 * Response: { success: true }
 */
function handleDeleteFolder(request) {
  const { folderId } = request;

  if (!folderId) {
    return jsonResponse({ success: false, error: 'Missing folderId' }, 400);
  }

  try {
    const folder = DriveApp.getFolderById(folderId);
    folder.setTrashed(true);

    return jsonResponse({ success: true });
  } catch (error) {
    // Folder might already be deleted - that's okay
    return jsonResponse({ success: true, alreadyDeleted: true });
  }
}

/**
 * List files in a folder
 * Request: { action: 'listFiles', folderId: string }
 * Response: { success: true, files: [{ id, name, mimeType, size, modifiedDate, webViewLink, iconLink }] }
 */
function handleListFiles(request) {
  const { folderId } = request;

  if (!folderId) {
    return jsonResponse({ success: false, error: 'Missing folderId' }, 400);
  }

  try {
    const folder = DriveApp.getFolderById(folderId);
    const filesIterator = folder.getFiles();
    const files = [];

    while (filesIterator.hasNext()) {
      const file = filesIterator.next();
      files.push({
        id: file.getId(),
        name: file.getName(),
        mimeType: file.getMimeType(),
        size: file.getSize(),
        modifiedDate: file.getLastUpdated().toISOString(),
        webViewLink: file.getUrl(),
        iconLink: getIconLink(file.getMimeType())
      });
    }

    // Sort by modified date, newest first
    files.sort((a, b) => new Date(b.modifiedDate) - new Date(a.modifiedDate));

    return jsonResponse({ success: true, files });
  } catch (error) {
    // Folder might have been deleted manually
    return jsonResponse({ success: true, files: [], folderNotFound: true });
  }
}

/**
 * Archive check - move old event folders to archive
 * Request: { action: 'archiveCheck', events: [{ folderId: string, endDate: string (ISO), isArchived: boolean }] }
 * Response: { success: true, archived: [{ folderId: string }] }
 */
function handleArchiveCheck(request) {
  const { events } = request;

  if (!events || !Array.isArray(events)) {
    return jsonResponse({ success: false, error: 'Missing events array' }, 400);
  }

  const archiveFolder = getOrCreateArchiveFolder();
  const today = new Date();
  today.setHours(0, 0, 0, 0);

  const archived = [];

  for (const event of events) {
    // Skip if no folder or already archived
    if (!event.folderId || event.isArchived) {
      continue;
    }

    // Check if end date is in the past
    const endDate = new Date(event.endDate);
    endDate.setHours(0, 0, 0, 0);

    if (endDate < today) {
      try {
        const folder = DriveApp.getFolderById(event.folderId);

        // Move to archive (remove from parent, add to archive)
        const parentFolder = DriveApp.getFolderById(CONFIG.PARENT_FOLDER_ID);
        parentFolder.removeFolder(folder);
        archiveFolder.addFolder(folder);

        archived.push({ folderId: event.folderId });
      } catch (error) {
        // Folder might not exist, skip it
        console.log('Could not archive folder ' + event.folderId + ': ' + error);
      }
    }
  }

  return jsonResponse({ success: true, archived });
}

// ============================================
// HELPER FUNCTIONS
// ============================================

/**
 * Format folder name as:
 * - Single-day event: "YYYY_MM_DD - <event name>"
 * - Multi-day event: "YYYY_MM_DD-YYYY_MM_DD - <event name>" (with underscores)
 */
function formatFolderName(name, dateString, endDateString) {
  const date = new Date(dateString);
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');

  // Check if endDate is provided and different from start date
  if (endDateString && endDateString !== null && endDateString !== undefined && endDateString !== '') {
    const endDate = new Date(endDateString);
    const endYear = endDate.getFullYear();
    const endMonth = String(endDate.getMonth() + 1).padStart(2, '0');
    const endDay = String(endDate.getDate()).padStart(2, '0');

    // If it's a multi-day event (different dates)
    if (date.toDateString() !== endDate.toDateString()) {
      return `${year}_${month}_${day}-${endYear}_${endMonth}_${endDay} - ${name}`;
    }
  }

  // Single-day event (with underscores as requested)
  return `${year}_${month}_${day} - ${name}`;
}

/**
 * Get or create the archive folder
 */
function getOrCreateArchiveFolder() {
  const parentFolder = DriveApp.getFolderById(CONFIG.PARENT_FOLDER_ID);
  const folders = parentFolder.getFoldersByName(CONFIG.ARCHIVE_FOLDER_NAME);

  if (folders.hasNext()) {
    return folders.next();
  }

  return parentFolder.createFolder(CONFIG.ARCHIVE_FOLDER_NAME);
}

/**
 * Get icon link based on MIME type
 */
function getIconLink(mimeType) {
  const iconBase = 'https://drive-thirdparty.googleusercontent.com/16/type/';
  return iconBase + mimeType;
}

/**
 * Create a JSON response
 */
function jsonResponse(data, statusCode = 200) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
}

// ============================================
// UTILITY FUNCTION FOR TESTING
// ============================================

/**
 * Test function - run this in Apps Script editor to verify setup
 */
function testSetup() {
  try {
    const parentFolder = DriveApp.getFolderById(CONFIG.PARENT_FOLDER_ID);
    console.log('✓ Parent folder found: ' + parentFolder.getName());

    const archiveFolder = getOrCreateArchiveFolder();
    console.log('✓ Archive folder ready: ' + archiveFolder.getName());

    // Test folder naming with underscores
    console.log('Test single-day: ' + formatFolderName('Test Event', '2025-01-15T10:00:00Z'));
    console.log('Test multi-day: ' + formatFolderName('Multi Day Event', '2025-01-15T10:00:00Z', '2025-01-17T18:00:00Z'));

    console.log('✓ Setup is valid!');
  } catch (error) {
    console.log('✗ Error: ' + error.toString());
  }
}