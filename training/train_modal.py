import modal
import sys
import os

# Define the image with dependencies
image = (
    modal.Image.debian_slim()
    .pip_install("numpy", "torch")
     # Mount the parent directory so 'five_hundred' is available
    .add_local_python_source("five_hundred") 
    .add_local_python_source("training")
)

app = modal.App("five-hundred-rl", image=image)

# Create a volume to persist checkpoints
volume = modal.Volume.from_name("five-hundred-checkpoints", create_if_missing=True)

@app.function(
    gpu="any",  # Request any available GPU
    volumes={"/checkpoints": volume},  # Mount volume
    timeout=86400,  # 24 hours
)
def train_remote():
    # We need to trick the module system slightly since we mounted 'five_hundred'
    # but the script expects to be run from root.
    # The 'add_local_python_source' puts 'five_hundred' package in python path.
    
    # Import locally to avoid issues during image build
    import sys
    # Ensure correct import
    from training.train_agent import train
    
    # Monkey patch sys.argv or modify train_agent to accept args function
    # Our train_agent.py now uses argparse.
    sys.argv = ["training/train_agent.py", "--save-dir", "/checkpoints"]
    
    print("🚀 Starting remote training on Modal GPU...")
    print("   Checkpoints will be saved to Modal Volume 'five-hundred-checkpoints'")
    
    # Run the training loop
    train()

@app.local_entrypoint()
def main():
    print("Deploying to Modal...")
    train_remote.remote()
