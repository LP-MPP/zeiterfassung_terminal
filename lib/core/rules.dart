enum WorkState { off, working, onBreak }

WorkState stateFromLastEvent(String? lastEventType) {
  if (lastEventType == null) return WorkState.off;
  switch (lastEventType) {
    case 'IN':
    case 'BREAK_END':
      return WorkState.working;
    case 'BREAK_START':
      return WorkState.onBreak;
    case 'OUT':
    default:
      return WorkState.off;
  }
}

bool isAllowed(WorkState state, String nextEventType) {
  switch (state) {
    case WorkState.off:
      return nextEventType == 'IN';
    case WorkState.working:
      return nextEventType == 'BREAK_START' || nextEventType == 'OUT';
    case WorkState.onBreak:
      return nextEventType == 'BREAK_END';
  }
}

String eventLabel(String eventType) {
  switch (eventType) {
    case 'IN':
      return 'Kommen';
    case 'OUT':
      return 'Gehen';
    case 'BREAK_START':
      return 'Pause Start';
    case 'BREAK_END':
      return 'Pause Ende';
    default:
      return eventType;
  }
}