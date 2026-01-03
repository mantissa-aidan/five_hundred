"""
Benchmark pretrained agent - using exact same setup as training script.
Metrics: avg score, contract wins, defense wins.
"""
import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

from five_hundred.game import Game
from five_hundred.agent import PyTorchAgent
from five_hundred.direct_rl_player import DirectRLPlayer

def main():
    print("=" * 60)
    print("PRETRAINED AGENT BENCHMARK")
    print("=" * 60)
    
    # Load pretrained model
    model_path = "pre_training/rules_bot/pretrained_agent.pth"
    agent = PyTorchAgent(state_dim=466)
    agent.load(model_path)
    agent.epsilon = 0.0  # Greedy only
    print(f"✅ Loaded: {model_path}")
    print(f"   Epsilon: {agent.epsilon}")
    
    # Stats
    games = 100
    total_score = 0
    games_won = 0
    
    # Detailed stats
    rounds_agent_bid = 0
    rounds_agent_bid_won = 0
    rounds_opp_bid = 0
    rounds_opp_bid_won = 0
    
    print(f"\n🎮 Playing {games} games vs RulesBot...")
    
    for i in range(games):
        # Create RL player (use is_training=True to match training script)
        p0 = DirectRLPlayer('Agent', agent, 0, is_training=True)
        
        # Create game (same as training script)
        game = Game(
            ['Agent', 'Bot1', 'Bot2', 'Bot3'],
            ['Team1', 'Team2'],
            bot_config={1: 'medium', 2: 'medium', 3: 'medium'},
            verbose=False
        )
        
        # Inject Agent (same as training script - set BOTH references)
        p0.game_ref = game
        game.players[0] = p0
        game.teams[0].players[0] = p0  # CRITICAL: Also update team reference
        
        # Play to completion (training script uses while loop)
        while not game.game_over:
            game.start_new_round()
        
        # Collect stats
        my_score = game.teams[0].team_score
        opp_score = game.teams[1].team_score
        
        total_score += my_score
        if my_score > opp_score:
            games_won += 1
        
        # Check who won bid
        if game.winning_bid:
            bidder_name = game.winning_bid.player.name
            agent_bid = (bidder_name == 'Agent')
            round_won = (my_score > opp_score)
            
            if agent_bid:
                rounds_agent_bid += 1
                if round_won:
                    rounds_agent_bid_won += 1
            else:
                rounds_opp_bid += 1
                if round_won:
                    rounds_opp_bid_won += 1
        
        # Progress
        if (i + 1) % 20 == 0:
            wr = 100.0 * games_won / (i + 1)
            print(f"  {i+1}/{games} - Win Rate: {wr:.1f}%")
    
    # Results
    print("\n" + "=" * 60)
    print("RESULTS")
    print("=" * 60)
    
    avg_score = total_score / games
    win_rate = 100.0 * games_won / games
    
    print(f"\n📊 OVERALL")
    print(f"  Win Rate:     {games_won}/{games} ({win_rate:.1f}%)")
    print(f"  Average Score: {avg_score:.0f} points")
    
    print(f"\n🎯 WHEN AGENT WON BID (Contract)")
    if rounds_agent_bid > 0:
        contract_wr = 100.0 * rounds_agent_bid_won / rounds_agent_bid
        print(f"  Times Agent Bid:  {rounds_agent_bid}")
        print(f"  Rounds Won:       {rounds_agent_bid_won}/{rounds_agent_bid} ({contract_wr:.1f}%)")
    else:
        print(f"  Agent never won bid!")
    
    print(f"\n🛡️  WHEN OPPONENT WON BID (Defense)")
    if rounds_opp_bid > 0:
        defense_wr = 100.0 * rounds_opp_bid_won / rounds_opp_bid
        print(f"  Times Opp Bid:    {rounds_opp_bid}")
        print(f"  Rounds Won:       {rounds_opp_bid_won}/{rounds_opp_bid} ({defense_wr:.1f}%)")
    else:
        print(f"  Opponents never won bid!")
    
    print("\n" + "=" * 60)
    
    # Interpretation
    print("\n💡 INTERPRETATION")
    if win_rate >= 50:
        print(f"  ✅ Strong baseline ({win_rate:.0f}% WR) - ready for RL fine-tuning")
    else:
        print(f"  ⚠️  Moderate baseline ({win_rate:.0f}% WR) - RL should improve")
    
    if rounds_agent_bid > 0:
        contract_wr = 100.0 * rounds_agent_bid_won / rounds_agent_bid
        if contract_wr >= 60:
            print(f"  ✅ Good contract play ({contract_wr:.0f}% win when bidding)")
        else:
            print(f"  ⚠️  Needs work on contracts ({contract_wr:.0f}% win when bidding)")
    
    print("=" * 60)

if __name__ == "__main__":
    main()
