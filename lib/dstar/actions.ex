defmodule Dstar.Actions do
  @moduledoc """
  Helpers for generating Datastar action expressions and encoding module names.

  ## Examples

      # In a Phoenix template:
      <button data-on:click="<%= Dstar.Actions.event(MyApp.CounterHandler, "increment") %>">+</button>

      # Dynamic module (reads from signal):
      <button data-on:click="<%= Dstar.Actions.event("increment") %>">+</button>

  """

  # Datastar options that attach the CSRF token from the `_csrfToken` signal
  # as an `x-csrf-token` request header. The signal uses a `_` prefix so
  # Datastar excludes it from the JSON body (it only needs to be a header).
  #
  # To set up the signal, add this to your root layout:
  #
  #     <body data-signals:_csrf-token={"'#{get_csrf_token()}'"}>
  #
  @csrf_opts "{headers: {'x-csrf-token': $_csrfToken}}"

  @doc """
  Generates an `@post(...)` action expression for Datastar attributes.

  Includes an `x-csrf-token` header that reads from the `$_csrfToken`
  Datastar signal, so `Plug.CSRFProtection` accepts the request.

  ## Setup

  Add the CSRF token signal to your root layout (on `<body>` or any
  persistent element):

      <body data-signals:_csrf-token={"'\#{get_csrf_token()}'"}>

  ## With a known module (compile-time):

      iex> Dstar.Actions.event(MyApp.CounterHandler, "increment")
      "@post('/ds/my_app-counter_handler/increment', {headers: {'x-csrf-token': $_csrfToken}})"

      iex> Dstar.Actions.event(MyApp.CounterHandler, "increment", prefix: "/my-workspace")
      "@post('/my-workspace/ds/my_app-counter_handler/increment', {headers: {'x-csrf-token': $_csrfToken}})"

  ## With a dynamic module signal (runtime on client):

      iex> Dstar.Actions.event("increment")
      "@post('/ds/' + $_dstar_module + '/increment', {headers: {'x-csrf-token': $_csrfToken}})"

  ## Options

  - `:prefix` — URL path prefix (e.g. `"/my-workspace"`). Only for the module form.
  - `:module` — Override the module signal name (default: `$_dstar_module`). Only for the dynamic form.

  """
  def event(module_or_name, name_or_opts \\ [])

  @spec event(module(), String.t()) :: String.t()
  def event(module, event_name) when is_atom(module) and is_binary(event_name) do
    encoded = encode_module(module)
    "@post('/ds/#{encoded}/#{event_name}', #{@csrf_opts})"
  end

  @spec event(String.t(), keyword()) :: String.t()
  def event(event_name, opts) when is_binary(event_name) and is_list(opts) do
    module = Keyword.get(opts, :module, "$_dstar_module")

    path =
      if module == "$_dstar_module" do
        "'/ds/' + $_dstar_module + '/#{event_name}'"
      else
        "'/ds/#{module}/#{event_name}'"
      end

    "@post(#{path}, #{@csrf_opts})"
  end

  @doc """
  Generates an `@post(...)` expression with a URL prefix.

  Useful for workspace-scoped routes where the dispatch endpoint
  is nested under a dynamic segment.

  ## Example

      iex> Dstar.Actions.event(MyApp.Handler, "save", prefix: "/my-workspace")
      "@post('/my-workspace/ds/my_app-handler/save', {headers: {'x-csrf-token': $_csrfToken}})"

  """
  @spec event(module(), String.t(), keyword()) :: String.t()
  def event(module, event_name, opts)
      when is_atom(module) and is_binary(event_name) and is_list(opts) do
    encoded = encode_module(module)
    prefix = Keyword.get(opts, :prefix, "")
    "@post('#{prefix}/ds/#{encoded}/#{event_name}', #{@csrf_opts})"
  end

  @doc """
  Encodes a module name for URL use.

  ## Examples

      iex> Dstar.Actions.encode_module(MyApp.CounterView)
      "my_app-counter_view"

      iex> Dstar.Actions.encode_module(MyApp.Web.ChatView)
      "my_app-web-chat_view"

  """
  @spec encode_module(module()) :: String.t()
  def encode_module(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.map(&Macro.underscore/1)
    |> Enum.join("-")
  end

  @doc """
  Decodes a URL-safe module name back to an Elixir module.

  Returns `{:ok, module}` if the module exists, `:error` otherwise.

  ## Examples

      iex> Dstar.Actions.decode_module("my_app-counter_view")
      {:ok, MyApp.CounterView}

  """
  @spec decode_module(String.t()) :: {:ok, module()} | :error
  def decode_module(encoded) when is_binary(encoded) do
    try do
      module_string =
        encoded
        |> String.split("-")
        |> Enum.map(&Macro.camelize/1)
        |> Enum.join(".")

      module = String.to_existing_atom("Elixir." <> module_string)
      {:ok, module}
    rescue
      ArgumentError -> :error
    end
  end
end
