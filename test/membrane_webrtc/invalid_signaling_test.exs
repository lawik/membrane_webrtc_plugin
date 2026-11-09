defmodule Membrane.WebRTC.InvalidSignalingTest do
  # Not async: the HTTP requests made here slow down the concurrently running
  # integration tests enough to make their negotiation assertions time out
  use ExUnit.Case, async: false

  import Membrane.ChildrenSpec
  import Membrane.Testing.Assertions

  alias ExWebRTC.{MediaStreamTrack, PeerConnection, SessionDescription}
  alias Membrane.Testing
  alias Membrane.WebRTC
  alias Membrane.WebRTC.Signaling

  # Parses as SDP, but is not a valid WebRTC offer
  @incomplete_offer """
  v=0\r
  o=- 0 0 IN IP4 127.0.0.1\r
  s=-\r
  t=0 0\r
  m=audio 9 UDP/TLS/RTP/SAVPF 111\r
  c=IN IP4 0.0.0.0\r
  a=rtpmap:111 opus/48000/2\r
  """

  test "source ignores malformed offers and keeps negotiating" do
    signaling = Signaling.new()
    Signaling.register_peer(signaling)

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec: child(:webrtc, %WebRTC.Source{signaling: signaling})
      )

    ref = Process.monitor(pipeline)

    for sdp <- ["v=abc", "not an sdp at all", @incomplete_offer] do
      Signaling.signal(signaling, %SessionDescription{type: :offer, sdp: sdp})
    end

    refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 500

    {:ok, pc} = PeerConnection.start_link()
    {:ok, _sender} = PeerConnection.add_track(pc, MediaStreamTrack.new(:audio))
    {:ok, offer} = PeerConnection.create_offer(pc)
    :ok = PeerConnection.set_local_description(pc, offer)

    Signaling.signal(signaling, offer)

    assert_pipeline_notified(pipeline, :webrtc, {:new_tracks, [%{kind: :audio}]})
    assert Process.alive?(pipeline)

    Testing.Pipeline.terminate(pipeline)
  end

  test "WHIP server rejects malformed offers and candidates with 400" do
    port = 6791

    pipeline =
      Testing.Pipeline.start_link_supervised!(
        spec:
          child(:webrtc, %WebRTC.Source{
            signaling: {:whip, ip: {127, 0, 0, 1}, port: port, token: "secret"}
          })
      )

    ref = Process.monitor(pipeline)

    assert %Req.Response{status: 400} =
             Req.post!("http://127.0.0.1:#{port}/",
               headers: [{"content-type", "application/sdp"}, {"authorization", "Bearer secret"}],
               body: "v=abc",
               retry: false
             )

    assert %Req.Response{status: 400} =
             Req.patch!("http://127.0.0.1:#{port}/resource/0123456789",
               headers: [{"content-type", "application/trickle-ice-sdpfrag"}],
               body: "v=abc",
               retry: false
             )

    refute_receive {:DOWN, ^ref, :process, _pid, _reason}, 500
    assert Process.alive?(pipeline)

    Testing.Pipeline.terminate(pipeline)
  end
end
