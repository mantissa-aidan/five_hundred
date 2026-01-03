import torch
import json
import os
import argparse
from five_hundred.ppo_agent import PPOPolicy
import torch.nn as nn

def export_weights(run_id, output_path, direct_path=None):
    if direct_path:
        ckpt_path = direct_path
        print(f"Loading direct path: {ckpt_path}...")
    elif run_id:
        print(f"Exporting weights for run {run_id} to {output_path}...")
        ckpt_dir = os.path.join("checkpoints", run_id)
        if not os.path.exists(ckpt_dir):
            print(f"Checkpoint dir not found: {ckpt_dir}")
            return
        files = [f for f in os.listdir(ckpt_dir) if f.endswith(".pth")]
        if not files:
            print("No .pth files found.")
            return
        if "best_model.pth" in files: ckpt_name = "best_model.pth"
        else: ckpt_name = sorted(files)[-1]
        ckpt_path = os.path.join(ckpt_dir, ckpt_name)
        print(f"Loading {ckpt_path}...")
    else:
        print("Must provide --run_id or --path")
        return
    
    # 1. Load Checkpoint
    try:
        state_dict = torch.load(ckpt_path, map_location='cpu')
    except Exception as e:
        print(f"Failed to load checkpoint: {e}")
        return

    # Check if nested
    if 'model_state_dict' in state_dict:
        state_dict = state_dict['model_state_dict']
    elif 'agent_state_dict' in state_dict:
        state_dict = state_dict['agent_state_dict']
        
    # 2. Extract Layers
    # PPOPolicy Structure:
    # shared: Sequential(Linear(466,256), ReLU, Linear(256,128), ReLU)
    # actor_bid: Linear(128, 26)
    # actor_play: Linear(128, 53)
    
    weights = {}
    
    def tensor_to_list(t):
        return t.detach().cpu().numpy().tolist()
    
    # Helper to extract layer
    def extract_linear(prefix, name_in_json):
        w_key = f"{prefix}.weight"
        b_key = f"{prefix}.bias"
        if w_key in state_dict:
            weights[name_in_json] = {
                'weight': tensor_to_list(state_dict[w_key]),
                'bias': tensor_to_list(state_dict[b_key])
            }
            print(f"Extracted {name_in_json} from {prefix}")
        else:
            print(f"Warning: Could not find {w_key}")

    # Shared Trunk
    extract_linear('shared.0', 'shared_fc1')
    extract_linear('shared.2', 'shared_fc2')
    
    # Heads
    extract_linear('actor_bid', 'actor_bid')
    extract_linear('actor_play', 'actor_play')
    
    # Critics (Optional, but useful if running full PPO in Lua later?)
    # For inference only, we don't strictly need them.
    
    # 3. Save
    # Ensure dir exists
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    
    with open(output_path, 'w') as f:
        json.dump(weights, f)
        
    print(f"Saved weights to {output_path}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--run_id", type=str, required=False, help="Run ID to export")
    parser.add_argument("--path", type=str, required=False, help="Direct path to checkpoint")
    parser.add_argument("--output", type=str, default="five_hundred_love/assets/weights.json", help="Output JSON path")
    args = parser.parse_args()
    
    export_weights(args.run_id, args.output, direct_path=args.path)
