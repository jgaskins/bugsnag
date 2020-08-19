# Bugsnag

`Bugsnag` is a [Bugsnag](https://bugsnag.com) client for Crystal, providing error tracking for your Crystal apps.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     bugsnag:
       github: jgaskins/bugsnag
   ```

2. Run `shards install`

## Usage

```crystal
require "bugsnag"
```

Set your Bugsnag API key either through the `BUGSNAG_API_KEY` environment variable or by setting `Bugsnag.api_key` in your Crystal code:

```
$ shards build my_app

$ BUGSNAG_API_KEY=my_bugsnag_key bin/my_app
```

```crystal
Bugsnag.api_key = "my_bugsnag_key"
```

### HTTP handler

For an HTTP server, you can use `Bugsnag::Middleware` as an intermediate HTTP handler:

```crystal
http = HTTP::Server.new([
  Bugsnag::Middleware.new
    .with_user { |context| Bugsnag::User.from_user(find_user_from(context)) }
    .with_app { Bugsnag::App.new(id: "my-app") }
    .with_metadata { |context| Bugsnag::Metadata { "session" => context.session.data } },
  MyApp.new,
])
```

### One-off usage

## Development

TODO: Write development instructions here

## Contributing

1. Fork it (<https://github.com/your-github-user/bugsnag/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [your-name-here](https://github.com/your-github-user) - creator and maintainer
