# Transfusion [![Build Status][travis-img]][travis] [![License][license-img]][license]

[travis-img]: https://travis-ci.org/doomspork/transfusion.svg?branch=master
[travis]: https://travis-ci.org/doomspork/transfusion
[license-img]: http://img.shields.io/badge/license-MIT-brightgreen.svg
[license]: http://opensource.org/licenses/MIT

An experimental event-based work flow — you probably don't want to use it just yet.

## Installation

The package is currently not on hex, instead point to master:

```elixir
def deps do
  [{:transfusion, github: "doomspork/transfusion"}]
end
```

## Routing Messages

The router is the core of `Transfusion` handling the message routing and results.  The router also maintains a list of current messages, retrying expired messages with an exponential backoff.

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

  def handle_error(msg, reason) do
    # Log or submit your error

    :noretry
  end
end
```

The `broadcast/2` macro enables us to distributes messages to other router throughout our application in addition to processing it ourselves.

We can redirect, or forward, all messages for a given topic to another router using `forward/2`.

Most importantly is the `topic/2` and `map/2` macros, with these we can subscribe a consumer to various messages on a given topic.

## Message Producing

Messages are primarily syntactic sugar for creating structs with a splash of validation.  You can use `Transfusion` without creating a message module, maps work just fine!

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

Consumers do the real work in `Transfusion`.  A consumer received events and is expected to do some work, returning `{:ok, result}` or `{:error, reason}`.

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
