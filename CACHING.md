# Caching CalInvite output in your application

CalInvite doesn't cache anything (see the [0.3.0 changelog](CHANGELOG.md)). Building a URL or `.ics` file is in-memory string work that takes microseconds, and the gem can't know when your data changes. Your application does, so caching belongs there.

This guide shows a few ways to do it in plain Ruby, Rails, Sinatra, Hanami and Grape. It isn't exhaustive. Every example was run against the framework version named in its section.

## Contents

- [Do you need a cache?](#do-you-need-a-cache)
- [Four rules for correct caching](#four-rules-for-correct-caching)
- [The example model](#the-example-model)
- [Plain Ruby](#plain-ruby)
- [Rails 8.1](#rails-81)
- [Sinatra](#sinatra)
- [Hanami](#hanami)
- [Grape](#grape)

## Do you need a cache?

Usually not for the output itself. Caching it pays off in two cases:

- **Repeated downloads of the same `.ics`.** Calendar apps that subscribe to a feed poll it every few minutes to hours. HTTP caching (`ETag`/`Last-Modified` and a `304 Not Modified` reply) saves the bandwidth and lets the client skip re-importing an unchanged file. This is the most useful kind of caching for calendar files.
- **Expensive work before the gem runs.** If building the `Event` means loading a meeting, its attendees and its venue from the database, cache the result to skip those queries. CalInvite's own share of the time is negligible.

Don't cache invites you send by email (`method: :request`, `:cancel`, ...). Each send should be generated when it's sent; see rule 3.

## Four rules for correct caching

1. **Key on the data's version, not on the output.** The key needs the record's identity, something that changes whenever the record changes (`updated_at`, a version column, the invite `sequence`), and every input that changes the output: provider, `method:`, and anything that varies per viewer, such as whether attendees are shown.
2. **Persist the event's `uid`.** Without an explicit `uid:`, each `Event` gets a random one, so two builds of the same meeting produce different `.ics` content. Store the `uid` on your record and pass it in.
3. **Never build an `ETag` by hashing the `.ics` content.** Every generation writes the current time into `DTSTAMP`, so the hash changes on every request and the client never gets a `304`. Derive the `ETag` from the record's version. A cached `.ics` also keeps the `DTSTAMP` from when it was cached. That's harmless for downloads and feeds, but it's another reason to generate emailed invites fresh.
4. **Include the configured timezone if it can change at runtime.** `CalInvite.configuration.timezone` is the default `timezone` for events. Most apps set it once at boot, so it doesn't need to be in the key.

## The example model

The plain Ruby, Sinatra, Hanami and Grape examples use this stand-in for a database record. In Rails it's an Active Record model with the same `to_cal_invite_event` method.

```ruby
require "cal_invite"

Meeting = Struct.new(:id, :title, :starts_at, :ends_at, :uid, :sequence, :updated_at, keyword_init: true) do
  def to_cal_invite_event
    CalInvite::Event.new(title: title, start_time: starts_at, end_time: ends_at, uid: uid, sequence: sequence)
  end

  # Changes whenever the meeting changes (rule 1).
  def cache_version
    "#{id}-#{updated_at.to_i}-#{sequence}"
  end
end

MEETINGS = {
  1 => Meeting.new(id: 1, title: "Design review", uid: "meeting-1@example.com", sequence: 0,
                   starts_at: Time.utc(2026, 11, 2, 15), ends_at: Time.utc(2026, 11, 2, 16),
                   updated_at: Time.utc(2026, 10, 20, 9))
}
```

## Plain Ruby

Written for Ruby 3.4 and run on Ruby 4.0. Ruby 4.0 doesn't add anything that changes these patterns; see [Ruby 4.0](#ruby-40) below.

### A small in-process LRU cache

A `Hash` keeps insertion order, so deleting and re-inserting a key on each hit makes the first key the least recently used one. A `Mutex` keeps it safe under threaded servers like Puma.

```ruby
class IcsCache
  def initialize(max_entries: 1_000)
    @max_entries = max_entries
    @entries = Hash.new(capacity: max_entries) # Ruby 3.4+: allocate the table once
    @lock = Mutex.new
  end

  def fetch(key)
    @lock.synchronize do
      return @entries[key] = @entries.delete(key) if @entries.key?(key) # move to most recent
    end

    value = yield # generate outside the lock
    @lock.synchronize do
      @entries[key] = value
      @entries.shift while @entries.size > @max_entries # evict least recently used
    end
    value
  end
end

ICS_CACHE = IcsCache.new

def meeting_ics(meeting)
  ICS_CACHE.fetch([meeting.cache_version, :ics, :publish]) do
    meeting.to_cal_invite_event.generate_calendar_url(:ics)
  end
end
```

When a meeting changes, its `cache_version` changes, so the next call misses and the old entry ages out. Nothing has to be deleted by hand.

Each server process has its own copy of this cache. That's fine for a single process or a small app. If several processes or machines should share one cache, use a shared store such as Redis.

### ActiveSupport cache stores

CalInvite already depends on `activesupport`, so its cache stores are available without Rails. `MemoryStore` adds a size limit and expiry to the pattern above, and the same `fetch` call works with `RedisCacheStore` (add the `redis` gem) or `FileStore` when processes need to share a cache.

```ruby
require "active_support"

STORE = ActiveSupport::Cache::MemoryStore.new(size: 32 * 1024 * 1024, expires_in: 3600)

def meeting_ics_from_store(meeting)
  STORE.fetch(["meeting-ics", meeting.cache_version]) do
    meeting.to_cal_invite_event.generate_calendar_url(:ics)
  end
end
```

On ActiveSupport 7.x and earlier, loading the cache stores also loads some of ActiveSupport's core extensions. ActiveSupport 8 doesn't.

### Ruby 4.0

Nothing in Ruby 4.0 improves this kind of caching. The headline changes are the `Ractor::Port` API, `Set` becoming a core class, and the experimental `Ruby::Box` isolation. The `Mutex`-guarded `Hash` above can't be shared between Ractors, but web servers and frameworks run requests on threads or processes rather than Ractors, so this doesn't affect normal applications. Both examples above run unchanged on 4.0.

## Rails 8.1

Tested with Rails 8.1. `Rails.cache` is the cache store (Solid Cache by default since Rails 8.0), and `stale?` handles conditional GET: it sets `ETag` and `Last-Modified` from the record and answers `304 Not Modified` when the client's copy is current. Rails already knows the `text/calendar` MIME type as `:ics`.

```ruby
# config/routes.rb
resources :meetings, only: :show

# app/models/meeting.rb
class Meeting < ApplicationRecord
  def to_cal_invite_event
    CalInvite::Event.new(title: title, start_time: starts_at, end_time: ends_at, uid: uid, sequence: sequence)
  end
end

# app/controllers/meetings_controller.rb
class MeetingsController < ApplicationController
  def show
    meeting = Meeting.find(params[:id])

    respond_to do |format|
      format.ics do
        # ETag from meeting.cache_key_with_version, Last-Modified from updated_at (rule 3)
        if stale?(meeting, public: true)
          ics = Rails.cache.fetch([meeting, :ics, :publish]) do
            meeting.to_cal_invite_event.generate_calendar_url(:ics)
          end
          send_data ics, type: :ics, disposition: "inline", filename: "meeting-#{meeting.id}.ics"
        end
      end
    end
  end
end
```

`GET /meetings/1.ics` returns the file, and a repeat request with the `ETag` it got back returns `304`. Passing `meeting` in the cache key uses its `cache_key_with_version`, which changes with `updated_at`, so updating the record (including bumping `sequence`) also refreshes the cached copy. If `sequence` lives somewhere that doesn't touch `updated_at`, add it to both the key and `stale?(etag: ...)`.

The [example app](Example/calendar_app) has a complete version in `MeetingsController#show`, with tests. Its meetings list attendees, so it keeps `Cache-Control` private (no `public: true`), uses `belongs_to :meeting, touch: true` so an attendee's RSVP change expires the cache, and bumps `sequence` with `increment!(:sequence, touch: true)`, because `increment!` alone doesn't update `updated_at`.

## Sinatra

Tested with Sinatra 4.2. The `etag` and `last_modified` helpers stop the route with a `304` when the client's copy is current, so the `.ics` is only generated, or read from the cache, for clients that need it.

```ruby
require "sinatra/base"

class CalendarApp < Sinatra::Base
  get "/meetings/:id.ics" do
    meeting = MEETINGS.fetch(params[:id].to_i) { halt 404 }

    cache_control :public, max_age: 300
    last_modified meeting.updated_at
    etag meeting.cache_version # halts with 304 if If-None-Match matches

    content_type "text/calendar", charset: "utf-8"
    meeting_ics(meeting) # the IcsCache helper from the plain Ruby section
  end
end
```

## Hanami

Tested with hanami-action 3.0, the action library in Hanami 2.3 and later. Register the `ics` format once in `config/app.rb` with `config.actions.formats.register(:ics, "text/calendar")`. Hanami 2.2 and earlier used `formats.add`, which was removed in hanami-action 3.0.

`response.fresh` sets the `ETag`/`Last-Modified` headers and halts with `304` when the request is still fresh, before the `.ics` is built.

```ruby
module Calendar
  module Actions
    module Meetings
      class Show < Calendar::Action
        def handle(request, response)
          meeting = MEETINGS.fetch(request.params[:id].to_i) { halt 404 }

          response.cache_control :public, max_age: 300
          response.fresh etag: meeting.cache_version, last_modified: meeting.updated_at

          response.format = :ics
          response.body = meeting_ics(meeting)
        end
      end
    end
  end
end
```

## Grape

Tested with Grape 4.0. Grape has no conditional-GET helper, so the endpoint compares `If-None-Match` itself. Registering an `ics` content type and a pass-through formatter makes `GET /meetings/1.ics` return the `.ics` string as-is, without JSON-encoding it.

```ruby
require "grape"

class CalendarAPI < Grape::API
  content_type :ics, "text/calendar"
  formatter :ics, ->(object, _env) { object }

  resource :meetings do
    get ":id" do
      meeting = MEETINGS.fetch(params[:id].to_i) { error!("Not found", 404) }
      etag = %("#{meeting.cache_version}")

      header "ETag", etag
      header "Cache-Control", "public, max-age=300"
      if env["HTTP_IF_NONE_MATCH"] == etag
        status 304
        return ""
      end

      content_type "text/calendar; charset=utf-8"
      meeting_ics(meeting)
    end
  end
end
```

The same API can still serve JSON from other endpoints. The `.ics` extension selects the formatter.
