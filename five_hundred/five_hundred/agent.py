import numpy as np
import random
from collections import deque
import pickle

class SimpleNN:
    def __init__(self, input_size, hidden_size, output_size, learning_rate=0.01):
        self.input_size = input_size
        self.hidden_size = hidden_size
        self.output_size = output_size
        self.learning_rate = learning_rate
        
        # Initialize weights
        self.W1 = np.random.randn(input_size, hidden_size) * np.sqrt(2.0/input_size)
        self.b1 = np.zeros((1, hidden_size))
        self.W2 = np.random.randn(hidden_size, output_size) * np.sqrt(2.0/hidden_size)
        self.b2 = np.zeros((1, output_size))

    def forward(self, X):
        self.z1 = np.dot(X, self.W1) + self.b1
        self.a1 = np.maximum(0, self.z1) # ReLU
        self.z2 = np.dot(self.a1, self.W2) + self.b2
        return self.z2 # Linear output for Q-values

    def backward(self, X, y_target):
        # Forward pass to be sure we have latest activations? Assuming forward called before.
        # But for batch update, we need to re-run forward for the batch
        output = self.forward(X)
        
        # MSE Gradient: dL/dOutput = 2 * (Output - Target) / N
        # We drop the 2/N constant scaling into learning rate usually, or keep it.
        delta2 = (output - y_target) 
        
        dW2 = np.dot(self.a1.T, delta2)
        db2 = np.sum(delta2, axis=0, keepdims=True)
        
        delta1 = np.dot(delta2, self.W2.T) * (self.z1 > 0) # ReLU derivative
        
        dW1 = np.dot(X.T, delta1)
        db1 = np.sum(delta1, axis=0, keepdims=True)
        
        # Update weights
        self.W1 -= self.learning_rate * dW1
        self.b1 -= self.learning_rate * db1
        self.W2 -= self.learning_rate * dW2
        self.b2 -= self.learning_rate * db2

    def get_weights(self):
        return [self.W1.copy(), self.b1.copy(), self.W2.copy(), self.b2.copy()]

    def set_weights(self, weights):
        self.W1, self.b1, self.W2, self.b2 = [w.copy() for w in weights]


class DQNAgent:
    def __init__(self, state_dim=360, action_dim=100, lr=1e-3, gamma=0.99, buffer_size=10000):
        self.state_dim = state_dim
        self.action_dim = action_dim
        self.gamma = gamma
        self.lr = lr
        
        self.model = SimpleNN(state_dim, 512, action_dim, learning_rate=lr)
        self.target_model = SimpleNN(state_dim, 512, action_dim, learning_rate=lr)
        self.update_target_network()
        
        self.memory = deque(maxlen=buffer_size)
        
        self.epsilon = 1.0
        self.epsilon_min = 0.01
        self.epsilon_decay = 0.995
        self.batch_size = 32
        
    def act(self, state: np.ndarray, mask: np.ndarray = None) -> int:
        state = state.reshape(1, -1)
        
        # Random Exploration (Epsilon-Greedy) with Mask
        if np.random.rand() <= self.epsilon:
            if mask is not None:
                valid_indices = np.where(mask == 1)[0]
                if len(valid_indices) > 0:
                    return np.random.choice(valid_indices)
            return random.randrange(self.action_dim)
        
        # Greedy Exploitation with Mask
        q_values = self.model.forward(state)
        
        if mask is not None:
            # Set invalid actions to negative infinity
            # Flatten mask to match q_values shape (1, action_dim) or broadcast
            # q_values is (1, action_dim)
            min_float = -1e9
            # Mask where 0 -> set to min_float
            # Where 1 -> keep q_vlues
            # We can just subtract huge number where mask is 0
            q_values[0, mask == 0] = min_float
            
        return np.argmax(q_values)
    
    def decay_epsilon(self):
        if self.epsilon > self.epsilon_min:
            self.epsilon *= self.epsilon_decay

    def remember(self, state, action, reward, next_state, done):
        self.memory.append((state, action, reward, next_state, done))
        
    def replay(self):
        if len(self.memory) < self.batch_size:
            return
        
        minibatch = random.sample(self.memory, self.batch_size)
        
        states = np.array([x[0] for x in minibatch])
        actions = np.array([x[1] for x in minibatch])
        rewards = np.array([x[2] for x in minibatch])
        next_states = np.array([x[3] for x in minibatch])
        dones = np.array([x[4] for x in minibatch])
        
        # Current Q values
        q_values = self.model.forward(states)
        
        # Next Q values (Target Network)
        next_q_values = self.target_model.forward(next_states)
        
        # Target calculation
        target = q_values.copy()
        
        # Basic DQN Target: reward + gamma * max(next_q)
        # Using vectorized ops
        max_next_q = np.max(next_q_values, axis=1)
        target_q_for_actions = rewards + (1 - dones) * self.gamma * max_next_q
        
        # Assign targets to strict action indices
        rows = np.arange(self.batch_size)
        target[rows, actions] = target_q_for_actions
        
        # Backprop
        self.model.backward(states, target)
        


        # Calculate loss for reporting (Mean Squared Error)
        # loss = np.mean((target - q_values)**2) # This is technically approximate as only specific actions were target
        # Accurate loss is just on the q_values we updated
        # But for visualization 'trend' is enough.
        # Let's return the mean absolute error of the update for simplicity or the actual loss if we tracked it in backward
        # Our backward didn't return loss. Let's calculate it here.
        # Only for the taken actions:
        # q_values[rows, actions] vs target[rows, actions] (which IS target_q_for_actions)
        # So we just compare q_values_before vs target?
        # No, q_values variable holds the Values BEFORE update.
        # Target holds the target values
        # Difference at the specific action indices:
        current_q_action = q_values[rows, actions]
        loss = np.mean((current_q_action - target_q_for_actions)**2)
        return loss
            
    def update_target_network(self):
        self.target_model.set_weights(self.model.get_weights())

    def save(self, path):
        with open(path, 'wb') as f:
            pickle.dump(self.model.get_weights(), f)
        
    def load(self, path):
        with open(path, 'rb') as f:
            weights = pickle.load(f)
            self.model.set_weights(weights)
