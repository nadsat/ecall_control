defmodule Ecall.Control.Parser.Sim7xxx do
  require Logger
  def setup_list do
    [
      "ATE0",
      "AT+CLCC=1",
      "AT+CRC=0",
      "AT+MORING=0"
    ]
  end
  def dial_command(number) do
    "ATD" <> number <> ";"
  end
  def hang_up_command() do
    "AT+CHUP"
  end
  def answer_command() do
    "ATA"
  end
  def reject_command() do
    "AT+CHUP"
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
  def get_event ("NO CARRIER"<>_b) do
    :no_carrier
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
    [_,_,number|_t] = rest
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
end
