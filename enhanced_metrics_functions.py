# Add these functions to server.py after record_bid function

def record_game_result(won, agent_bid):
    """
    Track game results split by contract vs defense
    won: bool - did agent win the round
    agent_bid: bool - did agent win the bidding
    """
    global CONTRACT_WINS, CONTRACT_TOTAL, DEFENSE_WINS, DEFENSE_TOTAL, RECENT_GAME_RESULTS
    
    with STATE_LOCK:
        if agent_bid:
            CONTRACT_TOTAL += 1
            if won:
                CONTRACT_WINS += 1
        else:
            DEFENSE_TOTAL += 1
            if won:
                DEFENSE_WINS += 1
        
        # Track last 50 results for moving average
        RECENT_GAME_RESULTS.append(1 if won else 0)
        if len(RECENT_GAME_RESULTS) > 50:
            RECENT_GAME_RESULTS.pop(0)

def get_enhanced_stats():
    """Get contract/defense stats and moving average"""
    with STATE_LOCK:
        contract_wr = (CONTRACT_WINS / CONTRACT_TOTAL * 100) if CONTRACT_TOTAL > 0 else 0
        defense_wr = (DEFENSE_WINS / DEFENSE_TOTAL * 100) if DEFENSE_TOTAL > 0 else 0
        moving_avg = (sum(RECENT_GAME_RESULTS) / len(RECENT_GAME_RESULTS) * 100) if RECENT_GAME_RESULTS else 0
        
        return {
            'contract_wr': round(contract_wr, 1),
            'contract_games': CONTRACT_TOTAL,
            'defense_wr': round(defense_wr, 1),
            'defense_games': DEFENSE_TOTAL,
            'moving_avg_50': round(moving_avg, 1),
            'recent_count': len(RECENT_GAME_RESULTS)
        }
