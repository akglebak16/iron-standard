// Durations only change dispatch order; they never select, skip or approve tests.
function schedule(tests, history = {}, estimates = {}) {
  const duration = name => {
    const value = history[name];
    return Number.isFinite(value) && value > 0 ? value : (estimates[name] || 1000);
  };
  return [...tests].sort((a, b) => duration(b) - duration(a) || a.localeCompare(b));
}
function jobCount(value, available, count) {
  const jobs = value === undefined ? Math.min(4, available) : Number(value);
  if (!Number.isInteger(jobs) || jobs < 1) throw Error('GODOT_TEST_JOBS / --jobs must be a positive integer');
  return Math.min(jobs, count);
}
module.exports = { schedule, jobCount };
