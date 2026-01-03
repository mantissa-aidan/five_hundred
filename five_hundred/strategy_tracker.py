from typing import Dict, Any, List
from .bid import Bid, BidType
import threading

class StrategyTracker:
    def __init__(self):
        self.lock = threading.Lock()
        self.milestones = {
            "tricks_won_total": 0,
            "contracts_won": 0,
            "contracts_made": 0,
            "slam_dunks": 0,
            "grand_slams": 0,
            "defensive_stops": 0,
            "bid_placed_count": 0,
            "pass_count": 0,
            "trump_played_when_losing": 0,
            "high_card_saved": 0,
            "optimal_wins": 0,
            "missed_wins": 0,
        }
        self.achievements = [
            {"id": "bid_1", "name": "First Words", "desc": "Place any bid that isn't a pass", "target": 1, "metric": "bid_placed_count"},
            {"id": "conservative_10", "name": "Risk Assessment", "desc": "Pass on weak hands 10 times", "target": 10, "metric": "pass_count"},
            {"id": "trump_aware_5", "name": "Trump Awareness", "desc": "Play trump when losing 5 times", "target": 5, "metric": "trump_played_when_losing"},
            {"id": "saver_10", "name": "Card Discipline", "desc": "Save high cards for later 10 times", "target": 10, "metric": "high_card_saved"},
            {"id": "maker_1", "name": "Contract Fulfilled", "desc": "Make your first contract", "target": 1, "metric": "contracts_made"},
            {"id": "bidder_10", "name": "Novice Bidder", "desc": "Win 10 Contracts", "target": 10, "metric": "contracts_won"},
            {"id": "maker_50", "name": "Contract Keeper", "desc": "Fulfill 50 Contracts", "target": 50, "metric": "contracts_made"},
            {"id": "slam_1", "name": "Grand Slam", "desc": "Win a 10-Trick Hand", "target": 1, "metric": "slam_dunks"},
        ]

    def record_play(self, player_name, chosen_card, playable_cards, current_trick, trump_suit, trick_number=0):
        """
        Analyze strategic decisions in card play.
        This is called JUST BEFORE the card is technically played to the table.
        """
        with self.lock:
            # We only care about Agent
            if "Agent" not in player_name:
                return

            # If agent is leading, different analysis
            if len(current_trick) == 0:
                # Check if agent is saving high cards (not leading with Aces/Kings early)
                from .card import Rank
                if trick_number <= 3 and chosen_card.rank in [Rank.ACE, Rank.KING]:
                    # Playing high card early - not saving
                    pass
                elif trick_number > 3 and chosen_card.rank in [Rank.ACE, Rank.KING]:
                    # Saving high cards for later tricks
                    self.milestones["high_card_saved"] += 1
                return
            
            # Determine current winner of the partial trick (before agent plays)
            from .heuristic import determine_trick_winner_index, get_card_play_value, get_effective_suit
            
            trick_cards = [c for p, c in current_trick]
            lead_suit = get_effective_suit(trick_cards[0], trump_suit)
            
            current_winner_idx = determine_trick_winner_index(trick_cards, trump_suit)
            current_winning_card = trick_cards[current_winner_idx]
            current_best_val = get_card_play_value(current_winning_card, lead_suit, trump_suit)
            
            # Check if chosen card beats the current best
            chosen_val = get_card_play_value(chosen_card, lead_suit, trump_suit)
            chosen_suit = get_effective_suit(chosen_card, trump_suit)
            
            agent_wins = chosen_val > current_best_val
            
            # Trump Awareness: Did agent play trump when losing in the led suit?
            if not agent_wins and chosen_suit == trump_suit and lead_suit != trump_suit:
                self.milestones["trump_played_when_losing"] += 1
            
            # Check if any OTHER card would have won
            could_have_won = False
            for card in playable_cards:
                if card == chosen_card: continue
                val = get_card_play_value(card, lead_suit, trump_suit)
                if val > current_best_val:
                    could_have_won = True
                    break
            
            if agent_wins:
                self.milestones["optimal_wins"] = self.milestones.get("optimal_wins", 0) + 1
            else:
                if could_have_won:
                    self.milestones["missed_wins"] = self.milestones.get("missed_wins", 0) + 1

    def record_game_end(self, winning_team_name, contract: Bid, made: bool, tricks_won: int):
        with self.lock:
            is_agent_team = "Agent" in winning_team_name
            
            if is_agent_team:
                # If Agent team WON the game logic (usually means positive score change?)
                # Wait, winning_team_name comes from score comparison.
                pass

            # We need specific event data. 
            # Ideally this is called when a Round ends.
            pass

    def record_bid(self, player_name, bid: Bid):
        with self.lock:
            if "Agent" in player_name:
                self.milestones["bid_placed_count"] += 1
    
    def record_pass(self, player_name):
        with self.lock:
            if "Agent" in player_name:
                self.milestones["pass_count"] += 1

    def record_round_end(self, contract: Bid, made_contract: bool, tricks_won: int, declarer_name: str, agent_name="Agent"):
        """Called at end of round."""
        with self.lock:
            # Check if Agent was Declarer (or Partner)
            # Simplification: If declarer name contains "Agent"
            is_agent = "Agent" in declarer_name
            
            if is_agent:
                self.milestones["contracts_won"] += 1
                if made_contract:
                    self.milestones["contracts_made"] += 1
                
                if tricks_won == 10:
                    self.milestones["slam_dunks"] += 1
                    if contract.bid_type == BidType.NO_TRUMP:
                        self.milestones["grand_slams"] += 1
                        
            else:
                # Opponent was declarer
                if not made_contract:
                    # We stopped them!
                    self.milestones["defensive_stops"] += 1

    def get_stats(self):
        with self.lock:
            # Calculate achievement progress
            unlocked = []
            progress = []
            
            for ach in self.achievements:
                current = self.milestones.get(ach["metric"], 0)
                target = ach["target"]
                pct = min(100, int((current / target) * 100))
                completed = current >= target
                
                item = {
                    "id": ach["id"],
                    "name": ach["name"],
                    "desc": ach["desc"],
                    "current": current,
                    "target": target,
                    "percent": pct,
                    "completed": completed
                }
                if completed:
                    unlocked.append(item)
                else:
                    progress.append(item)
                    
            return {
                "milestones": self.milestones,
                "achievements": {
                    "unlocked": unlocked,
                    "in_progress": progress
                }
            }

# Global Instance
TRACKER = StrategyTracker()

def record_round(contract, made, tricks, declarer):
    TRACKER.record_round_end(contract, made, tricks, declarer)

def get_strategy_stats():
    return TRACKER.get_stats()

def record_play(player_name, chosen_card, playable_cards, current_trick, trump_suit, trick_number=0):
    TRACKER.record_play(player_name, chosen_card, playable_cards, current_trick, trump_suit, trick_number)

def record_bid(player_name, bid):
    TRACKER.record_bid(player_name, bid)

def record_pass(player_name):
    TRACKER.record_pass(player_name)
