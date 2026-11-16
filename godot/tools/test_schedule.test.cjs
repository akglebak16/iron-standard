const assert = require('node:assert/strict');
const { schedule, jobCount } = require('./test_schedule.cjs');
const tests = ['fast', 'medium', 'slow', 'new'];
const history = { fast: 1, medium: 10, slow: 100, deleted: 9000 };
const ordered = schedule(tests, history);
assert.deepEqual([...ordered].sort(), [...tests].sort(), 'History cannot skip a new test or resurrect a deleted one');
assert.deepEqual(tests, ['fast', 'medium', 'slow', 'new'], 'Caller order is immutable');
assert.ok(ordered.indexOf('slow') < ordered.indexOf('fast'));
assert.deepEqual(schedule(['bad', 'missing'], { bad: '9000' }, { missing: 2000 }), ['missing', 'bad']);
assert.equal(jobCount(undefined, 2, 100), 2);
assert.equal(jobCount('6', 16, 100), 6);
assert.equal(jobCount('4', 16, 1), 1);
for (const invalid of ['0', '-1', 'NaN', '1.5']) assert.throws(() => jobCount(invalid, 16, 100));
// A late long test must not leave workers idle at the end of the queue.
const makespan = order => {
  const workers = [0, 0];
  for (const test of order) workers[workers.indexOf(Math.min(...workers))] += history[test];
  return Math.max(...workers);
};
assert.ok(makespan(schedule(['fast', 'medium', 'slow'], history)) < makespan(['fast', 'medium', 'slow']));
console.log('Test scheduling checks passed');
