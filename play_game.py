
from five_hundred.game import Game
from five_hundred.web_human_player import WebHumanPlayer, set_cmd_queue
from five_hundred.inference_player import InferencePlayer
from five_hundred.play_game_server import start_arena_server, set_game_state
from five_hundred.env import FiveHundredEnv # For static helpers if needed? Or just logging.
import threading
import time
import glob
import re
import os
from five_hundred.history_recorder import recorder

VERBOSE = True

def log_wrapper(msg):
    if VERBOSE:
        print(f"[GAME] {msg}")
    
    # Update UI Logs
    # We need to fetch current logs, append, and set state
    # Ideally passing a log handler to Game is better.
    pass

def main():
    print("Welcome to THE ARENA!")
    
    # 1. Start Server
    print("Starting Arena Server...")
    action_queue = start_arena_server(None)
    set_cmd_queue(action_queue) # Link Server Queue to Player Class
    
    # 2. Find Checkpoint
    # 2. Find Checkpoint
    search_paths = [".", "five_hundred/static", "local_checkpoints"]
    checkpoints = []
    for p in search_paths:
        checkpoints.extend(glob.glob(os.path.join(p, "model_checkpoint_*.pth")))
        
    if not checkpoints:
        print(f"ERROR: No checkpoints found in {search_paths}! Train some agents first.")
        return

    def extract_ep(filename):
        match = re.search(r"model_checkpoint_(\d+).pth", filename)
        return int(match.group(1)) if match else 0
        
    latest_checkpoint = max(checkpoints, key=extract_ep)
    print(f"Loading champion model: {latest_checkpoint}")
    
    # 3. Create Players
    # P0: You
    human = WebHumanPlayer("Human Leader")
    
    # P1, P2, P3: Agents
    agent1 = InferencePlayer("Agent 1 (Enemy)", latest_checkpoint)
    agent2 = InferencePlayer("Agent 2 (Partner)", latest_checkpoint)
    agent3 = InferencePlayer("Agent 3 (Enemy)", latest_checkpoint)
    
    # 4. Setup Game
    # We can't use standard Game constructor easily because it creates players internally?
    # Game.__init__ takes player_names and creates classes.
    # We need to inject our instances.
    # Game class isn't designed for injection. We must subclass or monkey-patch.
    # Or just instantiate Game and overwrite players list immediately.
    
    # Hook to pause between tricks
    waiting_for_next_trick = False
    
    def on_trick_complete():
        nonlocal waiting_for_next_trick
        print("[GAME] Trick Complete. Waiting for user to continue...")
        waiting_for_next_trick = True
        
        # We need to block here until 'next_trick' is received.
        # This blocks the Game Loop thread.
        while True:
            # We must not consume BID or PLAY actions here, but those shouldn't be valid now anyway.
            # But we might receive chat? Ignore for now except 'next_trick'
            try:
                # Use a specific mechanic or reuse queue?
                # Using action_queue directly.
                # Warning: If user sends other commands (like premature plays), they will be dropped!
                # For now assumes "Next" is the only valid interaction.
                cmd = action_queue.get(timeout=0.1)
                if cmd.get('action') == 'next_trick':
                    print("[GAME] Advancing to next trick.")
                    break
            except Exception: # Empty queue
                time.sleep(0.1)
        
        waiting_for_next_trick = False

    game = Game(["P0", "P1", "P2", "P3"], ["Your Team", "Enemy Team"], bot_config={}, trick_complete_hook=on_trick_complete)
    
    # Overwrite
    game.players[0] = human
    game.players[1] = agent1
    game.players[2] = agent2
    game.players[3] = agent3
    
    game.teams[0].players = [human, agent2]
    game.teams[1].players = [agent1, agent3]
    
    # Log Hook
    def custom_log(msg):
        print(msg)
        # TODO: Push to Game State 'logs' list
        # We need a thread-safe way to append logs to GAME_STATE in server
    
    game._log = custom_log
    
    # 5. Game Loop
    print("Starting Game Loop...")
    # 5. Start State Pusher (Background Thread)
    def state_pusher():
        while True:
            # Construct UI state
            
            # Check phase
            # Game doesn't store 'phase' explicitly as string 'BID'/'PLAY'.
            # We infer from internal vars.
            phase = "BID"
            if game.winning_bid is not None:
                if not game.kitty and len(game.players[0].hand) > 10: 
                     phase = "KITTY"
                else:
                     phase = "PLAY"
            
            contract_goal = 0
            contract_team_idx = -1
            if game.winning_bid:
                contract_goal = game.winning_bid.tricks
                # Find team index
                contract_player = game.winning_bid.player
                for idx, team in enumerate(game.teams):
                    if contract_player in team.players:
                        contract_team_idx = idx
                        break

            ui_state = {
                "phase": phase,
                "trump": str(game.trump_suit) if game.trump_suit else None,
                "contract": str(game.winning_bid) if game.winning_bid else None,
                "contract_goal": contract_goal,
                "contract_team_idx": contract_team_idx,
                "highest_bid": str(game.highest_bid_this_round) if game.highest_bid_this_round else None,
                "bid_history": [str(b) for b in game.bids_this_round],
                "finished_tricks": game.finished_tricks,
                # Serialize hands simply
                "hands": [[{"rank": c.rank.name, "suit": c.suit.name} for c in p.hand] for p in game.players],
                "scores": [t.team_score for t in game.teams],
                "trick": [{"player": game.players.index(p), "card": {"rank": c.rank.name, "suit": c.suit.name}} for p, c in game.current_trick_cards] if hasattr(game, 'current_trick_cards') else [],
                "active_player": game.active_player_index,
                "dealer": game.current_dealer_idx,
                "waiting_for_next": waiting_for_next_trick,
                "tricks_won": [p.tricks_won_this_round for p in game.players]
            }
            
            set_game_state(ui_state)
            
            # --- History Recording Integration ---
            # We want to catch when an action happened and log the transition.
            # This is simpler if we hook into the Player methods directly.
            # Let's see if we can instrument them here.
            
            time.sleep(0.5)

    # --- Instrumentation for History ---
    def instrument_player(player, game_obj):
        original_bid = player.decide_bid
        original_play = player.decide_play_card
        
        def bid_wrapper(*args, **kwargs):
            # Capture state BEFORE
            state_before = {
                "phase": "BID",
                "hand": player.hand[:],
                "scores": [t.team_score for t in game_obj.teams],
                "bids": [str(b) for b in game_obj.bids_this_round]
            }
            res = original_bid(*args, **kwargs)
            # Log
            recorder.record(state_before, res, 0, {"phase": "BID_POST"}, False)
            return res
            
        def play_wrapper(*args, **kwargs):
             state_before = {
                "phase": "PLAY",
                "hand": player.hand[:],
                "scores": [t.team_score for t in game_obj.teams],
                "trump": str(game_obj.trump_suit),
                "trick": [str(c) for _, c in game_obj.current_trick_cards]
            }
             res = original_play(*args, **kwargs)
             recorder.record(state_before, res, 0, {"phase": "PLAY_POST"}, False)
             return res
             
        player.decide_bid = bid_wrapper
        player.decide_play_card = play_wrapper

    # Instrument all players
    for p in [human, agent1, agent2, agent3]:
        instrument_player(p, game)

    t_state = threading.Thread(target=state_pusher, daemon=True)
    t_state.start()

    # 6. Game Loop
    print("Starting Game Loop...")
    while True:
        # Run Round
        if game.game_over:
            print("Game Over! Restarting...")
            game.game_over = False
            # Hard Reset Scores
            game.teams[0].team_score = 0
            game.teams[1].team_score = 0
            
        game.start_new_round()

if __name__ == "__main__":
    main()
