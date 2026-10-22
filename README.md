# CalInvite

![CalInvite: calendar invitations for Ruby. Google, Outlook, Apple, Yahoo, .ics](assets/social/cal-invite-github.webp)

Generate "add to calendar" links and `.ics` calendar invites from Ruby, for Google Calendar, Outlook, Outlook 365, Yahoo, Apple Calendar, and any client that reads iCalendar files.

[![Gem Version](https://badge.fury.io/rb/cal-invite.svg)](https://badge.fury.io/rb/cal-invite)
![Build Status](https://github.com/DashAPI-ai/cal-invite/actions/workflows/main.yml/badge.svg)
![License](https://img.shields.io/github/license/DashAPI-ai/cal-invite.svg)

- **One event, every calendar.** Describe an event once and get a URL or `.ics` content for each provider.
- **Real email invites.** `method: :request` produces an RFC 5545 meeting request that Gmail, Outlook and Apple Mail show with Accept/Decline buttons. You can also send updates and cancellations that replace the original invite.
- **Correct timezones.** A full `VTIMEZONE` for any IANA zone, with times converted properly.
- **Safe with user input.** Values are escaped so end-user strings can't inject extra properties into an invite.

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Providers](#providers)
- [More examples](#more-examples)
- [Serving a downloadable .ics file](#serving-a-downloadable-ics-file)
- [Sending email invites with RSVP](#sending-email-invites-with-rsvp)
- [Things to know](#things-to-know)
- [Upgrading to 0.3.0](#upgrading-to-030)
- [Documentation](#documentation)
- [Development](#development)

## Installation

Requires Ruby 3.0 or newer. It works with or without Rails, and supports Rails 6.0 through 8.1.

```ruby
# Gemfile
gem "cal-invite"
```

```bash
bundle install
```

## Quick start

```ruby
require "cal_invite"

event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.utc(2026, 11, 2, 15, 0),   # always pass UTC
  end_time:   Time.utc(2026, 11, 2, 16, 0),
  timezone: "America/New_York",               # how the time is displayed
  description: "Weekly sync",
  location: "Conference Room A",              # physical place
  url: "https://zoom.us/j/123456789"          # virtual meeting link
)

event.generate_calendar_url(:google)  # => "https://calendar.google.com/calendar/render?action=TEMPLATE&..."
event.generate_calendar_url(:ics)     # => "BEGIN:VCALENDAR\r\n..." (.ics file content)
```

## Providers

| Provider     | Returns | Notes |
|--------------|---------|-------|
| `:google`    | URL | Opens Google Calendar's "add event" page. |
| `:outlook`   | URL | Outlook.com (personal accounts). |
| `:office365` | URL | Outlook on the web for work/school (Microsoft 365) accounts. |
| `:yahoo`     | URL | One URL per session for multi-day events, separated by newlines. |
| `:ics`       | `.ics` content | Standard iCalendar file; works with Apple Calendar, Thunderbird, Proton, Fastmail and others. |
| `:ical`      | `.ics` content | Same content as `:ics`; kept for Apple Calendar naming. |

Only `:ics` and `:ical` support the `method:` option (`:publish` by default, also `:request`, `:cancel`, `:reply`, `:counter`, `:decline_counter`). Any other provider name raises `ArgumentError`.

## More examples

```ruby
# Attendees: email strings, or hashes with a display name and RSVP status
CalInvite::Event.new(
  title: "Planning",
  start_time: Time.utc(2026, 11, 2, 15), end_time: Time.utc(2026, 11, 2, 16),
  attendees: ["bob@example.com", { email: "ada@example.com", name: "Ada", partstat: :accepted }],
  show_attendees: true
)

# All-day event
CalInvite::Event.new(title: "Company Offsite", start_time: Time.utc(2026, 12, 4), all_day: true)

# Recurring event, with a reminder 15 minutes before
CalInvite::Event.new(
  title: "Standup",
  start_time: Time.utc(2026, 11, 2, 14), end_time: Time.utc(2026, 11, 2, 14, 15),
  timezone: "Europe/Paris",
  rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
  reminders: [15]
)

# Multi-day event with separate sessions
CalInvite::Event.new(
  title: "Training Workshop",
  multi_day_sessions: [
    { start_time: Time.utc(2026, 3, 1, 13), end_time: Time.utc(2026, 3, 1, 22) },
    { start_time: Time.utc(2026, 3, 2, 14), end_time: Time.utc(2026, 3, 2, 18) }
  ],
  timezone: "America/New_York",
  location: "Training Center"
)
```

For a multi-day event, `:ics`, `:ical` and `:yahoo` produce one entry per session. Google and Outlook can only show one range, so they show the whole span, from the first session's start to the last session's end.

Every attribute (`organizer`, `geo`, `busy`, `visibility`, `importance`, `calendar_name`, ...) is listed in [CONFIGURATION.md](CONFIGURATION.md#event-attributes).

## Serving a downloadable .ics file

```ruby
# app/controllers/events_controller.rb
def calendar
  event = CalInvite::Event.new(...)
  download = CalInvite::Providers::IcsDownload.wrap_for_download(
    event.generate_calendar_url(:ics), event.title
  )

  send_data download[:content],
            type: download[:headers]["Content-Type"],
            filename: "#{CalInvite::Providers::IcsDownload.sanitize_filename(event.title)}.ics",
            disposition: "attachment"
end
```

## Sending email invites with RSVP

A plain `.ics` attachment opens as a file. To have mail clients show it as a meeting invite with Accept/Decline buttons, you need three things: an `organizer`, `method: :request`, and a matching `method=REQUEST` on the attachment's content type.

```ruby
event = CalInvite::Event.new(
  title: "Design Review",
  start_time: Time.utc(2026, 11, 2, 15), end_time: Time.utc(2026, 11, 2, 16),
  organizer: { name: "Jane Doe", email: "jane@example.com" },
  attendees: ["guest@example.com"],
  show_attendees: true
)

# In your ActionMailer method:
attachments["invite.ics"] = {
  mime_type: "text/calendar; method=REQUEST",
  content: event.generate_calendar_url(:ics, method: :request)
}
```

Save `event.uid`. To reschedule or cancel later, rebuild the event with the **same `uid`** and a **higher `sequence`**, then send `method: :request` again (for a reschedule) or `method: :cancel`. See [Updating and cancelling invites](CONFIGURATION.md#updating-and-cancelling-invites). The [example Rails app](Example/calendar_app) has a working implementation.

## Things to know

- **Times are always UTC.** Pass UTC `Time`s for `start_time`/`end_time`. `timezone` only controls how the time is displayed. It must be `"UTC"` or an IANA name such as `"America/New_York"`, and defaults to `CalInvite.configuration.timezone` (`"UTC"`).
- **`location` and `url` are separate.** Put the physical place in `location` and the video-call link in `url`. Each provider formats them its own way.
- **Mistakes raise `ArgumentError`.** That covers a misspelled attribute (`locaton:`), an unknown timezone, an end time before the start time, and an unsupported provider.
- **CalInvite only sends.** It generates links and invites, but it doesn't receive RSVP replies and can't set Google/Microsoft API-only options such as guest permissions. See [Tracking RSVPs](CONFIGURATION.md#tracking-rsvps-what-the-gem-does-and-doesnt-do).
- **Nothing is cached.** Output is cheap to build, so it's generated fresh on every call.

Global settings:

```ruby
# config/initializers/cal_invite.rb
CalInvite.configure do |config|
  config.timezone = "America/New_York"   # default for events that don't set one
end
```

## Upgrading to 0.3.0

0.3.0 is stricter. Unknown attributes, invalid timezones and invalid time ranges now raise `ArgumentError`, where 0.2.x silently produced a broken invite. The gem also no longer loads all of `active_support/core_ext`. In plain Ruby, `1.hour` and `Time.current` no longer work unless you require them yourself.

The `cache_store`/`cache_prefix`/`cache_expires_in` settings and the top-level `::BaseProvider` constant are deprecated. They still work, but print a warning, and they'll be removed in 0.4.0. The full list of changes is in [CHANGELOG.md](CHANGELOG.md).

## Documentation

- [CONFIGURATION.md](CONFIGURATION.md): every attribute, provider and option, plus guides for email invites, updates and cancellations, RSVP status, COUNTER proposals, and timezones.
- [API reference](https://dashapi-ai.github.io/cal-invite/): generated from the YARD comments (`bundle exec rake rdoc` builds it locally).
- [CHANGELOG.md](CHANGELOG.md): release history.

## Development

```bash
bin/setup                                                  # install dependencies
bundle exec rake test                                      # full suite (+ coverage report in coverage/)
bundle exec rake test TEST=test/cal_invite/event_test.rb   # one file
bin/console                                                # IRB with the local lib/ loaded
```

To try unreleased changes in the [example Rails app](Example/calendar_app), switch its Gemfile to the commented-out `gem "cal-invite", path: "../../"` line and run `bundle install`. Switch it back before committing.

**Releasing:** bump `lib/cal_invite/version.rb`, update `CHANGELOG.md`, and merge to `main`. Then push a `vX.Y.Z` tag. CI runs the tests, publishes the gem to RubyGems and deploys the docs.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/DashAPI-ai/cal-invite). Please add tests for your change and run `bundle exec rake test` before opening a PR. To report a security issue, see [SECURITY.md](SECURITY.md). Everyone taking part in the project is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

Released under the [MIT License](https://opensource.org/licenses/MIT).
