import fs from 'node:fs/promises';
import path from 'node:path';
import {Workbook, SpreadsheetFile} from '@oai/artifact-tool';

const root = process.argv[2];
if (!root) throw new Error('Pass the repository root.');
const outputDir = path.join(root, 'outputs/geosustain-excel-import-20261109');
await fs.mkdir(outputDir, {recursive:true});
const wb = Workbook.create();
const input = wb.worksheets.add('Crop requirements');
const guide = wb.worksheets.add('Guide');
const crops = ['Banana','Cacao','Coconut','Durian','Mango','Rice','Rubber'];
const factors = [
  ['temperature','C','annual_mean'],
  ['rainfall','mm/year','annual_mean_total'],
  ['soil_ph','pH','soil_surface'],
  ['elevation','m','terrain'],
  ['slope','%','terrain'],
  ['humidity','%','annual_mean'],
];
const headers = ['Crop','Factor','Unit','Period','Preferred minimum','Preferred maximum',
  'Absolute minimum','Absolute maximum','Source','Source URL','Notes','Valid from','Valid until'];
input.getRange('A1:M1').values = [headers];
input.getRange('A1:M201').format.font = {name:'Arial',size:10,color:'#20352C'};
input.getRange('A1:M1').format = {fill:'#176140',font:{name:'Arial',size:10,bold:true,color:'#FFFFFF'},wrapText:true,rowHeight:34};
input.getRange('A2:H201').format.fill = '#FFF9EA';
input.getRange('A2:M201').format.rowHeight = 22;
input.getRange('E2:H201').setNumberFormat('0.00');
input.getRange('L2:M201').setNumberFormat('yyyy-mm-dd');
input.getRange('A1:A201').format.columnWidth = 16;
input.getRange('B1:D201').format.columnWidth = 22;
input.getRange('E1:H201').format.columnWidth = 17;
input.getRange('I1:K201').format.columnWidth = 36;
input.getRange('L1:M201').format.columnWidth = 15;
input.getRange('A2:A201').dataValidation = {rule:{type:'list',values:crops}};
input.getRange('B2:B201').dataValidation = {rule:{type:'list',values:factors.map(row=>row[0])}};
input.getRange('C2:C201').dataValidation = {rule:{type:'list',values:[...new Set(factors.map(row=>row[1]))]}};
input.getRange('D2:D201').dataValidation = {rule:{type:'list',values:[...new Set(factors.map(row=>row[2]))]}};
input.freezePanes.freezeRows(1);
input.freezePanes.freezeColumns(2);
input.showGridLines = false;
guide.showGridLines = false;
guide.getRange('A1:C31').format.font = {name:'Arial',size:10,color:'#20352C'};
guide.getRange('A1:A31').format.columnWidth = 25;
guide.getRange('B1:B31').format.columnWidth = 58;
guide.getRange('C1:C31').format.columnWidth = 55;
guide.getRange('A2').values = [['Crop requirement import']];
guide.getRange('A2').format.font = {name:'Arial',size:14,bold:true};
guide.getRange('A4:C18').values = [
  ['Column','What to enter','Notes'],
  ['Crop','Choose one of the seven crop groups.','Banana varieties are not separate crop groups.'],
  ['Factor','Choose a supported factor listed below.','One row per crop and factor. Maximum 200 rows.'],
  ['Unit and Period','Copy the matching unit and period from the table below.','Annual rainfall cannot be replaced by monthly rainfall.'],
  ['Preferred minimum','The lower preferred value stated by your source.','Number only. Put its unit in the Unit column.'],
  ['Preferred maximum','The upper preferred value stated by your source.','Must not be below the preferred minimum.'],
  ['Absolute minimum','The lower outer limit stated by your source.','Must be at or below the preferred minimum.'],
  ['Absolute maximum','The upper outer limit stated by your source.','Must be at or above the preferred maximum.'],
  ['Source','Publication, organization or source section.','Optional. The uploaded file and row are retained as evidence.'],
  ['Source URL','An HTTPS publication link, if available.','Optional. Links are citations and are not fetched.'],
  ['Notes','Method, limitations or scope of these ranges.','Optional. Do not put passwords or personal information here.'],
  ['Valid from','An Excel date or YYYY-MM-DD.','Optional. Blank means the import date.'],
  ['Valid until','An Excel date or YYYY-MM-DD.','Optional. Blank means no expiry.'],
  ['Missing limits','Use only values documented by your source.','All four range values are required. Do not invent a missing limit.'],
  ['Cell contents','Paste values instead of formulas.','No macros, linked workbooks, NPK or training-data rows.'],
];
guide.getRange('A4:C18').format.wrapText = true;
guide.getRange('A4:C18').format.rowHeight = 36;
guide.getRange('A21:C27').values = [['Factor','Unit','Period'], ...factors];
guide.getRange('A21:C27').format.rowHeight = 24;
for (const region of ['A4:C4','A21:C21']) {
  guide.getRange(region).format = {fill:'#176140',font:{name:'Arial',size:10,bold:true,color:'#FFFFFF'}};
}
guide.getRange('A29:C30').values = [
  ['After import','Preview all rows before saving.','Only an administrator can import or activate references.'],
  ['Effect','Activated ranges update new factor checks.','AI training and saved analyses are unchanged.'],
];
guide.getRange('A29:C30').format.wrapText = true;
guide.getRange('A29:C30').format.rowHeight = 36;
wb.recalculate();
console.log((await wb.inspect({kind:'table',range:"'Crop requirements'!A1:M3",tableMaxRows:3,tableMaxCols:13,maxChars:2200})).ndjson);
for (const [sheetName,range,name] of [['Crop requirements','A1:H6','template-ranges'],['Crop requirements','I1:M6','template-sources'],['Guide','A1:C30','template-guide']]) {
  const preview = await wb.render({sheetName,range,scale:1,format:'png'});
  await fs.writeFile(path.join(outputDir,name+'.png'),new Uint8Array(await preview.arrayBuffer()));
}
const xlsx = await SpreadsheetFile.exportXlsx(wb);
const target = path.join(outputDir,'GeoSustain_crop_requirements.xlsx');
await xlsx.save(target);
await fs.mkdir(path.join(root,'backend/assets'),{recursive:true});
await fs.copyFile(target,path.join(root,'backend/assets/crop_requirements_template.xlsx'));
console.log(target);
