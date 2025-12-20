
import threading
import time
import json
import urllib.request
import unittest
from five_hundred.server import run_server, update_state, get_control_state, STATE_LOCK, GAME_STATE, CONTROL_STATE

class TestServer(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Start server on a specific test port
        cls.port = 8081
        cls.server_thread = threading.Thread(target=run_server, args=(cls.port,), daemon=True)
        cls.server_thread.start()
        print("Test Server Starting...")
        time.sleep(2) # Give it time to bind

    def test_01_get_state(self):
        """Test that /state endpoint returns JSON with expected keys."""
        url = f"http://localhost:{self.port}/state"
        with urllib.request.urlopen(url) as response:
            self.assertEqual(response.status, 200)
            data = json.loads(response.read().decode())
            self.assertIn("control", data)
            self.assertIn("logs", data)
            self.assertIn("loss", data)
            # Check default control state
            self.assertFalse(data["control"]["running"])

    def test_02_update_game_state(self):
        """Test that server reflects state updates."""
        test_state = {"phase": "TESTING", "score": 100}
        update_state(test_state)
        
        url = f"http://localhost:{self.port}/state"
        with urllib.request.urlopen(url) as response:
            data = json.loads(response.read().decode())
            self.assertEqual(data.get("phase"), "TESTING")
            self.assertEqual(data.get("score"), 100)

    def test_03_control_command(self):
        """Test sending POST /control updates the state."""
        url = f"http://localhost:{self.port}/control"
        payload = json.dumps({"running": True}).encode('utf-8')
        req = urllib.request.Request(url, data=payload, method='POST')
        req.add_header('Content-Type', 'application/json')
        
        with urllib.request.urlopen(req) as response:
            self.assertEqual(response.status, 200)
        
        # Verify internal state updated
        control = get_control_state()
        self.assertTrue(control["running"])
        
        # Verify via GET
        url_get = f"http://localhost:{self.port}/state"
        with urllib.request.urlopen(url_get) as response:
            data = json.loads(response.read().decode())
            self.assertTrue(data["control"]["running"])

if __name__ == '__main__':
    unittest.main()
