# Cal Invite

## [v0.2.11] - 2026-10-22

- `Event#generate_calendar_url` now validates the provider against `CalInvite::Providers::SUPPORTED_PROVIDERS` and raises `ArgumentError` naming the supported providers. Previously the name was passed to `const_get`, which fell back to top-level constants, so e.g. `:string` resolved Ruby's `String` and failed with a confusing `unknown keyword: :method`. `:ics_content` keeps working as a legacy alias of `:ics`. (#11)

## [v0.2.10] - 2026-10-22

- **Breaking:** `Event.new` and `Event#update_attributes` now raise `ArgumentError` (`Unknown attribute(s): locaton`) for keys that aren't `Event` attributes, instead of silently ignoring them — so typos no longer drop data. Callers passing extra keys (e.g. a whole params hash) must slice them first. `update_attributes` checks every key before assigning, so a rejected call leaves the event unchanged. (#10)

## [v0.2.9] - 2026-10-22

- `Event` now raises `ArgumentError` when `end_time` isn't after `start_time` (RFC 5545 requires `DTEND` later than `DTSTART`; all-day events may end on the same date), and when a `multi_day_sessions` entry is missing a time or ends before it starts. Previously these produced nonsensical invites. (#9)

## [v0.2.8] - 2026-10-22

- `Event.new` no longer mutates the attributes hash passed in. It used to `delete` `timezone`, `show_attendees`, `uid`, `sequence`, `busy`, `visibility`, `allow_counter`, `all_day` and `multi_day_sessions` from the caller's hash, so reusing it for a second event silently dropped them. (#8)

## [v0.2.7] - 2026-10-22

- **Breaking:** `Event` now validates `timezone` and raises `ArgumentError` unless it's `'UTC'` or an IANA identifier recognized by tzinfo (e.g. `'America/New_York'`). Previously an unrecognized value — including raw offsets like `'+01:00'` — produced `DTSTART;TZID=<value>` with no matching `VTIMEZONE` (invalid RFC 5545, and times shifted by the offset), and a `;`/`:` in it could inject parameters into the `TZID=` line. (#7)
- `'UTC'` events now emit `Z`-suffixed `DTSTART`/`DTEND` (as already documented) instead of `TZID=UTC` with no `VTIMEZONE`.

## [v0.2.6] - 2026-10-22

- `.ics` output (`:ics`, `:ical`, `IcsContent`) now folds content lines longer than 75 octets (CRLF + single space, RFC 5545 §3.1), never splitting a multi-byte UTF-8 character. Long descriptions and attendee lines previously exceeded the limit, which Outlook and some mail gateways can mangle or reject. (#6)

## [v0.2.5] - 2026-10-22

- **Security:** fix content-line/parameter injection in `.ics` output (`:ics`, `:ical`, `IcsContent`). A CR or LF in event attributes (title, description, attendee/organizer names and emails, `uid`, `rrule`, `visibility`, `geo`, ...), or a `"` in a display name, could add arbitrary properties to a generated invite (e.g. extra attendees, a different `METHOD:`). URL providers were not affected. (#5)
  - TEXT values are now escaped per RFC 5545 (backslashes were previously left unescaped and lone `\r` passed through).
  - `CN=` display names are quoted and escaped per RFC 6868.
  - `URL:` is no longer TEXT-escaped (it is a URI value; commas/semicolons in links were being corrupted).
  - Values that can't be escaped raise `ArgumentError` if they contain a line break. `visibility` must be `:public`/`:private`/`:confidential`, `geo` must be numeric, and `sequence` must be an integer; invalid values now raise `ArgumentError` instead of being emitted.
- `SECURITY.md`: real policy (supported versions, private reporting via GitHub Security Advisories).

## [v0.2.4] - 2026-10-22

- `:ical` provider and `CalInvite::Providers::IcsContent` now delegate to the `:ics` generator, so all three produce identical RFC 5545 content. `IcsContent` previously emitted UTC-only times with no `VTIMEZONE`, ignored `notes`, and didn't support all-day events; `:ical` differed from `:ics` in property order and `PRODID`. (#4)
- `:ics` all-day events without `start_time`/`end_time` now default to today (one-day span), matching the previous `:ical` behavior instead of raising.

## [v0.2.3] - 2026-10-22

- Fix non-UTC timezones under tzinfo 1.x (Rails/ActiveSupport 6.0): `:ics`/`:ical` raised `NoMethodError` (`to_local`) for any non-UTC `timezone`, and `VTIMEZONE` was silently omitted. `IcalTimezone` now only uses APIs shared by tzinfo 1.2+ and 2.x; output is unchanged on tzinfo 2. (#17)

## [v0.2.2] - 2026-10-22

- Docs: README "Testing" section now covers the three ways to exercise the gem locally (`rake test` incl. single-file runs, `bin/console` with a working sample event, and the Example app's local-path Gemfile workflow).
- Docs: removed `CLAUDE.md` in favor of `AGENTS.md`, merging in its newer guidance.

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
