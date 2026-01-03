"""
Pretrain agent networks using behavioral cloning from RulesBot expert data.
This script:
1. Loads 15k games of RulesBot self-play
2. Converts states to 466-dim format (with void features)
3. Trains both BID and PLAY networks via supervised learning
4. Saves pretrained model for RL fine-tuning

Expected result: ~50% win rate baseline before RL training
"""

import sys
import os
import torch
import torch.nn as nn
import torch.nn.functional as F
from torch.utils.data import Dataset, DataLoader
import pickle
import numpy as np
from tqdm import tqdm

# Add parent directory to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from five_hundred.agent import PyTorchAgent
from five_hundred.utils_rl import get_state_vector

class ExpertDataset(Dataset):
    """Dataset of expert (RulesBot) state-action pairs"""
    
    def __init__(self, data_path, phase_filter=None, max_samples=None):
        """
        Args:
            data_path: Path to .pkl file containing list of dicts
            phase_filter: 'BID', 'PLAY', or None for all phases
            max_samples: Maximum number of samples to load (None = all)
        """
        print(f"Loading data from {data_path}...")
        print(f"  Phase filter: {phase_filter}")
        print(f"  Max samples: {max_samples if max_samples else 'unlimited'}")
        
        # Load data with streaming (memory efficient)
        with open(data_path, 'rb') as f:
            raw_data = pickle.load(f)
        
        print(f"Loaded {len(raw_data)} total transitions from file")
        
        # Filter by phase if specified
        if phase_filter:
            raw_data = [d for d in raw_data if d.get('phase') == phase_filter]
            print(f"After filtering for {phase_filter}: {len(raw_data)} transitions")
        
        # Limit samples if specified
        if max_samples and len(raw_data) > max_samples:
            # Take evenly distributed samples across the dataset
            step = len(raw_data) // max_samples
            raw_data = raw_data[::step][:max_samples]
            print(f"Sampled down to {len(raw_data)} transitions")
        
        self.states = []
        self.actions = []
        self.phases = []
        
        print("Converting states to 466-dim format (with void features)...")
        for entry in tqdm(raw_data):
            # entry should have: 'state' (dict or numpy array), 'action' (int), 'phase' (str)
            state_data = entry['state']
            action_idx = entry['action']
            phase = entry['phase']
            
            # Handle different state formats
            if isinstance(state_data, np.ndarray):
                # Already a numpy array (old format, likely 600-dim)
                # Pad with zeros to reach 466 dims if needed
                if len(state_data) < 466:
                    state_vec = np.zeros(466, dtype=np.float32)
                    state_vec[:len(state_data)] = state_data
                elif len(state_data) > 466:
                    # Truncate if too long
                    state_vec = state_data[:466].astype(np.float32)
                else:
                    state_vec = state_data.astype(np.float32)
               
                # Note: void features won't be accurate for old data
                # This is a quick fix - ideally we'd regenerate from raw game states
            elif isinstance(state_data, dict):
                # Dict format - convert using proper observation function
                state_vec = get_state_vector(state_data)
            else:
                print(f"Warning: Unknown state format: {type(state_data)}, skipping...")
                continue
            
            self.states.append(state_vec)
            self.actions.append(action_idx)
            self.phases.append(phase)
        
        self.states = np.array(self.states, dtype=np.float32)
        self.actions = np.array(self.actions, dtype=np.int64)
        
        print(f"✅ Dataset ready: {len(self.states)} examples")
        if phase_filter == 'BID':
            print(f"   Memory usage: ~{len(self.states) * 466 * 4 / 1024 / 1024:.1f} MB")
            print(f"   Note: Void features may not be accurate (using old dataset format)")
    
    def __len__(self):
        return len(self.states)
    
    def __getitem__(self, idx):
        return (
            torch.FloatTensor(self.states[idx]),
            torch.LongTensor([self.actions[idx]])[0],
            self.phases[idx]
        )

def pretrain_network(network, dataloader, optimizer, device, network_name="Network"):
    """Train a single network via behavioral cloning"""
    network.train()
    total_loss = 0.0
    correct = 0
    total = 0
    
    for states, actions, _ in tqdm(dataloader, desc=f"Training {network_name}"):
        states = states.to(device)
        actions = actions.to(device)
        
        # Forward pass
        outputs = network(states)
        
        # Cross-entropy loss (supervised learning)
        loss = F.cross_entropy(outputs, actions)
        
        # Backward pass
        optimizer.zero_grad()
        loss.backward()
        optimizer.step()
        
        # Statistics
        total_loss += loss.item()
        _, predicted = torch.max(outputs, 1)
        correct += (predicted == actions).sum().item()
        total += actions.size(0)
    
    avg_loss = total_loss / len(dataloader)
    accuracy = 100.0 * correct / total
    
    return avg_loss, accuracy

def main():
    print("=" * 60)
    print("BEHAVIORAL CLONING PRETRAINING")
    print("=" * 60)
    
    # Config
    data_path = "pre_training/rules_bot/rules_bot_data_15k.pkl"
    save_path = "pre_training/rules_bot/pretrained_agent.pth"
    batch_size = 256
    epochs = 20
    lr = 1e-3
    
    # Memory management: limit samples to fit in RAM
    # 2000 samples * 466 dims * 4 bytes ≈ 3.7 MB per dataset
    max_bid_samples = 2000   # Adjust based on available RAM
    max_play_samples = 5000  # Play actions are more common
    
    device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
    print(f"\nUsing device: {device}")
    print(f"Memory limits: {max_bid_samples} bid samples, {max_play_samples} play samples")
    
    # Initialize agent
    print("\nInitializing agent...")
    agent = PyTorchAgent(state_dim=466, buffer_size=1000)
    
    # Load datasets
    print("\n" + "=" * 60)
    print("LOADING BID DATASET")
    print("=" * 60)
    bid_dataset = ExpertDataset(data_path, phase_filter='BID', max_samples=max_bid_samples)
    bid_loader = DataLoader(bid_dataset, batch_size=batch_size, shuffle=True, num_workers=0)
    
    print("\n" + "=" * 60)
    print("LOADING PLAY DATASET")
    print("=" * 60)
    play_dataset = ExpertDataset(data_path, phase_filter='PLAY', max_samples=max_play_samples)
    play_loader = DataLoader(play_dataset, batch_size=batch_size, shuffle=True, num_workers=0)
    
    # Optimizers
    bid_optimizer = torch.optim.Adam(agent.bid_net.parameters(), lr=lr)
    play_optimizer = torch.optim.Adam(agent.play_net.parameters(), lr=lr)
    
    # Train BID network
    print("\n" + "=" * 60)
    print("TRAINING BID NETWORK")
    print("=" * 60)
    
    best_bid_accuracy = 0.0
    for epoch in range(epochs):
        loss, accuracy = pretrain_network(
            agent.bid_net, bid_loader, bid_optimizer, device, "Bid Net"
        )
        print(f"Epoch {epoch+1}/{epochs}: Loss={loss:.4f}, Accuracy={accuracy:.2f}%")
        
        if accuracy > best_bid_accuracy:
            best_bid_accuracy = accuracy
            print(f"  ✅ New best bid accuracy!")
    
    # Train PLAY network
    print("\n" + "=" * 60)
    print("TRAINING PLAY NETWORK")
    print("=" * 60)
    
    best_play_accuracy = 0.0
    for epoch in range(epochs):
        loss, accuracy = pretrain_network(
            agent.play_net, play_loader, play_optimizer, device, "Play Net"
        )
        print(f"Epoch {epoch+1}/{epochs}: Loss={loss:.4f}, Accuracy={accuracy:.2f}%")
        
        if accuracy > best_play_accuracy:
            best_play_accuracy = accuracy
            print(f"  ✅ New best play accuracy!")
    
    # Save pretrained model
    print("\n" + "=" * 60)
    print("SAVING PRETRAINED MODEL")
    print("=" * 60)
    
    agent.save(save_path)
    print(f"✅ Pretrained model saved to: {save_path}")
    
    # Summary
    print("\n" + "=" * 60)
    print("PRETRAINING COMPLETE")
    print("=" * 60)
    print(f"Best Bid Accuracy:  {best_bid_accuracy:.2f}%")
    print(f"Best Play Accuracy: {best_play_accuracy:.2f}%")
    print(f"\nNext steps:")
    print(f"1. Load this model in training/train_agent.py")
    print(f"2. Fine-tune with RL (low epsilon, conservative exploration)")
    print(f"3. Expected initial win rate: ~50% against RulesBot")
    print("=" * 60)

if __name__ == "__main__":
    main()
