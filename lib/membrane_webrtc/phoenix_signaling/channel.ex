if Code.ensure_loaded?(Phoenix) do
  defmodule Membrane.WebRTC.PhoenixSignaling.Channel do
    @moduledoc false
    use Phoenix.Channel
    alias Membrane.WebRTC.PhoenixSignaling
    alias Membrane.WebRTC.Signaling

    @impl true
    def join(signaling_id, _payload, socket) do
      signaling = PhoenixSignaling.Registry.get_or_create(signaling_id)

      case Signaling.register_peer(signaling, message_format: :json_data, pid: self()) do
        :ok ->
          Process.monitor(signaling.pid)
          socket = assign(socket, signaling_id: signaling_id, signaling: signaling)
          {:ok, socket}

        {:error, :busy} ->
          # The signaling already has its two peers, e.g. a browser and a Membrane element
          # in an ongoing session; don't let another socket join it
          {:error, %{reason: "busy"}}
      end
    end

    @impl true
    def handle_in(_signaling_id, msg, socket) do
      msg = Jason.decode!(msg)
      Signaling.signal(socket.assigns.signaling, msg)
      {:noreply, socket}
    end

    @impl true
    def handle_info({:membrane_webrtc_signaling, _pid, msg, _metadata}, socket) do
      push(socket, socket.assigns.signaling_id, msg)
      {:noreply, socket}
    end

    @impl true
    def handle_info({:DOWN, _ref, :process, _pid, _reason}, socket) do
      {:stop, :normal, socket}
    end
  end
end
