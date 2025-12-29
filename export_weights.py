
import torch
import json
import os
import sys

# Add project root to path
sys.path.append(os.getcwd())

from five_hundred.agent import PyTorchAgent

def export_weights(checkpoint_path, output_path):
    print(f"Loading checkpoint from {checkpoint_path}...")
    
    # Initialize agent (dims must match training, using defaults from file)
    agent = PyTorchAgent()
    try:
        agent.load(checkpoint_path)
    except Exception as e:
        print(f"Error loading model: {e}")
        return

    weights = {
        "bidding": {},
        "playing": {}
    }

    # Helper to serialize state dict
    def serialize_state_dict(state_dict):
        out = {}
        for k, v in state_dict.items():
            out[k] = v.cpu().numpy().tolist()
        return out

    weights["bidding"] = serialize_state_dict(agent.bid_net.state_dict())
    weights["playing"] = serialize_state_dict(agent.play_net.state_dict())

    print(f"Exporting to {output_path}...")
    with open(output_path, 'w') as f:
        json.dump(weights, f)
    print("Done.")

if __name__ == "__main__":
    # Find latest checkpoint
    static_dir = "five_hundred/static"
    checkpoints = [f for f in os.listdir(static_dir) if f.startswith("model_checkpoint_") and f.endswith(".pth")]
    
    if not checkpoints:
        print("No checkpoints found.")
        sys.exit(1)
        
    # Sort by number
    checkpoints.sort(key=lambda x: int(x.split('_')[-1].split('.')[0]))
    latest = checkpoints[-1]
    
    checkpoint_path = os.path.join(static_dir, latest)
    output_path = "five_hundred_love/assets/weights.json"
    
    export_weights(checkpoint_path, output_path)
