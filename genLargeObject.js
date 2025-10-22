///Use that file to generate a large JSON file.
const fs = require('fs');

function generateTestJSON(sizeInMB) {
  const obj = {};

//   const entry = { name: "Item", value: 123.456, active: true, tags: ["a", "b", "c"] };
//   const entry = { name: "Item", value: 123.456, active: true };
//   const entry = { name: "Item", value: 123.456};
//   const entry = { value: 123.456};
  // const entry = { name: "Item"};
  const entry = { active: true};
  let strData = JSON.stringify(entry);
  let data = "{";

  let i = 0;
  while (data.length < sizeInMB * 1024 * 1024) {
    data+= `"key${i++}": ${strData},`;
  }
  return data.substring(0, data.length-1) + "}";
}

function testJSONParseSpeed(jsonString) {
  const sizeMB = Buffer.byteLength(jsonString, 'utf8') / (1024 * 1024);

  const start = process.hrtime.bigint();
  const result = JSON.parse(jsonString);
  const end = process.hrtime.bigint();

  const durationSec = Number(end - start) / 1e9;
  const speedMBps = sizeMB / durationSec;

  console.log(`Parsed: ${sizeMB.toFixed(2)} MB in ${durationSec.toFixed(4)} s`);
  console.log(`Speed: ${speedMBps.toFixed(2)} MB/s`);

  return speedMBps;
}


// Main
const sizeMB = 50; // Tamanho do JSON em MB
const json = generateTestJSON(sizeMB);
fs.writeFileSync("testJson.json", json);
testJSONParseSpeed(json)