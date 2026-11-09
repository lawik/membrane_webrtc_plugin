defmodule Membrane.WebRTC.SignalingTest do
  use ExUnit.Case, async: true

  alias ExWebRTC.SessionDescription
  alias Membrane.WebRTC.Signaling

  test "a third peer is rejected without tearing down the signaling" do
    signaling = Signaling.new()
    peer_a = self()
    peer_b = spawn_link(fn -> forward_messages(peer_a) end)
    intruder = spawn_link(fn -> forward_messages(peer_a) end)

    assert :ok = Signaling.register_peer(signaling, pid: peer_a)
    assert :ok = Signaling.register_peer(signaling, pid: peer_b)
    assert {:error, :busy} = Signaling.register_peer(signaling, pid: intruder)

    # Neither a signal from the rejected process nor its death affects the session
    send(signaling.pid, {:signal, intruder, :intruder_message, %{}})
    Process.unlink(intruder)
    Process.exit(intruder, :kill)

    offer = %SessionDescription{type: :offer, sdp: "v=0\r\n"}
    Signaling.signal(signaling, offer)
    assert_receive {:forwarded, {:membrane_webrtc_signaling, _pid, ^offer, %{}}}
    refute_received {:forwarded, {:membrane_webrtc_signaling, _pid, :intruder_message, _meta}}
    assert Process.alive?(signaling.pid)
  end

  defp forward_messages(to) do
    receive do
      message ->
        send(to, {:forwarded, message})
        forward_messages(to)
    end
  end
end
