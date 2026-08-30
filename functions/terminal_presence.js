function publicLastEventType(state, todayKey) {
  if (!state || String(state.dayKey || "") !== todayKey) return "OUT";
  const eventType = String(state.lastEventType || "OUT");
  return ["IN", "OUT", "BREAK_START", "BREAK_END"].includes(eventType) ? eventType : "OUT";
}

module.exports = {publicLastEventType};
