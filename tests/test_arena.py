
import unittest
from unittest.mock import MagicMock, patch
from five_hundred.game import Game
from five_hundred.web_human_player import WebHumanPlayer
from five_hundred.inference_player import InferencePlayer
from five_hundred.card import Card, Suit, Rank
from five_hundred.bid import Bid, BidType

class TestArenaIntegration(unittest.TestCase):
    def setUp(self):
        self.human = WebHumanPlayer("Human")
        # Mock InferencePlayer to avoid loading model which is slow and requires file
        self.bot1 = MagicMock(spec=InferencePlayer)
        self.bot1.name = "Bot1"
        self.bot1.hand = []
        self.bot2 = MagicMock(spec=InferencePlayer)
        self.bot2.name = "Bot2"
        self.bot2.hand = []
        self.bot3 = MagicMock(spec=InferencePlayer)
        self.bot3.name = "Bot3"
        self.bot3.hand = []

        # We need to make sure HasAttr checks pass
        # MagicMock usually handles this if spec is set, but let's be explicit
        self.bot1.decide_bid.return_value = ("pass", None)
        self.bot1.decide_play_card.return_value = None
        self.bot1.decide_kitty_exchange.return_value = []
        
        # Setup Game
        # Game constructor expects names usually, but we overwrite players
        self.game = Game(["P0", "P1", "P2", "P3"], ["Team1", "Team2"])
        self.game.players[0] = self.human
        self.game.players[1] = self.bot1
        self.game.players[2] = self.bot2
        self.game.players[3] = self.bot3
        self.game.verbose = False

    def test_web_human_player_duck_typing(self):
        """Test that WebHumanPlayer duck typing works for Game checks."""
        # The game uses hasattr(player, 'decide_bid') etc.
        # WebHumanPlayer logic:
        self.assertTrue(hasattr(self.human, 'decide_bid'))
        self.assertTrue(hasattr(self.human, 'decide_play_card'))
        self.assertTrue(hasattr(self.human, 'decide_kitty_exchange'))
        
    def test_inference_player_duck_typing(self):
        # We need a real inference player instantation (mocked model) to test signature compatibility
        with patch('five_hundred.inference_player.PyTorchAgent'):
             real_bot = InferencePlayer("RealBot", "dummy_path")
             self.assertTrue(hasattr(real_bot, 'decide_bid'))
             self.assertTrue(hasattr(real_bot, 'decide_play_card'))
             
    @patch('five_hundred.web_human_player.WebHumanPlayer._wait_for_input')
    def test_bidding_integration(self, mock_wait):
        """Test that bidding relies on _wait_for_input and doesn't block."""
        
        # Setup: Mock Human Bid
        # _wait_for_input returns dict: {'action': 'pass'}
        mock_wait.return_value = {'action': 'pass'}
        
        # Setup: Bots pass
        self.bot1.decide_bid.return_value = ("pass", None)
        self.bot2.decide_bid.return_value = ("pass", None)
        self.bot3.decide_bid.return_value = ("pass", None)
        
        # Run Bidding
        # We verify it completes (all pass)
        self.game.run_bidding_round(0)
        
        # Verify human was asked
        mock_wait.assert_called()
        self.assertIsNone(self.game.winning_bid) # All passed
        
    @patch('five_hundred.web_human_player.WebHumanPlayer._wait_for_input')
    def test_bidding_human_bid(self, mock_wait):
        # Human bids 7 Spades
        mock_wait.side_effect = [
            {'action': 'bid', 'tricks': 7, 'suit': 'SPADES'}, # Human (P0)
             # Bots pass (Mocked below)
        ]
        
        self.bot1.decide_bid.return_value = ("pass", None)
        self.bot2.decide_bid.return_value = ("pass", None)
        self.bot3.decide_bid.return_value = ("pass", None)
        
        # Run
        self.game.run_bidding_round(0)
        
        self.assertIsNotNone(self.game.winning_bid)
        self.assertEqual(self.game.winning_bid.tricks, 7)
        self.assertEqual(self.game.winning_bid.suit, Suit.SPADES)
        
    @patch('five_hundred.web_human_player.WebHumanPlayer._wait_for_input')
    def test_play_card_integration(self, mock_wait):
        # Setup hands manually
        c_human = Card(Suit.SPADES, Rank.ACE)
        c_bot = Card(Suit.SPADES, Rank.KING)
        
        self.human.hand = [c_human]
        self.bot1.hand = [c_bot]
        self.bot2.hand = [Card(Suit.SPADES, Rank.QUEEN)]
        self.bot3.hand = [Card(Suit.SPADES, Rank.JACK)]
        
        # Human leads
        # _wait_for_input needs to return {'card_index': 0}
        mock_wait.return_value = {'card_index': 0}
        
        # Bot logic needs to return a Card
        self.bot1.decide_play_card.return_value = self.bot1.hand[0]
        self.bot2.decide_play_card.return_value = self.bot2.hand[0]
        self.bot3.decide_play_card.return_value = self.bot3.hand[0]

        # Trick loop
        winner = self.game._play_trick(self.human)
        
        # Should be human (Ace)
        self.assertEqual(winner, self.human)
        # Verify call
        mock_wait.assert_called()
        
if __name__ == '__main__':
    unittest.main()
