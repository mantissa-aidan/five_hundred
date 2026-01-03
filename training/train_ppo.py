"""
PPO Training Script for Five Hundred Card Game (M1 Optimized)

Uses Vectorized Environment (multiprocessing) to collect data efficiently.
Migrated from DQN to PPO for:
- On-policy stability
- Consistent long-term strategy (bidding + playing)
- Multi-objective handling (Bidding Value != Play Value)
"""

import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import time
import torch
import torch.nn as nn
import torch.optim as optim
import numpy as np
import wandb
from multiprocessing import cpu_count

from five_hundred.vectorized_env import VectorizedEnv
from five_hundred.ppo_agent import PPOPolicy, RolloutBuffer, transfer_dqn_to_ppo
from five_hundred.utils_rl import decode_action

def train():
    # --- Hyperparameters ---
    NUM_ENVS = 16  # Increased for higher batch throughput
    STEPS_PER_ROLLOUT = 32 # Faster updates
    TOTAL_TIMESTEPS = 5_000_000 # Extended for Long-Term League Play
    BATCH_SIZE = 64
    EPOCHS_PER_UPDATE = 4
    LR = 2.5e-4
    GAMMA = 0.99
    GAE_LAMBDA = 0.95
    CLIP_EPS = 0.2
    ENT_COEF = 0.01
    VF_COEF = 0.5
    MAX_GRAD_NORM = 0.5
    
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print(f"Using device: {device} with {NUM_ENVS} parallel environments")

    # --- Setup ---
    run_name = f"ppo_500_{int(time.time())}"
    wandb.init(
        project="five-hundred-rl",
        name=run_name,
        config={
            "algo": "PPO",
            "num_envs": NUM_ENVS,
            "steps_per_rollout": STEPS_PER_ROLLOUT,
            "total_timesteps": TOTAL_TIMESTEPS,
            "lr": LR,
            "gamma": GAMMA
        }
    )

    # Initialize Environment & Policy
    # Initialize Environment & Policy (With League Support)
    league_dir = "checkpoints/league"
    os.makedirs(league_dir, exist_ok=True)
    envs = VectorizedEnv(num_envs=NUM_ENVS, bot_difficulty='medium', league_path=league_dir, device='cpu') # Workers on CPU policy
    policy = PPOPolicy(state_dim=466).to(device)
    optimizer = optim.Adam(policy.parameters(), lr=LR, eps=1e-5)
    
    # Load Checkpoint (Resume or Warm Start)
    start_update = 1
    dqn_path = "pre_training/rules_bot/pretrained_agent.pth"
    latest_path = "checkpoints/ppo_latest.pth"
    best_reward = -float('inf')
    
    # Check for latest checkpoint
    if os.path.exists(latest_path):
        print(f"Resuming from LATEST checkpoint: {latest_path}")
        checkpoint = torch.load(latest_path, map_location=device)
        policy.load_state_dict(checkpoint['model_state_dict'] if 'model_state_dict' in checkpoint else checkpoint)
        if 'optimizer_state_dict' in checkpoint:
             optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        
        # Extract metadata
        if 'global_step' in checkpoint:
             global_step = checkpoint['global_step']
             start_update = global_step // (NUM_ENVS * STEPS_PER_ROLLOUT) + 1
             print(f"Resuming at Step {global_step} (Update {start_update})")
        if 'best_reward' in checkpoint:
             best_reward = checkpoint['best_reward']
             
    # Legacy Fallback (ppo_step_*.pth) - Migration
    elif os.path.exists("checkpoints") and any(f.startswith("ppo_step_") for f in os.listdir("checkpoints")):
        ppo_checkpoints = [f for f in os.listdir("checkpoints") if f.startswith("ppo_step_") and f.endswith(".pth")]
        latest = max(ppo_checkpoints, key=lambda x: int(x.split('_')[2].split('.')[0]))
        load_path = os.path.join("checkpoints", latest)
        print(f"Resuming from LEGACY checkpoint: {load_path}")
        
        checkpoint = torch.load(load_path, map_location=device)
        policy.load_state_dict(checkpoint['model_state_dict'] if 'model_state_dict' in checkpoint else checkpoint)
        if 'optimizer_state_dict' in checkpoint: optimizer.load_state_dict(checkpoint['optimizer_state_dict'])
        
        try:
             global_step = int(latest.split('_')[2].split('.')[0])
             start_update = global_step // (NUM_ENVS * STEPS_PER_ROLLOUT) + 1
        except: pass
        
    elif os.path.exists(dqn_path):
        print("Loading Warm Start (DQN)...")
        transfer_dqn_to_ppo(dqn_path, policy, device)

    # Buffers (One per env to handle independent GAE calculation)
    buffers = [RolloutBuffer(STEPS_PER_ROLLOUT) for _ in range(NUM_ENVS)]

    # Initial Observation
    obs, phases, masks = envs.reset()
    # obs: [N, 466], phases: [N], masks: [N, 53]
    
    # Init if not resumed
    if 'global_step' not in locals():
         global_step = 0
    
    start_time = time.time()
    
    # --- Main Loop ---
    num_updates = TOTAL_TIMESTEPS // (NUM_ENVS * STEPS_PER_ROLLOUT)
    
    for update in range(start_update, num_updates + 1):
        # Anneal Learning Rate
        frac = 1.0 - (update - 1.0) / num_updates
        lrnow = LR * frac
        optimizer.param_groups[0]["lr"] = lrnow

        # 1. Collect Rollouts
        policy.eval()
        
        # Stats for this update
        bid_counts = np.zeros(26, dtype=int)
        ep_offense_wins = []
        ep_defense_wins = []
        for step in range(STEPS_PER_ROLLOUT):
            global_step += NUM_ENVS
            
            # Convert to tensor
            obs_tensor = torch.tensor(obs, dtype=torch.float32).to(device)
            masks_tensor = torch.tensor(masks, dtype=torch.float32).to(device)
            
            # Action Selection
            actions_list = []
            values_list = []
            log_probs_list = []
            
            # Inference (Batch processing handling mixed phases?)
            # PPOPolicy expects 'phase' argument. Our batch has mixed phases!
            # We must group by phase to use the correct head.
            
            # Initialize outputs
            actions_final = np.zeros(NUM_ENVS, dtype=np.int64)
            log_probs_final = torch.zeros(NUM_ENVS).to(device)
            values_final = torch.zeros(NUM_ENVS).to(device)
            
            # Group indices by phase
            phase_indices = {'BID': [], 'PLAY': [], 'KITTY': []}
            for i, p in enumerate(phases):
                phase_indices[p].append(i)
                
            with torch.no_grad():
                for p_name, indices in phase_indices.items():
                    if not indices: continue
                    idx_tensor = torch.tensor(indices).to(device)
                    
                    sub_obs = obs_tensor[indices]
                    sub_masks = masks_tensor[indices]
                    
                    # PPO Inference
                    # Note: KITTY phase maps to Play head or separate?
                    inf_phase = 'PLAY' if p_name == 'KITTY' else p_name
                    
                    # Fix: Slice mask if BID
                    if inf_phase == 'BID':
                         sub_masks = sub_masks[:, :26]
                    
                    a, lp, ent, v = policy.get_action_and_value(sub_obs, phase=inf_phase, mask=sub_masks)
                    
                    # Store results using scatter/assign
                    for k, idx in enumerate(indices):
                        actions_final[idx] = a[k].item()
                        log_probs_final[idx] = lp[k]
                        values_final[idx] = v[k]

            # Step Environment
            next_obs, rewards, dones, next_phases, next_masks, infos = envs.step(actions_final)
            
            # Scale Rewards (Best Practice: Normalize large scores)
            rewards = rewards / 100.0
            
            # Metrics Tracking
            for k, phase in enumerate(phases):
                if phase == 'BID':
                    bid_counts[actions_final[k]] += 1
            
            for info in infos:
                if 'metrics' in info:
                    for m in info['metrics']:
                        if m['offense_win'] is not None: ep_offense_wins.append(m['offense_win'])
                        if m['defense_win'] is not None: ep_defense_wins.append(m['defense_win'])
            
            # Store in Buffers
            for i in range(NUM_ENVS):
                buffers[i].add(
                    obs_tensor[i], 
                    torch.tensor(actions_final[i], dtype=torch.int64).to(device),
                    log_probs_final[i],
                    rewards[i],
                    dones[i],
                    values_final[i],
                    masks_tensor[i],
                    phases[i]
                )
            
            # Debug Progress
            if step % 10 == 0:
                print(f"Step {step}/{STEPS_PER_ROLLOUT}", end='\r', flush=True)
            
            # Update state for next step
            obs = next_obs
            phases = next_phases
            masks = next_masks

        # 2. Compute Advantages & Bootstrap (GAE)
        # We need Value of Next State for bootstrapping
        # Do one more inference pass
        next_values_final = torch.zeros(NUM_ENVS).to(device)
        obs_tensor = torch.tensor(obs, dtype=torch.float32).to(device)
        
        # Phase grouping again
        phase_indices = {'BID': [], 'PLAY': [], 'KITTY': []}
        for i, p in enumerate(phases): phase_indices[p].append(i)
            
        with torch.no_grad():
             for p_name, indices in phase_indices.items():
                if not indices: continue
                inf_phase = 'PLAY' if p_name == 'KITTY' else p_name
                sub_obs = obs_tensor[indices]
                v = policy.get_value(sub_obs, inf_phase)
                for k, idx in enumerate(indices):
                    next_values_final[idx] = v[k]

        # Finish Buffers
        combined_data = {k: [] for k in ['states', 'actions', 'log_probs', 'returns', 'advantages', 'values', 'masks']}
        all_phases = [] # Cannot stack strings
        
        for i in range(NUM_ENVS):
            adv, ret = buffers[i].compute_advantages(next_values_final[i], GAMMA, GAE_LAMBDA)
            data = buffers[i].get()
            
            combined_data['states'].append(data['states'])
            combined_data['actions'].append(data['actions'])
            combined_data['log_probs'].append(data['log_probs'])
            combined_data['values'].append(data['values'])
            combined_data['masks'].append(data['masks'])
            combined_data['returns'].append(ret)
            combined_data['advantages'].append(adv)
            all_phases.extend(data['phases'])
            
            buffers[i].clear()
            
        # Flatten All Data
        # [NUM_ENVS, STEPS] -> [NUM_ENVS * STEPS]
        b_states = torch.cat(combined_data['states']).to(device)
        b_actions = torch.cat(combined_data['actions']).to(device)
        b_log_probs = torch.cat(combined_data['log_probs']).to(device)
        b_returns = torch.cat(combined_data['returns']).to(device)
        b_advantages = torch.cat(combined_data['advantages']).to(device)
        b_advantages = torch.cat(combined_data['advantages']).to(device)
        # Normalize Advantages (Best Practice)
        b_advantages = (b_advantages - b_advantages.mean()) / (b_advantages.std() + 1e-8)
        
        b_values = torch.cat(combined_data['values']).to(device)
        b_masks = torch.cat(combined_data['masks']).to(device)
        
        # 3. PPO Update (Optimization)
        policy.train()
        b_inds = np.arange(len(b_states))
        
        clipfracs = []
        for epoch in range(EPOCHS_PER_UPDATE):
            np.random.shuffle(b_inds)
            for start in range(0, len(b_states), BATCH_SIZE):
                end = start + BATCH_SIZE
                mb_inds = b_inds[start:end]
                
                # Slicing mixed-phase batch? 
                # PPOPolicy.get_action_and_value needs 'phase' argument.
                # Problem: A batch contains mixed BID and PLAY steps.
                # Solution: Partition mini-batch by phase.
                
                mb_phases = [all_phases[idx] for idx in mb_inds]
                
                # Group by phase within minibatch
                # This is inefficient but necessary given the architecture's strict separation
                # Optimization: Could mask losses instead of branching
                
                # Accumulate loss components
                loss_sum = 0
                count_sum = 0
                
                # Indices in minibatch relative to mb_inds
                mb_phase_map = {'BID': [], 'PLAY': [], 'KITTY': []}
                for mm_i, ph in enumerate(mb_phases):
                     mb_phase_map[ph].append(mm_i)
                
                total_loss = 0
                
                # Zero grad
                optimizer.zero_grad()
                
                for p_name, local_indices in mb_phase_map.items():
                    if not local_indices: continue
                    
                    # Get indices into the master Batch
                    global_indices = mb_inds[local_indices]
                    inf_phase = 'PLAY' if p_name == 'KITTY' else p_name
                    
                    # Fix: Slice mask if BID
                    current_masks = b_masks[global_indices]
                    if inf_phase == 'BID':
                         current_masks = current_masks[:, :26]
                    
                    # Forward pass
                    _, newlogprob, entropy, newvalue = policy.get_action_and_value(
                        b_states[global_indices], 
                        phase=inf_phase, 
                        action=b_actions[global_indices], 
                        mask=current_masks
                    )
                    
                    logratio = newlogprob - b_log_probs[global_indices]
                    ratio = logratio.exp()
                    
                    with torch.no_grad():
                        # Calculate approx_kl http://joschu.net/blog/kl-approx.html
                        old_approx_kl = (-logratio).mean()
                        approx_kl = ((ratio - 1) - logratio).mean()
                        clipfracs += [((ratio - 1.0).abs() > CLIP_EPS).float().mean().item()]

                    mb_advantages = b_advantages[global_indices]
                    # Normalize advantages locally? Or global? Global is standard.
                    
                    # Policy Loss
                    pg_loss1 = -mb_advantages * ratio
                    pg_loss2 = -mb_advantages * torch.clamp(ratio, 1 - CLIP_EPS, 1 + CLIP_EPS)
                    pg_loss = torch.max(pg_loss1, pg_loss2).mean()
                    
                    # Value Loss
                    v_loss = 0.5 * ((newvalue - b_returns[global_indices]) ** 2).mean()
                    
                    # Entropy Loss
                    entropy_loss = entropy.mean()
                    
                    # Total Loss (weighted sum)
                    # We just sum them and backward per phase group? effectively summing gradients
                    loss = pg_loss - ENT_COEF * entropy_loss + VF_COEF * v_loss
                    loss.backward()

                nn.utils.clip_grad_norm_(policy.parameters(), MAX_GRAD_NORM)
                optimizer.step()

        # Logging
        mean_reward = b_returns.mean().item()
        sps = int(global_step / (time.time() - start_time))
        
        # Win Rates
        win_off = np.mean(ep_offense_wins) if ep_offense_wins else 0.0
        win_def = np.mean(ep_defense_wins) if ep_defense_wins else 0.0
        
        # Bid Distribution
        # Helper to label
        def label_bid(i):
            if i == 0: return "Pass"
            if i == 26: return "Misere"
            if i == 27: return "OpenMisere"
            val = i - 1
            strains = ['S', 'C', 'D', 'H', 'NT']
            if val < 0 or val >= 25: return "Unk"
            return f"{6 + val // 5}{strains[val % 5]}"
            
        bid_log = {f"bids/{label_bid(i)}": c for i, c in enumerate(bid_counts) if c > 0}
        
        print(f"Update {update}/{num_updates}: Reward={mean_reward:.3f}, SPS={sps}, OffWin={win_off:.2f}, DefWin={win_def:.2f}")
        
        # New: Print Top 3 Bids
        sorted_bids = sorted([(label_bid(i), c) for i, c in enumerate(bid_counts) if c > 0], key=lambda x: x[1], reverse=True)
        top_bids_str = ", ".join([f"{k}:{v}" for k, v in sorted_bids[:5]])
        print(f"Top Bids: {top_bids_str}")
        
        log_data = {
            "charts/learning_rate": optimizer.param_groups[0]["lr"],
            "losses/value_loss": v_loss.item(),
            "losses/policy_loss": pg_loss.item(),
            "losses/entropy": entropy_loss.item(),
            "losses/approx_kl": approx_kl.item(),
            "charts/SPS": sps,
            "charts/mean_reward": mean_reward,
            "charts/win_rate_offense": win_off,
            "charts/win_rate_defense": win_def,
            "global_step": global_step,
        }
        log_data.update(bid_log)
        wandb.log(log_data)
        
        # Checkpointing
        # Checkpointing
        if update % 50 == 0:
            os.makedirs("checkpoints", exist_ok=True)
            
            # Save Latest (Overwrite to save space)
            checkpoint = {
                'model_state_dict': policy.state_dict(),
                'optimizer_state_dict': optimizer.state_dict(),
                'global_step': global_step,
                'best_reward': best_reward
            }
            torch.save(checkpoint, "checkpoints/ppo_latest.pth")
            
            # Save League Checkpoint (Snapshot for Self-Play)
            # Save every 100 updates (~50k steps) to populate the league
            if update % 100 == 0:
                league_path = os.path.join(league_dir, f"step_{global_step}.pth")
                torch.save(checkpoint, league_path)
                print(f" -> Saved League Snapshot: {league_path}")
            
            # Save Best
            if mean_reward > best_reward:
                best_reward = mean_reward
                checkpoint['best_reward'] = best_reward
                torch.save(checkpoint, "checkpoints/ppo_best.pth")
                print(f" -> New Best Reward! Saved to ppo_best.pth")

    envs.close()
    wandb.finish()

if __name__ == "__main__":
    train()
