# Remote Training with Modal

[Modal](https://modal.com) allows you to run your training script in the cloud with a single command, while seeing all the logs locally in real-time.

## Prerequisites
1.  **Sign up for Modal**: Go to [modal.com](https://modal.com) and create an account (free credits available).
2.  **Install Modal Client**:
    ```bash
    pip install modal
    ```
3.  **Authenticate**:
    ```bash
    python3 -m modal setup
    ```

## Running Training
Once setup is complete, simply run:

```bash
modal run train_modal.py
modal run train_modal.py
```

## Stopping Training
- **Terminal**: Just press `Ctrl+C` in your terminal. This will stop the remote job.
- **Dashboard**: You can also go to [modal.com/apps](https://modal.com/apps) to view running apps and stop them manually.

## Features
- **Remote GPU**: Uses a T4 or A10G GPU in the cloud.
- **Local Logs**: All print statements and training progress bars appear in your local terminal instantly.
- **Persistence**: Checkpoints are saved to a Modal Volume named `five-hundred-checkpoints`.

## Downloading Checkpoints
To get your trained models back to your local machine:

```bash
# List files
modal volume ls five-hundred-checkpoints

# Download a specific checkpoint
modal volume get five-hundred-checkpoints model_checkpoint_1000.pth .
```
