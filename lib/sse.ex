defmodule PhoenixDatastar.SSE do
  @moduledoc """
  Server-Sent Event (SSE) generator for streaming updates to clients.

  This module provides functionality for creating and managing SSE connections,
  sending events, and handling the streaming lifecycle.

  ## Example

      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)
      |> PhoenixDatastar.SSE.new()
      |> PhoenixDatastar.SSE.send_event("my-event", "data content")

  """

  @type t :: %__MODULE__{
          conn: Plug.Conn.t(),
          closed: boolean()
        }

  defstruct [:conn, closed: false]

  @doc """
  Creates a new SSE generator from a Plug connection.

  The connection must already have:
  - Content type set to "text/event-stream"
  - Response status set
  - Chunked response initiated via `send_chunked/2`

  ## Example

      conn
      |> put_resp_content_type("text/event-stream")
      |> send_chunked(200)
      |> PhoenixDatastar.SSE.new()

  """
  @spec new(Plug.Conn.t()) :: t()
  def new(conn) do
    %__MODULE__{conn: conn}
  end

  @doc """
  Sends an SSE event to the client.

  ## Parameters

  - `sse` - The SSE generator struct
  - `event_type` - The event type (e.g., "datastar-patch-elements")
  - `data_lines` - A list of data lines or a single string
  - `opts` - Optional keyword list with:
    - `:event_id` - Event ID for client tracking
    - `:retry` - Retry duration in milliseconds

  ## Example

      sse
      |> send_event("my-event", ["line1", "line2"], event_id: "123", retry: 5000)

  """
  @spec send_event(t(), String.t(), list(String.t()) | String.t(), keyword()) ::
          {:ok, t()} | {:error, term()}
  def send_event(sse, event_type, data_lines, opts \\ [])

  def send_event(%__MODULE__{closed: true} = sse, _event_type, _data_lines, _opts) do
    {:error, {:closed, sse}}
  end

  def send_event(%__MODULE__{conn: conn} = sse, event_type, data_lines, opts) do
    data_lines = if is_binary(data_lines), do: [data_lines], else: data_lines

    event_content =
      []
      |> maybe_add_event(event_type)
      |> maybe_add_id(opts[:event_id])
      |> maybe_add_retry(opts[:retry])
      |> add_data_lines(data_lines)
      |> Enum.join()
      |> Kernel.<>("\n")

    case Plug.Conn.chunk(conn, event_content) do
      {:ok, conn} ->
        {:ok, %{sse | conn: conn}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Sends an SSE event and raises on error.

  Same as `send_event/4` but raises if the event cannot be sent.
  Returns the updated SSE generator on success.

  ## Example

      sse
      |> send_event!("my-event", "data")
      |> send_event!("another-event", "more data")

  """
  @spec send_event!(t(), String.t(), list(String.t()) | String.t(), keyword()) :: t()
  def send_event!(sse, event_type, data_lines, opts \\ []) do
    case send_event(sse, event_type, data_lines, opts) do
      {:ok, sse} -> sse
      {:error, reason} -> raise "Failed to send SSE event: #{inspect(reason)}"
    end
  end

  @doc """
  Checks if the SSE connection is closed.
  """
  @spec closed?(t()) :: boolean()
  def closed?(%__MODULE__{closed: closed}), do: closed

  @doc """
  Marks the SSE connection as closed.
  """
  @spec close(t()) :: t()
  def close(%__MODULE__{} = sse) do
    %{sse | closed: true}
  end

  @doc """
  Formats a single SSE event as a string (for non-streaming responses).

  This is useful for stateless views that return SSE-formatted responses
  directly in a single HTTP response body rather than via chunked streaming.

  ## Parameters

  - `event_type` - The event type (e.g., "datastar-patch-elements")
  - `data_lines` - A list of data lines

  ## Example

      format_event("datastar-patch-elements", [
        "selector #count",
        "mode outer",
        "elements <span>42</span>"
      ])
      # => "event: datastar-patch-elements\\ndata: selector #count\\ndata: mode outer\\ndata: elements <span>42</span>\\n\\n"

  """
  @spec format_event(String.t(), [String.t()]) :: String.t()
  def format_event(event_type, data_lines) do
    event_line = "event: #{event_type}\n"
    data_content = Enum.map_join(data_lines, "\n", &"data: #{&1}")
    "#{event_line}#{data_content}\n\n"
  end

  # Private helpers

  defp maybe_add_event(lines, nil), do: lines
  defp maybe_add_event(lines, event_type), do: lines ++ ["event: #{event_type}\n"]

  defp maybe_add_id(lines, nil), do: lines
  defp maybe_add_id(lines, id), do: lines ++ ["id: #{id}\n"]

  defp maybe_add_retry(lines, nil), do: lines
  defp maybe_add_retry(lines, retry), do: lines ++ ["retry: #{retry}\n"]

  defp add_data_lines(lines, data_lines) do
    data_content =
      data_lines
      |> Enum.map(&"data: #{&1}\n")

    lines ++ data_content
  end
end
