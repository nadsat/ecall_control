defmodule Ecall.Control do
  use GenStateMachine, callback_mode: :state_functions
  require Logger
  @moduledoc """
  Make phone calls using modem with at commands.
  """
 defmodule StateData do
    @moduledoc false
    # from: pid of client (where the audio data is sent)
    # pid: pid of serial port process
    defstruct serial_pid: nil,
     controlling_process: nil,
     port_module: nil,
     last_state: :idle,
     ok_time: 300,
     dial_time: 300,
     ring_time: 20000,
     answer_time:  25000,
     max_time: :infinity
  end

  @doc """
  Start up a CallControl GenStateMachine.
  """
  @spec start_link( [term]) :: {:ok, pid} | {:error, term}
  def start_link( port_module, opts \\ []) do
    GenStateMachine.start_link(__MODULE__, port_module, opts)
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
  def init(port_module) do
    Logger.info "Init FSM"
    case  port_module.start_link do
      {:ok, pid} ->
        data = %StateData{serial_pid: pid,
                          port_module: port_module}
        {:ok, :setup, data}
      {:error, cause} ->
        {:stop, cause}
    end
  end

  def setup({:call,from}, {:open, proc_pid, name}, data) do
    Logger.info "[SETUP][:open]"
    module = data.port_module
    case module.open_port(data.serial_pid, name) do
      :ok -> 
        new_data = %{data | controlling_process: proc_pid}
        {:next_state, :idle, new_data, [{:reply, from, :ok}]}
      ret -> 
        {:stop, ret}
    end
  end

  def setup(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def idle(:cast, {:dial,number, max_time}, data) do
    Logger.info "[IDLE][:dial]"
    new_data = %{data | max_time: max_time}
    module = data.port_module
    module.dial(data.serial_pid,number)
    timeout_event = {:state_timeout, data.dial_time, :wait4_dialing}
    {:next_state, :wait4_dialing, new_data, timeout_event}
  end
  def idle(:info, {:incoming, number}, data) do
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
    module = data.port_module
    module.answer(data.serial_pid)
    {:next_state, :wait4_answer, new_data}
  end
  def wait4_action(:cast, :reject_call, data) do
    module = data.port_module
    module.reject(data.serial_pid)
    {:next_state, :idle, data}
  end
  def wait4_action(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
  
  def wait4_dialing(:info, :dialing, data) do
    Logger.info "[WAIT4_DIALING][:dialing]"
    timeout_event = {:state_timeout, data.ring_time, :wait4_ring}
    {:next_state, :wait4_ring, data,timeout_event}
  end
  def wait4_dialing(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def wait4_ring(:info, :ringing, data) do
    Logger.info "[WAIT4_RINGING][:ringing]"
    timeout_event = {:state_timeout, data.answer_time, :wait4_answer}
    {:next_state, :wait4_answer, data, timeout_event}
  end
  def wait4_ring(:info, :active, data) do
    Logger.info "[WAIT4_RING][:active]"
    pid = data.controlling_process
    send(pid, :ecall_connected)
    timeout_event = {:state_timeout, data.max_time, :connected}
    {:next_state, :connected, data, timeout_event}
  end
  def wait4_ring(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  def wait4_answer(:info, :active, data) do
    Logger.info "[WAIT4_ANSWER][:active]"
    pid = data.controlling_process
    send(pid, :ecall_connected)
    timeout_event = {:state_timeout, data.max_time, :connected}
    {:next_state, :connected, data, timeout_event}
  end
  def wait4_answer(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end
  
  def connected(:info, :disconnect, data) do
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

  def handle_event(:info, {:dtmf, digit}, data) do
    pid = data.controlling_process
    send(pid, {:dtmf, digit})
    {:next_state, :idle, data}
  end
  def handle_event(:info, :disconnect, data) do
    pid = data.controlling_process
    send(pid, :ecall_disconnected)
    {:next_state, :idle, data}
  end
  def handle_event(:cast, :hang_up, data) do
    Logger.info "Hang up received"
    module = data.port_module
    module.hang_up(data.serial_pid)
    pid = data.controlling_process
    send(pid, :ecall_hungup)
    {:next_state, :idle, data}
  end
  def handle_event(:state_timeout, event_content, data) do
    Logger.info "[:state_timeout] in [#{inspect(event_content)}]"
    new_data = %{data | last_state: event_content}
    module = data.port_module
    module.finish(data.serial_pid)
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
