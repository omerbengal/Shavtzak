/***********************
 * MULTI-SHEET CONFIG
 ***********************/
const CONFIGS = [
  {
    sheetName: "שיבוצים - לפי אירוע",
    columnLetter: "A",
    startRow: 2,
    colorStrategy: "golden", // "golden" | "palette"
    colorPalette: [
      '#FFE6E6','#E6F3FF','#E6FFE6','#FFFFE6','#FFE6F3',
      '#F3E6FF','#E6FFF3','#FFDAB9','#E6E6FF','#D4E6F1',
      '#FFEEE6','#E6FFFF','#F0E6FF','#FFE6EE','#E8F8F5',
      '#FEF9E7','#EBF5FB','#F4ECF7','#FEF5E7','#EAF2F8'
    ],
    goldenSaturation: 75, // for "golden"
    goldenLightness: 88
  },
  {
    sheetName: "שיבוצים - לפי אנשים",
    columnLetter: "A",
    startRow: 2,
    colorStrategy: "golden", // "golden" | "palette"
    // Used only when colorStrategy === "palette"
    colorPalette: [
      '#FFE6E6','#E6F3FF','#E6FFE6','#FFFFE6','#FFE6F3',
      '#F3E6FF','#E6FFF3','#FFDAB9','#E6E6FF','#D4E6F1',
      '#FFEEE6','#E6FFFF','#F0E6FF','#FFE6EE','#E8F8F5',
      '#FEF9E7','#EBF5FB','#F4ECF7','#FEF5E7','#EAF2F8'
    ],
    // Used only when colorStrategy === "golden"
    goldenSaturation: 75, // 0-100
    goldenLightness: 88   // 0-100 (pastel vibe)
  },
];

// Global feature flag + menu + guards
const FLAG_KEY = 'AUTO_COLORING_ENABLED';
const MENU_NAME = '🎨 Color Coding';
const THROTTLE_MS = 800; // skip re-runs inside this window
const RUN_TS_KEY = 'LAST_RUN_MS';

// Keys for per-sheet previous paint size
const kCols = name => `LAST_COLORED_COLS__${name}`;
const kRows = name => `LAST_COLORED_ROWS__${name}`;

function isAutoEnabled() {
  return PropertiesService.getDocumentProperties().getProperty(FLAG_KEY) === 'true';
}
function setAutoEnabled(on) {
  PropertiesService.getDocumentProperties().setProperty(FLAG_KEY, on ? 'true' : 'false');
}
function cfgByName(name) { return CONFIGS.find(c => c.sheetName === name); }

/***********************
 * COLOR UTILS (high-contrast)
 ***********************/
function gcd(a,b){return b?gcd(b,a%b):Math.abs(a);}
function findCoprimeNearHalf(n){
  if(n<=1) return 1;
  const t=Math.floor(n/2);
  for(let d=0; d<n; d++){
    const cands=[t+d,t-d];
    for(const c of cands){ if(c>0 && c<n && gcd(c,n)===1) return c; }
  }
  return 1;
}
function hslToHex(h,s,l){
  s/=100; l/=100;
  const c=(1-Math.abs(2*l-1))*s, x=c*(1-Math.abs(((h/60)%2)-1)), m=l-c/2;
  let r=0,g=0,b=0;
  if(h<60){ r=c; g=x; }
  else if(h<120){ r=x; g=c; }
  else if(h<180){ g=c; b=x; }
  else if(h<240){ g=x; b=c; }
  else if(h<300){ r=x; b=c; }
  else { r=c; }
  const toHex=v=>Math.round((v+m)*255).toString(16).padStart(2,'0');
  return `#${toHex(r)}${toHex(g)}${toHex(b)}`;
}
function makeGoldenPicker(cfg){
  const s=Math.min(Math.max(cfg.goldenSaturation ?? 60,0),100);
  const l=Math.min(Math.max(cfg.goldenLightness ?? 88,0),100);
  const GOLDEN=137.508;
  return idx => hslToHex((idx*GOLDEN)%360,s,l);
}
function makeColorPicker(sortedValues,cfg){
  if(cfg.colorStrategy==='palette'){
    const P=cfg.colorPalette||[];
    const m=P.length;
    if(m===0) return makeGoldenPicker(cfg);
    const step=findCoprimeNearHalf(m);
    const order=Array.from({length:m},(_,i)=>(i*step)%m);
    const seq=order.map(i=>P[i]);
    return idx=>seq[idx%m];
  }
  return makeGoldenPicker(cfg);
}

/***********************
 * CORE: color one sheet (delta clears)
 ***********************/
// function colorCodeOneSheet(cfg){
//   const ss=SpreadsheetApp.getActiveSpreadsheet();
//   const sheet=ss.getSheetByName(cfg.sheetName);
//   if(!sheet) return;

//   const props=PropertiesService.getDocumentProperties();
//   const prevCols=Number(props.getProperty(kCols(cfg.sheetName))||0);
//   const prevRows=Number(props.getProperty(kRows(cfg.sheetName))||0);

//   const dataRange=sheet.getDataRange();
//   const lastRow=dataRange.getLastRow();
//   const lastCol=dataRange.getLastColumn();

//   // Current used rows from startRow
//   const usedRows = Math.max(0, lastRow - cfg.startRow + 1);
//   if(usedRows<=0 || lastCol===0){
//     // No data: just clear any previously colored region
//     if(prevCols>0 && prevRows>0){
//       sheet.getRange(cfg.startRow, 1, prevRows, prevCols).setBackground(null);
//       props.deleteProperty(kCols(cfg.sheetName));
//       props.deleteProperty(kRows(cfg.sheetName));
//     }
//     return;
//   }

//   // Read key column
//   const keyRange=sheet.getRange(`${cfg.columnLetter}${cfg.startRow}:${cfg.columnLetter}${lastRow}`);
//   const values=keyRange.getValues(); // usedRows x 1

//   // Unique sorted values → indices
//   const uniques=[...new Set(values.flat().filter(v=>v!==""))].sort();
//   const indexByValue=new Map(uniques.map((v,i)=>[v,i]));
//   const pickColor=makeColorPicker(uniques,cfg);

//   // Build backgrounds for used rectangle only
//   const backgrounds = values.map(r=>{
//     const v=r[0];
//     const idx=indexByValue.has(v)?indexByValue.get(v):null;
//     const color=(v && idx!==null)?pickColor(idx):null;
//     return Array(lastCol).fill(color);
//   });

//   // 1) Paint used rectangle (single call)
//   sheet.getRange(cfg.startRow, 1, usedRows, lastCol).setBackgrounds(backgrounds);

//   // 2) Clear stale columns to the RIGHT (if sheet got narrower)
//   if(prevCols>lastCol){
//     sheet.getRange(cfg.startRow, lastCol+1, Math.max(usedRows, prevRows), prevCols-lastCol)
//          .setBackground(null);
//   }
//   // 3) Clear stale ROWS BELOW (if sheet got shorter)
//   if(prevRows>usedRows){
//     sheet.getRange(cfg.startRow+usedRows, 1, prevRows-usedRows, Math.max(lastCol, prevCols||lastCol))
//          .setBackground(null);
//   }

//   // Remember current painted size
//   props.setProperty(kCols(cfg.sheetName), String(lastCol));
//   props.setProperty(kRows(cfg.sheetName), String(usedRows));
// }

function colorCodeOneSheet(cfg){
  const ss=SpreadsheetApp.getActiveSpreadsheet();
  const sheet=ss.getSheetByName(cfg.sheetName);
  if(!sheet) return;

  const props=PropertiesService.getDocumentProperties();
  const prevCols=Number(props.getProperty(kCols(cfg.sheetName))||0);
  const prevRows=Number(props.getProperty(kRows(cfg.sheetName))||0);

  const dataRange=sheet.getDataRange();
  const lastRow=dataRange.getLastRow();
  const lastCol=dataRange.getLastColumn();

  const usedRows = Math.max(0, lastRow - cfg.startRow + 1);
  if(usedRows<=0 || lastCol===0){
    if(prevCols>0 && prevRows>0){
      sheet.getRange(cfg.startRow, 1, prevRows, prevCols).setBackground(null);
      props.deleteProperty(kCols(cfg.sheetName));
      props.deleteProperty(kRows(cfg.sheetName));
    }
    return;
  }

  const keyRange=sheet.getRange(`${cfg.columnLetter}${cfg.startRow}:${cfg.columnLetter}${lastRow}`);
  const values=keyRange.getValues();

  // CHANGED: Don't sort! Maintain order of first appearance
  const uniqueValuesInOrder = [];
  const seenValues = new Set();
  
  for(let i = 0; i < values.length; i++){
    const val = values[i][0];
    if(val !== "" && !seenValues.has(val)){
      uniqueValuesInOrder.push(val);
      seenValues.add(val);
    }
  }

  // Create index map based on order of appearance, not alphabetical
  const indexByValue = new Map();
  uniqueValuesInOrder.forEach((v, i) => indexByValue.set(v, i));
  
  // Create color picker
  const pickColor = makeColorPicker(uniqueValuesInOrder, cfg);

  // Build backgrounds
  const backgrounds = values.map(r=>{
    const v=r[0];
    const idx=indexByValue.has(v)?indexByValue.get(v):null;
    const color=(v && idx!==null)?pickColor(idx):null;
    return Array(lastCol).fill(color);
  });

  // Paint used rectangle
  sheet.getRange(cfg.startRow, 1, usedRows, lastCol).setBackgrounds(backgrounds);

  // Clear stale columns to the RIGHT
  if(prevCols>lastCol){
    sheet.getRange(cfg.startRow, lastCol+1, Math.max(usedRows, prevRows), prevCols-lastCol)
         .setBackground(null);
  }
  // Clear stale ROWS BELOW
  if(prevRows>usedRows){
    sheet.getRange(cfg.startRow+usedRows, 1, prevRows-usedRows, Math.max(lastCol, prevCols||lastCol))
         .setBackground(null);
  }

  props.setProperty(kCols(cfg.sheetName), String(lastCol));
  props.setProperty(kRows(cfg.sheetName), String(usedRows));
}

/***********************
 * APPLY to multiple
 ***********************/
function colorCodeAllConfiguredSheets(){
  CONFIGS.forEach(cfg=>colorCodeOneSheet(cfg));
}
function colorCodeActiveSheetIfConfigured(e){
  const active=e && e.source && e.source.getActiveSheet && e.source.getActiveSheet();
  const name=active && active.getName && active.getName();
  if(!name) return;
  const cfg=cfgByName(name);
  if(cfg) colorCodeOneSheet(cfg);
}

/***********************
 * GUARD (lock + throttle)
 ***********************/
function withGuard(runFn){
  const props=PropertiesService.getDocumentProperties();
  const now=Date.now();
  const last=Number(props.getProperty(RUN_TS_KEY)||0);
  if(now - last < THROTTLE_MS) return;         // throttle
  const lock=LockService.getDocumentLock();
  if(!lock.tryLock(100)) return;               // already running
  try{
    props.setProperty(RUN_TS_KEY, String(now)); // mark run start
    runFn();
  } finally {
    lock.releaseLock();
  }
}

/***********************
 * TRIGGERS
 ***********************/
function onEdit(e){
  // Avoid double-runs: rely on installable onChange only
  // (keep this no-op; manual menu still works)
  return;
}
function onChange(e){
  if(!isAutoEnabled()) return;
  withGuard(()=> {
    // We don't trust onChange to tell us exact sheet; refresh all configured
    colorCodeAllConfiguredSheets();
  });
}

/***********************
 * MENU (constant name; no duplicates)
 ***********************/
function buildMenu(){
  const ui=SpreadsheetApp.getUi();
  const menu=ui.createMenu(MENU_NAME)
    .addItem('🎨 Color Active Sheet Now', 'manualColorCodeActive')
    .addItem('🎨 Color ALL Configured Sheets Now', 'manualColorCodeAll');

  if(isAutoEnabled()){
    menu.addItem('❌ Disable Auto-Coloring', 'disableAutoColoring');
  }else{
    menu.addItem('✅ Enable Auto-Coloring', 'enableAutoColoring');
  }
  menu.addItem('🔄 Refresh Menu', 'onOpen').addToUi();
}
function onOpen(){ buildMenu(); }

/***********************
 * MENU COMMANDS
 ***********************/
function manualColorCodeActive(){
  colorCodeActiveSheetIfConfigured({source: SpreadsheetApp.getActive()});
  SpreadsheetApp.getActiveSpreadsheet().toast('✅ Colored active sheet', 'Complete', 2);
}
function manualColorCodeAll(){
  colorCodeAllConfiguredSheets();
  SpreadsheetApp.getActiveSpreadsheet().toast('✅ Colored all configured sheets', 'Complete', 2);
}
function enableAutoColoring(){
  removeOnlyInstallableTriggers();
  ScriptApp.newTrigger('onChange')
    .forSpreadsheet(SpreadsheetApp.getActive())
    .onChange()
    .create();
  setAutoEnabled(true);
  SpreadsheetApp.getActiveSpreadsheet().toast('🟢 Auto-coloring is ON', 'Status', 3);
  colorCodeAllConfiguredSheets();
  buildMenu();
}
function disableAutoColoring(){
  removeOnlyInstallableTriggers();
  setAutoEnabled(false);
  SpreadsheetApp.getActiveSpreadsheet().toast('🔴 Auto-coloring is OFF', 'Status', 3);
  buildMenu();
}
function removeOnlyInstallableTriggers(){
  ScriptApp.getProjectTriggers().forEach(t=>{
    if(t.getHandlerFunction()==='onChange') ScriptApp.deleteTrigger(t);
  });
}

/***********************
 * TEST
 ***********************/
function testColorCoding(){ colorCodeAllConfiguredSheets(); }
