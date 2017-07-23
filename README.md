# Transfusion [![Build Status][travis-img]][travis] [![License][license-img]][license]

[travis-img]: https://travis-ci.org/doomspork/transfusion.svg?branch=master
[travis]: https://travis-ci.org/doomspork/transfusion
[license-img]: http://img.shields.io/badge/license-MIT-brightgreen.svg
[license]: http://opensource.org/licenses/MIT

An experimental event-based work flow — you probably don't want to use it just yet.

## Installation

The package is currently not on hex, to use it point directly to master:

```elixir
def deps do
  [{:transfusion, github: "doomspork/transfusion"}]
end
```

## Routing Messages

```elixir
defmodule Example.Router do
  use Transfusion.Router,
    max_retries: 5,
    retry_after: 10000 # milliseconds

  require Logger

  broadcast "*", to: [AnotherExample.Router]
  
  forward "users", to: Users.Router
  
  topic "events", Example.Consumer do
    map "new.message", to: :new
  end
  
  on_error :handle_errors
  
  def handle_errors(reason, msg) do
    IO.warn("#{reason} caused an error to occur for #{msg}")
  end
end
```

## Message Producing

```elixir
defmodule Example.Message do
  use Transfusion.Message,
    router: Example.Router

  topic "events"

  message_type "new.message"

  values do
    attribute :subject, String
    attribute :body, String, required: true
  end
end
```

## Message Consuming

```elixir
defmodule Example.Consumer do
  require Logger

  def new(%{body: body, _meta: %{id: id}}),
    do: Logger.info("Message (id: #{id}) received with body: #{body}")
end
```

## Contributing

Feedback, feature requests, and fixes are welcomed and encouraged.  Please
make appropriate use of [Issues][issues] and [Pull Requests][pulls].  All code
should have accompanying tests.

[issues]: https://github.com/doomspork/transfusion/issues
[pulls]: https://github.com/doomspork/transfusion/pulls


## License

MIT license. Please see [LICENSE][license] for details.

[LICENSE]: https://github.com/doomspork/transfusion/blob/master/LICENSE
