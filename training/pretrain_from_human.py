"""
Pre-train the bidding network using behavioral cloning from human gameplay data.
"""
import json
import glob
import numpy as np
import torch
import torch.nn.functional as F
from five_hundred.agent import PyTorchAgent
from five_hundred.card import Suit, Rank, Card
import re

def parse_card(card_dict):
    """Convert card dict to Card object."""
    suit = Suit[card_dict['suit']]
    rank = Rank[card_dict['rank']]
    return Card(suit, rank)

def parse_bid_action(action_str):
    """
    Parse bid action string like "('bid', (6, <Suit.SPADES: 3>, <BidType.SUIT_TRUMP: 'Suit Trump'>))"
    Returns bid action index (0-27).
    """
    if "'pass'" in action_str:
        return 0  # Pass is action 0
    
    # Extract trick count and suit
    match = re.search(r"\((\d+),\s*<Suit\.(\w+):", action_str)
    if not match:
        return 0  # Default to pass if can't parse
    
    tricks = int(match.group(1))
    suit_name = match.group(2)
    
    # Map to action index
    # Encoding: Pass=0, then 6T-10T across 5 suits (Spades, Clubs, Diamonds, Hearts, NT)
    # Indices: 0=Pass, 1-5=6T (S,C,D,H,NT), 6-10=7T, 11-15=8T, 16-20=9T, 21-25=10T
    
    suit_order = {'SPADES': 0, 'CLUBS': 1, 'DIAMONDS': 2, 'HEARTS': 3, 'NO_TRUMP': 4}
    suit_idx = suit_order.get(suit_name, 0)
    
    # Calculate action index
    trick_offset = (tricks - 6) * 5  # 6T starts at index 1
    action_idx = 1 + trick_offset + suit_idx
    
    return action_idx

def convert_to_observation(state_dict):
    """
    Convert arena state dict to agent observation vector (600-dim).
    This is a simplified version - you may need to match your exact observation format.
    """
    obs = np.zeros(600, dtype=np.float32)
    
    # Hand encoding (first 53 elements for card presence)
    hand = state_dict.get('hand', [])
    for card_dict in hand:
        card = parse_card(card_dict)
        # Simple encoding: suit * 13 + rank
        suit_offset = {'SPADES': 0, 'CLUBS': 13, 'DIAMONDS': 26, 'HEARTS': 39, 'NO_TRUMP': 52}
        rank_offset = {'FOUR': 0, 'FIVE': 1, 'SIX': 2, 'SEVEN': 3, 'EIGHT': 4, 'NINE': 5,
                      'TEN': 6, 'JACK': 7, 'QUEEN': 8, 'KING': 9, 'ACE': 10, 'JOKER': 0}
        
        suit_key = card_dict['suit']
        rank_key = card_dict['rank']
        
        if suit_key in suit_offset and rank_key in rank_offset:
            idx = suit_offset[suit_key] + rank_offset[rank_key]
            if idx < 53:
                obs[idx] = 1.0
    
    # Bid history encoding (simplified - just count bids)
    bids = state_dict.get('bids', [])
    if len(bids) > 0:
        obs[100] = len(bids)  # Number of bids so far
    
    return obs

def load_arena_data(directory="arena_history"):
    """Load all human bidding decisions from arena JSONL files."""
    states = []
    actions = []
    
    files = glob.glob(f"{directory}/*.jsonl")
    print(f"Loading data from {len(files)} files...")
    
    for filepath in files:
        with open(filepath, 'r') as f:
            for line in f:
                try:
                    data = json.loads(line)
                    
                    # Only extract bidding actions
                    if data['state'].get('phase') == 'BID':
                        state = convert_to_observation(data['state'])
                        action = parse_bid_action(data['action'])
                        
                        states.append(state)
                        actions.append(action)
                except Exception as e:
                    # Skip malformed lines
                    continue
    
    print(f"Loaded {len(states)} bidding examples")
    return np.array(states), np.array(actions)

def pretrain_bidding_network(agent, states, actions, epochs=100, batch_size=32):
    """Pre-train the bidding network using supervised learning."""
    print(f"\\nPre-training bidding network for {epochs} epochs...")
    
    n_samples = len(states)
    
    for epoch in range(epochs):
        # Shuffle data
        indices = np.random.permutation(n_samples)
        total_loss = 0.0
        n_batches = 0
        
        for i in range(0, n_samples, batch_size):
            batch_indices = indices[i:i+batch_size]
            batch_states = torch.FloatTensor(states[batch_indices]).to(agent.device)
            batch_actions = torch.LongTensor(actions[batch_indices]).to(agent.device)
            
            # Forward pass
            q_values = agent.bid_net(batch_states)
            
            # Cross-entropy loss (treat as classification)
            loss = F.cross_entropy(q_values, batch_actions)
            
            # Backward pass
            agent.bid_optimizer.zero_grad()
            loss.backward()
            agent.bid_optimizer.step()
            
            total_loss += loss.item()
            n_batches += 1
        
        avg_loss = total_loss / n_batches
        
        if (epoch + 1) % 10 == 0:
            print(f"Epoch {epoch+1}/{epochs}, Loss: {avg_loss:.4f}")
    
    print("\\nPre-training complete!")

def main():
    # Initialize agent
    print("Initializing agent...")
    agent = PyTorchAgent(state_dim=600, action_dim=100)
    
    # Load human gameplay data
    states, actions = load_arena_data()
    
    if len(states) == 0:
        print("ERROR: No training data found!")
        return
    
    # Analyze bid distribution
    unique, counts = np.unique(actions, return_counts=True)
    print(f"\\nBid distribution in human data:")
    for action_idx, count in zip(unique, counts):
        print(f"  Action {action_idx}: {count} times ({100*count/len(actions):.1f}%)")
    
    # Pre-train
    pretrain_bidding_network(agent, states, actions, epochs=100)
    
    # Save pre-trained weights
    save_path = "model_pretrained.pth"
    agent.save(save_path)
    print(f"\\nSaved pre-trained model to {save_path}")
    
    # Test: sample some predictions
    print(f"\\nTesting predictions on first 5 examples:")
    agent.epsilon = 0.0  # Disable exploration for testing
    for i in range(min(5, len(states))):
        state = states[i]
        true_action = actions[i]
        
        # Get prediction
        with torch.no_grad():
            q_values = agent.bid_net(torch.FloatTensor(state).unsqueeze(0).to(agent.device))
            pred_action = torch.argmax(q_values).item()
        
        match = "✓" if pred_action == true_action else "✗"
        print(f"  Example {i+1}: True={true_action}, Pred={pred_action} {match}")

if __name__ == "__main__":
    main()
