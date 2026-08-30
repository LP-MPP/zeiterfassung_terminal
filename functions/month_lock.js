function monthKeysForRange(startDate, endDate) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(startDate) || !/^\d{4}-\d{2}-\d{2}$/.test(endDate) || endDate < startDate) {
    throw new Error("ABSENCE_RANGE_INVALID");
  }

  const start = new Date(`${startDate.slice(0, 7)}-01T00:00:00Z`);
  const end = new Date(`${endDate.slice(0, 7)}-01T00:00:00Z`);
  const result = [];
  for (const current = new Date(start); current <= end; current.setUTCMonth(current.getUTCMonth() + 1)) {
    if (result.length >= 120) throw new Error("ABSENCE_RANGE_TOO_LONG");
    result.push(current.toISOString().slice(0, 7));
  }
  return result;
}

function isAbsenceTransitionAllowed(currentStatus, nextStatus) {
  if (currentStatus === "PENDING") {
    return ["APPROVED", "REJECTED", "CANCELLED"].includes(nextStatus);
  }
  if (currentStatus === "APPROVED") return nextStatus === "CANCELLED";
  return false;
}

module.exports = {
  isAbsenceTransitionAllowed,
  monthKeysForRange,
};
