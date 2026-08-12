const MAX_PUNCH_NOTE_LENGTH = 300;

function preparePunchNote(value, eventType, employmentType) {
  if (value != null && typeof value !== "string") {
    return {ok: false, message: "Die Tätigkeit muss als Text übermittelt werden."};
  }

  const note = String(value ?? "")
      .replace(/\r\n?/g, "\n")
      .trim();

  if (Array.from(note).length > MAX_PUNCH_NOTE_LENGTH) {
    return {
      ok: false,
      message: `Die Tätigkeit darf maximal ${MAX_PUNCH_NOTE_LENGTH} Zeichen enthalten.`,
    };
  }

  if (note && eventType !== "OUT") {
    return {
      ok: false,
      message: "Eine Tätigkeit kann nur beim Auschecken erfasst werden.",
    };
  }

  if (note && employmentType !== "MINIJOB") {
    return {
      ok: false,
      message: "Eine Tätigkeit kann nur für Minijobber erfasst werden.",
    };
  }

  return {ok: true, note: note || null};
}

module.exports = {
  MAX_PUNCH_NOTE_LENGTH,
  preparePunchNote,
};
