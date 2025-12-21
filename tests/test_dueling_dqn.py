import torch
from five_hundred.agent import BiddingNetwork, PlayingNetwork

def test_bidding_net_forward():
    net = BiddingNetwork(input_dim=600, output_dim=28)
    x = torch.randn(1, 600)
    out = net(x)
    assert out.shape == (1, 28)
    # Check if backprop works
    out.sum().backward()
    assert net.feature[0].weight.grad is not None

def test_playing_net_forward():
    net = PlayingNetwork(input_dim=600, output_dim=53)
    x = torch.randn(1, 600)
    out = net(x)
    assert out.shape == (1, 53)
    # Check if backprop works
    out.sum().backward()
    assert net.feature[0].weight.grad is not None

if __name__ == "__main__":
    test_bidding_net_forward()
    test_playing_net_forward()
    print("Dueling DQN forward pass tests passed!")
