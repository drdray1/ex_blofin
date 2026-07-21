defmodule ExBlofin.PathsTest do
  use ExUnit.Case, async: true

  doctest ExBlofin.Paths

  alias ExBlofin.Paths

  describe "legacy_for/1" do
    test "returns the legacy spelling for an aliased path" do
      assert Paths.legacy_for("/api/v1/trade/orders-history") == "/api/v1/trade/order-history"
      assert Paths.legacy_for("/api/v1/user/query-apikey") == "/api/v1/user/api-key-info"
      assert Paths.legacy_for("/api/v1/affiliate/basic") == "/api/v1/affiliate/info"
    end

    test "returns nil for a path with no divergence" do
      assert Paths.legacy_for("/api/v1/account/balance") == nil
      assert Paths.legacy_for("/api/v1/market/tickers") == nil
    end

    test "is not reversible: legacy paths are not themselves keys" do
      # Guards against an entry being added backwards, which would make the
      # fallback try the legacy path first.
      for {documented, legacy} <- Paths.all() do
        assert Paths.legacy_for(documented) == legacy
        assert Paths.legacy_for(legacy) == nil
      end
    end
  end

  describe "all/0" do
    test "every entry is a distinct, absolute API path pair" do
      aliases = Paths.all()

      assert map_size(aliases) > 0

      for {documented, legacy} <- aliases do
        assert String.starts_with?(documented, "/api/v1/")
        assert String.starts_with?(legacy, "/api/v1/")
        refute documented == legacy
      end
    end

    test "no legacy path is reused by two documented paths" do
      legacy = Paths.all() |> Map.values()
      assert length(legacy) == length(Enum.uniq(legacy))
    end
  end

  describe "alignment with call sites" do
    test "every documented path is actually requested somewhere in lib/" do
      # An alias for a path no module calls is dead config, and would silently
      # stop protecting the endpoint it was written for.
      sources =
        Path.wildcard("lib/**/*.ex")
        |> Enum.map_join("\n", &File.read!/1)

      for {documented, _legacy} <- Paths.all() do
        assert sources =~ documented,
               "#{documented} is aliased in ExBlofin.Paths but never requested"
      end
    end

    test "no module still calls a legacy path directly" do
      sources =
        Path.wildcard("lib/**/*.ex")
        |> Enum.reject(&String.ends_with?(&1, "paths.ex"))
        |> Enum.map_join("\n", &File.read!/1)

      for {_documented, legacy} <- Paths.all() do
        refute sources =~ ~s("#{legacy}"),
               "#{legacy} is still called directly; it should go through Client.get/3"
      end
    end
  end
end
