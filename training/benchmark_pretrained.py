"""
Benchmark pretrained agent against RulesBot opponents.
Tracks detailed game statistics beyond simple win rate.
"""

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from five_hundred.game import Game
from five_hundred.agent import PyTorchAgent
from five_hundred.direct_rl_player import DirectRLPlayer
from five_hundred.bot_player import BotPlayer

def benchmark_agent(model_path, num_games=100):
    """
    Benchmark pretrained agent with detailed statistics.
    
    Returns:
        dict with metrics: win_rate, avg_score, contract_stats, etc.
    """
    print("=" * 60)
    print("BENCHMARKING PRETRAINED AGENT")
    print("=" * 60)
    print(f"Model: {model_path}")
    print(f"Games: {num_games}")
    print(f"Opponents: RulesBot")
    print()
    
    # Load agent
    agent = PyTorchAgent(state_dim=466)
    agent.load(model_path)
    agent.epsilon = 0.0  # Greedy policy only
    print(f"✅ Loaded pretrained model (ε=0.0)")
    
    # Statistics tracking
    stats = {
        'games_played': 0,
        'games_won': 0,
        'total_score': 0,
        
        # Contract stats (when agent won bid)
        'bids_won': 0,
        'contracts_made': 0,  # Made contract when agent bid
        'contracts_failed': 0,  # Failed contract when agent bid
        'rounds_won_with_contract': 0,
        
        # Defense stats (when opponent won bid)
        'bids_lost': 0,
        'rounds_won_on_defense': 0,
        
        # Bid distribution
        'bid_distribution': {},
        
        # Score distribution
        'scores': []
    }
    
    print("\nPlaying games...")
    for game_num in range(num_games):
        # Setup game
        player_names = ["Agent", "Opp1", "Opp2", "Opp3"]
        team_names = ["Team Agent", "Team Bots"]
        
        # Create game with bots for players 1-3
        bot_config = {1: "medium", 2: "medium", 3: "medium"}  # Players 1, 2, 3 are bots
        
        game = Game(
            player_names=player_names,
            team_names=team_names,
            bot_config=bot_config,
            verbose=False
        )
        
        # Create agent player
        agent_player = DirectRLPlayer(
            name=player_names[0],
            agent_instance=agent,
            seat_idx=0,
            is_training=False
        )
        agent_player.game_ref = game
        
        # Replace player 0 with agent, others are already BotPlayers
        game.players[0] = agent_player
        
        # Play game
        game.start_new_round()
        
        # Collect stats
        stats['games_played'] += 1
        
        my_team = game.teams[0]
        opp_team = game.teams[1]
        
        my_score = my_team.team_score
        opp_score = opp_team.team_score
        stats['total_score'] += my_score
        stats['scores'].append(my_score)
        
        # Did agent win?
        agent_won = my_score > opp_score
        if agent_won:
            stats['games_won'] += 1
        
        # Who won the bid?
        if game.winning_bid:
            bidder = game.winning_bid.player
            bid_tricks = game.winning_bid.tricks
            bid_suit = game.winning_bid.suit.name if game.winning_bid.suit else "NO_TRUMP"
            
            agent_won_bid = bidder.name == "Agent"
            
            if agent_won_bid:
                stats['bids_won'] += 1
                
                # Track bid distribution
                bid_key = f"{bid_tricks}T-{bid_suit}"
                stats['bid_distribution'][bid_key] = stats['bid_distribution'].get(bid_key, 0) + 1
                
                # Did agent make their contract?
                tricks_won = sum(p.tricks_won_this_round for p in my_team.players)
                contract_made = tricks_won >= bid_tricks
                
                if contract_made:
                    stats['contracts_made'] += 1
                    if agent_won:
                        stats['rounds_won_with_contract'] += 1
                else:
                    stats['contracts_failed'] += 1
            else:
                # Opponent won bid
                stats['bids_lost'] += 1
                if agent_won:
                    stats['rounds_won_on_defense'] += 1
        
        # Progress
        if (game_num + 1) % 20 == 0:
            win_pct = 100.0 * stats['games_won'] / stats['games_played']
            print(f"  {game_num + 1}/{num_games} games - WR: {win_pct:.1f}%")
    
    # Calculate final metrics
    stats['win_rate'] = 100.0 * stats['games_won'] / stats['games_played']
    stats['avg_score'] = stats['total_score'] / stats['games_played']
    
    if stats['bids_won'] > 0:
        stats['contract_success_rate'] = 100.0 * stats['contracts_made'] / stats['bids_won']
    else:
        stats['contract_success_rate'] = 0.0
    
    if stats['bids_lost'] > 0:
        stats['defense_win_rate'] = 100.0 * stats['rounds_won_on_defense'] / stats['bids_lost']
    else:
        stats['defense_win_rate'] = 0.0
    
    return stats

def print_results(stats):
    """Pretty print benchmark results"""
    print("\n" + "=" * 60)
    print("BENCHMARK RESULTS")
    print("=" * 60)
    
    print(f"\n📊 OVERALL PERFORMANCE")
    print(f"  Games Played:    {stats['games_played']}")
    print(f"  Games Won:       {stats['games_won']} ({stats['win_rate']:.1f}%)")
    print(f"  Average Score:   {stats['avg_score']:.0f} points")
    
    print(f"\n🎯 BIDDING & CONTRACTS")
    print(f"  Bids Won:        {stats['bids_won']}")
    print(f"  Contracts Made:  {stats['contracts_made']} / {stats['bids_won']} ({stats['contract_success_rate']:.1f}%)")
    print(f"  Contracts Failed: {stats['contracts_failed']}")
    print(f"  Rounds Won (Contract): {stats['rounds_won_with_contract']} / {stats['bids_won']}")
    
    print(f"\n🛡️ DEFENSE (When Opponent Bids)")
    print(f"  Opponent Bids:   {stats['bids_lost']}")
    print(f"  Rounds Won (Defense): {stats['rounds_won_on_defense']} / {stats['bids_lost']} ({stats['defense_win_rate']:.1f}%)")
    
    print(f"\n📈 BID DISTRIBUTION (Top 5)")
    sorted_bids = sorted(stats['bid_distribution'].items(), key=lambda x: x[1], reverse=True)
    for bid, count in sorted_bids[:5]:
        pct = 100.0 * count / stats['bids_won'] if stats['bids_won'] > 0 else 0
        print(f"  {bid:15s}: {count:3d} ({pct:5.1f}%)")
    
    print(f"\n📉 SCORE STATISTICS")
    scores = stats['scores']
    print(f"  Min Score:  {min(scores):5.0f}")
    print(f"  Max Score:  {max(scores):5.0f}")
    print(f"  Median:     {sorted(scores)[len(scores)//2]:5.0f}")
    
    print("\n" + "=" * 60)
    
    # Interpretation
    print("\n💡 INTERPRETATION")
    if stats['win_rate'] >= 60:
        print("  ✅ Excellent performance! Ready for RL fine-tuning.")
    elif stats['win_rate'] >= 50:
        print("  ✅ Good baseline. RL should improve to 70%+.")
    elif stats['win_rate'] >= 40:
        print("  ⚠️  Moderate baseline. Consider longer pretraining.")
    else:
        print("  ❌ Poor performance. Check state representation.")
    
    if stats['contract_success_rate'] >= 70:
        print("  ✅ Strong bidding - making most contracts.")
    elif stats['contract_success_rate'] >= 50:
        print("  ⚠️  Moderate bidding - some overbidding.")
    else:
        print("  ❌ Weak bidding - significant overbidding issues.")
    
    print("=" * 60)

if __name__ == "__main__":
    model_path = "pre_training/rules_bot/pretrained_agent.pth"
    
    if not os.path.exists(model_path):
        print(f"❌ Model not found: {model_path}")
        print("Run: python training/pretrain_agent.py first")
        sys.exit(1)
    
    stats = benchmark_agent(model_path, num_games=100)
    print_results(stats)
