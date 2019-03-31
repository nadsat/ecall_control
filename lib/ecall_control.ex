defmodule Ecall.Control do
  use GenStateMachine, callback_mode: :state_functions
  require Logger
  alias Ecall.Control.Parser
  @moduledoc """
  Make phone calls using modem with at commands.
  """
 defmodule StateData do
    @moduledoc false
    # from: pid of client (where the audio data is sent)
    # pid: pid of serial port process
    defstruct from: nil,
     serial_pid: nil,
     controlling_process: nil,
     last_state: :idle,
     cmd_list: [],
     ok_time: 200,
     dial_time: 200,
     ring_time: 20000,
     answer_time:  25000,
     max_time: :infinity
  end

  @doc """
  Start up a CallControl GenStateMachine.
  """
  @spec start_link( [term]) :: {:ok, pid} | {:error, term}
  def start_link( opts \\ []) do
    GenStateMachine.start_link(__MODULE__, [], opts)
  end

  @doc """
  open a serial device to send and receive AT commands
  """
  @spec open_device(pid(), binary) :: :ok | {:error, term}
  def open_device(pid, name) do
    GenStateMachine.call(pid, {:open, self(),name}, 6000)
  end

  @doc """
  Make call to a number, the call is hung up afeter max_time
  """
  @spec dial(pid(), String.t(), non_neg_integer()) :: :ok| {:error, term}
  def dial(pid, number, max_time \\ 60000) do
   GenStateMachine.cast(pid, {:dial, number, max_time}) 
  end

  @doc """
  Hang up a stablished or stablishing call 
  """
  @spec hang_up(pid()) :: :ok
  def hang_up(pid) do
   GenStateMachine.cast(pid, :hang_up) 
  end

  @doc """
  Accept incoming call 
  """
  @spec accept(pid(), non_neg_integer()) :: :ok
  def accept(pid, max_time \\ :infinity) do
   GenStateMachine.cast(pid, {:answer_call, max_time}) 
  end
  @doc """
  Reject incoming call 
  """
  @spec reject(pid()) :: :ok
  def reject(pid) do
   GenStateMachine.cast(pid, :reject_call) 
  end


  #gen_state_machine callbacks
  def init([]) do
    Logger.info "Init FSM"
    case  Circuits.UART.start_link do
      {:ok, pid} ->
        Circuits.UART.configure(pid, framing: Ecall.Framing)
        data = %StateData{serial_pid: pid}
        #{:next_state, :idle, state}
        {:ok, :setup, data}
      {:error, cause} ->
        {:stop, cause}
    end
  end

  def setup({:call,from}, {:open, proc_pid, name}, data) do
    Logger.info "[SETUP][:open]"
    options = [speed: 115200, active: true]
    case Circuits.UART.open(data.serial_pid, name, options) do
      :ok -> 
        cmds = Parser.Sim7xxx.setup_list
        new_data = %{data | from: from, 
          cmd_list: cmds,
          controlling_process: proc_pid}
        GenStateMachine.cast(self(), :at_cmd)
        {:next_state,:setup, new_data}
      ret -> 
        {:stop, ret}
    end
  end

  def setup(:cast,:at_cmd, %{cmd_list: [h|t]} = data) do
    Logger.info "[SETUP][:at_cmd]"
    new_data = %{data | cmd_list: t}
    Circuits.UART.write(data.serial_pid,h)
    Circuits.UART.drain(data.serial_pid)
    {:keep_state, new_data}
  end

  def setup(:cast,:at_cmd, %{cmd_list: []} = data) do
    Logger.info "[SETUP][:at_cmd] done"
    {:next_state, :idle, data, [{:reply, data.from, :ok}]}
  end
  def setup(:cast, :ok, data) do
    Logger.info "[SETUP][:ok]"
    GenStateMachine.cast(self(), :at_cmd)
    {:keep_state, data}
  end
  def setup(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def idle(:cast, {:dial,number, max_time}, data) do
    Logger.info "[IDLE][:dial]"
    new_data = %{data | max_time: max_time}
    cmd = Parser.Sim7xxx.dial_command(number)
    Circuits.UART.write(data.serial_pid,cmd)
    timeout_event = {:state_timeout, data.dial_time, :wait4_dialing}
    {:next_state, :wait4_dialing, new_data, timeout_event}
  end
  def idle(:cast, {:incoming, number}, data) do
    Logger.info "[IDLE][:incoming]"
    pid = data.controlling_process
    send(pid, {:ecall_incoming,number})
    {:next_state, :wait4_action, data}
  end
  def idle(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def wait4_action(:cast, {:answer_call, max_time}, data) do
    Logger.info "[WAIT4_ACTION][:answer_call]"
    new_data = %{data | max_time: max_time}
    cmd = Parser.Sim7xxx.answer_command()
    Circuits.UART.write(data.serial_pid,cmd)
    {:next_state, :wait4_answer, new_data}
  end
  def wait4_action(:cast, :reject_call, data) do
    cmd = Parser.Sim7xxx.reject_command()
    Circuits.UART.write(data.serial_pid,cmd)
    {:next_state, :idle, data}
  end
  def wait4_action(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
  
  def wait4_dialing(:cast, :ok, data) do
    Logger.info "[WAIT4_DIALING][:ok]"
    {:keep_state, data}
  end
  def wait4_dialing(:cast, :dialing, data) do
    Logger.info "[WAIT4_DIALING][:dialing]"
    timeout_event = {:state_timeout, data.ring_time, :wait4_ring}
    {:next_state, :wait4_ring, data,timeout_event}
  end
  def wait4_dialing(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def wait4_ring(:cast, :ringing, data) do
    Logger.info "[WAIT4_RINGING][:ringing]"
    timeout_event = {:state_timeout, data.answer_time, :wait4_answer}
    {:next_state, :wait4_answer, data, timeout_event}
  end
  def wait4_ring(:cast, :active, data) do
    Logger.info "[WAIT4_RING][:active]"
    pid = data.controlling_process
    send(pid, :ecall_connected)
    timeout_event = {:state_timeout, data.max_time, :connected}
    {:next_state, :connected, data, timeout_event}
  end
  def wait4_ring(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def wait4_answer(:cast, :active, data) do
    Logger.info "[WAIT4_ANSWER][:active]"
    pid = data.controlling_process
    send(pid, :ecall_connected)
    timeout_event = {:state_timeout, data.max_time, :connected}
    {:next_state, :connected, data, timeout_event}
  end
  def wait4_answer(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
  
  def connected(:cast, :disconnect, data) do
    Logger.info "[CONNECTED][:disconnect]"
    pid = data.controlling_process
    send(pid, :ecall_disconnected)
    {:next_state, :idle,data}
  end
  def connected(:state_timeout, :connected, data) do
    handle_event(:cast, :hang_up, data)
  end
  def connected(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def wait4_disconnect_ok(:cast, :ok, data) do
    Logger.info "[WAIT4DISCONNECT][:ok]"
    pid = data.controlling_process
    send(pid, :ecall_disconnected)
    {:next_state, :idle,data}
  end
  def wait4_disconnect_ok(:state_timeout, :wait4_disconnect_ok, data) do
    Logger.info "[WAIT4DISCONNECT][timeout :ok]"
    pid = data.controlling_process
    send(pid, :ecall_disconnected)
    {:next_state, :idle,data}
  end
  def wait4_disconnect_ok(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def abnormal_end(:cast, :ok, data) do
    Logger.info "[ABNORMAL_END][:ok]"
    pid = data.controlling_process
    send(pid, {:error, {:state_timeout, data.last_state}})
    {:next_state, :idle,data}
  end
  def abnormal_end(:state_timeout, _e, data) do
    Logger.info "[ABNORMAL_END][timeout :ok]"
    pid = data.controlling_process
    send(pid, {:error, {:state_timeout, data.last_state}})
    {:next_state, :idle,data}
  end
  def abnormal_end(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def handle_event(:info, {:circuits_uart, _port, ""}, data) do
    {:keep_state, data}
  end
  def handle_event(:info, {:circuits_uart, _port, "\r"}, data) do
    {:keep_state, data}
  end
  def handle_event(:cast, :hang_up, data) do
    Logger.info "Hang up received"
    cmd = Parser.Sim7xxx.hang_up_command()
    Circuits.UART.write(data.serial_pid,cmd)
    timeout_event = {:state_timeout, data.ok_time, :wait4_disconnect_ok}
    {:next_state, :wait4_disconnect_ok, data, timeout_event}
  end
  def handle_event(:info, {:circuits_uart, _port, payload}, data) do
    Logger.info "Data from modem arrived [#{inspect(payload)}]"
    event  = Parser.Sim7xxx.get_event(payload)
    GenStateMachine.cast(self(), event)
    {:keep_state, data}
  end
  def handle_event(:state_timeout, event_content, data) do
    Logger.info "[:state_timeout] in [#{inspect(event_content)}]"
    new_data = %{data | last_state: event_content}
    cmd = Parser.Sim7xxx.end_command()
    Circuits.UART.write(data.serial_pid,cmd)
    timeout_event = {:state_timeout, data.ok_time, event_content}
    {:next_state, :abnormal_end,new_data, timeout_event}
  end
  def handle_event(event_type, event_content, data) do
    Logger.info "Data from modem arrived Generic"
    Logger.info event_type
    Logger.info "#{inspect(event_content)}"
    {:keep_state, data}
  end
end
