defmodule ExBlofin.WebSocket.MessageParseEdgesTest do
  @moduledoc """
  Failure and fallback paths of `ExBlofin.WebSocket.Message.parse/1`.

  The happy path per channel is covered in `ExBlofin.WebSocket.MessageTest`;
  this file covers what happens when the exchange sends something unexpected —
  which is exactly when a client is most likely to crash.
  """
  use ExUnit.Case, async: true

  alias ExBlofin.WebSocket.Message

  describe "parse/1 malformed input" do
    test "rejects invalid JSON" do
      assert Message.parse("not json at all") == {:error, :invalid_json}
      assert Message.parse("{\"unclosed\": ") == {:error, :invalid_json}
    end

    test "rejects a well-formed JSON object it doesn't recognise" do
      assert Message.parse(~s({"something":"else"})) == {:error, :unknown_message_format}
    end

    test "rejects JSON that isn't an object" do
      assert Message.parse("[1,2,3]") == {:error, :unknown_message_format}
    end
  end

  describe "parse/1 control frames" do
    test "recognises the bare pong text frame" do
      assert Message.parse("pong") == {:ok, :pong, nil}
    end

    test "surfaces an error event with its payload" do
      raw = ~s({"event":"error","code":"60009","msg":"Login failed"})

      # Note the error payload is normalised to atom keys, unlike the
      # subscribe/unsubscribe args which stay as raw string-keyed maps.
      assert {:ok, :error, %{code: "60009", msg: "Login failed"}} = Message.parse(raw)
    end

    test "surfaces subscribe and unsubscribe confirmations" do
      arg = ~s({"channel":"trades","instId":"BTC-USDT"})

      assert {:ok, :subscribe, %{"channel" => "trades"}} =
               Message.parse(~s({"event":"subscribe","arg":#{arg}}))

      assert {:ok, :unsubscribe, %{"channel" => "trades"}} =
               Message.parse(~s({"event":"unsubscribe","arg":#{arg}}))
    end
  end

  describe "parse/1 unknown channels" do
    test "passes data through untyped rather than failing" do
      # A channel this library doesn't model yet must not break the connection.
      raw =
        ~s({"arg":{"channel":"some-future-channel","instId":"BTC-USDT"},) <>
          ~s("data":[{"foo":"bar"}]})

      assert {:ok, channel, data} = Message.parse(raw)
      assert channel == :"some-future-channel"
      assert data == [%{"foo" => "bar"}]
    end
  end

  describe "encode/1" do
    test "encodes a map to JSON" do
      assert {:ok, json} = Message.encode(%{"op" => "subscribe"})
      assert Jason.decode!(json) == %{"op" => "subscribe"}
    end

    test "returns an error for values JSON cannot represent" do
      assert {:error, _} = Message.encode(%{"pid" => self()})
    end
  end

  describe "round trip" do
    test "a built subscribe message parses back as a subscribe confirmation shape" do
      channels = [%{"channel" => "trades", "instId" => "BTC-USDT"}]

      built = Message.build_subscribe(channels)
      assert built["op"] == "subscribe"
      assert built["args"] == channels

      assert {:ok, json} = Message.encode(built)
      assert Jason.decode!(json)["args"] == channels
    end

    test "build_ping/0 is the literal frame BloFin expects" do
      # BloFin uses an application-level text ping, not a protocol ping frame.
      assert Message.build_ping() == "ping"
    end
  end
end
