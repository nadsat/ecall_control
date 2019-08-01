defmodule Ecall.Control.Port.Sim7xxx do
  require Logger
  use Ecall.Control.Port
  alias Ecall.Control.Port

  def setup_list do
    [
      "ATE0",
      "AT+CRC=0",
      "AT+CLIP=0",
      "AT+MORING=0",
      "AT+CLCC=1"
    ]
  end
  def get_event ("OK") do
    :ok
  end
  def get_event ("ERROR") do
    :error
  end
  def get_event ("+CLCC: " <> body) do
    [_,_,stat|t] = String.split(body, ",")
    process_clcc(stat,t)
  end
  def get_event ("+RXDTMF: " <> data) do
    [digit|_t] = String.split(data, "\r")
    {:dtmf, digit}
  end
  def get_event ("NO CARRIER"<>_b) do
    :nocarrier
  end
  def get_event (d) do
    Logger.info "[get_event] [unknown][#{inspect(d)}]"
    :modem_data
  end

  defp process_clcc("0",_) do
    :active
  end
  defp process_clcc("1",_) do
    :held
  end
  defp process_clcc("2",_) do
    :dialing
  end
  defp process_clcc("3",_) do
    :ringing
  end
  defp process_clcc("4",rest) do
    [_,_,n|_t] = rest
    number = String.replace(n, "\"","")
    {:incoming, number}
  end
  defp process_clcc("5",_) do
    :waiting
  end
  defp process_clcc("6",_) do
    :disconnect
  end
  defp process_clcc(_b,_) do
    :unknown
  end
  def idle(:cast, {:dial,number}, data) do
    Logger.info "[SIMCOM][IDLE][:dial]"
    cmd = "ATD" <> number <> ";"
    Port.write_data(data.serial_pid,cmd)
    {:next_state, :wait4_ok, data}
  end
  def idle(:cast, :hang_up, data) do
    Logger.info "[SIMCOM][IDLE][:hang_up]"
    cmd = "AT+CHUP"
    Port.write_data(data.serial_pid,cmd)
    {:next_state, :wait4_ok, data}
  end
  def idle(:cast, :reject, data) do
    Logger.info "[SIMCOM][IDLE][:hang_up]"
    cmd = "AT+CHUP"
    Port.write_data(data.serial_pid,cmd)
    {:next_state, :wait4_ok, data}
  end
  def idle(:cast, :answer, data) do
    Logger.info "[SIMCOM][IDLE][:answer]"
    cmd = "ATA"
    Port.write_data(data.serial_pid,cmd)
    {:next_state, :wait4_ok, data}
  end
  def idle(:cast, :end_cmd, data) do
    Logger.info "[SIMCOM][IDLE][:end_cmd]"
    cmd = "ATH"
    Port.write_data(data.serial_pid,cmd)
    {:next_state, :wait4_ok, data}
  end
  def idle(:cast, {:write_command, cmd, value}, data) do
    Logger.info "[SIMCOM][IDLE][:write_cmd]"
    sentence = cmd <> "=" <> value
    Port.write_data(data.serial_pid, sentence)
    {:next_state, :wait4_ok_cmd, data}
  end
  def idle(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
  def wait4_ok(:cast, :ok, data) do
    Logger.info "[SIMCOM][WAIT4_OK][:ok]"
    {:next_state, :idle, data}
  end
  def wait4_ok(:cast, e, data) do
    Logger.info "[SIMCOM][WAIT4_OK][#{inspect(e)}]"
    {:keep_state, data, :postpone}
  end
  def wait4_ok(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
  def wait4_ok_cmd(:cast, :ok, data) do
    Logger.info "[SIMCOM][WAIT4_OK_CMD][:ok]"
    pid = data.controlling_process
    send(pid,{:write_ans, :ok} )
    {:next_state, :idle, data}
  end
  def wait4_ok_cmd(:cast, e, data) do
    Logger.info "[SIMCOM][WAIT4_OK_CMD][#{inspect(e)}]"
    {:keep_state, data, :postpone}
  end
  def wait4_ok_cmd(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
end
