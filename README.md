# Kmk

[Komoku](https://github.com/comboy/komoku) client written in Elixir. Currently only a proof of concept although basic functionality (get, put, subscribe) already works.

## TODO Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed as:

  1. Add `kmk` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:kmk, "~> 0.1.0"}]
    end
    ```

## Usage

  ```elixir
  {:ok, client} = Kmk.Client.start_link("ws://127.0.0.1:7777")
  :ok = client |> Kmk.Client.put("foo", 123)
  client |> Kmk.Client.get("foo", 123) # {:ok, 123}
  ```

For more examples check [the tests](test/kmk/client_test.exs)

## Development

Copy `config/test.exs.example` to `config/test.exs` and make sure database name and user are properly set up.

## Contibutirng

Any kind of contribution is very much welcome. Even a random comment, just open an issue.

## License

MIT

