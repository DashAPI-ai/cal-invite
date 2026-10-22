# AGENTS.md

Guidance for AI coding agents working in this repository.

## Overview

CalInvite is a Ruby gem for generating calendar invitations (URLs and .ics files) across multiple platforms: Google, Outlook, Outlook 365, Yahoo, Apple iCal, and generic .ics. Ruby >= 3.0.0, Rails 6.0–8.0 compatible, depends on `activesupport`.

## Setup & commands

```bash
bundle install          # install dependencies
rake test                # run full test suite (default rake task)
rake test TEST=test/cal_invite/event_test.rb   # run a single test file
ruby -Itest -Ilib test/cal_invite/event_test.rb # run a single test file directly
rake rdoc                # generate RDoc documentation into doc/
rake rdoc:clean          # remove generated doc/
```

Tests are Minitest-based, files live under `test/cal_invite/`, named `*_test.rb`. Coverage is collected via SimpleCov (see `coverage/`). Always run `rake test` before considering a change complete.

## Architecture

- **`CalInvite` module** (`lib/cal_invite.rb`) — top-level entry point. Holds a singleton `CalInvite.configuration` (a `Configuration` instance) set via `CalInvite.configure { |c| ... }`.

- **`CalInvite::Event`** (`lib/cal_invite/event.rb`) — the central object. Holds all event attributes (title, start/end time, location, url, attendees, timezone, notes, multi-day sessions, all-day flag). `generate_calendar_url(provider)` is the main API: it validates the event, resolves `CalInvite::Providers::<CapitalizedProvider>`, instantiates it with `self`, and calls `#generate`. The gem deliberately caches **nothing** (output caching and the cache helpers were removed in 0.3.0; see CONFIGURATION.md's `generate_calendar_url` section for why) — don't reintroduce it. Location and virtual-meeting URL are intentionally separate fields (not merged) so each provider can format them appropriately.

- **`CalInvite::Providers`** (`lib/cal_invite/providers.rb`) — namespace with `SUPPORTED_PROVIDERS = %i[google ical outlook yahoo ics office365]`. Provider classes are autoloaded from `lib/cal_invite/providers/*.rb`. To add a new provider: create a class extending `BaseProvider`, implement `#generate`, register it here with `autoload`, and add its symbol to `SUPPORTED_PROVIDERS`.

- **`CalInvite::Providers::BaseProvider`** (`lib/cal_invite/providers/base_provider.rb`) — abstract base class. A deprecated top-level `::BaseProvider` alias (defined in `providers.rb` via `Object.deprecate_constant`, skipped if the host app already has a `BaseProvider`) remains until 0.4.0 — don't reference it from gem code. Defines the `#generate` contract (must raise `NotImplementedError` if not overridden) plus shared helpers used by subclasses: URL-building (`url_encode`, `format_description`, `format_location`, `format_url`, `format_description_with_url`, `add_optional_params`) and iCalendar property formatting (`attendees_list`, `attendee_emails`, `attendee_hash_value`, `attendee_line`, `organizer_line`, `method_value`, `status_line`, `geo_line`, `transp_line`, `busystatus_line`, `class_line`, `importance_lines`, `disallow_counter_line`, `rrule_line`, `valarm_lines`, `local_wall_time`, `vtimezone_lines`). `attendee_hash_value(attendee, key)` is the correct way to read an attendee-hash field (tries symbol then string key) — don't reintroduce `attendee[:key] || attendee["key"]`, which silently drops explicit `false` values. Each concrete provider (`Google`, `Outlook`, `Office365`, `Yahoo`, `Ical`, `Ics`) builds a provider-specific URL or content string from the `Event` using these helpers.

- **`Ics` / `IcsContent` providers** (`ics.rb`, `ics_content.rb`) — generate actual `.ics` file content (RFC 5545) rather than a URL, for direct download flows (see README's `send_data` controller example). `Ics` is the **only** `.ics` generator: `Ical` and `IcsContent` are empty subclasses kept for their public names, so make content changes in `ics.rb` only. `IcsDownload` (HTTP header/filename helpers) lives in `ics_content.rb` alongside `IcsContent` (not an alias). All ics-family providers accept a `method:` (`:publish`/`:request`/`:cancel`/`:reply`/`:counter`/`:decline_counter`) passed through `Event#generate_calendar_url`. Use `BaseProvider#method_value` (not `method.to_s.upcase`) when emitting the `METHOD:` line — `:decline_counter` must render as `METHOD:DECLINECOUNTER` (one word) per RFC 5545, unlike its Ruby symbol. `:request` plus `Event#organizer` produces an RFC 5545 meeting request that mail clients render with RSVP actions; `:cancel` (reusing the same `Event#uid`, with `Event#sequence` bumped) produces a real cancellation; `:reply`/`:counter`/`:decline_counter` all omit `RSVP=TRUE` on `ATTENDEE` lines (none of them request a further response). `Event#uid` is stable (auto-generated and memoized per instance, or pass your own) — required so a later `:request`/`:cancel` is recognized as updating the original invite rather than creating a new one. `Event#attendees` entries can be plain email strings or `{ email:, name:, partstat:, rsvp: }` hashes (`partstat:` drives `PARTSTAT=` on the `ATTENDEE` line, default `NEEDS-ACTION`; `rsvp:` overrides the method-derived `RSVP=TRUE`/absent default — needed for e.g. a registration-confirmation invite where the attendee is already `:accepted` and `rsvp: false` suppresses it under `method: :request`). Optional `Event` fields `geo`, `reminders`, `busy`, `visibility`, `rrule`, `calendar_name` map to `GEO:`, `VALARM`, `TRANSP:`, `CLASS:`, `RRULE:`, and `X-WR-CALNAME` respectively; `importance`/`allow_counter` map to Outlook's non-standard `X-MICROSOFT-CDO-IMPORTANCE`/`X-MICROSOFT-DISALLOW-COUNTER` (plus standard `PRIORITY:` and `X-MICROSOFT-CDO-BUSYSTATUS` alongside `TRANSP:`) — safe to always emit since unrecognized `X-` properties are required to be ignored by other clients. See `CONFIGURATION.md`.
- **Timezones** — `:ics`/`:ical` build a real `VTIMEZONE` (via `CalInvite::IcalTimezone`, backed by `tzinfo`) for any recognized IANA `timezone` other than `'UTC'`, and correctly convert `start_time`/`end_time` (always UTC) to that zone's local wall-clock time for `DTSTART;TZID=...`. `'UTC'` uses plain `Z`-suffixed timestamps with no `VTIMEZONE`. `Event#validate!` rejects any other `timezone` (`IcalTimezone.valid?`), so providers can rely on it being UTC or a real IANA zone.

- **`Configuration`** (`lib/cal_invite/configuration.rb`) — holds `webhook_secret` and `timezone` (default `'UTC'`; the default `Event#timezone` when `timezone:` isn't passed). `cache_store`/`cache_prefix`/`cache_expires_in` are deprecated no-ops kept until 0.4.0: their setters warn (`uplevel: 2`, so the warning points at the caller's initializer) but still store the value so app code reading them keeps working.

## Conventions

- Always pass times to `Event.new` in UTC; use the `timezone` attribute only to control display/formatting in the generated invite.
- **Treat every `Event` attribute as untrusted input** (host apps pass end-user strings: titles, display names, ...). In `.ics` output: TEXT values go through `Ics#escape_text`; parameter values (e.g. `CN=`) through `BaseProvider#quoted_param` (RFC 6868); enumerated/numeric values are whitelisted or coerced (`class_line`, `geo_line`, `sequence_line`); and `Ics#ensure_single_line_values!` raises on any CR/LF left in a content line — never bypass it or interpolate a raw attribute into a property/parameter. URL providers must pass every value through `url_encode`. Add a case to `test/cal_invite/ics_security_test.rb` for any new property.
- `location` (physical) and `url` (virtual meeting link) are kept as distinct fields throughout the provider layer — don't conflate them when adding provider logic.
- All-day events skip `start_time`/`end_time` validation; multi-day events use the separate `multi_day_sessions` array instead of `start_time`/`end_time`. `Event#start_time`/`#end_time` are readers that fall back to the earliest session start / latest session end when not set explicitly (computed on read, so they follow `update_attributes`), which is what single-range URL providers use.
- YARD-style doc comments (`@param`, `@return`, `@example`) are used throughout `lib/` and feed the RDoc-generated docs published to GitHub Pages (`.github/workflows/documentation.yml`) — keep them accurate when changing public method signatures.
- CalInvite is outbound-only: it renders `.ics` content/URLs and has no concept of inbound RSVP replies. It also can't express Google/Microsoft Calendar-API-only concepts like guest permissions (`guestsCanInviteOthers` etc.) since those have no `.ics`/URL representation at all — but it does generate the genuinely protocol-level equivalents that exist: `METHOD:COUNTER`/`DECLINECOUNTER` and Outlook's `X-MICROSOFT-*` extensions (`allow_counter`, `importance`, `busy`). See CONFIGURATION.md's "Tracking RSVPs" and "Guest permissions" sections for the full breakdown of what's real vs. not addable, and why.

## Example app (`Example/calendar_app`)

Rails 8.1 app demonstrating the gem. Its Gemfile depends on the **published** `cal-invite` gem (never commit it pointing at `path: "../.."`) — when testing example-app changes that rely on unreleased gem code, temporarily uncomment the `path: "../.."` line locally, `bundle install`, test, then revert the Gemfile and re-run `bundle install` against rubygems before committing. `Meeting`/`MeetingAttendee` (with a migration) is a working reference implementation of the `uid`/`sequence` persistence pattern CONFIGURATION.md describes — see `app/models/meeting.rb`, `app/controllers/meetings_controller.rb` (create/reschedule/cancel, plus `show` serving a cached `.ics` with `stale?` + `Rails.cache` per CACHING.md), and `app/controllers/event_replies_controller.rb` (illustrative inbound `METHOD:REPLY` parsing, not wired to a real inbound-email provider).

## PRs & commits

Gem released via standard Bundler `rake release` flow (`bundler/gem_tasks`). Version lives in `lib/cal_invite/version.rb`; update `CHANGELOG.md` alongside version bumps.
