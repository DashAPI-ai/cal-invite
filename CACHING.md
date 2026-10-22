## Caching

### Generated output is not cached

`Event#generate_calendar_url` always builds its URL or `.ics` content fresh. Earlier versions (up to 0.2.13) cached it in `CalInvite.configuration.cache_store`. That was removed in 0.2.14:

- **There was nothing to gain.** Building the output is in-memory string work that takes microseconds. A trip to Redis or Memcached costs more than that.
- **Cached `.ics` content had stale timestamps.** `DTSTAMP` should record when the content was generated. A cached copy kept its original value for as long as the entry lived (24 hours by default).
- **The cache was hard to use correctly.** Its keys ignored `cache_prefix`, and `update_attributes` deleted every event's entries, not just the event being updated. An event that wasn't given an explicit `uid` got a random one, so its key was different every time and the cache almost never hit.

Callers don't need to change anything: the output is the same as before. Configuring a `cache_store` is still allowed; the gem just doesn't store generated output in it.

If you still want to cache, cache at the place where you know what identifies the content and when it changes. For example, cache on your own record:

```ruby
Rails.cache.fetch([meeting, meeting.sequence, :ics]) do
  meeting.to_cal_invite_event.generate_calendar_url(:ics, method: :request)
end
```

### Cache helpers

`CalInvite` still provides small helpers on top of the configured store. Each key gets `cache_prefix` added to the front:

```ruby
CalInvite.configure do |config|
  config.cache_store = Rails.cache    # or :memory_store, :null_store, or a custom store
  config.cache_prefix = 'my_app_cal_invite'
  config.cache_expires_in = 3600      # default for write_to_cache, in seconds
end

CalInvite.write_to_cache('events:42:ics', content)  # key "my_app_cal_invite:events:42:ics"
CalInvite.read_from_cache('events:42:ics')
CalInvite.fetch_from_cache('events:42:ics') { build_content }
CalInvite.clear_event_cache!(42)        # deletes "my_app_cal_invite:events:42:*" (needs delete_matched)
CalInvite.clear_provider_cache!(:ics)   # deletes "my_app_cal_invite:providers:ics:*" (needs delete_matched)
CalInvite.clear_cache!                  # everything under the prefix (or store.clear without delete_matched)
```

### Configuration options

- `cache_store`: `:memory_store`, `:null_store`, or any object that responds to `read`, `write`, and `delete`, such as `Rails.cache`. Pattern deletes need `delete_matched`, and `clear_cache!` falls back to `clear` when the store doesn't have it.
- `cache_prefix`: the prefix added to every helper key (default `'cal_invite'`).
- `cache_expires_in`: the default expiry used by `write_to_cache` (default 24 hours).

### Custom cache stores

```ruby
class CustomCacheStore
  def read(key); end
  def write(key, value, options = {}); end  # options may include :expires_in
  def delete(key); end
  def clear; end                             # used by clear_cache! without delete_matched
end

CalInvite.configure do |config|
  config.cache_store = CustomCacheStore.new
end
```
