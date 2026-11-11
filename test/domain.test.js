import test from 'node:test';
import assert from 'node:assert/strict';
import { attendanceByClass, isAttendanceComplete, summarizeAttendance } from '../src/domain.js';

test('attendance rate excludes unchecked records and counts late as present', () => {
  const summary = summarizeAttendance([{ class_id:'a', status:'open', recorded:5, counts:{present:2,late:1,excused:1,unexcused:0,unchecked:1} }]);
  assert.equal(summary.attendanceRate, 75);
  assert.equal(summary.controlled, 4);
  assert.equal(summary.recorded, 5);
});

test('statistics return no invented percentage when there are no controlled entries', () => {
  assert.equal(summarizeAttendance([{ class_id:'a', recorded:1, counts:{unchecked:1} }]).attendanceRate, null);
  assert.equal(summarizeAttendance([]).attendanceRate, null);
});

test('class statistics are calculated separately from saved status data', () => {
  const result = attendanceByClass([
    {class_id:'a',recorded:2,counts:{present:1,unexcused:1}},
    {class_id:'b',recorded:1,counts:{late:1}},
  ],[{id:'a',name:'5a'},{id:'b',name:'6a'},{id:'c',name:'7a'}]);
  assert.deepEqual(result.map(x=>x.attendanceRate),[50,100,null]);
  assert.deepEqual(result.map(x=>x.recorded),[2,1,0]);
});

test('a list cannot be completed while a student remains unchecked or is missing', () => {
  assert.equal(isAttendanceComplete([{status:'present'},{status:'excused'}],2),true);
  assert.equal(isAttendanceComplete([{status:'present'},{status:'unchecked'}],2),false);
  assert.equal(isAttendanceComplete([{status:'present'}],2),false);
});
