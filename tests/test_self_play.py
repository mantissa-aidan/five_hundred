import pytest
from five_hundred.env import FiveHundredEnv
from five_hundred.agent import PyTorchAgent
import torch

class TestSelfPlay:
    def test_env_accepts_opponents(self):
        """Verify we can inject 3 opponents and run a reset cycle."""
        opponents = [PyTorchAgent(state_dim=600, action_dim=100) for _ in range(3)]
        
        env = FiveHundredEnv(verbose=False, start_server=False) # No server thread for test if possible?
        # start_server defaults to true in init, but we can ignore it.
        
        env.opponent_agents = opponents
        
        # Reset starts the game thread
        state, info = env.reset()
        
        assert state is not None
        assert len(state) == 600
        
        # We need to verify that players 1, 2, 3 are DirectRLPlayer
        # But env.game is created in the thread... race condition for test?
        # reset() blocks until first obs is received. By then, game is running.
        
        time.sleep(0.5) # Wait for thread setup just in case
        assert len(env.game.players) == 4
        from five_hundred.direct_rl_player import DirectRLPlayer
        assert isinstance(env.game.players[1], DirectRLPlayer)
        assert isinstance(env.game.players[2], DirectRLPlayer)
        assert isinstance(env.game.players[3], DirectRLPlayer)
        
        # Cleanup
        # Since logic isn't clean for killing threads, we just leave it.
        
    def test_full_round_self_play(self):
        """Run a full game with 4 dumb agents to see if it hangs."""
        opponents = [PyTorchAgent(state_dim=600, action_dim=100) for _ in range(3)]
        # Make them dumb (epsilon=1.0) so they play valid random moves?
        # PyTorchAgent handles masking in act().
        
        env = FiveHundredEnv(verbose=False, start_server=False)
        env.opponent_agents = opponents
        
        state, info = env.reset()
        
        # Play 100 steps or until done
        done = False
        steps = 0
        while not done and steps < 200:
             # Random action for main agent
             # We just need integer
             action = 0 
             # Masking... using agent logic is safest
             # main agent
             main_agent = PyTorchAgent(state_dim=600, action_dim=100)
             mask = info.get('mask')
             action = main_agent.act(state, env.last_phase, mask)
             
             state, reward, done, info = env.step(action)
             steps += 1
             
        # If we reached done or 200 steps without error/hanging, pass.
        # A full game is long, but a round is ~10 tricks * 4 cards + bidding
        # 1 game could be multiple rounds. 200 steps is enough to prove flow.
        assert steps > 0

import time
