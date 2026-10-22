# 📅 CalInvite

A Ruby gem for generating calendar invitations across multiple calendar platforms with webhook support.

[![Gem Version](https://badge.fury.io/rb/cal-invite.svg)](https://badge.fury.io/rb/cal-invite)
![Build Status](https://github.com/DashAPI-ai/cal-invite/actions/workflows/main.yml/badge.svg)

![License](https://img.shields.io/github/license/DashAPI-ai/cal-invite.svg)

## Compatibility

- Ruby >= 3.0.0
- Rails 6.0, 6.1, 7.0, 7.1, 8.0, 8.1

## Supported Calendar Platforms

Direct Integration:
- Apple iCal (with proper timezone support)
- Microsoft Outlook
- Microsoft Outlook 365
- Google Calendar
- Yahoo Calendar
- Standard .ics file generation

Any calendar application that supports the iCalendar (.ics) standard should work, including but not limited to:
- Proton Calendar
- FastMail Calendar
- Thunderbird Calendar
- Zoho Calendar
- Microsoft Teams Calendar
- Zoom Calendar Integration

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'cal-invite'
```

And then execute:
```bash
$ bundle install
```

Or install it yourself as:
```bash
$ gem install cal-invite
```

## Usage

### Basic Event Creation

Important notes:
- Always provide times in UTC
- Use the timezone parameter to specify the display timezone
- Location and URL are handled separately for better calendar integration

For the full list of `Event` attributes, providers, and configuration options, see [CONFIGURATION.md](CONFIGURATION.md).

```ruby
# Create an event with physical location
event = CalInvite::Event.new(
  title: "Team Meeting",
  start_time: Time.current.utc,  # Always use UTC times
  end_time: Time.current.utc + 2.hours,
  description: "Weekly team sync",
  location: "Conference Room A",  # Physical location
  timezone: "America/New_York",  # Display timezone
  attendees: ["person@example.com"],
  show_attendees: true,
  notes: "Please bring your laptop"
)

# Create an event with both physical and virtual locations
event = CalInvite::Event.new(
  title: "Hybrid Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 2.hours,
  description: "Weekly team sync",
  location: "Conference Room A",  # Physical location
  url: "https://zoom.us/j/123456789",  # Virtual meeting URL
  timezone: "America/New_York",
  attendees: ["person@example.com"],
  show_attendees: true
)

# All-day event
event = CalInvite::Event.new(
  title: "Company All-Day Event",
  start_time: Date.today.beginning_of_day.utc,
  end_time: Date.today.end_of_day.utc,
  all_day: true,
  timezone: "America/New_York"
)

# Multi-day event
event = CalInvite::Event.new(
  title: "Training Workshop",
  multi_day_sessions: [
    {
      start_time: Time.parse("2024-03-01 08:00:00 UTC"),
      end_time: Time.parse("2024-03-01 17:00:00 UTC")
    },
    {
      start_time: Time.parse("2024-03-02 09:00:00 UTC"),
      end_time: Time.parse("2024-03-02 13:00:00 UTC")
    }
  ],
  description: "Advanced Ruby Training",
  location: "Training Center",
  url: "https://zoom.us/j/123456789",  # Virtual meeting URL kept separate
  timezone: "America/New_York",
  notes: "Bring your own laptop"
)

# Generate calendar URLs
ical_url       = event.generate_calendar_url(:ical)
google_url     = event.generate_calendar_url(:google)
outlook_url    = event.generate_calendar_url(:outlook)
outlook365_url = event.generate_calendar_url(:office365)
yahoo_url      = event.generate_calendar_url(:yahoo)
```

### Implementing ICS Downloads

To enable ICS file downloads in your application, you'll need to:

1. Create an endpoint that will handle the download request
2. Generate the ICS content
3. Send the file to the user

Here's a basic example of the controller logic:

```ruby
# In your controller action
def download_calendar
  event = # ... your event creation logic ...
  
  content = CalInvite::Providers::Ics.new(event).generate
  filename = "#{event.title.downcase.gsub(/[^0-9A-Za-z.\-]/, '_')}_#{Time.now.strftime('%Y%m%d')}.ics"
  
  send_data(
    content,
    filename: filename,
    type: 'text/calendar; charset=UTF-8',
    disposition: 'attachment'
  )
end
```

You can implement this in any controller and route that makes sense for your application's architecture.

### Sending Email Meeting Invites (RSVP-capable)

By default, a `.ics` attachment opens as a file in most mail clients. To get
Gmail/Outlook/Apple Mail to render the message as an invite with Accept/Decline
actions (like Luma or Google Calendar invites do), set an `organizer` on the
event and pass `method: :request` when generating. Full walkthrough and all
options in [CONFIGURATION.md](CONFIGURATION.md#email-meeting-invites-rsvp-capable).

### ICS File Generation

The gem provides two ways to generate ICS files:

1. Direct content generation:
```ruby
event = CalInvite::Event.new(
  title: "Meeting",
  start_time: Time.current.utc,
  end_time: Time.current.utc + 1.hour,
  timezone: "America/New_York"
)

# Generate ICS content
content = CalInvite::Providers::Ics.new(event).generate
```

2. Rails controller integration:
```ruby
# In your controller
def download_ics
  event = CalInvite::Event.new(
    title: "Meeting",
    start_time: Time.current.utc,
    end_time: Time.current.utc + 1.hour,
    timezone: "America/New_York"
  )
  
  content = CalInvite::Providers::Ics.new(event).generate
  filename = "#{event.title.downcase.gsub(/[^0-9A-Za-z.\-]/, '_')}_#{Time.now.strftime('%Y%m%d')}.ics"
  
  send_data(
    content,
    filename: filename,
    type: 'text/calendar; charset=UTF-8',
    disposition: 'attachment'
  )
end
```

### Important Notes

1. Time Handling:
   - Always provide times in UTC to the Event constructor
   - Use the timezone parameter to specify the display timezone
   - All-day events should use beginning_of_day.utc and end_of_day.utc

2. Location and URL:
   - Physical location goes in the `location` parameter
   - Virtual meeting URL goes in the `url` parameter
   - They are handled separately for better calendar integration

3. ICS Files:
   - Both Apple iCal and standard ICS files now properly handle timezones
   - Attendees are properly formatted with RSVP options
   - Virtual meeting URLs are properly separated from physical locations

## Caching Support

Generated URLs and `.ics` content are not cached: they're cheap to build and always fresh. `CalInvite.configure` still accepts a `cache_store` (e.g. `Rails.cache`) backing small prefixed cache helpers (`CalInvite.fetch_from_cache` etc.) you can use yourself.

For why output isn't cached, how to cache it at your own layer, and the helper API, see the [Caching Guide](https://github.com/DashAPI-ai/cal-invite/blob/master/CACHING.md). For every other configuration option (`Event` attributes, providers, email invites), see [CONFIGURATION.md](CONFIGURATION.md).

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Testing

Add test(s) as necessary.

Run all the tests before submitting: `bundle exec rake test`

There are three ways to exercise the gem while working on a change:

**1. Unit tests** (Minitest, under `test/cal_invite/`) — use these to lock a change in:

```bash
bundle exec rake test                                      # full suite (+ SimpleCov report in coverage/)
bundle exec rake test TEST=test/cal_invite/event_test.rb   # a single file
```

**2. Interactive console** — `bin/console` opens IRB with your local `lib/` loaded, handy for eyeballing generated URLs and `.ics` output:

```ruby
event = CalInvite::Event.new(
  title: "Demo",
  start_time: Time.utc(2026, 11, 1, 15),
  end_time: Time.utc(2026, 11, 1, 16),
  timezone: "America/New_York",
  organizer: { email: "me@example.com", name: "Me" },
  attendees: ["guest@example.com"],
  show_attendees: true
)

puts event.generate_calendar_url(:ics, method: :request)  # raw .ics content
event.generate_calendar_url(:google)                      # provider URL
```

**3. Example Rails app** (`Example/calendar_app`) — for end-to-end checks in a real browser or mail client (downloading the `.ics`, RSVP buttons, etc.). Its Gemfile points at the published gem; to test unreleased changes, temporarily swap `gem "cal-invite"` for the commented-out `gem "cal-invite", path: "../../"` line and run `bundle install`. Revert the Gemfile and re-run `bundle install` before committing.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/DashAPI-ai/cal-invite. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/DashAPI-ai/cal-invite/blob/master/CODE_OF_CONDUCT.md).

## Documentation

The documentation is spread across the README, [CONFIGURATION.md](CONFIGURATION.md), [CACHING.md](CACHING.md), and the doc folder.

The documentation can be generated using `bundle exec rake rdoc`

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Cal::Invite project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/DashAPI-ai/cal-invite/blob/master/CODE_OF_CONDUCT.md).