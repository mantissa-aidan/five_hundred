import json
import os
from datetime import datetime

class HistoryRecorder:
    def __init__(self, log_dir="arena_history"):
        self.log_dir = log_dir
        if not os.path.exists(log_dir):
            os.makedirs(log_dir)
        
        self.current_file = os.path.join(
            self.log_dir, 
            f"arena_{datetime.now().strftime('%Y%m%d_%H%M%S')}.jsonl"
        )
        self.buffer = []

    def record(self, state_dict, action, reward, next_state_dict, done):
        """
        Records a transition in raw dictionary format (for future-proofing).
        """
        # We need to serialize some objects (like Card, Suit, etc.)
        def serialize(obj):
            if hasattr(obj, 'name'): return obj.name
            if isinstance(obj, list): return [serialize(x) for x in obj]
            if isinstance(obj, dict): return {k: serialize(v) for k, v in obj.items()}
            if hasattr(obj, '__dict__'): return serialize(obj.__dict__)
            return str(obj)

        entry = {
            "timestamp": datetime.now().isoformat(),
            "state": serialize(state_dict),
            "action": serialize(action),
            "reward": reward,
            "next_state": serialize(next_state_dict),
            "done": done
        }
        
        with open(self.current_file, "a") as f:
            f.write(json.dumps(entry) + "\n")

recorder = HistoryRecorder()
