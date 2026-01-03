"""
Training script with Weights & Biases integration for experiment tracking.
Replaces custom dashboard with professional ML logging.
"""
import sys
import os
sys.path.append(os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

import time
import glob
import re
import random
import numpy as np
import wandb

from five_hundred.game import Game
from five_hundred.agent import PyTorchAgent
from five_hundred.direct_rl_player import DirectRLPlayer
import torch
import pickle
from collections import defaultdict

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
        if len(self.pool) > self.pool_size:
            self.pool.pop(0)
        
        self.save_league()
        print(f"Added Episode {episode} to League pool. Pool size: {len(self.pool)}")
    
    def load_league(self):
        if os.path.exists(self.league_file):
            try:
                with open(self.league_file, "rb") as f:
                    self.pool = pickle.load(f)
                print(f"Loaded League pool with {len(self.pool)} snapshots.")
            except Exception as e:
                print(f"Could not load league pool: {e}")
    
    def save_league(self):
        with open(self.league_file, "wb") as f:
            pickle.dump(self.pool, f)

def train():
    save_dir = "checkpoints"
    os.makedirs(save_dir, exist_ok=True)
    start_episode = 0
    
    print("Initializing W&B Trainer...")
    
    # Initialize Weights & Biases
    run = wandb.init(
        project="five-hundred-rl",
        name=f"training-{time.strftime('%Y%m%d-%H%M%S')}",
        config={
            "state_dim": 466,
            "buffer_size": 50000,
            "gamma": 0.99,
            "lr": 1e-4,
            "update_target_every": 1000,
            "pretrained": "rules_bot",
            "reward_shaping": "contract_bonus_0.5",
            "hybrid_learning": "mc_bidding_td_playing"
        }
    )
    
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
    pretrained_path = "pre_training/rules_bot/pretrained_agent.pth"
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

    episode_count = start_episode
    
    # Tracking metrics
    contract_wins = 0
    contract_total = 0
    defense_wins = 0
    defense_total = 0
    recent_results = []  # Last 50 for moving average
    bid_histogram = defaultdict(int)
    
    # Main Training Loop
    while episode_count < 100000:
        episode_count += 1
        
        # Create fresh game and RL player each episode
        p0 = DirectRLPlayer("Agent", agent, 0, is_training=True)
        game = Game(['Agent', 'Opp1', 'Opp2', 'Opp3'], ['T1', 'T2'], bot_config={1:'medium', 2:'medium', 3:'medium'}, verbose=False)
        p0.game_ref = game
        game.players[0] = p0
        game.teams[0].players[0] = p0
        
        # Execute full game
        while not game.game_over:
            game.start_new_round()
        
        # Extract results
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
        
        # Training step
        total_loss = 0
        if episode_count % 1 == 0:
            # Low bidding LR (1e-5) prevents rapid forgetting
            freeze_bidding = False
            
            # Single replay batch per episode for faster training
            l = agent.replay(batch_size=64, freeze_bidding=freeze_bidding)
            if l: total_loss += l
        
        # Track metrics
        if agent_won_bid:
            contract_total += 1
            if agent_won:
                contract_wins += 1
        else:
            defense_total += 1
            if agent_won:
                defense_wins += 1
        
        recent_results.append(1 if agent_won else 0)
        if len(recent_results) > 50:
            recent_results.pop(0)
        
        # Extract bid info
        bid_info = "No Bid"
        bidder_name = "None"
        if game.winning_bid:
            bid_tricks = game.winning_bid.tricks
            bidder_name = game.winning_bid.player.name
            suit_name = game.winning_bid.suit.name if game.winning_bid.suit else ("Misere" if game.winning_bid.bid_type.name == "MISERE" else "OpenMisere")
            bid_str = f"{bid_tricks}-{suit_name}"
            bid_info = f"{bid_tricks}T-{suit_name}"
            
            if "Agent" in bidder_name:
                bid_histogram[bid_str] += 1
        
        # Log to W&B
        metrics = {
            "episode": episode_count,
            "loss": total_loss if total_loss else 0,
            "reward": float(game.teams[0].team_score),
            "epsilon": agent.epsilon,
            "agent_won": int(agent_won),
            "moving_avg_wr": (sum(recent_results) / len(recent_results) * 100) if recent_results else 0,
        }
        
        # Contract/Defense split
        if contract_total > 0:
            metrics["contract_wr"] = contract_wins / contract_total * 100
            metrics["contract_games"] = contract_total
        if defense_total > 0:
            metrics["defense_wr"] = defense_wins / defense_total * 100
            metrics["defense_games"] = defense_total
        
        wandb.log(metrics)
        
        # Periodic logging
        if episode_count % 500 == 0:
            print(f"Ep {episode_count}: Score={game.teams[0].team_score}, Bid={bid_info} by {bidder_name}, AgentWon={agent_won}, Eps={agent.epsilon:.3f}")
            
            # Log bid histogram as table
            if bid_histogram:
                wandb.log({"bid_distribution": wandb.Table(
                    columns=["bid", "count"],
                    data=[[k, v] for k, v in sorted(bid_histogram.items())]
                )})
        
        # Evaluation every 200 episodes
        if episode_count % 200 == 0:
            league.add_to_league(episode_count, agent)
            
            # Benchmark against league
            print(f"--- Benchmarking Ep {episode_count} ---")
            wins = 0
            for _ in range(20):
                eval_game = Game(['Agent', 'B1', 'B2', 'B3'], ['T1', 'T2'], bot_config={1:'medium', 2:'medium', 3:'medium'}, verbose=False)
                eval_p0 = DirectRLPlayer("Agent", agent, 0, is_training=False)
                eval_p0.game_ref = eval_game
                eval_game.players[0] = eval_p0
                eval_game.teams[0].players[0] = eval_p0
                
                while not eval_game.game_over:
                    eval_game.start_new_round()
                
                if eval_game.teams[0].team_score > eval_game.teams[1].team_score:
                    wins += 1
            
            eval_wr = wins / 20 * 100
            print(f"Eval Win Rate: {eval_wr}%")
            wandb.log({"eval_wr": eval_wr, "episode": episode_count})
        
        # Save checkpoint every 1000 episodes
        if episode_count % 1000 == 0:
            checkpoint_path = os.path.join(save_dir, f"model_checkpoint_{episode_count}.pth")
            agent.save(checkpoint_path)
            print(f"Saved checkpoint to {checkpoint_path}")
        
        # Epsilon decay
        if episode_count % 100 == 0:
            agent.epsilon = max(0.05, agent.epsilon * 0.995)
    
    wandb.finish()
    return agent

if __name__ == "__main__":
    train()
