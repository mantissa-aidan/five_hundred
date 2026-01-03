import http.server
import socketserver
import json
import threading
import os
import time
import numpy as np

# Global state to be shared
GAME_STATE = {}
CONTROL_STATE = {"running": False} # Default paused
LOG_BUFFER = []
LOSS_BUFFER = []
REWARD_BUFFER = []
# Global state to be shared
GAME_STATE = {}
CONTROL_STATE = {"running": True, "mode": "dashboard"} # Default to Running + Dashboard
LOG_BUFFER = []
REWARD_BUFFER = []
EVAL_BUFFER = [] 

# Check for existing persist files
def _load_persist(filename, default):
    try:
        if os.path.exists(filename):
            with open(filename, "r") as f:
                return json.load(f)
    except Exception:
        pass
    return default

LOSS_BUFFER = _load_persist("loss_history.json", [])
REWARD_BUFFER = _load_persist("reward_history.json", [])
EVAL_BUFFER = _load_persist("eval_history.json", [])

WIN_STATS = {"Agent": 0, "Bots": 0}
TOTAL_STEPS = 0
INITIAL_EPISODE_OFFSET = 0
BID_HISTOGRAM = {}  # {bid_tricks: count} for current window
STATE_LOCK = threading.Lock()

# Phase 4: Enhanced metrics
CONTRACT_WINS = 0  # Wins when agent bid
CONTRACT_TOTAL = 0
DEFENSE_WINS = 0   # Wins when opponent bid  
DEFENSE_TOTAL = 0
RECENT_GAME_RESULTS = []  # Last 50 for moving average

# Historical buffers for charts
CONTRACT_HISTORY = _load_persist("contract_history.json", [])
DEFENSE_HISTORY = _load_persist("defense_history.json", [])

from .strategy_tracker import get_strategy_stats
TOTAL_STEPS = 0
INITIAL_EPISODE_OFFSET = 0
STATE_LOCK = threading.Lock()

class StateHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/state':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.send_header('Access-Control-Allow-Origin', '*') 
            self.end_headers()
            
            # Quick copy under lock, then release before expensive operations
            with STATE_LOCK:
                # Fast shallow copy of state
                game_state_copy = GAME_STATE.copy()
                control_copy = CONTROL_STATE.copy()
                logs_copy = LOG_BUFFER[-50:]
                loss_copy = list(LOSS_BUFFER)
                reward_copy = list(REWARD_BUFFER)
                eval_copy = list(EVAL_BUFFER)
                win_stats_copy = WIN_STATS.copy()
                steps_copy = TOTAL_STEPS
                episodes_copy = INITIAL_EPISODE_OFFSET + len(REWARD_BUFFER)
            
            # Now do expensive operations WITHOUT holding the lock
            combined = {
                **game_state_copy, 
                "control": control_copy,
                "logs": logs_copy,
                "steps": steps_copy,
                "episodes": episodes_copy,
                "win_stats": win_stats_copy
            }
            
            # Sampling for charts if too big (limit to 1000 points)
            max_pts = 1000
            
            import math
            def sanitize(val):
                return val if math.isfinite(val) else 0.0

            # Loss
            if len(loss_copy) > max_pts:
                 step = len(loss_copy) // max_pts
                 combined["loss"] = [sanitize(x) for x in loss_copy[::step]]
            else:
                 combined["loss"] = [sanitize(x) for x in loss_copy]
                 
            # Reward
            if len(reward_copy) > max_pts:
                 step = len(reward_copy) // max_pts
                 combined["reward"] = [sanitize(x) for x in reward_copy[::step]]
            else:
                 combined["reward"] = [sanitize(x) for x in reward_copy]
            
            if control_copy.get("mode") == "dashboard":
                # Only send milestone stats
                combined["strategy_stats"] = get_strategy_stats()
                combined["eval_history"] = eval_copy
                combined["bid_histogram"] = BID_HISTOGRAM.copy()  # Send bid distribution
                
                # Phase 4.5: Historical Charts
                combined["contract_history"] = CONTRACT_HISTORY[-500:]  # Send last 500 points
                combined["defense_history"] = DEFENSE_HISTORY[-500:]    # Send last 500 points
                
                # Phase 4: Enhanced metrics
                contract_wr = (CONTRACT_WINS / CONTRACT_TOTAL * 100) if CONTRACT_TOTAL > 0 else 0
                defense_wr = (DEFENSE_WINS / DEFENSE_TOTAL * 100) if DEFENSE_TOTAL > 0 else 0
                moving_avg = (sum(RECENT_GAME_RESULTS) / len(RECENT_GAME_RESULTS) * 100) if RECENT_GAME_RESULTS else 0
                combined["contract_wr"] = round(contract_wr, 1)
                combined["defense_wr"] = round(defense_wr, 1)
                combined["moving_avg_wr"] = round(moving_avg, 1)
                
                # Do not send hands/tricks to save bandwidth
                if "hands" in combined: del combined["hands"]
                if "trick" in combined: del combined["trick"]
            
            def json_serial(obj):
                if isinstance(obj, (np.int64, np.int32)):
                    return int(obj)
                if isinstance(obj, (np.float64, np.float32)):
                    return float(obj)
                raise TypeError ("Type %s not serializable" % type(obj))

            response = json.dumps(combined, default=json_serial)
            self.wfile.write(response.encode('utf-8'))
        elif self.path == '/' or self.path == '':
            # Redirect root to dashboard.html
            self.send_response(301)
            self.send_header('Location', '/dashboard.html')
            self.end_headers()
        else:
            # Serve static files
            super().do_GET()

    def do_POST(self):
        if self.path == '/control':
            content_length = int(self.headers['Content-Length'])
            post_data = self.rfile.read(content_length)
            data = json.loads(post_data)
            
            with STATE_LOCK:
                if 'running' in data:
                    CONTROL_STATE['running'] = bool(data['running'])
                if 'mode' in data:
                    CONTROL_STATE['mode'] = data['mode']
            
            self.send_response(200)
            self.send_header('Access-Control-Allow-Origin', '*')
            self.end_headers()
            self.wfile.write(b'{"status": "ok"}')

def get_control_state():
    with STATE_LOCK:
        return CONTROL_STATE.copy()

def log_message(msg):
    with STATE_LOCK:
        LOG_BUFFER.append(msg)
        if len(LOG_BUFFER) > 200:
            LOG_BUFFER.pop(0)
    
    # Write to file
    try:
        # Use a relative path to workspace root generally safe here as cwd is usually root
        with open("game_training.log", "a") as f:
            f.write(f"{msg}\n")
    except Exception:
        pass # Don't crash on logging fail

def record_loss(loss_val):
    with STATE_LOCK:
        LOSS_BUFFER.append(loss_val)
        if len(LOSS_BUFFER) % 100 == 0: # Periodic save
            try:
                with open("loss_history.json", "w") as f:
                    json.dump(LOSS_BUFFER[-2000:], f) # Keep last 2000 for chart
            except Exception: pass

def record_reward(reward_val):
    with STATE_LOCK:
        REWARD_BUFFER.append(reward_val)
        if len(REWARD_BUFFER) % 10 == 0: # Periodic save
            try:
                with open("reward_history.json", "w") as f:
                    json.dump(REWARD_BUFFER[-2000:], f) # Keep last 2000 for chart
            except Exception: pass

def record_eval_result(episode, win_rate):
    with STATE_LOCK:
        entry = {"episode": episode, "win_rate": win_rate}
        EVAL_BUFFER.append(entry)
        
        # Persist
        try:
           with open("eval_history.json", "w") as f:
               json.dump(EVAL_BUFFER, f)
        except Exception as e:
            print(f"Failed to save eval history: {e}")

def record_bid(bid_str, is_agent):
    """Record agent bids for histogram tracking. bid_str ex: '7-Spades'"""
    if not is_agent:
        return
    with STATE_LOCK:
        if bid_str not in BID_HISTOGRAM:
            BID_HISTOGRAM[bid_str] = 0
        BID_HISTOGRAM[bid_str] += 1

def record_game_result(won, agent_bid):
    """Track contract vs defense win rates"""
    global CONTRACT_WINS, CONTRACT_TOTAL, DEFENSE_WINS, DEFENSE_TOTAL, RECENT_GAME_RESULTS
    with STATE_LOCK:
        if agent_bid:
            CONTRACT_TOTAL += 1
            if won:
                CONTRACT_WINS += 1
        else:
            DEFENSE_TOTAL += 1
            if won:
                DEFENSE_WINS += 1
        RECENT_GAME_RESULTS.append(1 if won else 0)
        if len(RECENT_GAME_RESULTS) > 50:
            RECENT_GAME_RESULTS.pop(0)

def record_history_snapshot(episode):
    """Record snapshot of contract/defense stats for historical graphing"""
    global CONTRACT_HISTORY, DEFENSE_HISTORY
    
    with STATE_LOCK:
        contract_wr = (CONTRACT_WINS / CONTRACT_TOTAL * 100) if CONTRACT_TOTAL > 0 else 0
        defense_wr = (DEFENSE_WINS / DEFENSE_TOTAL * 100) if DEFENSE_TOTAL > 0 else 0
        
        # Add to history
        CONTRACT_HISTORY.append({"episode": episode, "wr": round(contract_wr, 1)})
        DEFENSE_HISTORY.append({"episode": episode, "wr": round(defense_wr, 1)})
        
        # Keep manageable size (last 2000 points)
        if len(CONTRACT_HISTORY) > 2000:
            CONTRACT_HISTORY = CONTRACT_HISTORY[-2000:]
            DEFENSE_HISTORY = DEFENSE_HISTORY[-2000:]
            
        # Persist
        try:
            with open("contract_history.json", "w") as f:
                json.dump(CONTRACT_HISTORY, f)
            with open("defense_history.json", "w") as f:
                json.dump(DEFENSE_HISTORY, f)
        except Exception: pass

def increment_steps():
    global TOTAL_STEPS
    with STATE_LOCK:
        TOTAL_STEPS += 1

def set_initial_episode_count(n):
    global INITIAL_EPISODE_OFFSET
    with STATE_LOCK:
        INITIAL_EPISODE_OFFSET = n

def update_state(new_state):
    global GAME_STATE
    with STATE_LOCK:
        GAME_STATE = new_state

def run_server(start_port=8000):
    port = start_port
    while port < start_port + 10:
        try:
            print(f"Attempting to start server on port {port}...")
            web_dir = os.path.join(os.path.dirname(__file__), 'static')
            if not os.path.exists(web_dir):
                print(f"ERROR: Static dir not found: {web_dir}")
                return
                
            # os.chdir(web_dir) # REMOVED: Do not change global CWD
            
            import functools
            
            class ReusableTCPServer(socketserver.TCPServer):
                allow_reuse_address = True
            
            # Create handler factory with directory arg (Python 3.7+)
            handler_factory = functools.partial(StateHandler, directory=web_dir)
    
            with ReusableTCPServer(("", port), handler_factory) as httpd:
                print(f"Serving UI at http://localhost:{port}")
                # Save port to a global if needed, or print clearly
                httpd.serve_forever()
                return # Should not reach here
        except OSError as e:
            if e.errno == 48: # Address in use
                print(f"Port {port} in use, trying next...")
                port += 1
                time.sleep(1)
            else:
                raise e
        except Exception as e:
            import traceback
            traceback.print_exc()
            print(f"SERVER CRASH: {e}")
            return
            
    print("Could not find open port after 10 attempts.")

def start_server_thread():
    print("Launching server thread...")
    t = threading.Thread(target=run_server, daemon=True)
    t.start()
    return t
