import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import time
import glob
import re
import argparse
import random
import numpy as np

from five_hundred.game import Game
from five_hundred.agent import PyTorchAgent
from five_hundred.direct_rl_player import DirectRLPlayer
from five_hundred.server import record_loss, record_reward, record_eval_result, record_bid, record_game_result, record_history_snapshot, increment_steps, set_initial_episode_count, start_server_thread
import torch
import pickle

class LeagueManager:
    def __init__(self, save_dir, pool_size=10):
        self.save_dir = save_dir
        self.pool_size = pool_size
        self.league_file = os.path.join(save_dir, "league_pool.pkl")
        self.pool = [] # List of (episode, bid_state, play_state)
        self.load_league()

    def add_to_league(self, episode, agent):
        # Deep copy the state dicts
        bid_state = {k: v.cpu().clone() for k, v in agent.bid_net.state_dict().items()}
        play_state = {k: v.cpu().clone() for k, v in agent.play_net.state_dict().items()}
        
        self.pool.append((episode, bid_state, play_state))
        
        # Keep only the N best/random? For now, just most recent
        if len(self.pool) > self.pool_size:
            self.pool.pop(0)
            
        self.save_league()
        print(f"Added Episode {episode} to League pool. Pool size: {len(self.pool)}")

    def sample_weights(self):
        if not self.pool:
            return None, None
        return random.choice(self.pool)[1:] # Return (bid_state, play_state)

    def save_league(self):
        try:
            with open(self.league_file, 'wb') as f:
                pickle.dump(self.pool, f)
        except Exception as e:
            print(f"Failed to save league: {e}")

    def load_league(self):
        if os.path.exists(self.league_file):
            try:
                with open(self.league_file, 'rb') as f:
                    self.pool = pickle.load(f)
                print(f"Loaded League pool with {len(self.pool)} snapshots.")
            except Exception as e:
                print(f"Failed to load league: {e}")

def train():
    parser = argparse.ArgumentParser(description='Train the Five Hundred Agent (Sync Mode)')
    parser.add_argument('--save-dir', type=str, default='.', help='Directory to save checkpoints to')
    args = parser.parse_args()
    
    save_dir = args.save_dir
    os.makedirs(save_dir, exist_ok=True)

    print("Initializing Synchronous Trainer...")
    start_server_thread()
    
    # Wait for server to be ready
    import socket
    print("Waiting for dashboard server to start on port 8000...")
    server_ready = False
    for i in range(10):
        try:
            with socket.create_connection(("127.0.0.1", 8000), timeout=1):
                server_ready = True
                print("Dashboard Server Ready! access at http://localhost:8000")
                break
        except (ConnectionRefusedError, socket.timeout):
            time.sleep(1)
            print(".", end="", flush=True)
            
    if not server_ready:
        print("\nWARNING: Dashboard server did not respond on port 8000. Training will continue but dashboard may be unavailable.")
    
    # 1. Main Agent
    agent = PyTorchAgent(state_dim=466, action_dim=100)
    
    # 2. League Manager
    league = LeagueManager(save_dir)
    
    # 3. Opponent Agents (3 separate for diversity) - Phase 3: 466 dims
    opponents = [PyTorchAgent(state_dim=466, action_dim=100) for _ in range(3)]
    for opp in opponents:
        opp.epsilon = 0.05 # Low noise for opponents
    
    # Auto-Resume Logic
    checkpoints = glob.glob(os.path.join(save_dir, "model_checkpoint_*.pth"))
    start_episode = 0
    
    # 1. Load pretrained model (Phase 3: correct path + higher epsilon)
    pretrained_path = "pre_training/rules_bot/pretrained_agent.pth"  # Fixed path
    if os.path.exists(pretrained_path):
        print(f"Loading pretrained model from {pretrained_path}...")
        agent.load(pretrained_path)
        # Phase 3: Higher epsilon (0.3) for exploration from good baseline
        agent.epsilon = 0.3
        print(f"Set epsilon to {agent.epsilon} (Phase 3 fine-tuning)")
        print(f"Expected baseline: ~70% WR, will improve bidding aggression")
    elif checkpoints:
        def extract_ep(filename):
            match = re.search(r"model_checkpoint_(\d+).pth", filename)
            return int(match.group(1)) if match else 0
            
        latest_checkpoint = max(checkpoints, key=extract_ep)
        start_episode = extract_ep(latest_checkpoint)
        
        print(f"Resuming from {latest_checkpoint} (Ep {start_episode})")
        agent.load(latest_checkpoint)
    else:
        print("Starting fresh training (no pre-trained model found).")

    set_initial_episode_count(start_episode)
    episode_count = start_episode
    
    # Bid histogram tracking (for monitoring MC returns effect)
    from collections import defaultdict
    bid_histogram = defaultdict(int)  # {bid_tricks: count}
    last_histogram_episode = 0
    
    while True:
        episode_count += 1
        
        # 2. Setup Game with RulesBot opponents (NO SELF-PLAY)
        player_names = ["Agent", "Opp1", "Opp2", "Opp3"]
        team_names = ["Team Agent", "Team Opponents"]
        # Use RulesBot for all opponents (seats 1, 2, 3)
        game = Game(player_names, team_names, bot_config={1: "Rules", 2: "Rules", 3: "Rules"}, verbose=False)
        
        # Inject RL Agent at seat 0
        p0 = DirectRLPlayer("Agent", agent, 0, is_training=True, bid_epsilon=None)
        p0.game_ref = game
        game.players[0] = p0
        game.teams[0].players[0] = p0
        
        # 3. Play Game to completion
        while not game.game_over:
            game.start_new_round()
            
        # 4. Finalize & Reward (with bid shaping)
        agent_won = (game.teams[0].team_score > game.teams[1].team_score)
        
        # Extract bid information for reward shaping
        agent_won_bid = False
        bid_tricks = 0
        contract_made = False
        
        if game.winning_bid and "Agent" in game.winning_bid.player.name:
            agent_won_bid = True
            bid_tricks = game.winning_bid.tricks
            # Contract is made if score >= 0 (simplified check)
            contract_made = (game.teams[0].team_score >= 0)
        
        p0.finalize_training_game(
            win=agent_won,
            game_score=game.teams[0].team_score,
            agent_won_bid=agent_won_bid,
            bid_tricks=bid_tricks,
            contract_made=contract_made
        )
        
        # 5. Training (only when epsilon is low enough to have meaningful data)
        total_loss = 0
        if agent.epsilon < 0.8:  # Don't learn from purely random play
            # NO CURRICULUM: Train both networks simultaneously
            # Low bidding LR (1e-5) prevents rapid forgetting
            freeze_bidding = False
            
            # Single replay batch per episode for faster training
            l = agent.replay(batch_size=64, freeze_bidding=freeze_bidding)
            if l: total_loss += l
        
        # 6. Stats & Logs
        record_loss(total_loss if total_loss else 0)
        record_reward(float(game.teams[0].team_score))
        increment_steps()
        
        # Phase 4: Enhanced metrics
        record_game_result(won=agent_won, agent_bid=agent_won_bid)
        
        # Extract bid info for logging
        bid_info = "No Bid"
        bid_tricks = 0
        bidder_name = "None"
        if game.winning_bid:
            bid_tricks = game.winning_bid.tricks
            bidder_name = game.winning_bid.player.name
            # Format: "7-Spades", "8-NT", "Misere"
            suit_name = game.winning_bid.suit.name if game.winning_bid.suit else ("Misere" if game.winning_bid.bid_type.name == "MISERE" else "OpenMisere")
            bid_str = f"{bid_tricks}-{suit_name}"
            
            bid_info = f"{bid_tricks}T-{suit_name}"

            # Track agent's bids for histogram
            if "Agent" in bidder_name:
                record_bid(bid_str, is_agent=True)  # Send full string to dashboard
        
        if episode_count % 500 == 0:
            print(f"Ep {episode_count}: Score={game.teams[0].team_score}, Bid={bid_info} by {bidder_name}, AgentWon={agent_won}, Eps={agent.epsilon:.3f}")
            
        # Record history snapshot every 50 episodes
        if episode_count % 50 == 0:
             record_history_snapshot(episode_count)
        


        
        # 7. Housekeeping
        agent.update_target_network()
        agent.decay_epsilon()
        
        # 8. Checkpoint & Evaluation & Curriculum Progression
        if episode_count % 200 == 0:
            save_path = os.path.join(save_dir, f"model_checkpoint_{episode_count}.pth")
            agent.save(save_path)
            
            # Add to League Pool
            league.add_to_league(episode_count, agent)
            
            # Evaluate vs Easy Bots
            print(f"--- Benchmarking Ep {episode_count} ---")
            wr = evaluate_agent(agent, episode_count)
            record_eval_result(episode_count, wr)

def evaluate_agent(agent, episode_num, num_games=20):
    """Benchmarks agent against default BotPlayers (Easy)."""
    original_eps = agent.epsilon
    agent.epsilon = 0.0
    
    wins = 0
    for i in range(num_games):
        # Explicit bot config for opponents
        bot_cfg = {1: "Easy", 2: "Easy", 3: "Easy"}
        game = Game(["Agent", "B1", "B2", "B3"], ["T1", "T2"], bot_config=bot_cfg, verbose=False)
        p0 = DirectRLPlayer("Agent", agent, 0, is_training=False)
        p0.game_ref = game
        
        # Game already initialized with easy bots for seats 1, 2, 3
        game.players[0] = p0
        game.teams[0].players[0] = p0
        
        while not game.game_over:
            game.start_new_round()
            
        if game.teams[0].team_score > game.teams[1].team_score:
            wins += 1
            
    wr = (wins / num_games) * 100
    print(f"Eval Win Rate: {wr:.1f}%")
    agent.epsilon = original_eps
    return wr

if __name__ == "__main__":
    train()
