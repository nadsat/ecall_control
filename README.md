# ecall_control
[![Build Status](https://travis-ci.org/nadsat/ecall_control.svg?branch=master)](https://travis-ci.org/nadsat/ecall_control)

Make phone calls using AT commands
## Example use

Currently only the modem SIM7600 is supported, the example place a call, the calling party answers and then hang up the call

```elixir
iex(1)> {:ok, pid} = Ecall.Control.start_link(Ecall.Control.Port.Sim7xxx)
{:ok, #PID<0.199.0>}
iex(2)> Ecall.Control.open_device(pid,"ttyUSB2")
:ok
iex(3)> Ecall.Control.dial(pid,"+3388888888")
iex(4)> flush
:ecall_connected
:ecall_disconnected
:ok
```
