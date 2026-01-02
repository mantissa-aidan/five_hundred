# Five Hundred AI - Training Roadmap

**Date:** January 2, 2026

## 1. Achieved Milestones
We have significantly upgraded the agent's infrastructure from the initial prototype.

### Infrastructure & Architecture
- [x] **Migration to PyTorch**: Replaced the manual NumPy neural network with a robust PyTorch implementation, enabling Adam optimization and GPU/MPS acceleration.
- [x] **Split-Brain Architecture**: Implemented separate neural networks for **Bidding** (28 outputs) and **Playing** (53 outputs), allowing the agent to specialize in each distinct phase of the game.
- [x] **Expanded State Space**: Increased input dimensionality from ~360 to **600**, now incorporating:
    - **Played Cards History**: 53-dim vector tracking all cards played in the round (crucial for card counting).
    - **Score Context**: Normalized scores and score delta (learning when to play safe vs aggressive).
    - **Trick History**: Detailed sequence of the current trick.
- [x] **Resume Capability**: Implemented checkpoint saving/loading to allow long-term training sessions.

### Testing
- [x] **Unit Tests**: Added `test_obs_expansion.py` and `test_agent_networks.py` to verify the new architecture.

## 2. Current Status
The **infrastructure is essentially complete**. The agent has "eyes" (richer state) and a "brain" (PyTorch networks). 

**Current Challenge:** We need to verify if the *brain* is actually learning to use its *eyes*. The `arena_history` logs show games are being played, but we need to quantify the improvement.

## 3. Future Milestones (Continued Training)

### Phase 1: Validation (Immediate)
- [ ] **Win Rate Baseline**: Run 1,000 games against the "Easy" bots and establish a win-rate baseline. (Target: >55% win rate).
- [ ] **Exclude Misere**: hard-code the agent to ignore Misere/Open Misere bids for now to focus on suit play and No Trump.

### Phase 2: Advanced Strategy (Short Term)
- [ ] **Self-Play Infrastructure**:
    -   Modify `train_agent.py` to support `Agent vs Agent` mode.
    -   Implement "League" training (current agent vs past versions) to prevent forgetting.
- [ ] **Memory Upgrade**: Implement an **LSTM** layer to better track the "story" of the hand.

### Phase 3: Strategic Behavior Milestones
We will measure progress not just by win rate, but by the emergence of specific strategies.

#### Milestone A: Basic Competence
- [ ] **Follow Suit Efficacy**: Error rate for "invalid moves" (trying to play off-suit) drops to near 0% without masking.
- [ ] **Play High to Win**: Probability of playing the highest card in hand when last to act and winning the trick > 90%.

#### Milestone B: Partner Awareness
- [ ] **Lead to Partner's Bid**: When partner wins the bid, frequency of leading their bid suit > 70%.
- [ ] **Support Lead**: When partner leads a suit, frequency of playing a high card (if unable to follow suit but can trump) or signalling?
- [ ] **Third Hand High**: Frequency of playing high when partner leads low (unless winning trick).

#### Milestone C: Expert Tactics
- [ ] **Finessing**: Leading a low card through an opponent's high card to trap it.
- [ ] **Drawing Trumps**: When Declarer, frequency of leading trumps early to clear opponents > 80%.
- [ ] **Sloughing**: Discarding loser cards on partner's winning tricks.

## 4. Measuring Progress
We will create a `check_strategy.py` script to parse `arena_history` logs and quantify these behaviors:
- **Metric**: `Partner_Lead_Adherence` (Did we lead partner's suit?)
- **Metric**: `Trump_Clearance_Rate` (Did declarer lead trumps in first 2 tricks?)
- **Metric**: `Invalid_Move_Rate`

---
*Created by Antigravity*
