const STATUS_KEYS = ['present','excused','unexcused','late','unchecked'];

export function summarizeAttendance(sessions = []) {
  const counts = Object.fromEntries(STATUS_KEYS.map(key => [key, 0]));
  for (const session of sessions) for (const key of STATUS_KEYS) counts[key] += Number(session.counts?.[key] || 0);
  const controlled = counts.present + counts.excused + counts.unexcused + counts.late;
  return {
    counts,
    recorded: sessions.reduce((sum, session) => sum + Number(session.recorded || 0), 0),
    openSessions: sessions.filter(session => session.status === 'open').length,
    classCount: new Set(sessions.map(session => session.class_id)).size,
    controlled,
    attendanceRate: controlled ? Math.round((counts.present + counts.late) / controlled * 100) : null,
  };
}

export function attendanceByClass(sessions = [], classes = []) {
  return classes.map(classroom => {
    const matching = sessions.filter(session => session.class_id === classroom.id);
    const summary = summarizeAttendance(matching);
    return { classId: classroom.id, className: classroom.name, attendanceRate: summary.attendanceRate, recorded: summary.recorded };
  });
}

export function isAttendanceComplete(records = [], expectedCount = records.length) {
  return records.length === expectedCount && records.every(record => record.status && record.status !== 'unchecked');
}
