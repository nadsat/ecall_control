defmodule Ecall.ControlTest do
  use ExUnit.Case
  alias Ecall.Control
  alias Ecall.Control.Parser
  doctest Ecall.Control

  setup do
    CallControlTest.common_setup()
  end


  test "dial number, hang up called", %{sim_port: uart}do
    {:ok, pid} = Control.start_link
    cmds = for n <- Parser.Sim7xxx.setup_list, do: n <> "\r"
    spawn fn ->
      CallControlTest.send_async_ok(uart, cmds)
    end
    assert :ok = Control.open_device(pid, CallControlTest.control_port())
    assert :ok = Control.dial(pid, "272727")
    assert {:ok, "ATD272727;\r"} = Circuits.UART.read(uart)
    assert :ok = Circuits.UART.write(uart, "OK\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,2,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,3,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,0,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,6,0,0,\"272727\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:ecall_connected, 20000)
    assert_receive(:ecall_disconnected, 20000)
  end

  test "dial number, hang up calling", %{sim_port: uart}do
    {:ok, pid} = Control.start_link
    cmds = for n <- Parser.Sim7xxx.setup_list, do: n <> "\r"
    spawn fn ->
      CallControlTest.send_async_ok(uart, cmds)
    end
    assert :ok = Control.open_device(pid, CallControlTest.control_port())
    assert :ok = Control.dial(pid, "131313")
    assert {:ok, "ATD131313;\r"} = Circuits.UART.read(uart)
    assert :ok = Circuits.UART.write(uart, "OK\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,2,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,3,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,0,0,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:ecall_connected, 20000)
    spawn fn ->
      CallControlTest.send_async_ok(uart, ["AT+CHUP\r"])
    end
    Control.hang_up(pid)
    assert_receive(:ecall_disconnected, 20000)
  end

  test "incoming call, hang up calling", %{sim_port: uart}do
    {:ok, pid} = Control.start_link
    cmds = for n <- Parser.Sim7xxx.setup_list, do: n <> "\r"
    spawn fn ->
      CallControlTest.send_async_ok(uart, cmds)
    end
    assert :ok = Control.open_device(pid, CallControlTest.control_port())
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,1,4,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive({:ecall_incoming,"131313"}, 20000)
    spawn fn ->
      CallControlTest.send_async_ok(uart, ["ATA\r"])
    end
    Control.accept pid
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,1,0,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:ecall_connected, 20000)
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,1,6,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:ecall_disconnected, 20000)
  end

  test "incoming call, hang up called", %{sim_port: uart}do
    {:ok, pid} = Control.start_link
    cmds = for n <- Parser.Sim7xxx.setup_list, do: n <> "\r"
    spawn fn ->
      CallControlTest.send_async_ok(uart, cmds)
    end
    assert :ok = Control.open_device(pid, CallControlTest.control_port())
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,1,4,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive({:ecall_incoming,"131313"}, 20000)
    spawn fn ->
      CallControlTest.send_async_ok(uart, ["ATA\r"])
    end
    Control.accept pid
    assert :ok = Circuits.UART.write(uart, "+CLCC: 2,1,0,0,0,\"131313\",129\r\n")
    Circuits.UART.drain(uart)
    assert_receive(:ecall_connected, 20000)
    spawn fn ->
      CallControlTest.send_async_ok(uart, ["AT+CHUP\r"])
    end
    Control.hang_up(pid)
    assert_receive(:ecall_disconnected, 20000)
  end
end
