"""Send generic control events over OSC.

This adapter should transmit already-mapped control events without deciding
what a hand feature means musically.
"""

from pythonosc.udp_client import SimpleUDPClient


class OscOutput:
    """OSC sender for generic control events."""

    def __init__(self, host, port):
        self.host = host
        self.port = port
        self.client = SimpleUDPClient(host, port)

    def send(self, event):
        """Send one generic control event."""
        self.client.send_message(event.address, event.value)

    def send_many(self, events):
        """Send multiple generic control events."""
        for event in events:
            self.send(event)

    def close(self):
        """Release any OSC output resources."""
        return None
