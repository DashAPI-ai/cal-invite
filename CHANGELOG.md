# Cal Invite

## [v0.3.0] - 2026-10-22

### Upgrading from 0.2.x

These changes can break existing callers:

- **Unknown `Event` attributes raise.** `Event.new` and `Event#update_attributes` raise `ArgumentError` (`Unknown attribute(s): locaton`) for keys that aren't `Event` attributes, instead of silently ignoring them. If you pass a whole params hash, slice it first. A rejected `update_attributes` leaves the event unchanged. (#10)
- **`timezone` is validated.** It must be `'UTC'` or an IANA identifier known to tzinfo (e.g. `'America/New_York'`); anything else, including raw offsets like `'+01:00'`, raises `ArgumentError`. Such values previously produced invalid `.ics` (a `TZID=` with no `VTIMEZONE`, times shifted by the offset) and could inject parameters. (#7)
- **Time order is validated.** `ArgumentError` when `end_time` isn't after `start_time` (all-day events may end on the same date), or a `multi_day_sessions` entry is missing a time or ends before it starts. (#9)
- **Provider names are validated.** `generate_calendar_url` raises `ArgumentError` listing the supported providers for anything outside `CalInvite::Providers::SUPPORTED_PROVIDERS` (`:ics_content` still works as an alias of `:ics`). Previously e.g. `:string` resolved Ruby's `String` and failed confusingly. (#11)
- **`config.timezone` is now honored** as the default `Event#timezone` when `timezone:` isn't passed, as documented. If you set it to something other than `'UTC'`, your events now render in that zone. An explicit `timezone:` still wins. (#22)
- **No more blanket `active_support/core_ext`.** Requiring `cal_invite` no longer monkey-patches core classes (`Integer#hours`, `Object#blank?`, `String#squish`, ...) in non-Rails apps. Plain-Ruby code that used those only because `cal_invite` loaded them must `require "active_support/core_ext"` (or the specific file). Rails apps are unaffected. This also lets the gem load with ActiveSupport 6.0 on Ruby 4.0. (#15)

### Removed

- **Output caching.** `generate_calendar_url` builds its output fresh on every call and never touches a cache store; `update_attributes` no longer wipes every event's cache entries. The cache ignored `cache_prefix`, almost never hit, froze `.ics` `DTSTAMP`, and cost more than regenerating. Output is unchanged. To cache anyway, do it in your app; CONFIGURATION.md has an example. (#14)
- **Cache helpers.** `CalInvite.fetch_from_cache`, `write_to_cache`, `read_from_cache`, `clear_cache!`, `clear_event_cache!`, `clear_provider_cache!` and `CalInvite::Caching` are gone. They had never worked (every call raised `NoMethodError`). `CACHING.md` is gone too. (#32)

### Deprecated (removed in 0.4.0)

- **`config.cache_store=`, `cache_prefix=`, `cache_expires_in=`** have no effect. They print `warning: [cal_invite] Configuration#cache_store= is deprecated and has no effect ...` pointing at your initializer line, but still store the value, so code that reads them keeps working. Delete them from your initializer. (#32)
- **`::BaseProvider`.** The provider base class is now `CalInvite::Providers::BaseProvider`, so the gem no longer owns a top-level constant that can collide with your app's. `::BaseProvider` remains as an alias (not defined at all if your app has its own `BaseProvider`). Ruby prints `constant ::BaseProvider is deprecated` when deprecation warnings are enabled (e.g. `RUBYOPT=-W:deprecated`). (#13)

### Security

- **Fix content-line/parameter injection in `.ics` output** (`:ics`, `:ical`, `IcsContent`). A CR or LF in event attributes (title, description, attendee/organizer names and emails, `uid`, `rrule`, `visibility`, `geo`, ...), or a `"` in a display name, could add arbitrary properties to a generated invite (e.g. extra attendees, a different `METHOD:`). URL providers were not affected. (#5)
  - TEXT values are escaped per RFC 5545 (backslashes were previously left unescaped and lone `\r` passed through).
  - `CN=` display names are quoted and escaped per RFC 6868.
  - `URL:` is no longer TEXT-escaped (it's a URI; commas and semicolons in links were being corrupted).
  - Values that can't be escaped raise `ArgumentError` if they contain a line break. `visibility` must be `:public`/`:private`/`:confidential`, `geo` numeric, and `sequence` an integer.
- `SECURITY.md`: real policy (supported versions, private reporting via GitHub Security Advisories).

### Added

- `organizer:` accepts a plain email string (`organizer: "jane@example.com"`), like `attendees`; a string previously crashed `.ics` generation with `TypeError`. String-keyed hashes are read too. (#12)
- Multi-day events no longer need top-level `start_time`/`end_time`: they default to the earliest session start and latest session end, so the README's multi-day example works. `:google`/`:outlook`/`:office365` show the overall span; `:ics`/`:ical`/`:yahoo` still emit one entry per session. Explicit times win. (#24)

### Fixed

- `.ics` content lines longer than 75 octets are folded (RFC 5545 §3.1), never splitting a multi-byte UTF-8 character. Long lines could be mangled or rejected by Outlook and mail gateways. (#6)
- `'UTC'` events emit `Z`-suffixed `DTSTART`/`DTEND` instead of `TZID=UTC` with no `VTIMEZONE`. (#7)
- `:ical` and `IcsContent` now produce exactly the same content as `:ics`. `IcsContent` previously emitted UTC-only times with no `VTIMEZONE`, ignored `notes`, and didn't support all-day events. `:ics` all-day events without times default to today, as `:ical` did. (#4)
- Non-UTC timezones under tzinfo 1.x (Rails/ActiveSupport 6.0): `:ics`/`:ical` raised `NoMethodError` (`to_local`) and silently omitted `VTIMEZONE`. (#17)
- `Event.new` no longer mutates the attributes hash passed in (it used to delete several keys from it, so reusing the hash dropped them). (#8)

### Docs

- README "Testing" section covers `rake test`, `bin/console`, and the Example app's local-path Gemfile workflow. `CLAUDE.md` merged into `AGENTS.md`.

## [v0.2.1] - 2026-08-10

- `:google` provider: honor `Event#attendees`/`show_attendees` (`add=`), `Event#timezone` (`ctz=`), `Event#rrule` (`recur=`), and `Event#busy` (`crm=BUSY`/`AVAILABLE`) in the generated Google Calendar URL — these were already modeled on `Event` for the ics providers but never wired into `:google`.
- `:outlook`/`:office365` providers: honor `Event#busy` via `freebusy=`.
- `:outlook`/`:office365` providers: fix stale deep-link URLs. Switched from the legacy `outlook.live.com/calendar/0/action/compose` and `outlook.office.com/owa/` hosts to the currently documented `outlook.live.com/calendar/deeplink/compose` and `outlook.office.com/calendar/deeplink/compose`, and added the required `rru=addevent` param.
- CI: fix Rails 6 + Ruby 3.3/3.4 test failures (missing `logger`/`mutex_m`/`bigdecimal` requires), fix RDoc doc generation (stale `.rdoc_options` crashing the darkfish generator and silently excluding all of `lib/`), and fix a GitHub Pages deploy deadlock (duplicate `concurrency: group: "pages"` between `main.yml` and the reusable `documentation.yml`).

## [v0.2.0] - 2026-08-09

- Add `Event#organizer` and a `method:` option (`:publish`/`:request`/`:cancel`) to `generate_calendar_url`, so ics/ical output can carry `METHOD:REQUEST`/`METHOD:CANCEL` + `ORGANIZER`/`SEQUENCE`/`STATUS`, matching what mail clients (Gmail, Outlook, Apple Mail) need to render an attached `.ics` as an RSVP-capable meeting invite (or a real cancellation) rather than a plain file
- `ATTENDEE` lines now include `CUTYPE`/`ROLE`/`PARTSTAT`
- `IcsDownload.headers`/`.wrap_for_download` accept `method:` to add the matching `method=REQUEST` Content-Type parameter
- Fix a `superclass mismatch` crash when both the `:ics` provider and `IcsDownload`/`IcsContent` were loaded (dead duplicate `Ics`/`Ical` class definitions in `ics_content.rb`)
- **Fix: stable `UID`.** `Event#uid` is now a real attribute (auto-generated and memoized per `Event` instance, or pass your own) instead of the ics/ical/ics_content providers each minting a fresh random UID on every `generate` call — required for mail/calendar clients to recognize a `:request` update or `:cancel` as referring to a previously sent invite rather than a new, unrelated event. See new `Event#sequence` (defaults to `0`) and CONFIGURATION.md's "Updating and cancelling invites".
- **Fix: real `VTIMEZONE`.** `:ics`/`:ical` now emit a complete `VTIMEZONE` component (`STANDARD`/`DAYLIGHT` observances with correct offsets and `RRULE`s, derived from TZInfo's transition data) for any recognized IANA timezone, instead of an empty/absent block. `DTSTART;TZID=...`/`DTEND;TZID=...` are also now correctly converted from UTC to that zone's local wall-clock time — previously the UTC clock digits were emitted verbatim under a non-UTC `TZID`, mislabeling the time. `'UTC'` continues to use plain `Z`-suffixed timestamps with no `VTIMEZONE`, as before.
- Add `tzinfo` as an explicit gem dependency (previously relied on it only transitively via `activesupport`).
- `Event#attendees` entries can now be `{ email:, name:, partstat: }` hashes (plain email strings still work) — `ATTENDEE` lines gain `CN=` and a settable `PARTSTAT` (`:accepted`/`:declined`/`:tentative`/`:needs_action`/`:delegated`) instead of always `NEEDS-ACTION`.
- Add `method: :reply`, for building an attendee's `METHOD:REPLY` back to an organizer (omits `RSVP=TRUE`, honors each attendee's `partstat:`).
- Add `Event#geo` (`GEO:` property), `Event#reminders` (`VALARM` blocks), `Event#busy` (`TRANSP:`), `Event#visibility` (`CLASS:`), `Event#rrule` (raw `RRULE:` recurrence value), and `Event#calendar_name` (`X-WR-CALNAME` on the `VCALENDAR`) — all optional, all emitted by `:ics`/`:ical`/`IcsContent`.
- Add `method: :counter`/`:decline_counter`, generating `METHOD:COUNTER`/`METHOD:DECLINECOUNTER` for an attendee proposing a new time and an organizer rejecting it, respectively. (Note: `:decline_counter` correctly renders as `METHOD:DECLINECOUNTER` — one word per RFC 5545 — not a literal upcase of the Ruby symbol; fixed via a new `BaseProvider#method_value` used everywhere a `METHOD:`/`method=` value is emitted, including `IcsDownload.headers`.)
- Add `Event#importance` (`:low`/`:normal`/`:high` → standard `PRIORITY:` + Outlook's `X-MICROSOFT-CDO-IMPORTANCE:`) and `Event#allow_counter` (default `true`; `false` → Outlook's `X-MICROSOFT-DISALLOW-COUNTER:TRUE`, hiding its "Propose New Time" action) and `X-MICROSOFT-CDO-BUSYSTATUS` alongside the existing `TRANSP:` — genuinely real, protocol-level, Outlook-specific properties (confirmed against Microsoft's documented `.ics` extensions), safe to always emit since RFC 5545 requires unrecognized `X-` properties be ignored by other clients.
- CONFIGURATION.md: rewrite "Guest permissions" — Google/Microsoft's guest-permission toggles are confirmed API-only (no `.ics` property, no parameter on Google's own "add to calendar" render URL either), but the section now documents the real Outlook-specific levers above as the closest addable equivalent. Rewrite "Attendee-proposed reschedules (COUNTER)" now that generation is implemented, with the caveat that mainstream mail clients still don't reliably expose a "propose new time" UI to trigger one from. Add "Tracking RSVPs" (inbound `METHOD:REPLY` webhook vs. provider-API alternative, with the Gmail reliability caveat) for the RSVP-tracking gap, which remains genuinely outbound-only.
- `Example/calendar_app`: add a working `Meeting`/`MeetingAttendee` persistence example (migration + models + `MeetingsController#create`/`#reschedule`/`#cancel` + `MeetingMailer`) demonstrating the `uid`/`sequence` lifecycle end-to-end, plus an illustrative `EventRepliesController` showing how to parse an inbound `METHOD:REPLY` email. The example app's Gemfile still tracks the published gem — this demo needs 0.2.0, so run it locally against `path: "../.."` until that's released.
- Add per-attendee `rsvp:` override (`{ email:, name:, partstat:, rsvp: }`) so `RSVP=TRUE` can be suppressed even under `method: :request` — needed for a "registration confirmed" style invite where the recipient is already `partstat: :accepted` and nothing is actually being requested. **Fixed a real bug found while adding it**: the existing symbol/string dual-key lookup pattern (`attendee[:key] || attendee["key"]`) silently discards an explicit `false` value (`false || x` evaluates to `x` in Ruby, not `false`), which would have made `rsvp: false` a no-op; replaced with `BaseProvider#attendee_hash_value`, used for all attendee-hash reads.
- CONFIGURATION.md: add "Replicating a ticketing-platform confirmation email" — a full worked example (matching a real Luma-style confirmation email byte-for-byte in structure, brand names genericized) covering the `partstat: :accepted, rsvp: false` attendee pattern, the full ActionMailer attachment setup, why `From`/`Reply-To`/`ORGANIZER` can legitimately all differ, and an explicit note that Apple Wallet `.pkpass` passes are an unrelated technology (PassKit, not iCalendar) and out of scope for this gem.

## [Released]

## [v0.1.7] - 2025-11-09

- Upgrading to support Rails 8.1
- Support gems upgrades

## [v0.1.6] - 2024-12-20

- Adding Mailer example

## [v0.1.5] - 2024-12-19

- Should deploy the doc to a GitHub page
- Fixing a version number in the CHANGELOG file

## [v0.1.4] - 2024-12-19

- Add support to RDoc

## [v0.1.3] - 2024-12-19

- Apple iCal and ics file can now be either generated or wrap to be downloaded
- Add Caching management support
- Add CACHING.md for more details about how to use caching in a Rails app
- Updating the README file to reflect latest usage changes
- Minor bug fixes and improvments.

## [v0.1.2] - 2024-12-17

⚠️ This version should not be used

- Add support to Microsoft office 365 calendar invite URL
- Update the README
- Add an example
- Better testing

## [v0.1.1] - 2024-12-17

⚠️ This version should not be used

Fixing a bug in the gemspec file

## [Unreleased]

## [v0.1.0] - 2024-12-17

First public release of the Calendar Invite gem

Support the calendar invites for the following calendars:

- Microsoft Outlook
- Google Calendar
- Yahoo Calendar

Support Apple iCal

Support other calendars via .ics
