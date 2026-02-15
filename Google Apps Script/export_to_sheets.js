// ============================================
// CONFIGURATION - Update these values
// ============================================
const CONFIG = {
  API_KEY: '<API_KEY>',  // Generate a random string
  PARENT_FOLDER_ID: '12vY488nOKgDM-zPcPtB6d7_ZNeQr6pUj',  // The "שבצק - אירועים" folder ID
  EXPORTED_FILES_FOLDER_ID: '1VxTHhXfe724KUuq4-h9hpVVjnJEEwCsO',
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
      case 'exportToSheets':
        return handleExportToSheets(request);
      case 'exportAssignmentsOnly':
        return handleExportAssignmentsOnly(request);
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
 * Create a JSON response
 */
function jsonResponse(data, statusCode = 200) {
  return ContentService
    .createTextOutput(JSON.stringify(data))
    .setMimeType(ContentService.MimeType.JSON);
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
  newFolder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.EDIT);
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
        folder.moveTo(archiveFolder);
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
// EXPORT HANDLERS
// ============================================

/**
 * Full export to Google Sheets - creates multiple sheets with all DB data
 */
function handleExportToSheets(request) {
  var exportData = request.exportData;
  if (!exportData || !exportData.sheets || !exportData.sheets.length) {
    return jsonResponse({ success: false, error: 'No export data provided' }, 400);
  }

  // Create spreadsheet with timestamp
  var now = new Date();
  var timestamp = Utilities.formatDate(now, Session.getScriptTimeZone(), 'dd/MM/yyyy HH:mm');
  var spreadsheetName = 'שבצק - מסד נתונים מלא - נכון ל-' + timestamp;
  var spreadsheet = SpreadsheetApp.create(spreadsheetName);

  // Move to Shavtzak Drive folder
  try {
    var file = DriveApp.getFileById(spreadsheet.getId());
    var folder = DriveApp.getFolderById(CONFIG.EXPORTED_FILES_FOLDER_ID);
    file.moveTo(folder);
  } catch (e) {
    console.log('Could not move spreadsheet to Shavtzak folder: ' + e.message);
  }

  // Process each sheet
  for (var i = 0; i < exportData.sheets.length; i++) {
    var sheetDef = exportData.sheets[i];

    // Create or get sheet
    var sheet;
    if (i === 0) {
      sheet = spreadsheet.getSheets()[0];
      sheet.setName(sheetDef.sheetName);
    } else {
      sheet = spreadsheet.insertSheet(sheetDef.sheetName);
    }

    // Set RTL direction IMMEDIATELY after sheet creation
    sheet.setRightToLeft(true);

    // Set font family and alignment for entire sheet
    var maxRows = Math.max(sheetDef.rows.length + 1, 1);
    var maxCols = sheetDef.headers.length;
    var fullRange = sheet.getRange(1, 1, maxRows, maxCols);
    fullRange.setFontFamily('Rubik');
    fullRange.setHorizontalAlignment('center');
    fullRange.setVerticalAlignment('middle');

    // Set wrap on entire sheet
    fullRange.setWrap(true);

    // Replace <<<NEWLINE>>> placeholders with actual newlines
    for (var r = 0; r < sheetDef.rows.length; r++) {
      for (var c = 0; c < sheetDef.rows[r].length; c++) {
        if (typeof sheetDef.rows[r][c] === 'string') {
          sheetDef.rows[r][c] = sheetDef.rows[r][c].replace(/<<<NEWLINE>>>/g, '\n');
        }
      }
    }

    // Write headers (bold, frozen, light gray background)
    if (sheetDef.headers.length > 0) {
      var headerRange = sheet.getRange(1, 1, 1, sheetDef.headers.length);
      headerRange.setValues([sheetDef.headers]);
      headerRange.setFontWeight('bold');
      headerRange.setFontSize(14);
      headerRange.setBackground('#f3f3f3');
      sheet.setFrozenRows(1);
    }

    // Write data rows (font size 12)
    if (sheetDef.rows.length > 0) {
      var dataRange = sheet.getRange(2, 1, sheetDef.rows.length, sheetDef.headers.length);
      dataRange.setValues(sheetDef.rows);
      dataRange.setFontSize(12);
    }

    // Auto-resize columns
    for (var c = 1; c <= sheetDef.headers.length; c++) {
      try {
        sheet.autoResizeColumn(c);
        var currentWidth = sheet.getColumnWidth(c);
        sheet.setColumnWidth(c, currentWidth + 12);
      } catch (e) {
        // Ignore resize errors for empty columns
      }
    }

    // Handle textColumns (no wrap for specific columns)
    if (sheetDef.textColumns && sheetDef.textColumns.length > 0) {
      for (var idx = 0; idx < sheetDef.textColumns.length; idx++) {
        var colIndex = sheetDef.textColumns[idx] + 1; // 1-based
        var numCols = sheetDef.rows.length > 0 ? sheet.getRange(2, colIndex, sheetDef.rows.length, 1).getNumRows() : 1;
        sheet.getRange(2, colIndex, numCols, 1).setWrap(false);
      }
    }
  }

  return jsonResponse({
    success: true,
    spreadsheetUrl: spreadsheet.getUrl(),
    spreadsheetId: spreadsheet.getId()
  });
}

/**
 * Assignments-only export to Google Sheets - creates single sheet with formatting
 */
function handleExportAssignmentsOnly(request) {
  var exportData = request.exportData;
  if (!exportData || !exportData.sheets || !exportData.sheets.length) {
    return jsonResponse({ success: false, error: 'No export data provided' }, 400);
  }

  var sheetDef = exportData.sheets[0];

  // Create spreadsheet with timestamp format: dd/MM/yyyy HH:mm
  var now = new Date();
  var timestamp = Utilities.formatDate(now, Session.getScriptTimeZone(), 'dd/MM/yyyy HH:mm');
  var spreadsheetName = 'שבצק - שיבוצים - נכון ל-' + timestamp;
  var spreadsheet = SpreadsheetApp.create(spreadsheetName);

  // Move to Shavtzak Drive folder
  try {
    var file = DriveApp.getFileById(spreadsheet.getId());
    var folder = DriveApp.getFolderById(CONFIG.EXPORTED_FILES_FOLDER_ID);
    file.moveTo(folder);
  } catch (e) {
    console.log('Could not move spreadsheet to Shavtzak folder: ' + e.message);
  }

  // Get the default sheet and rename it
  var sheet = spreadsheet.getSheets()[0];
  sheet.setName(sheetDef.sheetName);

  // Set RTL direction IMMEDIATELY after sheet creation, before any formatting
  sheet.setRightToLeft(true);

  // Set font family and alignment for entire sheet
  var maxRows = Math.max(sheetDef.rows.length + 1, 1);
  var maxCols = sheetDef.headers.length;
  var fullRange = sheet.getRange(1, 1, maxRows, maxCols);
  fullRange.setFontFamily('Rubik');
  fullRange.setHorizontalAlignment('center');
  fullRange.setVerticalAlignment('middle');

  // NO text wrap for assignments export (except notes column J)
  fullRange.setWrap(false);

  // Write headers (bold, frozen, light gray background)
  if (sheetDef.headers.length > 0) {
    var headerRange = sheet.getRange(1, 1, 1, sheetDef.headers.length);
    headerRange.setValues([sheetDef.headers]);
    headerRange.setFontWeight('bold');
    headerRange.setFontSize(14);
    headerRange.setBackground('#f3f3f3');
    sheet.setFrozenRows(1);
  }

  // Write data rows FIRST (font size 12)
  if (sheetDef.rows.length > 0) {
    var dataRange = sheet.getRange(2, 1, sheetDef.rows.length, sheetDef.headers.length);
    dataRange.setValues(sheetDef.rows);
    dataRange.setFontSize(12);
  }

  // Merge cells D and E AFTER writing data (for single-day events where E is empty)
  // merge() keeps the top-left cell value (column D has the date) and clears the rest
  if (sheetDef.rows.length > 0) {
    for (var r = 0; r < sheetDef.rows.length; r++) {
      var rowIndex = r + 2; // +2 because row 1 is headers

      // If column E (index 4) is empty, it's a single-day event - merge D and E
      if (sheetDef.rows[r][4] === '') {
        sheet.getRange(rowIndex, 4, 1, 2).merge();
      }
    }
  }

  // Set specific column widths (NO auto-resize)
  var columnWidths = [240, 200, 320, 180, 180, 160, 160, 160, 320, 330];
  for (var c = 0; c < columnWidths.length && c < sheetDef.headers.length; c++) {
    sheet.setColumnWidth(c + 1, columnWidths[c]); // 1-based index
  }

  // Enable wrap for notes column (column J = index 9) only
  if (sheetDef.rows.length > 0) {
    sheet.getRange(2, 10, sheetDef.rows.length, 1).setWrap(true);
  }

  // Color rows by team member if requested
  if (sheetDef.colorByTeamMember) {
    var colors = [
      '#E3F2FD', '#F3E5F5', '#E8F5E9', '#FFF3E0', '#FFEBEE',
      '#E1F5FE', '#FCE4EC', '#E0F2F1', '#FFF9C4', '#F1F8E9',
      '#FFCCBC', '#D1C4E9', '#B2DFDB', '#FFECB3'
    ];

    var memberColors = {};
    var colorIndex = 0;

    for (var r = 0; r < sheetDef.rows.length; r++) {
      var memberName = sheetDef.rows[r][0]; // Column A is team member name

      if (!memberColors[memberName]) {
        memberColors[memberName] = colors[colorIndex % colors.length];
        colorIndex++;
      }

      sheet.getRange(r + 2, 1, 1, sheetDef.headers.length).setBackground(memberColors[memberName]);
    }
  }

  return jsonResponse({
    success: true,
    spreadsheetUrl: spreadsheet.getUrl(),
    spreadsheetId: spreadsheet.getId()
  });
}
