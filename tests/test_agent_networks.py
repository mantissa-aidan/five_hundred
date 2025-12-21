import pytest
import torch
import numpy as np
from five_hundred.agent import PyTorchAgent, BiddingNetwork, PlayingNetwork

def test_networks_init():
    """Verify networks initialize with correct dimensions."""
    agent = PyTorchAgent(state_dim=600, action_dim=100)
    
    assert isinstance(agent.bid_net, BiddingNetwork)
    assert isinstance(agent.play_net, PlayingNetwork)
    
    # Check output layers
    # bid_net output should be 28
    assert agent.bid_net.fc3.out_features == 28
    # play_net output should be 53
    assert agent.play_net.fc3.out_features == 53

def test_forward_pass_bid():
    """Verify Bidding Network forward pass."""
    batch_size = 4
    state_dim = 600
    
    net = BiddingNetwork(state_dim, 28)
    dummy_input = torch.randn(batch_size, state_dim)
    
    output = net(dummy_input)
    assert output.shape == (batch_size, 28)
    
def test_forward_pass_play():
    """Verify Playing Network forward pass."""
    # input 600, output 53
    net = PlayingNetwork(600, 53)
    dummy_input = torch.randn(1, 600)
    output = net(dummy_input)
    assert output.shape == (1, 53)

def test_agent_act_bid():
    """Verify agent acts correctly in BID phase."""
    agent = PyTorchAgent(state_dim=600)
    agent.epsilon = 0.0 # Force greedy to test network usage
    
    state = np.zeros(600, dtype=np.float32)
    state[0] = 1 # Mark as BID phase explicitly if needed by logic, but act calls net directly based on param phase
    
    # Mask: 100 dim. Only indices 0-27 valid for bid.
    mask = np.zeros(100)
    mask[0] = 1 # Valid Pass
    mask[15] = 1 # Valid Bid
    
    action = agent.act(state, 'BID', valid_mask=mask)
    
    assert 0 <= action <= 27

def test_agent_act_play():
    """Verify agent acts correctly in PLAY phase."""
    agent = PyTorchAgent(state_dim=600)
    agent.epsilon = 0.0
    
    state = np.zeros(600, dtype=np.float32)
    # Mask
    mask = np.zeros(100)
    # Valid card: 11
    mask[11] = 1
    
    action = agent.act(state, 'PLAY', valid_mask=mask)
    
    # Logic might map 0-52. 
    assert 0 <= action <= 52 
    # With epsilon 0, it should pick the only valid one (11) if network hasn't initialized -inf?
    # Actually network is random init. 
    # But act() masks invalid logits to -inf.
    # So it MUST pick 11.
    assert action == 11

def test_learning_step():
    """Verify replay/train step doesn't crash."""
    agent = PyTorchAgent(state_dim=600, buffer_size=100)
    
    # Add some experiences
    state = np.zeros(600, dtype=np.float32)
    next_state = np.zeros(600, dtype=np.float32)
    state[0] = 1 # Bid phase
    
    # BID Experience
    agent.remember(state, action=5, reward=1.0, next_state=next_state, done=False, info={})
    
    # PLAY Experience
    state_play = np.zeros(600, dtype=np.float32)
    state_play[1] = 1 # Play phase
    agent.remember(state_play, action=10, reward=0.5, next_state=next_state, done=False, info={})
    
    # We need enough samples > batch_size to trigger training?
    # PyTorchAgent: replay(batch_size=64).
    # Force smaller batch for test.
    loss = agent.replay(batch_size=2)
    
    assert loss is not None, "Loss should be returned (float) or 0"
