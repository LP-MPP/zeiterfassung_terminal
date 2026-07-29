"use strict";

function addAbsenceToBalance(totals, {type, status, days}) {
  const next = {...totals};

  if (type === "URLAUB") {
    if (status === "APPROVED") next.used += days;
    else if (status === "PENDING") next.planned += days;
  } else if (type === "KRANKHEIT" && status === "APPROVED") {
    next.sickDays += days;
  } else if (type === "SONDERURLAUB" && status === "APPROVED") {
    next.specialLeaveDays += days;
  }

  return next;
}

module.exports = {addAbsenceToBalance};
