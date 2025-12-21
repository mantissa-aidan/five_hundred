import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import random
from collections import deque

class BiddingNetwork(nn.Module):
    def __init__(self, input_dim, output_dim):
        super(BiddingNetwork, self).__init__()
        self.fc1 = nn.Linear(input_dim, 512)
        self.fc2 = nn.Linear(512, 512)
        self.fc3 = nn.Linear(512, output_dim)
        self.relu = nn.ReLU()
        
    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.relu(self.fc2(x))
        return self.fc3(x)

class PlayingNetwork(nn.Module):
    def __init__(self, input_dim, output_dim):
        super(PlayingNetwork, self).__init__()
        self.fc1 = nn.Linear(input_dim, 512)
        self.fc2 = nn.Linear(512, 512)
        self.fc3 = nn.Linear(512, output_dim)
        self.relu = nn.ReLU()
        
    def forward(self, x):
        x = self.relu(self.fc1(x))
        x = self.relu(self.fc2(x))
        return self.fc3(x)

class PyTorchAgent:
    def __init__(self, state_dim=600, action_dim=100, lr=1e-4, gamma=0.99, buffer_size=50000):
        self.state_dim = state_dim
        self.action_dim = action_dim
        self.gamma = gamma
        self.device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
        # Ensure MPS on Mac if available (PyTorch > 1.12)
        if torch.backends.mps.is_available():
             self.device = torch.device("mps")

        print(f"Agent initialized on device: {self.device}")

        # --- Architecture: Split Brains ---
        # Bidding Space: 0-27 (28 actions)
        # Playing Space: 0-52 (53 actions) - but we map output to 0..52
        
        # Bidding Brain
        self.bid_net = BiddingNetwork(state_dim, 28).to(self.device)
        self.target_bid_net = BiddingNetwork(state_dim, 28).to(self.device)
        self.target_bid_net.load_state_dict(self.bid_net.state_dict())
        
        # Playing Brain
        self.play_net = PlayingNetwork(state_dim, 53).to(self.device)
        self.target_play_net = PlayingNetwork(state_dim, 53).to(self.device)
        self.target_play_net.load_state_dict(self.play_net.state_dict())
        
        # Optimizers (Adam!)
        self.bid_optimizer = optim.Adam(self.bid_net.parameters(), lr=lr)
        self.play_optimizer = optim.Adam(self.play_net.parameters(), lr=lr)
        
        self.criterion = nn.MSELoss() # Or HuberLoss
        
        # Memory
        self.memory = deque(maxlen=buffer_size)
        
        # Epsilon
        self.epsilon = 1.0
        self.epsilon_min = 0.05 # Lower floor for meaningful play
        self.epsilon_decay = 0.995

    def act(self, state, phase, valid_mask=None):
        """
        Returns action_idx (int).
        Uses Bidding Net if phase='BID'/'KITTY'.
        Uses Playing Net if phase='PLAY'.
        """
        if np.random.rand() <= self.epsilon:
            # Random valid action
            if valid_mask is not None:
                valid_indices = np.where(valid_mask == 1)[0]
                if len(valid_indices) > 0:
                    return np.random.choice(valid_indices)
            return random.randrange(self.action_dim)

        state_tensor = torch.FloatTensor(state).unsqueeze(0).to(self.device)
        
        if phase == 'BID' or phase == 'KITTY': # Treat KITTY as BID for now or generic
            # Bidding Logic (Actions 0-27)
            with torch.no_grad():
                q_values = self.bid_net(state_tensor).squeeze(0) # [28]
            
            # Masking
            # valid_mask is size 100. extract first 28
            mask_subset = torch.FloatTensor(valid_mask[:28]).to(self.device)
            # Set invalid to -inf
            q_values[mask_subset == 0] = -float('inf')
            
            action_idx = torch.argmax(q_values).item()
            return action_idx # 0-27 works directly
            
        elif phase == 'PLAY':
            # Playing Logic (Actions 0-52 representing Cards)
            # Wait, global action space is 100?
            # 0-52 are card IDs.
            # My 'PlayingNetwork' outputs 53 dims.
            # Does action 0 mean Card 0? Yes.
            
            with torch.no_grad():
                q_values = self.play_net(state_tensor).squeeze(0) # [53]
                
            # Masking
            # Play actions are 0-52 in new Env logic?
            # Env._decode_action handles 0..52 as card IDs for PLAY phase.
            mask_subset = torch.FloatTensor(valid_mask[:53]).to(self.device)
            q_values[mask_subset == 0] = -float('inf')
            
            action_idx = torch.argmax(q_values).item()
            return action_idx
            
        else:
            return 0 # Fallback

    def remember(self, state, action, reward, next_state, done, info):
        # We need 'phase' to know which net to train. 
        # But 'info' might contain it, or we infer from action idx?
        # Actually, store phase explicitly or derive?
        # Env provides phase in obs. 
        # simpler: agent stores it.
        # But `train_agent.py` only passes these args. 
        # I'll update remember signature in train_agent.py OR infer.
        # Inference: Bidding actions < 28? No, play actions overlap (0-52).
        # We MUST know phase.
        # Let's extract phase from 'state'?
        # In current state vector, index 0, 1 are phase.
        # idx 0 = BID/KITTY, idx 1 = PLAY.
        
        is_bid = (state[0] == 1)
        phase_code = 'BID' if is_bid else 'PLAY'
        
        self.memory.append((state, action, reward, next_state, done, phase_code))

    def replay(self, batch_size=64):
        if len(self.memory) < batch_size:
            return 0
            
        minibatch = random.sample(self.memory, batch_size)
        
        # We need to process BID and PLAY stats separately or just loop?
        # Looping is slow. Vectorization is better.
        # Split batch
        bid_batch = [e for e in minibatch if e[5] == 'BID']
        play_batch = [e for e in minibatch if e[5] == 'PLAY']
        
        total_loss = 0
        
        if bid_batch:
            total_loss += self.train_network(bid_batch, self.bid_net, self.target_bid_net, self.bid_optimizer, 28)
            
        if play_batch:
            total_loss += self.train_network(play_batch, self.play_net, self.target_play_net, self.play_optimizer, 53)
            
        return total_loss

    def decay_epsilon(self):
        if self.epsilon > self.epsilon_min:
            self.epsilon *= self.epsilon_decay

    def train_network(self, batch, policy_net, target_net, optimizer, output_dim):
        states = torch.FloatTensor(np.array([x[0] for x in batch])).to(self.device)
        actions = torch.LongTensor(np.array([x[1] for x in batch])).to(self.device)
        rewards = torch.FloatTensor(np.array([x[2] for x in batch])).to(self.device)
        next_states = torch.FloatTensor(np.array([x[3] for x in batch])).to(self.device)
        dones = torch.FloatTensor(np.array([x[4] for x in batch])).to(self.device) # 1 if done, 0 else
        
        # Current Q
        # actions are 1D indices.
        # policy_net(states) -> [batch, output_dim]
        # gather -> [batch]
        
        # Valid action range check? 
        # If playing, actions are 0..52. If bidding, 0..27.
        # actions tensor should match output_dim range roughly.
        
        curr_q = policy_net(states).gather(1, actions.unsqueeze(1)).squeeze(1)
        
        # Next Q
        with torch.no_grad():
            next_q_vals = target_net(next_states)
            max_next_q = next_q_vals.max(1)[0]
            target_q = rewards + (self.gamma * max_next_q * (1 - dones))
            
            # Clip targets logic from Exp 3
            target_q = torch.clamp(target_q, -20, 20)
            
        loss = self.criterion(curr_q, target_q)
        
        optimizer.zero_grad()
        loss.backward()
        # Gradient clipping
        torch.nn.utils.clip_grad_norm_(policy_net.parameters(), 1.0)
        optimizer.step()
        
        return loss.item()

    def update_target_network(self):
        self.target_bid_net.load_state_dict(self.bid_net.state_dict())
        self.target_play_net.load_state_dict(self.play_net.state_dict())
        
    def save(self, name):
        torch.save({
            'bid': self.bid_net.state_dict(),
            'play': self.play_net.state_dict()
        }, name)
        
    def load(self, name):
        checkpoint = torch.load(name, map_location=self.device)
        self.bid_net.load_state_dict(checkpoint['bid'])
        self.play_net.load_state_dict(checkpoint['play'])
        self.target_bid_net.load_state_dict(checkpoint['bid'])
        self.target_play_net.load_state_dict(checkpoint['play'])
