import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from five_hundred.env import FiveHundredEnv
from five_hundred.agent import PyTorchAgent
from five_hundred.server import get_control_state
import time

import glob
import os
import re

import argparse

def train():
    parser = argparse.ArgumentParser(description='Train the Five Hundred Agent')
    parser.add_argument('--save-dir', type=str, default='.', help='Directory to save checkpoints to')
    args = parser.parse_args()
    
    save_dir = args.save_dir
    os.makedirs(save_dir, exist_ok=True) # Ensure dir exists

    print("Initializing Environment...")
    env = FiveHundredEnv(verbose=False) # Reduced noise
    print("Initializing Agent...")
    agent = PyTorchAgent(state_dim=600, action_dim=100)
    
    # Auto-Resume Logic
    # Scan save_dir for checkpoints
    checkpoints = glob.glob(os.path.join(save_dir, "model_checkpoint_*.pth"))
    start_episode = 0
    if checkpoints:
        # Sort by episode number
        def extract_ep(filename):
            match = re.search(r"model_checkpoint_(\d+).pth", filename)
            return int(match.group(1)) if match else 0
            
        latest_checkpoint = max(checkpoints, key=extract_ep)
        start_episode = extract_ep(latest_checkpoint)
        
        print(f"Resuming training from: {latest_checkpoint}")
        agent.load(latest_checkpoint)
    else:
        print(f"No checkpoint found in {save_dir}. Starting fresh.")
        
    from five_hundred.server import set_initial_episode_count
    set_initial_episode_count(start_episode)
    
    print("Waiting for Start Command from UI...")
    
    episode_count = start_episode
    state = None
    
    while True:
        # Check control state
        control = get_control_state()
        if not control.get("running", False):
            time.sleep(1) # Idle wait
            continue

        # If we are starting fresh or need reset
        if state is None:
             state, info = env.reset() # Info contains mask
             episode_count += 1
             # print(f"Episode {episode_count} start.") # Too noisy
             step_count = 0
             total_reward = 0

        # Step
        mask = info.get('mask') if 'info' in locals() else None
        # PyTorchAgent needs explicit phase for split network
        # We can get it from env.last_phase
        action = agent.act(state, env.last_phase, mask)
        next_state, reward, done, next_info = env.step(action)
        
        info = next_info # Update info for next loop
        
        agent.remember(state, action, reward, next_state, done, info)
        loss = agent.replay()
        
        if loss is not None:
             from five_hundred.server import record_loss, record_reward, increment_steps
             record_loss(float(loss))
             increment_steps()
        
        state = next_state
        total_reward += reward
        step_count += 1
        
        if done:
            # Concise Log
            invalid_cnt = info.get('invalid_moves', 0)
            avg_loss_str = f"{loss:.2f}" if loss else "N/A"
            print(f"Ep {episode_count}: Reward={total_reward:.1f}, Invalid={invalid_cnt}, Steps={step_count}, Eps={agent.epsilon:.3f}, Loss={avg_loss_str}")
            
            from five_hundred.server import record_reward
            record_reward(float(total_reward))
            
            
            agent.update_target_network()
            agent.decay_epsilon() 
            
            if episode_count % 50 == 0:
                save_path = os.path.join(save_dir, f"model_checkpoint_{episode_count}.pth")
                agent.save(save_path)
                print(f"Saved checkpoint: {save_path}")
            
            state = None # Trigger reset on next loop iteration            
            # Optional: Pause after each episode? 
            # For "continuous", we just keep going.

if __name__ == "__main__":
    train()
