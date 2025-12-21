# Five Hundred Card Game

A Python implementation of the card game Five Hundred.

## Description

Five Hundred is a trick-taking card game that is an extension of Euchre with some ideas from Bridge. For four players, it uses a standard 43-card deck (which includes a Joker, sometimes called the Bird). Players play in two partnerships. The game involves bidding, declaring a trump suit (or No Trump/Misère), playing tricks, and scoring points based on the contract.

Detailed rules can be found on [Wikipedia](https://en.wikipedia.org/wiki/500_(card_game)).

## Features

*   **Core Game Logic:**
    *   Standard 43-card deck (4s through Aces in four suits, plus a Joker).
    *   Player and Team management.
    *   Card dealing according to 500 rules (including a 3-card kitty).
*   **Bidding:**
    *   Supports standard suit bids, No Trump, Misère, and Open Misère.
    *   Calculates bid points and seniority.
    *   Automated auction process to determine the winning bid.
    *   Kitty exchange mechanism for the winning bidder.
*   **Gameplay:**
    *   Trick-taking mechanics.
    *   Enforcement of following suit.
    *   Correct handling of trump suit, including Right Bower, Left Bower, and Joker.
    *   No Trump gameplay rules.
    *   Determination of trick winners based on card strength.
*   **Scoring:**
    *   Awards points for making or failing contracts (including slam bonuses for 10 tricks on low bids).
    *   Handles scoring for Misère and Open Misère bids.
    *   Tracks team scores and determines game end conditions (±500 points).
*   **Testing:**
    *   Comprehensive unit tests for all major components and game logic scenarios.

## Setup/Installation

To install the Five Hundred game engine package, you can use pip:

```bash
pip install five-hundred-card-game-engine  # Replace with the actual name on PyPI if different
```

Alternatively, if you want to contribute to development or run tests from the source:

1.  Clone the repository:
    ```bash
    git clone https://github.com/yourusername/five_hundred.git # Replace with your actual repo URL
    cd five_hundred
    ```
2.  (Optional) Create and activate a virtual environment:
    ```bash
    python3 -m venv venv
    source venv/bin/activate 
    ```
3.  Install dependencies for testing:
    ```bash
    pip install pytest
    ```

## Running the Game

Currently, the game is implemented as a set of classes and does not have a fully interactive command-line interface or GUI for gameplay. You can interact with the game logic programmatically.

The `five_hundred/game.py` file contains an example of how to initialize and start a game:

```python
# Example from the bottom of five_hundred/game.py
if __name__ == '__main__':
    player_names = ["Alice", "Bob", "Charlie", "David"]
    team_names = ["Team A/C", "Team B/D"]
    game = Game(player_names, team_names)
    
    # To start a round (deals cards, runs bidding, plays tricks, scores):
    game.start_new_round() 
    
    # You can then inspect the game state:
    print(f"Game Over: {game.game_over}")
    for team in game.teams:
        print(f"{team.name} Score: {team.team_score}")
    # etc.
```

To run this example:
```bash
python -m five_hundred.game
```
This will simulate one round of play with the current automated bidding and play logic.

## Running Tests

To run the unit tests, navigate to the project's root directory and run:
```bash
python -m pytest
```

## Project Structure

*   `five_hundred/`
    *   `bid.py`: Contains the `Bid` class and related enums/constants.
    *   `card.py`: Defines `Card`, `Suit`, and `Rank`.
    *   `deck.py`: Implements the `Deck` class.
    *   `game.py`: The main `Game` class orchestrating game flow, bidding, play, and scoring.
    *   `player.py`: The `Player` class.
    *   `team.py`: The `Team` class.
*   `tests/`: Contains unit tests for the game components.
    *   `test_bid.py`
    *   `test_card.py`
    *   `test_deck.py`
    *   `test_game.py`
    *   `test_player.py`
    *   `test_team.py`
*   `README.md`: This file.
*   `TODO.md`: Tracks project progress. 