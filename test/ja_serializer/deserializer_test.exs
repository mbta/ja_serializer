defmodule JaSerializer.DeserializerTest do
  use ExUnit.Case
  use Plug.Test

  defmodule ExamplePlug do
    use Plug.Builder
    plug(Plug.Parsers, parsers: [:json], json_decoder: Poison)
    plug(JaSerializer.Deserializer)
    plug(:return)

    def return(conn, _opts) do
      send_resp(conn, 200, "success")
    end
  end

  setup do
    on_exit(fn ->
      Application.delete_env(:ja_serializer, :key_format)
    end)

    :ok
  end

  @ct "application/vnd.api+json"

  test "Ignores bodyless requests" do
    conn =
      Plug.Test.conn("GET", "/")
      |> put_req_header("content-type", @ct)
      |> put_req_header("accept", @ct)

    result = ExamplePlug.call(conn, [])
    assert result.params == %{}
  end

  test "converts non-jsonapi.org format params" do
    req_body = Poison.encode!(%{"some-nonsense" => "yup"})

    conn =
      Plug.Test.conn("POST", "/", req_body)
      |> put_req_header("content-type", @ct)
      |> put_req_header("accept", @ct)

    result = ExamplePlug.call(conn, [])
    assert result.params == %{"some_nonsense" => "yup"}
  end

  test "converts attribute key names" do
    req_body =
      Poison.encode!(%{
        "data" => %{
          "attributes" => %{
            "some-nonsense" => true,
            "foo-bar" => true,
            "some-map" => %{
              "nested-key" => "unaffected-values"
            }
          }
        }
      })

    conn =
      Plug.Test.conn("POST", "/", req_body)
      |> put_req_header("content-type", @ct)
      |> put_req_header("accept", @ct)

    result = ExamplePlug.call(conn, [])
    assert result.params["data"]["attributes"]["some_nonsense"]
    assert result.params["data"]["attributes"]["foo_bar"]
    assert result.params["data"]["attributes"]["some_map"]["nested_key"]
  end

  test "converts query param key names - dasherized" do
    req_body = Poison.encode!(%{"data" => %{}})

    conn =
      Plug.Test.conn("POST", "/?page[page-size]=2", req_body)
      |> put_req_header("content-type", @ct)
      |> put_req_header("accept", @ct)

    result = ExamplePlug.call(conn, [])
    assert result.params["page"]["page_size"] == "2"
  end

  test "converts query param key names - underscored" do
    Application.put_env(:ja_serializer, :key_format, :underscored)

    req_body = Poison.encode!(%{"data" => %{}})

    conn =
      Plug.Test.conn("POST", "/?page[page_size]=2", req_body)
      |> put_req_header("content-type", @ct)
      |> put_req_header("accept", @ct)

    result = ExamplePlug.call(conn, [])
    assert result.query_params["page"]["page_size"] == "2"
  end

  test "retains payload type" do
    req_body =
      Poison.encode!(%{
        "data" => %{
          "type" => "foo"
        }
      })

    conn =
      Plug.Test.conn("POST", "/", req_body)
      |> put_req_header("content-type", @ct)
      |> put_req_header("accept", @ct)

    result = ExamplePlug.call(conn, [])
    assert result.params["data"]["type"] == "foo"
  end
end
