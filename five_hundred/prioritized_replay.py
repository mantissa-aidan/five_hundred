"""
Prioritized Experience Replay Buffer
Based on: Schaul et al. (2016) - Prioritized Experience Replay
"""
import numpy as np
import random
from collections import namedtuple

Transition = namedtuple('Transition', ['state', 'action', 'reward', 'next_state', 'done', 'phase'])

class SumTree:
    """Binary heap for efficient priority sampling"""
    def __init__(self, capacity):
        self.capacity = capacity
        self.tree = np.zeros(2 * capacity - 1)
        self.data = [None] * capacity
        self.write = 0
        self.n_entries = 0
    
    def _propagate(self, idx, change):
        parent = (idx - 1) // 2
        self.tree[parent] += change
        if parent != 0:
            self._propagate(parent, change)
    
    def _retrieve(self, idx, s):
        left = 2 * idx + 1
        right = left + 1
        
        if left >= len(self.tree):
            return idx
        
        if s <= self.tree[left]:
            return self._retrieve(left, s)
        else:
            return self._retrieve(right, s - self.tree[left])
    
    def total(self):
        return self.tree[0]
    
    def add(self, priority, data):
        idx = self.write + self.capacity - 1
        self.data[self.write] = data
        self.update(idx, priority)
        
        self.write = (self.write + 1) % self.capacity
        if self.n_entries < self.capacity:
            self.n_entries += 1
    
    def update(self, idx, priority):
        change = priority - self.tree[idx]
        self.tree[idx] = priority
        self._propagate(idx, change)
    
    def get(self, s):
        idx = self._retrieve(0, s)
        data_idx = idx - self.capacity + 1
        return idx, self.tree[idx], self.data[data_idx]

class PrioritizedReplayBuffer:
    """
    Prioritized Experience Replay Buffer
    Samples transitions with probability proportional to their TD-error
    """
    def __init__(self, capacity, alpha=0.6, beta=0.4, epsilon=1e-6):
        self.tree = SumTree(capacity)
        self.capacity = capacity
        self.alpha = alpha  # How much prioritization (0=uniform, 1=full)
        self.beta = beta    # Importance sampling correction (increases to 1)
        self.epsilon = epsilon  # Small constant to ensure non-zero priority
        self.max_priority = 1.0
    
    def push(self, state, action, reward, next_state, done, phase):
        transition = Transition(state, action, reward, next_state, done, phase)
        # New transitions get max priority (optimistic initialization)
        self.tree.add(self.max_priority, transition)
    
    def sample(self, batch_size):
        batch = []
        idxs = []
        priorities = []
        segment = self.tree.total() / batch_size
        
        for i in range(batch_size):
            a = segment * i
            b = segment * (i + 1)
            s = random.uniform(a, b)
            idx, priority, data = self.tree.get(s)
            
            if data is not None:
                batch.append(data)
                idxs.append(idx)
                priorities.append(priority)
        
        # Importance sampling weights
        sampling_probs = np.array(priorities) / self.tree.total()
        weights = np.power(self.tree.n_entries * sampling_probs, -self.beta)
        weights /= weights.max()  # Normalize for stability
        
        return batch, idxs, weights
    
    def update_priorities(self, idxs, td_errors):
        """Update priorities based on TD-errors"""
        for idx, td_error in zip(idxs, td_errors):
            priority = (abs(td_error) + self.epsilon) ** self.alpha
            self.tree.update(idx, priority)
            self.max_priority = max(self.max_priority, priority)
    
    def __len__(self):
        return self.tree.n_entries
