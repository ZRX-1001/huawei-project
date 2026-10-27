const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const ts = require(process.argv[2] || 'typescript');
const root = path.join(__dirname, '../entry/src/main/ets');
const cache = new Map();
const plain = value => JSON.parse(JSON.stringify(value));
const files = new Map(), descriptors = new Map();
let nextId = 1, diskFailure = false, allowed = true, enabled = true, publishingFails = false;
let permissionHook = () => {}, shares = 0, publishes = 0;
const fileIo = {
  OpenMode: { CREATE: 1, WRITE_ONLY: 2, TRUNC: 4 },
  accessSync: p => files.has(p), readTextSync: p => files.get(p),
  openSync(p) { if (diskFailure) throw Error('disk full'); const file = { fd: nextId++ }; descriptors.set(file.fd, p); return file; },
  writeSync(fd, data) { files.set(descriptors.get(fd), data); }, fsyncSync() {}, closeSync() {},
  copyFileSync(a, b) { files.set(b, files.get(a)); },
  renameSync(a, b) { files.set(b, files.get(a)); files.delete(a); }
};
let eventId = 100;
const makeCalendar = id => ({ id, events: [], fail: false,
  async queryEventInstances(start, end, ids, keys) { if (this.fail) throw Error('denied');
    const events = plain(this.events.filter(e => e.startTime < end && e.endTime > start));
    if (!keys?.includes('reminderTime')) events.forEach(e => delete e.reminderTime);
    if (!keys?.includes('recurrenceRule')) events.forEach(e => delete e.recurrenceRule);
    return events; },
  async getEvents(filter) { return plain(filter.ids ? this.events.filter(e => filter.ids.includes(e.id)) : this.events.filter(e => e.startTime < filter.end && e.endTime > filter.start)); },
  async addEvent(event) { const id = eventId++; this.events.push({ ...event, id }); return id; },
  async updateEvent(event) { this.events[this.events.findIndex(e => e.id === event.id)] = event; },
  async deleteEvent(id) { this.events = this.events.filter(e => e.id !== id); }
});
const primary = makeCalendar(1), secondary = makeCalendar(2);
const manager = { getAllCalendars: async () => [primary, secondary], getCalendar: async () => primary };
const calendarManager = { getCalendarManager: () => manager, EventType: { NORMAL: 0 },
  EventFilter: { filterById: ids => ({ ids }), filterByTime: (start, end) => ({ start, end }) } };
const reminders = [];
const reminderAgentManager = {
  ReminderType: { REMINDER_TYPE_TIMER: 0, REMINDER_TYPE_CALENDAR: 1, REMINDER_TYPE_ALARM: 2 },
  async getAllValidReminders() { return reminders; },
  async publishReminder(request) { publishes++; if (publishingFails) throw Object.assign(Error('permission restricted'), { code: 1700002 });
    const reminderId = nextId++; reminders.push({ reminderId, reminderReq: request }); return reminderId; },
  async cancelReminder(id) { const index = reminders.findIndex(r => r.reminderId === id); if (index >= 0) reminders.splice(index, 1); }
};
const kits = {
  '@kit.AbilityKit': { abilityAccessCtrl: { createAtManager: () => ({ checkAccessTokenSync: () => allowed ? 0 : -1, async requestPermissionsFromUser(ctx, permissions) {
    permissionHook(); return { authResults: permissions.map(() => allowed ? 0 : -1) }; } }) } },
  '@kit.CalendarKit': { calendarManager }, '@kit.BackgroundTasksKit': { reminderAgentManager },
  '@kit.NotificationKit': { notificationManager: { SlotType: { SOCIAL_COMMUNICATION: 1 }, isNotificationEnabled: async () => enabled,
    requestEnableNotification: async () => {}, addSlot: async () => {} } },
  '@kit.BasicServicesKit': { systemDateTime: { getTimezoneSync: () => 'Asia/Shanghai' } },
  '@kit.CoreFileKit': { fileIo }, '@kit.ArkTS': { util: { generateRandomUUID: () => `memo-${nextId++}` } },
  '@kit.ShareKit': { systemShare: { SharedData: class { constructor(record) { this.record = record; } },
    ShareController: class { async show(ctx, options) { assert.ok(options.anchor); shares++; } } } }
};
function load(file) {
  const absolute = path.resolve(root, file + '.ets');
  if (cache.has(absolute)) return cache.get(absolute);
  const result = {}; cache.set(absolute, result);
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(absolute, 'utf8'), { compilerOptions: {
    module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2020 } }).outputText, {
    exports: result, require: name => {
      if (kits[name]) return kits[name];
      if (!name.startsWith('.')) throw Error('Unexpected dependency: ' + name);
      return load(path.relative(root, path.resolve(path.dirname(absolute), name)));
    }
  });
  return result;
}
const { ScheduleService: service } = load('services/ScheduleService');
const { HarmonyScheduleAdapter: Native } = load('services/HarmonyScheduleAdapter');
const { MemoStore } = load('services/MemoStore');
const { ChatService } = load('services/ChatService');
const { ScheduleOverviewService: overview } = load('services/ScheduleOverviewService');
const platform = new Native({ filesDir: '/data', applicationInfo: { name: 'test.app' } });
let active = true;
const yes = async () => true, no = async () => false;
const call = (name, args, confirm = yes) => service.execute({ id: 'test', name, arguments: JSON.stringify(args) }, platform, () => active, confirm);
const future = new Date(Math.ceil((Date.now() + 86400000) / 60000) * 60000).toISOString().replace('.000', '');
const later = new Date(Date.parse(future) + 3600000).toISOString().replace('.000', '');
const event = { title: 'Schedule regression fixture', start: future, end: later, description: 'Keep this description', reminderMinutes: [10] };

(async () => {
  assert.equal(service.tools().length, 9);
  assert.equal(new Set(service.tools().map(t => t.function.name)).size, 9);
  assert.equal(service.handles('delete_everything'), false);
  for (const [name, args] of [
    ['get_system_time', { arbitrary: true }], ['query_calendar_events', { start: 'tomorrow', end: later }],
    ['query_calendar_events', { start: later, end: future }], ['create_calendar_event', { ...event, start: '2026-02-30T09:00:00+08:00' }],
    ['create_calendar_event', { ...event, start: '2026-10-28T24:00:00+08:00' }], ['create_calendar_event', { ...event, reminderMinutes: [-1] }],
    ['delete_calendar_event', { calendarId: 1, eventId: '2' }], ['delete_calendar_event', { calendarId: 1, eventId: 2.2 }],
    ['create_system_reminder', { kind: 'alarm', title: 'wake', hour: 24, minute: 0 }],
    ['create_system_reminder', { kind: 'alarm', title: 'wake', hour: 7, minute: 0, weekdays: [0] }],
    ['create_system_reminder', { kind: 'timer', title: 'work', seconds: 0 }],
    ['create_system_reminder', { kind: 'calendar', title: 'work', at: '2020-01-01T08:00:00Z' }],
    ['create_system_reminder', { kind: 'timer', title: 'work', seconds: 60, hour: 7 }],
    ['manage_memo', { action: 'delete' }], ['manage_memo', { action: 'save', title: ' ', content: 'body' }]
  ]) assert.throws(() => service.validate(name, JSON.stringify(args)), name + JSON.stringify(args));
  for (const args of ['null', '[]', '123', '"hello"']) assert.throws(() => service.validate('get_system_time', args));
  assert.throws(() => service.instant('2026-10-28T08:00:00+14:30'));
  assert.equal(service.instant('2026-10-28T08:00:00+08:00'), service.instant('2026-10-28T00:00:00Z'));
  assert.equal(service.instant('2026-10-28T00:00:00.000Z'), service.instant('2026-10-28T00:00:00Z'), 'native ISO strings round trip');
  assert.equal(service.localLabel(Date.parse(service.localInstant('2026-10-28 09:00'))), '2026-10-28 09:00');
  assert.throws(() => service.localInstant('2026-02-30 09:00'));
  assert.throws(() => service.localInstant('2026-10-28 24:00'));
  assert.equal((await call('get_system_time', {})).timeZone, 'Asia/Shanghai');
  assert.ok(ChatService.request('what time?', 'home', [], { context: '' }).systemInstruction.includes('当前设备时间'));

  allowed = false;
  const backgroundNative = new Native({ filesDir: '/data', applicationInfo: { name: 'test.app', accessTokenId: 1 } }, false);
  assert.equal((await service.execute({ id: 'bg', name: 'query_calendar_events', arguments: JSON.stringify({ start: future, end: later }) }, backgroundNative, () => true, yes)).ok, false, 'background reads never open a permission prompt');
  assert.equal((await call('query_calendar_events', { start: future, end: later })).ok, false);
  assert.equal((await call('create_calendar_event', event)).ok, false);
  assert.equal(primary.events.length, 0);
  allowed = true;
  assert.equal((await call('create_calendar_event', event, no)).status, 'cancelled');
  assert.equal(primary.events.length, 0);
  permissionHook = () => { active = false; };
  assert.equal((await call('create_calendar_event', event)).ok, false);
  permissionHook = () => {}; active = true;
  assert.equal((await call('create_calendar_event', event, async () => { active = false; return true; })).ok, false);
  active = true; assert.equal(primary.events.length, 0);

  const created = await call('create_calendar_event', event);
  assert.equal(created.ok, true); assert.equal(created.entries[0].calendarId, 1);
  assert.deepEqual(plain(created.entries[0].reminderMinutes), [10]);
  const overviewCalendar = await overview.list('calendar', platform, () => true);
  assert.ok(overviewCalendar.entries.some(e => e.eventId === created.entries[0].eventId));
  const zeroAlert = await call('create_calendar_event', { ...event, title: 'On-time calendar alert', reminderMinutes: [0] });
  const noAlert = await call('create_calendar_event', { ...event, title: 'No alert', reminderMinutes: [] });
  const overviewReminders = await overview.list('reminders', platform, () => true);
  assert.ok(overviewReminders.entries.some(e => e.eventId === zeroAlert.entries[0].eventId), 'zero minute calendar alerts belong in reminders');
  assert.ok(!overviewReminders.entries.some(e => e.eventId === noAlert.entries[0].eventId));
  assert.match(overviewReminders.entries.find(e => e.eventId === zeroAlert.entries[0].eventId).detail, /日历提醒[\s\S]*\n提醒：准时/);
  await call('delete_calendar_event', { calendarId: 1, eventId: zeroAlert.entries[0].eventId });
  await call('delete_calendar_event', { calendarId: 1, eventId: noAlert.entries[0].eventId });
  assert.equal((await call('create_calendar_event', event)).status, 'already_exists');
  assert.equal(primary.events.length, 1);
  const id = created.entries[0].eventId;
  secondary.fail = true;
  const partial = await call('query_calendar_events', { start: future, end: later });
  assert.equal(partial.ok, true); assert.equal(partial.partial, true); assert.equal(partial.entries.length, 1);
  primary.fail = true;
  assert.equal((await call('query_calendar_events', { start: future, end: later })).ok, false);
  primary.fail = secondary.fail = false;
  assert.equal((await call('update_calendar_event', { calendarId: 1, eventId: id, title: 'Renamed' })).ok, true);
  assert.equal(primary.events[0].description, event.description);
  assert.deepEqual(plain(primary.events[0].reminderTime), [10]);
  primary.events[0].recurrenceRule = { recurrenceFrequency: -1 };
  const singleInstance = await call('query_calendar_events', { start: future, end: later });
  assert.ok(!singleInstance.entries[0].detail.includes('重复日程'), 'native empty recurrence sentinels are not repeating events');
  assert.equal((await call('update_calendar_event', { calendarId: 1, eventId: id, title: 'Renamed' })).ok, true);
  assert.equal((await call('update_calendar_event', { calendarId: 1, eventId: id, end: '2020-01-01T00:00:00Z' })).ok, false);
  assert.equal(primary.events[0].endTime, Date.parse(later), 'rejected patch leaves native data unchanged');
  primary.events[0].recurrenceRule = { recurrenceFrequency: 1 };
  assert.equal((await call('delete_calendar_event', { calendarId: 1, eventId: id })).ok, false);
  delete primary.events[0].recurrenceRule;
  assert.equal((await call('delete_calendar_event', { calendarId: 1, eventId: id }, no)).ok, false);
  assert.equal(primary.events.length, 1);
  assert.equal((await call('delete_calendar_event', { calendarId: 1, eventId: id })).ok, true);
  assert.equal(primary.events.length, 0);

  const alarmArgs = { kind: 'alarm', title: 'Wake regression fixture', hour: 7, minute: 30, weekdays: [1, 3, 5] };
  enabled = false;
  assert.equal((await call('create_system_reminder', alarmArgs)).ok, false); assert.equal(publishes, 0);
  enabled = true; publishingFails = true;
  const restricted = await call('create_system_reminder', alarmArgs);
  assert.equal(restricted.ok, false); assert.match(restricted.message, /数量已达上限/); assert.equal(reminders.length, 0);
  assert.equal(restricted.status, 'reminder_restricted');
  assert.match(restricted.message, /有效提醒0项/); assert.match(restricted.message, /上限也可能为0/);
  assert.match(restricted.message, /Profile/); assert.match(restricted.message, /不能据此认定是其他应用占满/);
  publishingFails = false;
  const beforeCancelledPublish = publishes;
  assert.equal((await call('create_system_reminder', alarmArgs, async () => { active = false; return true; })).ok, false);
  assert.equal(publishes, beforeCancelledPublish, 'stopping during review cannot publish afterwards'); active = true;
  const alarm = await call('create_system_reminder', alarmArgs);
  assert.equal(alarm.ok, true); assert.deepEqual(plain(reminders[0].reminderReq.daysOfWeek), [1, 3, 5]);
  assert.equal((await call('list_system_reminders', {})).entries[0].reminderId, alarm.entries[0].reminderId);
  const dated = await call('create_system_reminder', { kind: 'calendar', title: 'Dated fixture', at: future });
  assert.equal(dated.ok, true);
  const date = new Date(future), nativeDate = reminders[1].reminderReq.dateTime;
  assert.equal(nativeDate.hour, date.getHours()); assert.equal(nativeDate.month, date.getMonth() + 1);
  const timer = await call('create_system_reminder', { kind: 'timer', title: 'Timer fixture', seconds: 1500 });
  assert.equal(timer.ok, true); assert.equal(reminders[2].reminderReq.triggerTimeInSeconds, 1500);
  const mergedOverview = await overview.list('reminders', platform, () => true);
  assert.equal(mergedOverview.entries.filter(e => e.kind === 'reminder').length, 3);
  primary.fail = secondary.fail = true;
  const degradedOverview = await overview.list('reminders', platform, () => true);
  assert.equal(degradedOverview.ok, true); assert.equal(degradedOverview.partial, true);
  assert.equal(degradedOverview.entries.length, 3, 'calendar read failure does not hide successful proxy results');
  primary.fail = secondary.fail = false;
  assert.equal((await call('cancel_system_reminder', { reminderId: 99999 })).ok, false);
  assert.equal((await call('cancel_system_reminder', { reminderId: alarm.entries[0].reminderId }, no)).ok, false);
  assert.equal((await call('cancel_system_reminder', { reminderId: alarm.entries[0].reminderId })).ok, true);
  assert.equal(reminders.length, 2);

  assert.equal((await call('manage_memo', { action: 'save', title: 'memo', content: 'body' }, no)).ok, false);
  assert.equal((await call('manage_memo', { action: 'list' })).entries.length, 0);
  const memo = await call('manage_memo', { action: 'save', title: 'Memo fixture', content: 'Take ID card' });
  assert.equal(memo.ok, true); const memoId = memo.entries[0].id;
  let store = new MemoStore('/data'); assert.equal(store.get(memoId).content, 'Take ID card');
  assert.equal((await call('manage_memo', { action: 'save', id: memoId, title: 'Updated', content: 'Take umbrella' })).ok, true);
  store = new MemoStore('/data'); assert.equal(store.get(memoId).content, 'Take umbrella');
  assert.equal((await call('manage_memo', { action: 'read', id: memoId })).entries[0].content, 'Take umbrella');
  assert.equal((await call('manage_memo', { action: 'list' })).entries[0].content, undefined, 'lists do not flood the model with full note bodies');
  const largeMemo = await call('manage_memo', { action: 'save', title: 'Long fixture', content: 'full text '.repeat(150) });
  assert.ok((await call('manage_memo', { action: 'list' })).entries.find(e => e.id === largeMemo.entries[0].id).detail.length < 500);
  assert.equal((await call('manage_memo', { action: 'read', id: largeMemo.entries[0].id })).entries[0].content.length, 1500);
  assert.equal((await call('manage_memo', { action: 'delete', id: largeMemo.entries[0].id })).ok, true);
  assert.equal((await call('manage_memo', { action: 'share', id: memoId })).status, 'share_opened'); assert.equal(shares, 1);
  diskFailure = true;
  assert.equal((await call('manage_memo', { action: 'save', title: 'No disk', content: 'must fail' })).ok, false);
  diskFailure = false;
  assert.equal((await call('manage_memo', { action: 'list' })).entries.length, 1);
  assert.equal((await call('manage_memo', { action: 'delete', id: memoId })).ok, true);
  assert.equal(new MemoStore('/data').list().length, 0);
  files.set('/data/local_memos.json', 'corrupt');
  assert.equal(new MemoStore('/data').list().length, 0, 'backup keeps deletions across recovery');
  files.set('/data/local_memos.json.bak', 'corrupt too');
  assert.throws(() => new MemoStore('/data').list(), /读取失败/);
  active = false;
  assert.equal((await call('manage_memo', { action: 'save', title: 'stale', content: 'no write' })).ok, false);
  console.log('PASS: native schedule adapter with mocked SDK — strict dates/arguments, calendar CRUD and partial reads, permission/cancellation gates, reminder failures/ids, persistent memo CRUD/recovery and truthful share receipts.');
})().catch(error => { console.error(error); process.exitCode = 1; });
