const fs = require("fs")

const logPath = process.argv[2]
if (!logPath) {
  throw new Error("usage: node check_terminal_log.js <pty-log>")
}

const bytes = fs.readFileSync(logPath)
const source = bytes.toString("utf8")
const required = [
  ["ProudBackground", "48;2;28;18;23", "dev-lee"],
  ["ProudPreviewSurface", "48;2;28;18;23", "Preview"],
  ["ProudPanel", "48;2;42;27;34", "live-repo"],
  ["ProudAccent", "48;2;240;100;43", "NORMAL"],
  ["ProudAdd", "48;2;23;56;46", "throw error"],
  ["ProudDelete", "48;2;68;33;39", "await sleep(1000)"],
  ["ProudSelection", "48;2;58;34;44m", ["Fix Capture list pagination"]],
  ["ProudPreviewBorder", "38;2;113;64;78m", "Preview"],
  ["ProudAccentText", "38;2;253;186;116m", ["▌", "Fix Capture list pagination"]],
  ["ProudBorder", "38;2;81;48;59m", "─"],
]

function stripTerminalControls(value) {
  return value
    .replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, "")
    .replace(/\x1b\([A-Z]/g, "")
    .replace(/\x1b\][^\x07]*(?:\x07|\x1b\\)/g, "")
}

function visibleAfter(sequence, text) {
  const expected = Array.isArray(text) ? text : [text]
  const needle = sequence
  let offset = 0
  while (offset < source.length) {
    const index = source.indexOf(needle, offset)
    if (index < 0) return false
    const visible = stripTerminalControls(source.slice(index, index + 5000))
    if (expected.every((item) => visible.includes(item))) return true
    offset = index + needle.length
  }
  return false
}

for (const [name, sequence, text] of required) {
  if (!source.includes(sequence)) {
    throw new Error(`${name} was not emitted to the terminal as true color (${sequence})`)
  }
  if (!visibleAfter(sequence, text)) {
    throw new Error(`${name} color was not visibly rendered near ${text}`)
  }
}

let selectionIndex = source.indexOf("▌")
let selectionFound = false
while (selectionIndex >= 0) {
  const selectionStyle = source.slice(Math.max(0, selectionIndex - 120), selectionIndex)
  if (selectionStyle.includes("38;2;253;186;116m")) {
    selectionFound = true
    break
  }
  selectionIndex = source.indexOf("▌", selectionIndex + 1)
}
if (!selectionFound) {
  throw new Error("ProudAccentText foreground was not attached to the selected PR rail")
}

console.log("terminal palette OK: " + required.map(([name]) => name).join(", "))
