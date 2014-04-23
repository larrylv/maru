defmodule Lazymaru.Server do

  defmacro __using__(_) do
    quote do
      import Plug.Connection
      import unquote(__MODULE__)
      Module.register_attribute __MODULE__,
             :socks, accumulate: true, persist: false
      Module.register_attribute __MODULE__,
             :statics, accumulate: true, persist: false
      @before_compile unquote(__MODULE__)
    end
  end


  defmacro __before_compile__(_) do
    quote do
      def start do
        dispatch =
          lc {url_path, sys_path} inlist @statics do
            { "#{url_path}/[...]", :cowboy_static, {:dir, sys_path} }
          end
          ++
          lc m inlist @socks do
            { "#{m.path}/[...]", m, [] }
          end
          ++ [{"/[...]", Plug.Adapters.Cowboy.Handler, {Lazymaru.Handler, __MODULE__} }]
        Plug.Adapters.Cowboy.http nil, nil, [port: @port, ref: Lazymaru.HTTP, dispatch: [{:_, dispatch}]]
      end
    end
  end


  defmacro port(port_num) do
    quote do
      @port unquote(port_num)
    end
  end


  defmacro rest({_, _, mod}) do
    endpoints = Module.concat(mod).endpoints
    lc i inlist endpoints do
      quote do
        dispatch(unquote i)
      end
    end
  end


  defmacro sock({_, _, mod}) do
    m = Module.concat(mod)
    quote do
      @socks unquote(m)
    end
  end


  defmacro static(url_path, sys_path) do
    quote do
      @statics { unquote(url_path), unquote(sys_path) }
    end
  end


  defmacro map_params(n) when n < 0, do: []
  defmacro map_params(n) do
    Enum.map 0..n,
      fn(x) ->
          param_name = :"param_#{x}"
          quote do
            var!(unquote param_name)
          end
      end
  end


  def map_params_path(path), do: map_params_path(path, 0, [])
  def map_params_path([], _, r), do: r |> Enum.reverse
  def map_params_path([h|t], n, r) when is_atom(h) do
    new_path = quote do: var!(unquote :"param_#{n}")
    map_params_path(t, n+1, [new_path|r])
  end
  def map_params_path([h|t], n, r) do
    map_params_path(t, n, [h|r])
  end


  defmacro dispatch({method, path, params, [do: block], params_block}) do
    new_path = map_params_path(path)
    quote do
      def service(unquote(method), unquote(new_path), var!(unquote :conn)) do
        var!(:params) = List.zip [unquote(params), map_params(unquote(length(params)-1))]
        unquote(params_block)
        unquote(block)
      end
    end
  end


  defmacro json(reply) do
    quote do
      var!(conn)
   |> put_resp_content_type("application/json")
   |> send_resp(200, unquote(reply) |> JSON.encode!)
    end
  end


  defmacro html(reply) do
    quote do
      var!(conn)
   |> put_resp_content_type("text/html")
   |> send_resp(200, unquote(reply))
    end
  end


  defmacro text(reply) do
    quote do
      var!(conn)
   |> put_resp_content_type("text/plain")
   |> send_resp(200, unquote(reply))
    end
  end


  def parse_param(value, param, option) do
    try do
      Module.safe_concat(LazyParamType, option[:type]).from(value)
    rescue
      _ -> LazyException.InvalidFormatter
        |> raise [reason: :illegal, param: param, option: option]
    end |> check_param(param, option)
  end


  def check_param(value, param, option) do
    [ regexp: fn(x) -> Regex.match?(x |> to_string, value) end,
      range: fn(x) -> Enum.member?(x, value) end,
    ] |> check_param(value, param, option)
  end
  def check_param([], value, param, _), do: [{param, value}]
  def check_param([{k, f}|t], value, param, option) do
    if Dict.has_key?(option, k) and not f.(option[k]) do
      LazyException.InvalidFormatter |> raise [reason: :unformatted, param: param, option: option]
    end
    check_param(t, value, param, option)
  end


  defmacro requires(param, option) do
    quote do
      case var!(:conn).params[unquote(param) |> to_string] || unquote(option[:default]) do
        nil -> LazyException.InvalidFormatter
            |> raise [reason: :required, param: unquote(param), option: unquote(option)]
        v   -> var!(:params) = var!(:params)
            |> Dict.merge parse_param(v, unquote(param), unquote(option))
      end
    end
  end

  defmacro optional(param, option) do
    quote do
      case var!(:conn).params[unquote(param) |> to_string] || unquote(option[:default]) do
        nil -> nil
        v   -> var!(:params) = var!(:params)
            |> Dict.merge parse_param(v, unquote(param), unquote(option))
      end
    end
  end
end