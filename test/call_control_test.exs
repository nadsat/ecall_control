defmodule CallControlTest do
  use ExUnit.Case
  @moduledoc """
  This module provides common setup code for unit tests  tty0tty
  is required. See https://github.com/freemed/tty0tty.
  """

  def control_port() do
    System.get_env("ECALL_CONTROL_PORT")
  end

  def simulator_port() do
    System.get_env("ECALL_SIM_PORT")
  end

  def common_setup() do
    if is_nil(control_port()) || is_nil(simulator_port()) do
      header = "Please define ECALL_CONTROL_PORT and ECALL_SIM_PORT in your
  environment (e.g. to ttyS0 ).\n\n"

      ports = Circuits.UART.enumerate()

      msg =
        case ports do
          [] -> header <> "No serial ports were found. Check your OS to see if they exist"
          _ -> header <> "The following ports were found: #{inspect(Map.keys(ports))}"
        end

      flunk(msg)
    end
    options = [speed: 115200, active: false]
    {:ok, uart} = Circuits.UART.start_link()
    case Circuits.UART.open(uart, simulator_port(), options) do
      :ok ->
        {:ok, sim_port: uart}
      {:error, reason} ->
        flunk(reason)
    end
  end

  def write_data(pid , data) when byte_size(data) > 0 do
    Circuits.UART.write(pid, data)
    write_data(pid, <<>>)
  end

  def write_data(pid , <<>>) do
    Circuits.UART.drain(pid)
  end

  def send_async_ok(pid, [h|t]) do
    send_async_ok_p(pid, h)
    send_async_ok(pid, t)
  end

  def send_async_ok(_pid, []) do
    :ok
  end

  defp send_async_ok_p(pid, data) do
    case Circuits.UART.read(pid, 10000) do
      {:ok, payload} ->
        case payload === data do
          true ->
               Circuits.UART.write(pid, "ok\r\n")
               Circuits.UART.drain(pid)
          false ->
            flunk("Received [#{inspect(payload)}]" <>"[#{inspect(data)}]"<> 
              "different from expected")
        end
      msg ->
               flunk("Received [#{inspect(msg)}] different from expected")
    end
  end
 end

