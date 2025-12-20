from five_hundred.env import FiveHundredEnv
from five_hundred.agent import DQNAgent
from five_hundred.server import get_control_state
import time

def train():
    print("Initializing Environment...")
    env = FiveHundredEnv(verbose=True)
    print("Initializing Agent...")
    agent = DQNAgent(state_dim=360, action_dim=100)
    
    print("Waiting for Start Command from UI...")
    
    episode_count = 0
    state = None
    
    while True:
        # Check control state
        control = get_control_state()
        if not control.get("running", False):
            time.sleep(1) # Idle wait
            continue

        # If we are starting fresh or need reset
        if state is None:
             state, info = env.reset() # Info contains mask
             episode_count += 1
             print(f"Episode {episode_count} start.")
             step_count = 0
             total_reward = 0

        # Step
        mask = info.get('mask') if 'info' in locals() else None
        action = agent.act(state, mask)
        next_state, reward, done, next_info = env.step(action)
        
        info = next_info # Update info for next loop
        
        
        agent.remember(state, action, reward, next_state, done)

        loss = agent.replay()
        
        if loss is not None:
             from five_hundred.server import record_loss, record_reward, increment_steps
             record_loss(float(loss))
             record_reward(float(total_reward)) # Using Cumulative Reward? Or Step Reward? Usually Step Reward (reward) or Ep total?
             # User asked for trend. Usually 'Episode Return' is the metric.
             # But here this is called inside the step.
             # Let's record instantaneous buffer, but Ep Total is stored in 'total_reward'.
             # Maybe best to record 'total_reward' ONLY at end of Episode?
             # But user wants real-time?
             # Let's record 'reward' (instantaneous) at step? It's often 0.
             # Better: Record 'Total Reward' at END of episode.
             
             increment_steps()
             
             if step_count % 10 == 0:
                 print(f"Episode {episode_count} Step {step_count}: Loss={loss:.4f}, Memory={len(agent.memory)}")
        else:
             if step_count % 10 == 0:
                 print(f"Episode {episode_count} Step {step_count}: Collecting... Mem={len(agent.memory)}")
        
        state = next_state
        total_reward += reward
        step_count += 1
        
        # Slow down for visualization
        # time.sleep(0.5) 
        
        if done:
            print(f"Episode {episode_count} finished. Steps: {step_count}, Total Reward: {total_reward}")
            from five_hundred.server import record_reward
            record_reward(float(total_reward))
            
            agent.update_target_network()
            agent.decay_epsilon()
            
            if episode_count % 50 == 0:
                agent.save(f"model_checkpoint_{episode_count}.pkl")
                print(f"Saved checkpoint: model_checkpoint_{episode_count}.pkl")
            
            state = None # Trigger reset on next loop iteration
            
            # Optional: Pause after each episode? 
            # For "continuous", we just keep going.

if __name__ == "__main__":
    train()
