from typing import List
from .player import Player # Assuming Player class is in player.py

class Team:
    def __init__(self, name: str, players: List[Player]):
        if not players or len(players) > 2: # Standard 500 has 2 players per team
            # For variations (e.g. 6-handed), this might change
            raise ValueError("Team must consist of 1 or 2 players for standard 500.")
        
        self.name: str = name
        self.players: List[Player] = players
        self.team_score: int = 0
        self.has_bid_this_round: bool = False # Tracks if the team holds the current bid

    def update_score(self, points: int):
        """Updates the team's score."""
        self.team_score += points
        # Also update individual player scores if that's how we want to track it.
        # For now, team score is primary for game win/loss conditions.
        # Individual scores on Player objects can still track personal game history.

    def get_total_tricks_won_this_round(self) -> int:
        """Calculates the total tricks won by all players in the team for the current round."""
        return sum(player.tricks_won_this_round for player in self.players)

    def reset_for_new_round(self):
        """Resets round-specific information for the team and its players."""
        self.has_bid_this_round = False
        for player in self.players:
            player.reset_for_new_round() # This clears hand and player's tricks_won_this_round

    def __repr__(self):
        player_names = ", ".join(player.name for player in self.players)
        return f"Team({self.name}, Players: [{player_names}], Score: {self.team_score})"

    def __str__(self):
        return f"{self.name} (Score: {self.team_score})"

    # Consider adding methods if a team makes a bid, e.g.:
    # def set_bid(self, bid_details):
    #     self.has_bid_this_round = True
    #     self.current_bid = bid_details 